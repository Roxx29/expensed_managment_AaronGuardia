import 'package:firebase_core/firebase_core.dart' show FirebaseException;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart' show GoogleSignInException;
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/routes.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/layout/breakpoints.dart';
import '../../../data/backup/backup_codec.dart';
import '../../../data/backup/backup_crypto.dart';
import '../../../data/database/app_database.dart';
import '../../../domain/backup/backup_policy.dart';
import '../../../domain/export/csv_export.dart';
import '../../../shared/providers/providers.dart';
import '../../../shared/widgets/common_widgets.dart';
import '../../premium/presentation/paywall_screen.dart';
import '../../wallets/application/wallet_cloud.dart';
import '../application/backup_providers.dart';
import '../application/cloud_backup.dart';

String backupErrorMessage(BuildContext context, Object error) => switch (error) {
      BackupException(error: BackupError.tooLarge) => context.tr('The file is too large to be a backup.'),
      BackupException(error: BackupError.notABackup) => context.tr('This file is not a Monchi backup.'),
      BackupException(error: BackupError.newerVersion) =>
        context.tr('This backup was made with a newer version of the app. Update the app first.'),
      BackupException(error: BackupError.corrupted) => context.tr('The backup file is damaged or incomplete.'),
      BackupException(error: BackupError.invalidData) =>
        context.tr('The backup contains invalid data. Nothing was changed.'),
      BackupException(error: BackupError.wrongPassphrase) =>
        context.tr('Wrong passphrase, or the file is damaged. Nothing was changed.'),
      CloudChanged() || LocalDataChanged() =>
        context.tr('Your data changed while syncing. Try again in a moment.'),
      FirebaseException(code: 'requires-recent-login') =>
        context.tr('For your security, sign out, sign in again and repeat.'),
      FirebaseException(code: 'not-found') => context.tr('There is no backup in the cloud yet.'),
      FirebaseException(code: 'permission-denied') =>
        context.tr('The cloud did not allow this. If it keeps happening, contact support.'),
      FirebaseException() || GoogleSignInException() =>
        context.tr('Could not connect to the cloud. Check your internet connection and try again.'),
      _ => context.tr('Something went wrong. Nothing was changed.'),
    };

