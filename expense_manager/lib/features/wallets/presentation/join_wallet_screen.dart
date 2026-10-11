import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/layout/breakpoints.dart';
import '../../../domain/wallets/invite_code.dart';
import '../../backup/application/cloud_backup.dart';
import '../application/wallet_cloud.dart';
import 'wallets_screen.dart' show walletErrorMessage;

/// Opened by an invite link (https://monchiadmin.nubiksoft.com/join#<code>).
/// One tap joins: nobody is added to a wallet just by opening a link.
class JoinWalletScreen extends ConsumerStatefulWidget {
  const JoinWalletScreen({super.key, required this.link});

  /// The whole link; the code is found anywhere in it (its #fragment).
  final String link;

  @override
  ConsumerState<JoinWalletScreen> createState() => _JoinWalletScreenState();
}

class _JoinWalletScreenState extends ConsumerState<JoinWalletScreen> {
  bool _busy = false;

  Future<void> _join() async {
    if (_busy) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);
    try {
      final wallet = await ref.read(walletCloudProvider).join(widget.link);
      if (!mounted) return;
      router.pushReplacement(Routes.wallet(wallet.id));
    } on Object catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      messenger.showSnackBar(SnackBar(content: Text(walletErrorMessage(context, e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final valid = parseInviteCode(widget.link) != null;
    final email = ref.watch(cloudUserProvider).value;
    Widget action;
    if (!valid) {
      action = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(context.tr('This invite link is incomplete. Ask for a new one, or paste the code in Wallets › Join with a code.')),
          const SizedBox(height: 16),
          FilledButton(onPressed: () => context.go(Routes.wallets), child: Text(context.tr('Go to Wallets'))),
        ],
      );
    } else if (email == null) {
      action = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(context.tr('Sign in first. Then you join with one tap.')),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: cloudAvailable ? () => context.push(Routes.welcome) : null,
            icon: const Icon(Icons.login_rounded),
            label: Text(context.tr('Sign in')),
          ),
        ],
      );
    } else {
      action = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(context.tr('You will join as {email}. The other members will see your name.', {'email': email})),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _busy ? null : _join,
            icon: _busy
                ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.group_add_rounded),
            label: Text(context.tr('Join the wallet')),
          ),
        ],
      );
    }
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('Join a wallet'))),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: Breakpoints.medium),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Icon(Icons.account_balance_wallet_rounded, size: 56, color: theme.colorScheme.primary),
              const SizedBox(height: 16),
              Text(
                context.tr('You were invited to a shared wallet'),
                textAlign: TextAlign.center,
                style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 24),
              action,
            ],
          ),
        ),
      ),
    );
  }
}
