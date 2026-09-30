import 'package:drift/drift.dart';

import '../../core/money/currency.dart';
import '../../core/utils/validators.dart';
import '../../domain/entities/entities.dart';
import '../../domain/repositories/repositories.dart';
import '../database/app_database.dart';
import '../database/default_data.dart';

class DriftProfileRepository implements ProfileRepository {
  DriftProfileRepository(this._db);

  final AppDatabase _db;

  @override
  Stream<Profile> watch() =>
      (_db.select(_db.profiles)..where((p) => p.id.equals(localProfileId)))
          .watchSingleOrNull()
          .map((r) => r == null
              // Seeded on first launch; the fallback only covers a restore gap.
              ? const Profile(id: localProfileId, currency: Currency.fallback)
              : Profile(
                  id: r.id,
                  name: r.name,
                  email: r.email,
                  avatarPath: r.avatarPath,
                  countryCode: r.countryCode,
                  currency: Currency.fromCode(r.currencyCode),
                ));

  @override
  Future<void> save(Profile profile) {
    final email = profile.email?.trim();
    if (email != null && email.isNotEmpty && !emailPattern.hasMatch(email)) {
      throw ArgumentError('invalid email', 'email');
    }
    return _db.into(_db.profiles).insertOnConflictUpdate(
          ProfilesCompanion.insert(
            id: profile.id,
            name: Value(profile.name.trim()),
            email: Value(email == null || email.isEmpty ? null : email),
            avatarPath: Value(profile.avatarPath),
            countryCode: Value(profile.countryCode),
            currencyCode: profile.currency.code,
            updatedAt: Value(DateTime.now()),
          ),
        );
  }
}

class DriftSettingsRepository implements SettingsRepository {
  DriftSettingsRepository(this._db);

  final AppDatabase _db;

  SimpleSelectStatement<$AppSettingsTable, SettingRecord> _byKey(String key) =>
      _db.select(_db.appSettings)..where((s) => s.key.equals(key));

  @override
  Stream<String?> watch(String key) =>
      _byKey(key).watchSingleOrNull().map((r) => r?.value);

  @override
  Future<String?> read(String key) async =>
      (await _byKey(key).getSingleOrNull())?.value;

  @override
  Future<void> write(String key, String value) => _db
      .into(_db.appSettings)
      .insertOnConflictUpdate(AppSettingsCompanion.insert(key: key, value: value));
}
