import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/l10n/l10n.dart';
import '../../data/backup/backup_storage.dart';
import '../../shared/providers/providers.dart';
import '../backup/application/backup_providers.dart';
import '../backup/application/cloud_backup.dart';
import '../backup/presentation/backup_screen.dart' show PassphraseDialog;

const _doneKey = 'welcome.done';

/// Shown once: on a fresh install with something to restore, or whenever
/// Google sign-in is available. Never in tests (no Android, no Firebase).
final showWelcomeProvider = FutureProvider<bool>((ref) async {
  try {
    final settings = ref.read(settingsRepositoryProvider);
    if (await settings.read(_doneKey) == '1') return false;
    if (cloudAvailable) return await ref.read(cloudUserProvider.future) == null;
    final actions = ref.read(backupActionsProvider);
    return await actions.hasNoData() && await actions.newestStoredFile() != null;
  } on Object {
    return false;
  }
});

/// A previous backup the app found by itself.
class _Found {
  const _Found.local(this.fileName, this.date) : cloud = false;
  const _Found.cloud(this.date)
      : cloud = true,
        fileName = null;

  final bool cloud;
  final String? fileName;
  final DateTime? date;
}

/// Sign in with Google and get previous data back: a backup Android kept
/// in the app folder, the cloud backup of the account, or a file.
class WelcomeScreen extends ConsumerStatefulWidget {
  const WelcomeScreen({super.key});

  @override
  ConsumerState<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends ConsumerState<WelcomeScreen> {
  bool _busy = false;
  bool _fresh = false; // nothing saved yet on this install
  _Found? _found;
  bool _searchedCloud = false;

  @override
  void initState() {
    super.initState();
    ref.read(settingsRepositoryProvider).write(_doneKey, '1');
    _searchLocal();
  }

  Future<void> _searchLocal() async {
    final actions = ref.read(backupActionsProvider);
    try {
      _fresh = await actions.hasNoData();
      final name = _fresh ? await actions.newestStoredFile() : null;
      if (name != null && mounted) setState(() => _found = _Found.local(name, backupNameDate(name)));
      if (_fresh && cloudAvailable && await ref.read(cloudUserProvider.future) != null) await _searchCloud();
    } on Object {
      // Nothing found is fine: the user can still pick a file.
    }
  }

  Future<void> _searchCloud() async {
    final date = await ref.read(cloudBackupProvider).backupDate();
    if (!mounted) return;
    setState(() {
      _searchedCloud = true;
      if (date != null) _found = _Found.cloud(date);
    });
  }

  Future<void> _run(Future<String?> Function() task) async {
    if (_busy) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    final failed = context.tr('Something went wrong. Nothing was changed.');
    try {
      final message = await task();
      if (message != null) messenger.showSnackBar(SnackBar(content: Text(message)));
    } on Object {
      messenger.showSnackBar(SnackBar(content: Text(failed)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String?> _passphrase() => showDialog<String>(context: context, builder: (_) => const PassphraseDialog(confirm: false));

  void _close() => Navigator.of(context).pop();

  Future<String?> _restoreFound(_Found found, String restoredText) async {
    if (found.cloud) {
      if (!await ref.read(cloudBackupProvider).restore(askPassphrase: _passphrase)) return null;
    } else {
      await ref.read(backupActionsProvider).restoreStoredFile(found.fileName!);
    }
    if (mounted) _close();
    return restoredText;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final email = ref.watch(cloudUserProvider).value;
    final restoredText = context.tr('Backup restored');
    final found = _found;
    final when = found?.date == null ? '' : DateFormat.yMMMd(context.lang).add_jm().format(found!.date!);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: ListView(
              padding: const EdgeInsets.all(24),
              shrinkWrap: true,
              children: [
                Image.asset('assets/brand/monchi_mark.png', height: 96),
                const SizedBox(height: 16),
                Text(
                  context.tr('Welcome to Monchi'),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                Text(
                  context.tr('Your money, clear and only yours. Sign in with Google to keep Premium and your cloud backup with you.'),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 24),
                if (found != null)
                  Card(
                    color: theme.colorScheme.primaryContainer,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            found.cloud
                                ? context.tr('We found your cloud backup from {when}.', {'when': when})
                                : context.tr('We found a backup saved on this phone from {when}.', {'when': when}),
                            style: theme.textTheme.titleSmall,
                          ),
                          const SizedBox(height: 12),
                          FilledButton.icon(
                            onPressed: _busy ? null : () => _run(() => _restoreFound(found, restoredText)),
                            icon: const Icon(Icons.restore_rounded),
                            label: Text(context.tr('Restore it')),
                          ),
                        ],
                      ),
                    ),
                  ),
                if (cloudAvailable && email == null)
                  FilledButton.icon(
                    onPressed: _busy
                        ? null
                        : () => _run(() async {
                              if (await ref.read(cloudBackupProvider).signIn() && _fresh) await _searchCloud();
                              return null;
                            }),
                    icon: const Icon(Icons.login_rounded),
                    label: Text(context.tr('Sign in with Google')),
                  ),
                if (email != null)
                  Text(
                    context.tr('Signed in as {email}', {'email': email}),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall,
                  ),
                if (email != null && _fresh && _searchedCloud && found == null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      context.tr('There is no backup in the cloud yet.'),
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _busy
                      ? null
                      : () => _run(() async {
                            final restored =
                                await ref.read(backupActionsProvider).restoreFromFile(askPassphrase: _passphrase);
                            if (!restored) return null;
                            if (mounted) _close();
                            return restoredText;
                          }),
                  icon: const Icon(Icons.file_open_rounded),
                  label: Text(context.tr('Restore from a backup file')),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: _busy ? null : _close,
                  child: Text(email == null && cloudAvailable ? context.tr('Continue without an account') : context.tr('Continue')),
                ),
                if (_busy) const LinearProgressIndicator(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
