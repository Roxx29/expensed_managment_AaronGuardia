import 'package:firebase_auth/firebase_auth.dart' show FirebaseAuthException;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/l10n/l10n.dart';
import '../../data/backup/backup_storage.dart';
import '../../shared/providers/providers.dart';
import '../backup/application/backup_providers.dart';
import '../backup/application/cloud_backup.dart';
import '../backup/application/email_verification.dart';
import '../backup/presentation/backup_screen.dart' show PassphraseDialog, backupErrorMessage;
import '../premium/application/gift_providers.dart';
import '../profile/application/profile_providers.dart';

const _skippedKey = 'welcome.skipped';
const _doneKey = 'welcome.done';

/// The sign-in page opens on launch while signed out, until the user picks
/// "Continue without an account". Without Firebase (tests, local builds) it
/// only opens once, on a fresh install with a backup to restore.
final showWelcomeProvider = FutureProvider<bool>((ref) async {
  try {
    final settings = ref.read(settingsRepositoryProvider);
    if (cloudAvailable) {
      return await settings.read(_skippedKey) != '1' && await ref.read(cloudUserProvider.future) == null;
    }
    if (await settings.read(_doneKey) == '1') return false;
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

enum _Mode { signIn, register }

/// Account page: sign in with e-mail or Google, create an account, reset the
/// password; on a fresh install it also finds previous data (a backup file
/// Android restored, or the account's cloud backup) and offers to restore it.
class WelcomeScreen extends ConsumerStatefulWidget {
  const WelcomeScreen({super.key});

  @override
  ConsumerState<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends ConsumerState<WelcomeScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _password2 = TextEditingController();
  _Mode _mode = _Mode.signIn;
  bool _showPassword = false;
  bool _busy = false;
  bool _fresh = false; // nothing saved yet on this install
  bool _searchedCloud = false;
  _Found? _found;

  CloudBackup get _cloud => ref.read(cloudBackupProvider);

  @override
  void initState() {
    super.initState();
    if (!cloudAvailable) ref.read(settingsRepositoryProvider).write(_doneKey, '1');
    _searchLocal();
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    _password2.dispose();
    super.dispose();
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
    final date = await _cloud.backupDate();
    if (!mounted) return;
    setState(() {
      _searchedCloud = true;
      if (date != null) _found = _Found.cloud(date);
    });
  }

  String _authError(BuildContext context, Object e) => switch (e) {
        FirebaseAuthException(code: 'invalid-credential' || 'wrong-password' || 'user-not-found') =>
          context.tr('Wrong e-mail or password.'),
        FirebaseAuthException(code: 'email-already-in-use') =>
          context.tr('There is already an account with this e-mail. Sign in instead.'),
        FirebaseAuthException(code: 'weak-password') => context.tr('Use at least 6 characters.'),
        FirebaseAuthException(code: 'invalid-email') => context.tr('Enter a valid e-mail.'),
        FirebaseAuthException(code: 'too-many-requests') => context.tr('Too many attempts. Try again in a few minutes.'),
        FirebaseAuthException(code: 'network-request-failed') =>
          context.tr('Could not connect to the cloud. Check your internet connection and try again.'),
        _ => backupErrorMessage(context, e),
      };

  /// Runs [task] with a progress bar; its result (or the error) is shown in a snackbar.
  Future<void> _run(Future<String?> Function() task) async {
    if (_busy) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final message = await task();
      if (message != null) messenger.showSnackBar(SnackBar(content: Text(message)));
    } on Object catch (e) {
      if (mounted) messenger.showSnackBar(SnackBar(content: Text(_authError(context, e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _afterSignIn() async {
    if (_fresh) await _searchCloud();
    if (!_fresh && mounted && _cloud.emailVerified) _close();
  }

  void _submit() {
    if (!_form.currentState!.validate()) return;
    final email = _email.text, password = _password.text, name = _name.text.trim();
    final checkInbox = context.tr('We sent you an e-mail to verify your account. Open the link, then come back.');
    _run(() async {
      if (_mode == _Mode.register) {
        await _cloud.register(email, password, name);
        await ref.read(profileActionsProvider).setName(name);
        await _afterSignIn();
        return checkInbox;
      }
      await _cloud.signInWithEmail(email, password);
      await _afterSignIn();
      return null;
    });
  }

  void _forgotPassword() {
    final email = _email.text.trim();
    if (!_validEmail(email)) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.tr('Write your e-mail first.'))));
      return;
    }
    final sent = context.tr('If there is an account with this e-mail, we sent you a link to change your password.');
    _run(() async {
      await _cloud.resetPassword(email);
      return sent;
    });
  }

  static bool _validEmail(String v) => RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v.trim());

  Future<String?> _passphrase() async {
    if (!mounted) return null;
    return showDialog<String>(context: context, builder: (_) => const PassphraseDialog(confirm: false));
  }

  void _close() {
    if (Navigator.of(context).canPop()) Navigator.of(context).pop();
  }

  Future<String?> _restoreFound(_Found found, String restoredText) async {
    if (found.cloud) {
      if (!await _cloud.restore(askPassphrase: _passphrase)) return null;
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
    ref.listen(emailVerifiedProvider, (previous, next) {
      if (previous?.value == false && next.value == true) {
        ref.invalidate(giftPremiumProvider);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.tr('Your e-mail is verified.'))));
      }
    });
    final restoredText = context.tr('Backup restored');
    final found = _found;
    final when = found?.date == null ? '' : DateFormat.yMMMd(context.lang).add_jm().format(found!.date!);
    const gap = SizedBox(height: 12);

    return Scaffold(
      appBar: AppBar(automaticallyImplyLeading: Navigator.of(context).canPop()),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              shrinkWrap: true,
              children: [
                Image.asset('assets/brand/monchi_mark.png', height: 88),
                gap,
                Text(
                  email == null ? context.tr('Welcome to Monchi') : context.tr('Your account'),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 6),
                Text(
                  context.tr('Your money, clear and only yours. Sign in to keep Premium and your cloud backup with you.'),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 20),
                if (found != null) ...[
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
                          gap,
                          FilledButton.icon(
                            onPressed: _busy ? null : () => _run(() => _restoreFound(found, restoredText)),
                            icon: const Icon(Icons.restore_rounded),
                            label: Text(context.tr('Restore it')),
                          ),
                        ],
                      ),
                    ),
                  ),
                  gap,
                ],
                if (cloudAvailable && email == null) ..._signInForm(context),
                if (email != null) ..._account(context, email),
                if (email != null && _fresh && _searchedCloud && found == null)
                  Text(
                    context.tr('There is no backup in the cloud yet.'),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall,
                  ),
                gap,
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
                if (email == null)
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () {
                            ref.read(settingsRepositoryProvider).write(_skippedKey, '1');
                            _close();
                          },
                    child: Text(context.tr('Continue without an account')),
                  ),
                if (_busy) const LinearProgressIndicator(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _signInForm(BuildContext context) {
    final register = _mode == _Mode.register;
    return [
      SegmentedButton<_Mode>(
        showSelectedIcon: false,
        segments: [
          ButtonSegment(value: _Mode.signIn, label: Text(context.tr('Sign in'))),
          ButtonSegment(value: _Mode.register, label: Text(context.tr('Create account'))),
        ],
        selected: {_mode},
        onSelectionChanged: (s) => setState(() => _mode = s.first),
      ),
      const SizedBox(height: 12),
      Form(
        key: _form,
        child: AutofillGroup(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (register) ...[
                // Required: other wallet members and our support see this name.
                TextFormField(
                  controller: _name,
                  maxLength: 60,
                  textCapitalization: TextCapitalization.words,
                  autofillHints: const [AutofillHints.name],
                  decoration: InputDecoration(labelText: context.tr('Your name'), prefixIcon: const Icon(Icons.person_rounded)),
                  validator: (v) => (v ?? '').trim().isEmpty ? context.tr('Write your name.') : null,
                ),
                const SizedBox(height: 8),
              ],
              TextFormField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
                decoration: InputDecoration(labelText: context.tr('E-mail'), prefixIcon: const Icon(Icons.mail_rounded)),
                validator: (v) => _validEmail(v ?? '') ? null : context.tr('Enter a valid e-mail.'),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _password,
                obscureText: !_showPassword,
                autofillHints: [register ? AutofillHints.newPassword : AutofillHints.password],
                decoration: InputDecoration(
                  labelText: context.tr('Password'),
                  prefixIcon: const Icon(Icons.lock_rounded),
                  suffixIcon: IconButton(
                    tooltip: _showPassword ? context.tr('Hide password') : context.tr('Show password'),
                    icon: Icon(_showPassword ? Icons.visibility_off_rounded : Icons.visibility_rounded),
                    onPressed: () => setState(() => _showPassword = !_showPassword),
                  ),
                ),
                validator: (v) => (v ?? '').length < 6 ? context.tr('Use at least 6 characters.') : null,
                onFieldSubmitted: register ? null : (_) => _submit(),
              ),
              if (register) ...[
                const SizedBox(height: 8),
                TextFormField(
                  controller: _password2,
                  obscureText: !_showPassword,
                  decoration: InputDecoration(
                    labelText: context.tr('Repeat the password'),
                    prefixIcon: const Icon(Icons.lock_rounded),
                  ),
                  validator: (v) => v == _password.text ? null : context.tr('The passwords do not match.'),
                  onFieldSubmitted: (_) => _submit(),
                ),
              ],
            ],
          ),
        ),
      ),
      if (!register)
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: _busy ? null : _forgotPassword,
            child: Text(context.tr('Forgot your password?')),
          ),
        )
      else
        const SizedBox(height: 12),
      FilledButton(
        onPressed: _busy ? null : _submit,
        child: Text(register ? context.tr('Create account') : context.tr('Sign in')),
      ),
      const SizedBox(height: 12),
      Row(children: [
        const Expanded(child: Divider()),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: Text(context.tr('or'))),
        const Expanded(child: Divider()),
      ]),
      const SizedBox(height: 12),
      OutlinedButton.icon(
        onPressed: _busy
            ? null
            : () => _run(() async {
                  if (await _cloud.signIn()) await _afterSignIn();
                  return null;
                }),
        icon: const Icon(Icons.login_rounded),
        label: Text(context.tr('Continue with Google')),
      ),
    ];
  }

  List<Widget> _account(BuildContext context, String email) {
    // Updates by itself when the link is opened (email_verification.dart).
    final verified = ref.watch(emailVerifiedProvider).value ?? _cloud.emailVerified;
    final resent = context.tr('We sent you an e-mail to verify your account. Open the link, then come back.');
    final stillPending = context.tr('Your e-mail is not verified yet.');
    return [
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.account_circle_rounded, size: 36),
        title: Text(email),
        subtitle: Text(verified ? context.tr('Signed in') : context.tr('Your e-mail is not verified yet.')),
      ),
      if (!verified)
        Wrap(
          spacing: 8,
          children: [
            FilledButton.tonal(
              onPressed: _busy
                  ? null
                  : () => _run(() async {
                        await _cloud.reloadUser();
                        if (!_cloud.emailVerified) return stillPending;
                        ref.invalidate(giftPremiumProvider);
                        return null;
                      }),
              child: Text(context.tr('I already verified it')),
            ),
            TextButton(
              onPressed: _busy
                  ? null
                  : () => _run(() async {
                        await _cloud.resendVerification();
                        return resent;
                      }),
              child: Text(context.tr('Send the e-mail again')),
            ),
          ],
        ),
      const SizedBox(height: 8),
      FilledButton(onPressed: _busy ? null : _close, child: Text(context.tr('Continue'))),
      TextButton(
        onPressed: _busy
            ? null
            : () => _run(() async {
                  await _cloud.signOut();
                  return null;
                }),
        child: Text(context.tr('Sign out')),
      ),
    ];
  }
}
