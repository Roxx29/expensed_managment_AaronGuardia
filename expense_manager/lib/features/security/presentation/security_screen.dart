import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/layout/breakpoints.dart';
import '../../../domain/security/pin_hasher.dart';
import '../../../shared/widgets/common_widgets.dart';
import '../application/app_lock.dart';

class SecurityScreen extends ConsumerWidget {
  const SecurityScreen({super.key});

  /// Opens a PIN dialog that runs [submit] itself (hashing takes ~1 s) and
  /// shows [done] when it succeeds.
  Future<void> _pinFlow(
    BuildContext context, {
    required String title,
    required bool askCurrent,
    required bool askNew,
    required String done,
    required Future<UnlockResult> Function(String current, String newPin) submit,
  }) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => _PinDialog(title: title, askCurrent: askCurrent, askNew: askNew, submit: submit),
    );
    if (ok == true && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(done)));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lock = ref.watch(appLockProvider);
    final notifier = ref.read(appLockProvider.notifier);

    void setPin() => _pinFlow(
          context,
          title: context.tr('Set a PIN'),
          askCurrent: false,
          askNew: true,
          done: context.tr('App lock is on'),
          submit: (_, pin) async {
            await notifier.setPin(pin);
            return UnlockResult.success;
          },
        );
    void changePin() => _pinFlow(
          context,
          title: context.tr('Change PIN'),
          askCurrent: true,
          askNew: true,
          done: context.tr('PIN changed'),
          submit: notifier.changePin,
        );
    void removeLock() => _pinFlow(
          context,
          title: context.tr('Remove app lock'),
          askCurrent: true,
          askNew: false,
          done: context.tr('App lock is off'),
          submit: (current, _) => notifier.disable(current),
        );
    Future<void> setBiometrics(bool on) async {
      final messenger = ScaffoldMessenger.of(context);
      final error = context.tr('Something went wrong. Try again.');
      try {
        await notifier.setBiometrics(on);
      } on Object {
        messenger.showSnackBar(SnackBar(content: Text(error)));
      }
    }

    return Scaffold(
      appBar: AppBar(title: Text(context.tr('Security'))),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: Breakpoints.expanded),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              SectionCard(
                title: context.tr('App lock'),
                child: Column(
                  children: [
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      secondary: const Icon(Icons.lock_rounded),
                      title: Text(context.tr('Lock with a PIN')),
                      subtitle: Text(context.tr('Asks for your PIN when the app opens and after 30 seconds in the background.')),
                      value: lock.enabled,
                      onChanged: lock.ready
                          ? (on) {
                              if (on) {
                                setPin();
                              } else {
                                removeLock();
                              }
                            }
                          : null,
                    ),
                    if (lock.enabled)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.password_rounded),
                        title: Text(context.tr('Change PIN')),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: changePin,
                      ),
                    if (lock.biometricsAvailable)
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        secondary: const Icon(Icons.fingerprint_rounded),
                        title: Text(context.tr('Unlock with biometrics')),
                        subtitle: Text(lock.enabled
                            ? context.tr('Fingerprint or face. Your PIN always works too.')
                            : context.tr('Set a PIN first.')),
                        value: lock.enabled && lock.biometricsEnabled,
                        onChanged: lock.enabled ? setBiometrics : null,
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              SectionCard(
                title: context.tr('If you forget your PIN'),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(context.tr(
                        'A forgotten PIN cannot be recovered. You would have to reinstall the app, which deletes all your data unless you exported a backup.')),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: () => context.push(Routes.backup),
                      icon: const Icon(Icons.backup_rounded),
                      label: Text(context.tr('Export a backup')),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PinDialog extends StatefulWidget {
  const _PinDialog({required this.title, required this.askCurrent, required this.askNew, required this.submit});

  final String title;
  final bool askCurrent;
  final bool askNew;
  final Future<UnlockResult> Function(String current, String newPin) submit;

  @override
  State<_PinDialog> createState() => _PinDialogState();
}

class _PinDialogState extends State<_PinDialog> {
  final _form = GlobalKey<FormState>();
  final _current = TextEditingController();
  final _new = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _current.dispose();
    _new.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy || !_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    String? error;
    try {
      final result = await widget.submit(_current.text, _new.text);
      if (!mounted) return;
      switch (result) {
        case UnlockResult.success:
          Navigator.of(context).pop(true);
          return;
        case UnlockResult.wrongPin:
          error = context.tr('Wrong PIN');
        case UnlockResult.lockedOut:
          error = context.tr('Too many attempts. Try again later.');
      }
    } on Object {
      if (!mounted) return;
      error = context.tr('Something went wrong. Try again.');
    }
    setState(() {
      _busy = false;
      _error = error;
      _current.clear();
    });
  }

  Widget _field(TextEditingController c, String label, String? Function(String) validate,
          {String? helper, bool autofocus = false}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: TextFormField(
          controller: c,
          enabled: !_busy,
          autofocus: autofocus,
          obscureText: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(12)],
          decoration: InputDecoration(labelText: label, helperText: helper, helperMaxLines: 2),
          validator: (v) => validate(v ?? ''),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: Form(
        key: _form,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.askCurrent)
                _field(_current, context.tr('Current PIN'),
                    (v) => v.isEmpty ? context.tr('Enter your PIN') : null,
                    autofocus: true),
              if (widget.askNew) ...[
                _field(_new, context.tr('New PIN'),
                    (v) => isValidPin(v) ? null : context.tr('Use 4 to 12 digits'),
                    helper: context.tr('6 digits or more is safer.'), autofocus: !widget.askCurrent),
                _field(_confirm, context.tr('Confirm PIN'),
                    (v) => v == _new.text ? null : context.tr('PINs don\'t match')),
              ],
              if (_busy) const LinearProgressIndicator(),
              if (_error != null)
                Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(false),
          child: Text(context.tr('Cancel')),
        ),
        FilledButton(onPressed: _busy ? null : _save, child: Text(context.tr('Save'))),
      ],
    );
  }
}
