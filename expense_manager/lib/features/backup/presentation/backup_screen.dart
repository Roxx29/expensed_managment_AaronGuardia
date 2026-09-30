import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/layout/breakpoints.dart';
import '../../../data/backup/backup_codec.dart';
import '../../../data/database/app_database.dart';
import '../../../domain/backup/backup_policy.dart';
import '../../../shared/widgets/common_widgets.dart';
import '../application/backup_providers.dart';

String _errorMessage(Object error) => switch (error) {
      BackupException(error: BackupError.tooLarge) => 'The file is too large to be a backup.',
      BackupException(error: BackupError.notABackup) => 'This file is not an Expense Manager backup.',
      BackupException(error: BackupError.newerVersion) =>
        'This backup was made with a newer version of the app. Update the app first.',
      BackupException(error: BackupError.corrupted) => 'The backup file is damaged or incomplete.',
      BackupException(error: BackupError.invalidData) => 'The backup contains invalid data. Nothing was changed.',
      _ => 'Something went wrong. Nothing was changed.',
    };

String _originLabel(String origin) => switch (origin) {
      'manual' => 'Manual',
      'automatic' => 'Automatic',
      'safety' => 'Before restore',
      _ => origin,
    };

String _size(int bytes) =>
    bytes < 1024 * 1024 ? '${(bytes / 1024).ceil()} KB' : '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';

class BackupScreen extends ConsumerStatefulWidget {
  const BackupScreen({super.key});

  @override
  ConsumerState<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends ConsumerState<BackupScreen> {
  bool _busy = false;

  /// Runs [task] with a progress indicator and reports the outcome.
  Future<void> _run(Future<String?> Function() task) async {
    if (_busy) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final message = await task();
      if (message != null) messenger.showSnackBar(SnackBar(content: Text(message)));
    } on Object catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(_errorMessage(e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Screen rect used as the share-sheet anchor on iPad.
  Rect? _shareOrigin() {
    final box = context.findRenderObject() as RenderBox?;
    return box == null ? null : box.localToGlobal(Offset.zero) & box.size;
  }

  Future<bool> _confirmRestore(String when) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Restore this backup?'),
          content: Text(
            'All current data will be replaced with the backup from $when. '
            'A copy of your current data is saved first, so you can go back.',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Restore')),
          ],
        ),
      ) ??
      false;

  @override
  Widget build(BuildContext context) {
    final actions = ref.read(backupActionsProvider);
    final frequency = ref.watch(backupFrequencyProvider).value ?? BackupFrequency.off;
    final backups = ref.watch(backupsProvider).value ?? const <BackupRecord>[];
    final dateFormat = DateFormat.yMMMd().add_jm();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Backup & restore'),
        bottom: _busy ? const PreferredSize(preferredSize: Size.fromHeight(4), child: LinearProgressIndicator()) : null,
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: Breakpoints.expanded),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              SectionCard(
                title: 'Automatic backup',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SegmentedButton<BackupFrequency>(
                      showSelectedIcon: false,
                      segments: const [
                        ButtonSegment(value: BackupFrequency.off, label: Text('Off')),
                        ButtonSegment(value: BackupFrequency.daily, label: Text('Daily')),
                        ButtonSegment(value: BackupFrequency.weekly, label: Text('Weekly')),
                        ButtonSegment(value: BackupFrequency.monthly, label: Text('Monthly')),
                      ],
                      selected: {frequency},
                      onSelectionChanged: (s) => actions.setFrequency(s.first),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Checked when you open the app. The last ${BackupPolicy.keepAutomatic} automatic backups are kept.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: _busy ? null : () => _run(() async {
                      await actions.backupNow();
                      return 'Backup created';
                    }),
                    icon: const Icon(Icons.backup_rounded),
                    label: const Text('Back up now'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _busy
                        ? null
                        : () => _run(() async {
                              if (!await _confirmRestore('the file you choose')) return null;
                              return await actions.restoreFromFile() ? 'Backup restored' : null;
                            }),
                    icon: const Icon(Icons.file_open_rounded),
                    label: const Text('Restore from file'),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              SectionCard(
                title: 'Backups on this device',
                child: backups.isEmpty
                    ? const EmptyState(icon: Icons.cloud_off_rounded, message: 'No backups yet.')
                    : Column(
                        children: [
                          for (final b in backups)
                            ListTile(
                              key: ValueKey(b.id),
                              contentPadding: EdgeInsets.zero,
                              leading: Icon(
                                b.origin == 'automatic' ? Icons.schedule_rounded : Icons.save_rounded,
                              ),
                              title: Text(dateFormat.format(b.createdAt)),
                              subtitle: Text('${_originLabel(b.origin)} · ${_size(b.sizeBytes)}'),
                              trailing: PopupMenuButton<String>(
                                tooltip: 'Options',
                                enabled: !_busy,
                                onSelected: (action) => _run(() async {
                                  switch (action) {
                                    case 'restore':
                                      if (!await _confirmRestore(dateFormat.format(b.createdAt))) return null;
                                      await actions.restore(b);
                                      return 'Backup restored';
                                    case 'export':
                                      await actions.export(b, origin: _shareOrigin());
                                      return null;
                                    default:
                                      await actions.delete(b);
                                      return 'Backup deleted';
                                  }
                                }),
                                itemBuilder: (_) => const [
                                  PopupMenuItem(value: 'restore', child: Text('Restore')),
                                  PopupMenuItem(value: 'export', child: Text('Export / share')),
                                  PopupMenuItem(value: 'delete', child: Text('Delete')),
                                ],
                              ),
                            ),
                        ],
                      ),
              ),
              const SizedBox(height: 12),
              const EmptyState(
                icon: Icons.lock_outline_rounded,
                message: 'Backup files are not encrypted. Keep exported copies in a private place. '
                    'Export a backup before changing or resetting your phone.',
              ),
            ],
          ),
        ),
      ),
    );
  }
}
