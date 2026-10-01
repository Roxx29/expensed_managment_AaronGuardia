import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

import '../../../domain/security/pin_hasher.dart';
import '../../../shared/providers/providers.dart';

// Secure-storage keys. The PIN never touches SQLite.
const _pinKey = 'security.pin';
const _failedKey = 'security.failed';
const _untilKey = 'security.locked_until';
const _biometricsKey = 'security.biometrics';
const _secureKeys = [_pinKey, _failedKey, _untilKey, _biometricsKey];

/// SQLite settings marker; missing means first launch after (re)install.
const _installedKey = 'security.installed';

/// SQLite settings marker, 'on' while a PIN is set. Lets startup skip the
/// platform plugins entirely when the lock is off (tests, fresh installs).
/// The lock is enabled only if this is 'on' AND a PIN record exists, so a
/// reinstall (SQLite gone, iOS keychain kept) never inherits an old PIN.
const _lockKey = 'security.lock';

const _storage = FlutterSecureStorage(
  // resetOnError: an Android auto-backup restored onto another device cannot
  // be decrypted; start clean instead of throwing on every read and write.
  aOptions: AndroidOptions(encryptedSharedPreferences: true, resetOnError: true),
  iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock_this_device),
);

/// Override with a lower iteration count in tests.
final pinHasherProvider = Provider<PinHasher>((ref) => const PinHasher());

final appLockProvider = NotifierProvider<AppLock, AppLockState>(AppLock.new);

enum UnlockResult { success, wrongPin, lockedOut }

class AppLockState {
  const AppLockState({
    this.ready = false,
    this.enabled = false,
    this.locked = false,
    this.biometricsEnabled = false,
    this.biometricsAvailable = false,
    this.lockedUntil,
  });

  /// False until secure storage has been read once.
  final bool ready;
  final bool enabled;
  final bool locked;
  final bool biometricsEnabled;

  /// Device has enrolled biometrics and the plugin works.
  final bool biometricsAvailable;

  /// PIN entry is refused until then (too many failed attempts).
  final DateTime? lockedUntil;

  AppLockState copyWith({
    bool? enabled,
    bool? locked,
    bool? biometricsEnabled,
    bool? biometricsAvailable,
    DateTime? lockedUntil,
    bool clearLockedUntil = false,
  }) =>
      AppLockState(
        ready: ready,
        enabled: enabled ?? this.enabled,
        locked: locked ?? this.locked,
        biometricsEnabled: biometricsEnabled ?? this.biometricsEnabled,
        biometricsAvailable: biometricsAvailable ?? this.biometricsAvailable,
        lockedUntil: clearLockedUntil ? null : (lockedUntil ?? this.lockedUntil),
      );
}

class AppLock extends Notifier<AppLockState> {
  final _auth = LocalAuthentication();
  bool _authenticating = false;

  /// Completes when startup work (incl. background cleanup) is done.
  late Future<void> loaded;

  /// Fresh-install keychain wipe; setPin waits for it so it can't delete a new PIN.
  Future<void> _wipe = Future.value();

  DateTime _now() => ref.read(clockProvider)();

  @override
  AppLockState build() {
    loaded = _load();
    return const AppLockState();
  }

  Future<void> _load() async {
    final settings = ref.read(settingsRepositoryProvider);
    String? installed = '1', marker = 'on';
    try {
      installed = await settings.read(_installedKey);
      marker = await settings.read(_lockKey);
    } on Object {
      // Unreadable settings: fall back to checking secure storage.
    }
    // marker 'on' means SQLite survived (only the installed write failed):
    // not a fresh install, so the PIN must not be wiped.
    if (installed == null && marker != 'on') {
      // Keychain entries can survive an uninstall on iOS: wipe them so a
      // fresh install never inherits old lock state. Retried next launch.
      _wipe = () async {
        try {
          for (final key in _secureKeys) {
            await _storage.delete(key: key);
          }
          await settings.write(_installedKey, '1');
        } on Object {
          // Plugin missing (tests) or storage error.
        }
      }();
    }

    if (marker != 'on') {
      // Lock off: show the app now, without waiting on any platform plugin.
      if (!ref.mounted) return;
      state = const AppLockState(ready: true);
      final available = await _biometricsAvailable();
      await _wipe;
      if (ref.mounted) state = state.copyWith(biometricsAvailable: available);
      return;
    }

    var enabled = false, biometrics = false;
    DateTime? until;
    try {
      enabled = await _storage.read(key: _pinKey) != null;
      if (enabled) {
        biometrics = await _storage.read(key: _biometricsKey) == 'on';
        until = DateTime.tryParse(await _storage.read(key: _untilKey) ?? '');
      }
    } on Object {
      // No secure storage (unsupported platform): lock unavailable.
      enabled = false;
    }
    final available = await _biometricsAvailable();
    await _wipe;
    if (!ref.mounted) return;
    state = AppLockState(
      ready: true,
      enabled: enabled,
      locked: enabled,
      biometricsEnabled: biometrics,
      biometricsAvailable: available,
      lockedUntil: until,
    );
  }

