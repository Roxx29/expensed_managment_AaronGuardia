import 'package:firebase_core/firebase_core.dart' show FirebaseException;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/layout/breakpoints.dart';
import '../../../core/theme/app_theme.dart';
import '../../../domain/entities/entities.dart';
import '../../../domain/finance/summary_calculator.dart';
import '../../../shared/providers/providers.dart';
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
      RemovedFromWallet() => context.tr('You are no longer a member of this wallet. You can leave it.'),
      NotWalletOwner() => context.tr('Only the owner of the wallet can do this.'),
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
    final result = await showDialog<(String, WalletKind)>(context: context, builder: (_) => const WalletEditDialog());
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

  Future<void> _setMain(String id) => ref.read(settingsRepositoryProvider).write(mainWalletKey, id);

  @override
  Widget build(BuildContext context) {
    final wallets = ref.watch(walletsProvider).value ?? const <Wallet>[];
    final mainId = ref.watch(mainWalletIdProvider);
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
                  )
                else ...[
                _WalletTile(
                  icon: Icons.person_rounded,
                  title: context.tr('Personal'),
                  summary: ref.watch(personalMonthSummaryProvider),
                  isMain: mainId == null,
                  onMain: () => _setMain(''),
                  onTap: () => context.go(Routes.transactions),
                ),
                for (final w in wallets)
                  _WalletTile(
                    icon: walletIcon(w.kind),
                    title: w.name,
                    summary: ref.watch(walletMonthSummaryProvider(w.id)),
                    isMain: mainId == w.id,
                    onMain: () => _setMain(w.id),
                    onTap: () => context.push(Routes.wallet(w.id)),
                  ),
                const SizedBox(height: 8),
                Text(
                  context.tr('The star marks your main wallet: Home shows it first and new entries go there.'),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Name and type of a new wallet, or of an existing one ([initialName]).
class WalletEditDialog extends StatefulWidget {
  const WalletEditDialog({super.key, this.initialName, this.initialKind = WalletKind.business});

  final String? initialName;
  final WalletKind initialKind;

  @override
  State<WalletEditDialog> createState() => _WalletEditDialogState();
}

class _WalletEditDialogState extends State<WalletEditDialog> {
  late final _name = TextEditingController(text: widget.initialName ?? '');
  late WalletKind _kind = widget.initialKind;

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
      scrollable: true,
      title: Text(widget.initialName == null ? context.tr('New wallet') : context.tr('Edit wallet')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final k in WalletKind.values)
                ChoiceChip(
                  avatar: Icon(walletIcon(k), size: 18),
                  label: Text(walletKindLabel(context, k)),
                  showCheckmark: false,
                  selected: _kind == k,
                  onSelected: (_) => setState(() => _kind = k),
                ),
            ],
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
        FilledButton(
          onPressed: _submit,
          child: Text(widget.initialName == null ? context.tr('Create') : context.tr('Save')),
        ),
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
      scrollable: true,
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

/// A wallet in the list: this month's line, the main-wallet star and open.
class _WalletTile extends StatelessWidget {
  const _WalletTile({
    required this.icon,
    required this.title,
    required this.summary,
    required this.isMain,
    required this.onMain,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final MonthSummary? summary;
  final bool isMain;
  final VoidCallback onMain;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: isMain ? scheme.primaryContainer : scheme.surfaceContainerHighest,
          child: Icon(icon, color: isMain ? scheme.onPrimaryContainer : scheme.onSurfaceVariant),
        ),
        title: Text(title, overflow: TextOverflow.ellipsis),
        subtitle: WalletMonthLine(summary: summary),
        trailing: IconButton(
          tooltip: isMain ? context.tr('Main wallet') : context.tr('Make it my main wallet'),
          icon: Icon(isMain ? Icons.star_rounded : Icons.star_outline_rounded, color: isMain ? Brand.yellow : null),
          onPressed: isMain ? null : onMain,
        ),
        onTap: onTap,
      ),
    );
  }
}
