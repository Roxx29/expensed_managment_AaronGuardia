import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/l10n.dart';
import '../../../shared/providers/providers.dart';
import '../application/app_lock.dart';

/// Sits above the router (MaterialApp.router `builder`), so no screen renders
/// before unlock. There is no Navigator/Overlay here: no dialogs or tooltips.
class AppLockGate extends ConsumerStatefulWidget {
  const AppLockGate({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends ConsumerState<AppLockGate> {
  static const _relockAfter = Duration(seconds: 30);

  late final AppLifecycleListener _lifecycle;
  bool _covered = false;
  // Both clocks: the monotonic Stopwatch ignores clock changes but stops while
  // the device sleeps (CLOCK_MONOTONIC); the wall clock covers sleep.
  Stopwatch? _background;
  DateTime? _backgroundAt;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onStateChange: _onLifecycle);
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  void _onLifecycle(AppLifecycleState s) {
    if (s == AppLifecycleState.hidden || s == AppLifecycleState.paused) {
      _background ??= Stopwatch()..start();
      _backgroundAt ??= ref.read(clockProvider)();
    } else if (s == AppLifecycleState.resumed) {
      final away = _background?.elapsed;
      final since = _backgroundAt;
      _background = null;
      _backgroundAt = null;
      if (away != null &&
          since != null &&
          (away >= _relockAfter || ref.read(clockProvider)().difference(since) >= _relockAfter)) {
        ref.read(appLockProvider.notifier).lock();
      }
    }
    setState(() => _covered = s != AppLifecycleState.resumed);
  }

  @override
  Widget build(BuildContext context) {
    final lock = ref.watch(appLockProvider);
    final hideApp = !lock.ready || lock.locked;
    // Same tree shape in every state, so the router keeps its state across
    // lock/unlock. Lock off → only the (visible) child: effectively transparent.
    return Stack(
      fit: StackFit.expand,
      children: [
        Offstage(
          offstage: hideApp,
          child: TickerMode(
            enabled: !hideApp,
            child: ExcludeFocus(excluding: hideApp, child: widget.child),
          ),
        ),
        // Opaque until secure storage has been read once (fast; resolves to
        // "not enabled" when the plugin is missing, e.g. in tests).
        if (!lock.ready) ColoredBox(color: Theme.of(context).colorScheme.surface),
        if (lock.ready && lock.locked) const _LockScreen(),
        // Hides balances in the app switcher.
        if (lock.enabled && _covered) const _PrivacyCover(),
      ],
    );
  }
}

class _PrivacyCover extends StatelessWidget {
  const _PrivacyCover();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surface,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lock_rounded, size: 56, color: scheme.primary),
            const SizedBox(height: 12),
            Text('Expense Manager', style: Theme.of(context).textTheme.titleLarge),
          ],
        ),
      ),
    );
  }
}

class _LockScreen extends ConsumerStatefulWidget {
  const _LockScreen();

