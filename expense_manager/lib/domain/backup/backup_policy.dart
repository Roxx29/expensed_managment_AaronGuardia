/// Automatic backup schedule. Persisted by name in app settings.
enum BackupFrequency { off, daily, weekly, monthly }

enum BackupOrigin { manual, automatic, safety }

abstract final class BackupPolicy {
  /// Automatic backups kept; older ones are deleted. Manual backups are
  /// only deleted by the user.
  static const keepAutomatic = 10;
  static const keepSafety = 3;

  /// Whether an automatic backup should run now.
  static bool isDue(BackupFrequency frequency, DateTime? lastBackupAt, DateTime now) {
    if (frequency == BackupFrequency.off) return false;
    if (lastBackupAt == null) return true;
    final next = switch (frequency) {
      BackupFrequency.daily => DateTime(lastBackupAt.year, lastBackupAt.month, lastBackupAt.day + 1),
      BackupFrequency.weekly => DateTime(lastBackupAt.year, lastBackupAt.month, lastBackupAt.day + 7),
      // Clamped: Jan 31 → Feb 28, never skipping into March.
      BackupFrequency.monthly => DateTime(
          lastBackupAt.year,
          lastBackupAt.month + 1,
          lastBackupAt.day.clamp(1, DateTime(lastBackupAt.year, lastBackupAt.month + 2, 0).day),
        ),
      BackupFrequency.off => throw StateError('unreachable'),
    };
    return !now.isBefore(next);
  }

  /// IDs to delete so that at most [keep] backups of one origin remain.
  /// [newestFirst] must be sorted by creation date, newest first.
  static List<String> toPrune(List<String> newestFirst, int keep) =>
      newestFirst.length <= keep ? const [] : newestFirst.sublist(keep);
}