  Future<bool> _biometricsAvailable() async {
    try {
      return await _auth.isDeviceSupported() && await _auth.canCheckBiometrics;
    } on Object {
      // MissingPluginException / PlatformException: treat as unavailable.
      return false;
    }
  }

  /// Locks again (e.g. back from background). Ignored while a biometric
  /// prompt is up, since the prompt itself can background the app.
  void lock() {
    if (state.enabled && !_authenticating) state = state.copyWith(locked: true);
  }

  /// Turns the lock on (or replaces the PIN while unlocked).
  /// Throws [ArgumentError] for a PIN that breaks the rules.
  Future<void> setPin(String pin) async {
    if (!isValidPin(pin)) throw ArgumentError('PIN must be 4–12 digits');
    final settings = ref.read(settingsRepositoryProvider);
    final record = await ref.read(pinHasherProvider).hash(pin);
    await _wipe;
    await _storage.write(key: _pinKey, value: record);
    await _resetFailures();
    await settings.write(_lockKey, 'on');
    if (ref.mounted) state = state.copyWith(enabled: true, locked: false, clearLockedUntil: true);
  }

  Future<UnlockResult> changePin(String oldPin, String newPin) async {
    if (!isValidPin(newPin)) throw ArgumentError('PIN must be 4–12 digits');
    final result = await _checkPin(oldPin);
    if (result == UnlockResult.success) await setPin(newPin);
    return result;
  }

  /// Removes the lock (and the biometrics setting).
  Future<UnlockResult> disable(String pin) async {
    final settings = ref.read(settingsRepositoryProvider);
    final result = await _checkPin(pin);
    if (result != UnlockResult.success) return result;
    for (final key in _secureKeys) {
      await _storage.delete(key: key);
    }
    await settings.write(_lockKey, 'off');
    if (ref.mounted) {
      state = state.copyWith(enabled: false, locked: false, biometricsEnabled: false, clearLockedUntil: true);
    }
    return result;
  }

  Future<UnlockResult> unlockWithPin(String pin) async {
    final result = await _checkPin(pin);
    if (result == UnlockResult.success && ref.mounted) state = state.copyWith(locked: false);
    return result;
  }

  /// [reason] is the localized text the system prompt shows.
  Future<bool> unlockWithBiometrics(String reason) async {
    if (!state.enabled || !state.biometricsEnabled || !state.biometricsAvailable || _authenticating) return false;
    _authenticating = true;
    try {
      final ok = await _auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(biometricOnly: true, stickyAuth: true),
      );
      if (!ok) return false;
      await _resetFailures();
      if (ref.mounted) state = state.copyWith(locked: false, clearLockedUntil: true);
      return true;
    } on Object {
      // Cancelled, locked out by the OS, or plugin missing: PIN still works.
      return false;
    } finally {
      _authenticating = false;
    }
  }

  /// Only allowed with a PIN set (the PIN is always the fallback).
  Future<void> setBiometrics(bool on) async {
    if (!state.enabled || (on && !state.biometricsAvailable)) return;
    await _storage.write(key: _biometricsKey, value: on ? 'on' : 'off');
    if (ref.mounted) state = state.copyWith(biometricsEnabled: on);
  }

  // Storage errors propagate here on purpose: a failed read must never unlock.
  Future<UnlockResult> _checkPin(String pin) async {
    final until = state.lockedUntil;
    // ponytail: wall-clock lockout; a user moving the clock forward skips
    // it. A monotonic/boot-time source needs a platform channel.
    if (until != null && _now().isBefore(until)) return UnlockResult.lockedOut;
    final record = await _storage.read(key: _pinKey);
    if (record == null) return UnlockResult.wrongPin;

    // Counted before the slow check, so killing the app mid-check gives no
    // free attempts.
    final failed = (int.tryParse(await _storage.read(key: _failedKey) ?? '') ?? 0) + 1;
    await _storage.write(key: _failedKey, value: '$failed');

    if (await ref.read(pinHasherProvider).verify(pin, record)) {
      await _resetFailures();
      if (ref.mounted) state = state.copyWith(clearLockedUntil: true);
      return UnlockResult.success;
    }

    final wait = lockoutFor(failed);
    if (wait > Duration.zero) {
      final lockedUntil = _now().add(wait);
      await _storage.write(key: _untilKey, value: lockedUntil.toIso8601String());
      if (ref.mounted) state = state.copyWith(lockedUntil: lockedUntil);
    }
    return UnlockResult.wrongPin;
  }

  Future<void> _resetFailures() async {
    await _storage.delete(key: _failedKey);
    await _storage.delete(key: _untilKey);
  }
}