  @override
  ConsumerState<_LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends ConsumerState<_LockScreen> {
  static const _maxDigits = 12;

  String _pin = '';
  bool _busy = false;
  String? _error;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    final lock = ref.read(appLockProvider);
    _syncTicker(lock);
    // Auto-prompt once each time the lock screen appears.
    if (lock.biometricsEnabled && lock.biometricsAvailable) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _biometrics();
      });
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Duration _remaining(AppLockState lock) {
    final until = lock.lockedUntil;
    if (until == null) return Duration.zero;
    final left = until.difference(ref.read(clockProvider)());
    return left.isNegative ? Duration.zero : left;
  }

  /// Ticks once a second only while a lockout is running.
  void _syncTicker(AppLockState lock) {
    if (_remaining(lock) == Duration.zero || _ticker != null) return;
    _ticker = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      if (_remaining(ref.read(appLockProvider)) == Duration.zero) {
        t.cancel();
        _ticker = null;
      }
      setState(() {});
    });
  }

  void _type(String digit) {
    if (_busy || _pin.length >= _maxDigits) return;
    setState(() {
      _pin += digit;
      _error = null;
    });
  }

  void _backspace() {
    if (_busy || _pin.isEmpty) return;
    setState(() => _pin = _pin.substring(0, _pin.length - 1));
  }

  Future<void> _submit() async {
    if (_busy || _pin.isEmpty) return;
    setState(() => _busy = true);
    String? error;
    try {
      final result = await ref.read(appLockProvider.notifier).unlockWithPin(_pin);
      if (!mounted) return;
      if (result == UnlockResult.wrongPin) {
        error = context.tr('Wrong PIN');
        unawaited(HapticFeedback.heavyImpact());
      }
    } on Object {
      if (!mounted) return;
      error = context.tr('Something went wrong. Try again.');
    }
    setState(() {
      _busy = false;
      _pin = '';
      _error = error;
    });
  }

  Future<void> _biometrics() async {
    if (_busy) return;
    await ref.read(appLockProvider.notifier).unlockWithBiometrics(context.tr('Unlock Expense Manager'));
  }

  String _format(Duration d) =>
      '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final lock = ref.watch(appLockProvider);
    ref.listen(appLockProvider, (_, next) => _syncTicker(next));
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final remaining = _remaining(lock);
    final lockedOut = remaining > Duration.zero;
    final disabled = _busy || lockedOut;
    final message = lockedOut
        ? context.tr('Too many attempts. Try again in {time}.', {'time': _format(remaining)})
        : _error;

    return Material(
      color: scheme.surface,
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.lock_rounded, size: 48, color: scheme.primary),
                  const SizedBox(height: 16),
                  Text(
                    context.tr('Enter your PIN'),
                    style: theme.textTheme.headlineSmall,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  _Dots(count: _pin.length),
                  const SizedBox(height: 16),
                  SizedBox(
                    height: 48,
                    child: _busy
                        ? const Center(child: SizedBox.square(dimension: 24, child: CircularProgressIndicator()))
                        : Semantics(
                            liveRegion: true,
                            child: Text(
                              message ?? '',
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodyMedium?.copyWith(color: scheme.error),
                            ),
                          ),
                  ),
                  const SizedBox(height: 8),
                  _Keypad(
                    enabled: !disabled,
                    canSubmit: _pin.isNotEmpty,
                    onDigit: _type,
                    onBackspace: _backspace,
                    onSubmit: _submit,
                  ),
                  if (lock.biometricsEnabled && lock.biometricsAvailable) ...[
                    const SizedBox(height: 16),
                    FilledButton.tonalIcon(
                      onPressed: _busy ? null : _biometrics,
                      icon: const Icon(Icons.fingerprint_rounded),
                      label: Text(context.tr('Use biometrics')),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Dots extends StatelessWidget {
  const _Dots({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    // At least 6 slots; grows for longer PINs.
    final slots = count < 6 ? 6 : count;
    return Semantics(
      label: context.tr('{count} digits entered', {'count': count}),
      child: ExcludeSemantics(
        child: Wrap(
          spacing: 12,
          runSpacing: 8,
          alignment: WrapAlignment.center,
          children: [
            for (var i = 0; i < slots; i++)
              Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: i < count ? color : null,
                  border: Border.all(color: color, width: 2),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Keypad extends StatelessWidget {
  const _Keypad({
    required this.enabled,
    required this.canSubmit,
    required this.onDigit,
    required this.onBackspace,
    required this.onSubmit,
  });

  final bool enabled;
  final bool canSubmit;
  final ValueChanged<String> onDigit;
  final VoidCallback onBackspace;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    Widget digit(String d) => _Key(label: d, onTap: enabled ? () => onDigit(d) : null, child: Text(d));
    final rows = [
      ['1', '2', '3'],
      ['4', '5', '6'],
      ['7', '8', '9'],
    ];
    return Column(
      children: [
        for (final row in rows) Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [for (final d in row) digit(d)]),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _Key(
              label: context.tr('Delete digit'),
              onTap: enabled ? onBackspace : null,
              child: const Icon(Icons.backspace_outlined),
            ),
            digit('0'),
            _Key(
              label: context.tr('Unlock'),
              onTap: enabled && canSubmit ? onSubmit : null,
              child: const Icon(Icons.check_rounded),
            ),
          ],
        ),
      ],
    );
  }
}

class _Key extends StatelessWidget {
  const _Key({required this.label, required this.onTap, required this.child});

  final String label;
  final VoidCallback? onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = onTap == null ? theme.disabledColor : theme.colorScheme.onSurface;
    return Padding(
      padding: const EdgeInsets.all(6),
      child: Semantics(
        button: true,
        enabled: onTap != null,
        label: label,
        onTap: onTap,
        excludeSemantics: true,
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: SizedBox.square(
            dimension: 72,
            child: Center(
              child: IconTheme.merge(
                data: IconThemeData(color: color, size: 28),
                child: DefaultTextStyle.merge(
                  style: theme.textTheme.headlineMedium?.copyWith(color: color),
                  child: child,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
