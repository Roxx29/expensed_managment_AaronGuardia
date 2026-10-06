import 'package:firebase_core/firebase_core.dart' show FirebaseException;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/layout/breakpoints.dart';
import '../../../domain/entities/entities.dart';
import '../../../shared/widgets/common_widgets.dart';
import '../../backup/application/cloud_backup.dart';
import '../../premium/presentation/paywall_screen.dart';
import '../application/wallet_cloud.dart';
import '../application/wallet_providers.dart';
import 'wallet_widgets.dart';

/// Message for a failed wallet action.
String walletErrorMessage(BuildContext context, Object error) => switch (error) {
      NotSignedIn() => context.tr('Sign in to use shared wallets.'),
      InvalidInvite() => context.tr('This invite code is not valid or the wallet no longer exists.'),
      FirebaseException(code: 'permission-denied') =>
        context.tr('This invite code is not valid or the wallet no longer exists.'),
      _ => context.tr('Could not connect to the cloud. Check your internet connection and try again.'),
    };

/// Wallets (Carteras): shared business/family wallets — list, new, join.
class WalletsScreen extends ConsumerStatefulWidget {
  const WalletsScreen({super.key});

  @override
  ConsumerState<WalletsScreen> createState() => _WalletsScreenState();
}

class _WalletsScreenState extends ConsumerState<WalletsScreen> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() task) async {
    if (_busy) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await task();
    } on Object catch (e) {
      if (mounted) messenger.showSnackBar(SnackBar(content: Text(walletErrorMessage(context, e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Wallets need an account: signed-out users go to the sign-in page.
  bool _requireAccount() {
    if (ref.read(cloudUserProvider).value != null) return true;
    context.push(Routes.welcome);
    return false;
  }

  Future<void> _create() async {
    if (!_requireAccount() || !requirePremium(context, ref)) return;
    final result = await showDialog<(String, WalletKind)>(context: context, builder: (_) => const _NewWalletDialog());
    if (result == null || !mounted) return;
    await _run(() async {
      final wallet = await ref.read(walletCloudProvider).create(result.$1, result.$2);
      if (mounted) context.push(Routes.wallet(wallet.id));
    });
  }

  Future<void> _join() async {
    if (!_requireAccount()) return;
    final code = await showDialog<String>(context: context, builder: (_) => const _JoinDialog());
    if (code == null || !mounted) return;
    await _run(() async {
      final wallet = await ref.read(walletCloudProvider).join(code);
      if (mounted) context.push(Routes.wallet(wallet.id));
    });
  }

  @override
  Widget build(BuildContext context) {
    final wallets = ref.watch(walletsProvider).value ?? const <Wallet>[];
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('Wallets')),
        bottom: _busy ? const PreferredSize(preferredSize: Size.fromHeight(4), child: LinearProgressIndicator()) : null,
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: Breakpoints.expanded),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                context.tr(
                  'Share a wallet with your business partners or your family: everyone records income and expenses, and you see who did it. Everything is encrypted on the phones.',
                ),
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              if (!cloudAvailable)
                EmptyState(
                  icon: Icons.cloud_off_rounded,
                  message: context.tr('Shared wallets need the Android app with Google Play services.'),
                )
              else ...[
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    FilledButton.icon(
                      onPressed: _busy ? null : _create,
                      icon: const Icon(Icons.add_rounded),
                      label: Text(context.tr('New wallet')),
                    ),
                    OutlinedButton.icon(
                      onPressed: _busy ? null : _join,
                      icon: const Icon(Icons.group_add_rounded),
                      label: Text(context.tr('Join with a code')),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                if (wallets.isEmpty)
                  EmptyState(
                    icon: Icons.account_balance_wallet_outlined,
                    message: context.tr('No shared wallets yet. Create one for your business or family, or join one with an invite code.'),
                  ),
                for (final w in wallets)
                  Card(
                    child: ListTile(
                      leading: Icon(walletIcon(w.kind)),
                      title: Text(w.name),
                      subtitle: WalletMonthLine(summary: ref.watch(walletMonthSummaryProvider(w.id))),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => context.push(Routes.wallet(w.id)),
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _NewWalletDialog extends StatefulWidget {
  const _NewWalletDialog();

  @override
  State<_NewWalletDialog> createState() => _NewWalletDialogState();
}

class _NewWalletDialogState extends State<_NewWalletDialog> {
  final _name = TextEditingController();
  WalletKind _kind = WalletKind.business;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _name.text.trim();
    if (name.isNotEmpty) Navigator.pop(context, (name, _kind));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(context.tr('New wallet')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SegmentedButton<WalletKind>(
            showSelectedIcon: false,
            segments: [
              for (final k in WalletKind.values)
                ButtonSegment(value: k, icon: Icon(walletIcon(k)), label: Text(walletKindLabel(context, k))),
            ],
            selected: {_kind},
            onSelectionChanged: (s) => setState(() => _kind = s.first),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _name,
            autofocus: true,
            maxLength: 50,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(labelText: context.tr('Name (e.g. My shop, Home)')),
            onSubmitted: (_) => _submit(),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(context.tr('Cancel'))),
        FilledButton(onPressed: _submit, child: Text(context.tr('Create'))),
      ],
    );
  }
}

class _JoinDialog extends StatefulWidget {
  const _JoinDialog();

  @override
  State<_JoinDialog> createState() => _JoinDialogState();
}

class _JoinDialogState extends State<_JoinDialog> {
  final _code = TextEditingController();

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _paste() async {
    final text = (await Clipboard.getData(Clipboard.kTextPlain))?.text;
    if (text != null) _code.text = text;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(context.tr('Join a wallet')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(context.tr('Paste the invite code (or the whole message) you received.')),
          const SizedBox(height: 12),
          TextField(
            controller: _code,
            minLines: 1,
            maxLines: 4,
            maxLength: 1000,
            decoration: InputDecoration(
              labelText: context.tr('Invite code'),
              suffixIcon: IconButton(
                tooltip: context.tr('Paste'),
                icon: const Icon(Icons.content_paste_rounded),
                onPressed: _paste,
              ),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(context.tr('Cancel'))),
        FilledButton(onPressed: () => Navigator.pop(context, _code.text), child: Text(context.tr('Join'))),
      ],
    );
  }
}
