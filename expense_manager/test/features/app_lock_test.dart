// App lock logic against mocked secure storage and an in-memory database.
@Tags(['db'])
library;

import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:drift/native.dart';
import 'package:expense_manager/data/database/app_database.dart';
import 'package:expense_manager/domain/security/pin_hasher.dart';
import 'package:expense_manager/features/security/application/app_lock.dart';
import 'package:expense_manager/shared/providers/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const hasher = PinHasher(iterations: 1000);

  late AppDatabase db;
  late ProviderContainer c;
  var now = DateTime(2026, 1, 1, 12);

  Future<AppLock> start({Map<String, String> secure = const {}, bool installed = true}) async {
    FlutterSecureStorage.setMockInitialValues(Map.of(secure));
    now = DateTime(2026, 1, 1, 12);
    db = AppDatabase(DatabaseConnection(NativeDatabase.memory(), closeStreamsSynchronously: true));
    c = ProviderContainer(overrides: [
      appDatabaseProvider.overrideWithValue(db),
      pinHasherProvider.overrideWithValue(hasher),
      clockProvider.overrideWithValue(() => now),
    ]);
    if (installed) {
      final settings = c.read(settingsRepositoryProvider);
      await settings.write('security.installed', '1');
      if (secure.containsKey('security.pin')) await settings.write('security.lock', 'on');
    }
    c.listen(appLockProvider, (_, _) {});
    final lock = c.read(appLockProvider.notifier);
    await lock.loaded;
    return lock;
  }

  AppLockState state() => c.read(appLockProvider);

  tearDown(() async {
    c.dispose();
    await db.close();
  });

  test('no PIN: ready, not enabled, not locked', () async {
    await start();
    expect(state().ready, isTrue);
    expect(state().enabled, isFalse);
    expect(state().locked, isFalse);
  });

  test('first launch after reinstall wipes stale secure entries', () async {
    await start(secure: {'security.pin': await hasher.hash('1234')}, installed: false);
    expect(state().enabled, isFalse);
    expect(await c.read(settingsRepositoryProvider).read('security.installed'), isNotNull);
    expect(await const FlutterSecureStorage().read(key: 'security.pin'), isNull);
  });

  test('setPin persists across a cold start; disable turns it off', () async {
    var lock = await start();
    await lock.setPin('1234');
    c.dispose();
    c = ProviderContainer(overrides: [
      appDatabaseProvider.overrideWithValue(db),
      pinHasherProvider.overrideWithValue(hasher),
      clockProvider.overrideWithValue(() => now),
    ]);
    c.listen(appLockProvider, (_, _) {});
    lock = c.read(appLockProvider.notifier);
    await lock.loaded;
    expect(state().locked, isTrue);
    expect(await lock.disable('1234'), UnlockResult.success);
    expect(await c.read(settingsRepositoryProvider).read('security.lock'), 'off');
  });

  test('cold start with a PIN is locked; PIN unlocks', () async {
    final lock = await start(secure: {'security.pin': await hasher.hash('1234')});
    expect(state().enabled, isTrue);
    expect(state().locked, isTrue);
    expect(await lock.unlockWithPin('0000'), UnlockResult.wrongPin);
    expect(state().locked, isTrue);
    expect(await lock.unlockWithPin('1234'), UnlockResult.success);
    expect(state().locked, isFalse);
  });

  test('setPin, relock, change and disable', () async {
    final lock = await start();
    await expectLater(lock.setPin('12'), throwsArgumentError);
    await lock.setPin('123456');
    expect(state().enabled, isTrue);
    expect(state().locked, isFalse);

    lock.lock();
    expect(state().locked, isTrue);
    expect(await lock.unlockWithPin('123456'), UnlockResult.success);

    expect(await lock.changePin('999999', '4321'), UnlockResult.wrongPin);
    expect(await lock.changePin('123456', '4321'), UnlockResult.success);
    expect(await lock.disable('123456'), UnlockResult.wrongPin);
    expect(await lock.disable('4321'), UnlockResult.success);
    expect(state().enabled, isFalse);

    lock.lock(); // no-op without a PIN
    expect(state().locked, isFalse);
  });

  test('lockout after 5 failures blocks even the right PIN until it expires', () async {
    final lock = await start(secure: {'security.pin': await hasher.hash('1234')});
    for (var i = 0; i < 4; i++) {
      expect(await lock.unlockWithPin('0000'), UnlockResult.wrongPin);
      expect(state().lockedUntil, isNull);
    }
    expect(await lock.unlockWithPin('0000'), UnlockResult.wrongPin);
    expect(state().lockedUntil, now.add(const Duration(seconds: 30)));
    expect(await lock.unlockWithPin('1234'), UnlockResult.lockedOut);
    expect(state().locked, isTrue);

    now = now.add(const Duration(seconds: 31));
    expect(await lock.unlockWithPin('1234'), UnlockResult.success);
    expect(state().lockedUntil, isNull);
    expect(state().locked, isFalse);
  });

  test('biometrics cannot be enabled when unavailable or without a PIN', () async {
    final lock = await start();
    await lock.setBiometrics(true);
    expect(state().biometricsEnabled, isFalse);
    expect(await lock.unlockWithBiometrics('reason'), isFalse);
  });
}