String _originLabel(BuildContext context, String origin) => switch (origin) {
      'manual' => context.tr('Manual'),
      'automatic' => context.tr('Automatic'),
      'safety' => context.tr('Before restore'),
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
      // The error text needs a live context; skip it if the screen was closed.
      if (mounted) messenger.showSnackBar(SnackBar(content: Text(backupErrorMessage(context, e))));
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
          title: Text(context.tr('Restore this backup?')),
          content: Text(
            context.tr(
              'All current data will be replaced with the backup from {when}. A copy of your current data is saved first, so you can go back.',
              {'when': when},
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: Text(context.tr('Cancel'))),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(context.tr('Restore'))),
          ],
        ),
      ) ??
      false;

  /// Asks for a passphrase; [confirm] adds a second field for new ones.
  /// Returns null when cancelled.
  Future<String?> _askPassphrase({required bool confirm}) async {
    if (!mounted) return null;
    return showDialog<String>(context: context, builder: (_) => PassphraseDialog(confirm: confirm));
  }

  /// There is one cloud slot per account: confirm before replacing a copy
  /// (e.g. on a new phone that hasn't restored it yet). False = cancelled.
  Future<bool> _confirmReplaceCloud(CloudBackup cloud) async {
    final date = await cloud.backupDate();
    if (!mounted) return false;
    if (date == null) return true;
    final when = DateFormat.yMMMd(context.lang).add_jm().format(date);
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(context.tr('Replace your cloud backup?')),
            content: Text(
              context.tr(
                'The cloud backup from {when} will be replaced with the data on this phone. To bring that backup to this phone, use Restore from the cloud instead.',
                {'when': when},
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: Text(context.tr('Cancel'))),
              FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(context.tr('Replace'))),
            ],
          ),
        ) ??
        false;
  }

  /// Premium: keep this phone and the cloud copy merged (asks the passphrase
  /// once; with a cloud copy already there it must be that copy's one).
  void _setAutoUpload(bool on) {
    final cloud = ref.read(cloudBackupProvider);
    if (!on) {
      _run(() async {
        await cloud.disableAutoUpload();
        return null;
      });
      return;
    }
    if (!requirePremium(context, ref)) return;
    // Resolved now: the screen may be gone after the awaits.
    final syncedText = context.tr('Synced with the cloud');
    _run(() async {
      final passphrase = await _askPassphrase(confirm: await cloud.backupDate() == null);
      if (passphrase == null) return null;
      // Merge first (no copy is replaced): the passphrase is only kept once it worked.
      await cloud.sync(passphrase);
      await cloud.enableAutoUpload(passphrase);
      return syncedText;
    });
  }

  /// One encrypted backup per account. Uploading and restoring are free;
  /// automatic uploads are Premium.
  Widget _cloudCard(BuildContext context) {
    final cloud = ref.read(cloudBackupProvider);
    final email = ref.watch(cloudUserProvider).value;
    final autoUpload = ref.watch(cloudAutoUploadProvider).value ?? false;
    final lastUpload = ref.watch(lastCloudUploadProvider).value;
    final uploadedText = context.tr('Backup saved in the cloud');
    final restoredText = context.tr('Backup restored');
    final deletedText = context.tr('Account and cloud backup deleted');
    return SectionCard(
      title: context.tr('Cloud backup'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.tr(
              'Your data is encrypted on this phone with your passphrase before it is uploaded. Nobody else can read it, not even Monchi. If you forget the passphrase, the cloud backup cannot be opened.',
            ),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          if (email == null)
            FilledButton.tonalIcon(
              onPressed: _busy
                  ? null
                  : () => context.push(Routes.welcome),
              icon: const Icon(Icons.login_rounded),
              label: Text(context.tr('Sign in')),
            )
          else ...[
            Text(context.tr('Signed in as {email}', {'email': email})),
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: _busy
                      ? null
                      : () => _run(() async {
                            if (!await _confirmReplaceCloud(cloud)) return null;
                            final passphrase = await _askPassphrase(confirm: true);
                            if (passphrase == null) return null;
                            await cloud.upload(passphrase);
                            // Automatic uploads must keep the newest copy's passphrase.
                            if (autoUpload) await cloud.enableAutoUpload(passphrase);
                            return uploadedText;
                          }),
                  icon: const Icon(Icons.cloud_upload_rounded),
                  label: Text(context.tr('Upload to the cloud')),
                ),
                OutlinedButton.icon(
                  onPressed: _busy
                      ? null
                      : () {
                          // Restoring is free: nobody loses their own data.
                          final when = context.tr('your cloud backup');
                          _run(() async {
                            if (!await _confirmRestore(when)) return null;
                            final restored = await cloud.restore(askPassphrase: () => _askPassphrase(confirm: false));
                            return restored ? restoredText : null;
                          });
                        },
                  icon: const Icon(Icons.cloud_download_rounded),
                  label: Text(context.tr('Restore from the cloud')),
                ),
              ],
            ),
            if (lastUpload != null) ...[
              const SizedBox(height: 8),
              Text(
                context.tr('Last upload: {date}', {'date': DateFormat.yMMMd(context.lang).add_jm().format(lastUpload)}),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: autoUpload,
              onChanged: _busy ? null : _setAutoUpload,
              title: Text(context.tr('Sync automatically')),
              subtitle: Text(
                context.tr(
                  'Premium. Turn it on with the same account and passphrase on your other phones, or your partner\'s, to share the same data. It syncs when you open Monchi and the newest change wins. The passphrase stays on this phone, in secure storage.',
                ),
              ),
            ),
            if (autoUpload)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _busy
                      ? null
                      : () {
                          final syncedText = context.tr('Synced with the cloud');
                          _run(() async {
                            await cloud.syncNow();
                            return syncedText;
                          });
                        },
                  icon: const Icon(Icons.sync_rounded),
                  label: Text(context.tr('Sync now')),
                ),
              ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 4,
              children: [
                TextButton(
                  onPressed: _busy
                      ? null
                      : () => _run(() async {
                            await cloud.signOut();
                            return null;
                          }),
                  child: Text(context.tr('Sign out')),
                ),
                TextButton(
                  onPressed: _busy
                      ? null
                      : () => _run(() async {
                            if (!await _confirmDeleteAccount()) return null;
                            // Leave the shared wallets first (needs the account).
                            final wallets = ref.read(walletCloudProvider);
                            for (final w in await ref.read(walletRepositoryProvider).watchAll().first) {
                              await wallets.leave(w, strict: true);
                            }
                            await cloud.deleteAccount();
                            return deletedText;
                          }),
                  style: TextButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error),
                  child: Text(context.tr('Delete account and cloud data')),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Future<bool> _confirmDeleteAccount() async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(context.tr('Delete your cloud account?')),
          content: Text(
            context.tr(
              'Your cloud backup and your Monchi cloud account are deleted permanently. The data on this phone is kept.',
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: Text(context.tr('Cancel'))),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(context.tr('Delete'))),
          ],
        ),
      ) ??
      false;

  @override
  Widget build(BuildContext context) {
    final actions = ref.read(backupActionsProvider);
    final frequency = ref.watch(backupFrequencyProvider).value ?? BackupFrequency.off;
    final backups = ref.watch(backupsProvider).value ?? const <BackupRecord>[];
    final dateFormat = DateFormat.yMMMd(context.lang).add_jm();
    // Resolved now: the snackbar texts are used after awaits, when the screen may be gone.
    final createdText = context.tr('Backup created');
    final restoredText = context.tr('Backup restored');
    final deletedText = context.tr('Backup deleted');
    final categoryById = ref.watch(categoryByIdProvider);
    final paymentMethodById = ref.watch(paymentMethodByIdProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('Backup & restore')),
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
                title: context.tr('Automatic backup'),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SegmentedButton<BackupFrequency>(
                      showSelectedIcon: false,
                      segments: [
                        ButtonSegment(value: BackupFrequency.off, label: Text(context.tr('Off'))),
                        ButtonSegment(value: BackupFrequency.daily, label: Text(context.tr('Daily'))),
                        ButtonSegment(value: BackupFrequency.weekly, label: Text(context.tr('Weekly'))),
                        ButtonSegment(value: BackupFrequency.monthly, label: Text(context.tr('Monthly'))),
                      ],
                      selected: {frequency},
                      onSelectionChanged: (s) {
                        if (s.first == BackupFrequency.off || requirePremium(context, ref)) {
                          actions.setFrequency(s.first);
                        }
                      },
                    ),
                    const SizedBox(height: 8),
                    Text(
                      context.tr(
                        'Checked when you open the app. The last {count} automatic backups are kept.',
                        {'count': BackupPolicy.keepAutomatic},
                      ),
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
                      return createdText;
                    }),
                    icon: const Icon(Icons.backup_rounded),
                    label: Text(context.tr('Back up now')),
                  ),
                  OutlinedButton.icon(
                    onPressed: _busy
                        ? null
                        : () => _run(() async {
                              if (!await _confirmRestore(context.tr('the file you choose'))) return null;
                              final restored = await actions.restoreFromFile(
                                askPassphrase: () => _askPassphrase(confirm: false),
                              );
                              return restored ? restoredText : null;
                            }),
                    icon: const Icon(Icons.file_open_rounded),
                    label: Text(context.tr('Restore from file')),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (cloudAvailable) ...[_cloudCard(context), const SizedBox(height: 16)],
              SectionCard(
                title: context.tr('Backups on this device'),
                child: backups.isEmpty
                    ? EmptyState(icon: Icons.cloud_off_rounded, message: context.tr('No backups yet.'))
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
                              subtitle: Text('${_originLabel(context, b.origin)} · ${_size(b.sizeBytes)}'),
                              trailing: PopupMenuButton<String>(
                                tooltip: context.tr('Options'),
                                enabled: !_busy,
                                onSelected: (action) => _run(() async {
                                  switch (action) {
                                    case 'restore':
                                      if (!await _confirmRestore(dateFormat.format(b.createdAt))) return null;
                                      await actions.restore(b);
                                      return restoredText;
                                    case 'export':
                                      await actions.export(b, origin: _shareOrigin());
                                      return null;
                                    case 'exportEncrypted':
                                      if (!requirePremium(context, ref)) return null;
                                      final passphrase = await _askPassphrase(confirm: true);
                                      if (passphrase == null || !mounted) return null;
                                      await actions.exportEncrypted(b, passphrase, origin: _shareOrigin());
                                      return null;
                                    default:
                                      await actions.delete(b);
                                      return deletedText;
                                  }
                                }),
                                itemBuilder: (_) => [
                                  PopupMenuItem(value: 'restore', child: Text(context.tr('Restore'))),
                                  PopupMenuItem(value: 'exportEncrypted', child: Text(context.tr('Export encrypted'))),
                                  PopupMenuItem(
                                    value: 'export',
                                    child: Text(context.tr('Export / share (not encrypted)')),
                                  ),
                                  PopupMenuItem(value: 'delete', child: Text(context.tr('Delete'))),
                                ],
                              ),
                            ),
                        ],
                      ),
              ),
              const SizedBox(height: 16),
              SectionCard(
                title: context.tr('Export'),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.tr(
                        'A spreadsheet file with your transactions, for you or your accountant. Choose the period and the project or client. It is not encrypted.',
                      ),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: _busy
                          ? null
                          : () async {
                              if (!requirePremium(context, ref)) return;
                              // Labels resolved now, in the current UI language (no context after awaits).
                              final categories = {for (final c in categoryById.values) c.id: c.label(context)};
                              final methods = {for (final m in paymentMethodById.values) m.id: m.label(context)};
                              final choice = await showDialog<(ExportPeriod, String?)>(
                                context: context,
                                builder: (_) => _ExportDialog(projects: ref.read(projectsProvider)),
                              );
                              if (choice == null || !mounted) return;
                              _run(() async {
                                await actions.exportTransactionsCsv(
                                  categoryName: (id) => categories[id] ?? '',
                                  paymentMethodName: (id) => methods[id] ?? '',
                                  period: choice.$1,
                                  project: choice.$2,
                                  origin: _shareOrigin(),
                                );
                                return null;
                              });
                            },
                      icon: const Icon(Icons.table_view_rounded),
                      label: Text(context.tr('Export transactions (CSV)')),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              EmptyState(
                icon: Icons.lock_outline_rounded,
                message: context.tr(
                  'Each backup is also saved in Documents › backupmonchi on your phone, so it survives reinstalling the app. Those files are not encrypted: use Export encrypted to send a copy elsewhere.',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Period and project of the CSV export. Pops `(period, project)`;
/// project null = all, '' = personal only.
class _ExportDialog extends StatefulWidget {
  const _ExportDialog({required this.projects});

  final List<String> projects;

  @override
  State<_ExportDialog> createState() => _ExportDialogState();
}

class _ExportDialogState extends State<_ExportDialog> {
  ExportPeriod _period = ExportPeriod.lastMonth;
  String? _project;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(context.tr('Export transactions (CSV)')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DropdownButtonFormField<ExportPeriod>(
            initialValue: _period,
            isExpanded: true,
            decoration: InputDecoration(labelText: context.tr('Period')),
            items: [
              DropdownMenuItem(value: ExportPeriod.thisMonth, child: Text(context.tr('This month'))),
              DropdownMenuItem(value: ExportPeriod.lastMonth, child: Text(context.tr('Last month'))),
              DropdownMenuItem(value: ExportPeriod.thisYear, child: Text(context.tr('This year'))),
              DropdownMenuItem(value: ExportPeriod.all, child: Text(context.tr('Everything'))),
            ],
            onChanged: (p) => setState(() => _period = p ?? _period),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String?>(
            initialValue: _project,
            isExpanded: true,
            decoration: InputDecoration(labelText: context.tr('Project or client')),
            items: [
              DropdownMenuItem(value: null, child: Text(context.tr('All'))),
              DropdownMenuItem(value: '', child: Text(context.tr('Personal only (no project)'))),
              for (final p in widget.projects)
                DropdownMenuItem(value: p, child: Text(p, overflow: TextOverflow.ellipsis)),
            ],
            onChanged: (p) => setState(() => _project = p),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(context.tr('Cancel'))),
        FilledButton(
          onPressed: () => Navigator.pop(context, (_period, _project)),
          child: Text(context.tr('Export')),
        ),
      ],
    );
  }
}

class PassphraseDialog extends StatefulWidget {
  const PassphraseDialog({super.key, required this.confirm});

  /// True for a new passphrase (encrypting): asks twice and enforces the length.
  final bool confirm;

  @override
  State<PassphraseDialog> createState() => _PassphraseDialogState();
}

class _PassphraseDialogState extends State<PassphraseDialog> {
  final _formKey = GlobalKey<FormState>();
  final _passphrase = TextEditingController();
  final _repeat = TextEditingController();

  @override
  void dispose() {
    _passphrase.dispose();
    _repeat.dispose();
    super.dispose();
  }

  void _submit() {
    if (_formKey.currentState!.validate()) Navigator.pop(context, _passphrase.text);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.confirm ? context.tr('Encrypt backup') : context.tr('Encrypted backup')),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.confirm
                    ? context.tr(
                        'Choose a passphrase of at least {count} characters. If you forget it, the backup cannot be restored.',
                        {'count': minPassphraseLength},
                      )
                    : context.tr('Enter the passphrase used to encrypt this backup.'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _passphrase,
                autofocus: true,
                obscureText: true,
                autocorrect: false,
                enableSuggestions: false,
                textInputAction: widget.confirm ? TextInputAction.next : TextInputAction.done,
                onFieldSubmitted: widget.confirm ? null : (_) => _submit(),
                decoration: InputDecoration(labelText: context.tr('Passphrase')),
                validator: (v) {
                  final value = v ?? '';
                  if (value.isEmpty) return context.tr('Enter the passphrase.');
                  if (widget.confirm && value.length < minPassphraseLength) {
                    return context.tr('Use at least {count} characters.', {'count': minPassphraseLength});
                  }
                  return null;
                },
              ),
              if (widget.confirm) ...[
                const SizedBox(height: 12),
                TextFormField(
                  controller: _repeat,
                  obscureText: true,
                  autocorrect: false,
                  enableSuggestions: false,
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _submit(),
                  decoration: InputDecoration(labelText: context.tr('Repeat passphrase')),
                  validator: (v) => v == _passphrase.text ? null : context.tr('The passphrases do not match.'),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(context.tr('Cancel'))),
        FilledButton(onPressed: _submit, child: Text(context.tr('OK'))),
      ],
    );
  }
}
