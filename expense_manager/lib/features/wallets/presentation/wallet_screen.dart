import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../../../app/routes.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/layout/breakpoints.dart';
import '../../../core/theme/app_theme.dart';
import '../../../domain/entities/entities.dart';
import '../../../shared/providers/providers.dart';
import '../../../shared/widgets/common_widgets.dart';
import '../application/wallet_cloud.dart';
import '../application/wallet_providers.dart';
import 'wallet_widgets.dart';
import 'wallets_screen.dart' show walletErrorMessage;

/// One shared wallet: this month, the history with who recorded each entry,
/// invite, members and leave.
class WalletScreen extends ConsumerStatefulWidget {
  const WalletScreen({super.key, required this.walletId});

  final String walletId;

  @override
  ConsumerState<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends ConsumerState<WalletScreen> {
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    // Fresh entries from the other members when the wallet opens.
    WidgetsBinding.instance.addPostFrameCallback((_) => _sync(quiet: true));
  }

  Future<void> _sync({bool quiet = false}) async {
    final wallet = ref.read(walletByIdProvider(widget.walletId));
    if (wallet == null || currentUid == null) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(walletCloudProvider).sync(wallet);
      ref.invalidate(walletMembersProvider(wallet.id));
    } on Object catch (e) {
      if (!quiet && mounted) messenger.showSnackBar(SnackBar(content: Text(walletErrorMessage(context, e))));
    }
  }

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

  Rect? _shareOrigin() {
    final box = context.findRenderObject() as RenderBox?;
    return box == null ? null : box.localToGlobal(Offset.zero) & box.size;
  }

  void _invite(Wallet wallet) {
    final origin = _shareOrigin();
    final subject = context.tr('Monchi wallet');
    _run(() async {
      final code = await ref.read(walletCloudProvider).invite(wallet);
      if (!mounted) return;
      final text = context.tr(
        'Join my wallet "{name}" in Monchi: open Monchi › More › Wallets › Join with a code and paste this code: {code}',
        {'name': wallet.name, 'code': code},
      );
      await SharePlus.instance.share(ShareParams(text: text, subject: subject, sharePositionOrigin: origin));
    });
  }

  Future<void> _leave(Wallet wallet) async {
    final ok = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(context.tr('Leave this wallet?')),
            content: Text(
              context.tr(
                'It disappears from this phone and you stop seeing its entries. The other members keep using it. You can come back with a new invite code.',
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: Text(context.tr('Cancel'))),
              FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(context.tr('Leave'))),
            ],
          ),
        ) ??
        false;
    if (!ok || !mounted) return;
    await _run(() async {
      await ref.read(walletCloudProvider).leave(wallet);
      if (mounted) context.pop();
    });
  }

  void _showMembers(Map<String, WalletMember> members) {
    final me = currentUid;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          ListTile(title: Text(context.tr('Members'), style: Theme.of(context).textTheme.titleMedium)),
          for (final m in members.values)
            ListTile(
              leading: MemberAvatar(member: m),
              title: Text(m.name.isEmpty ? context.tr('Member') : m.name),
              subtitle: m.uid == me ? Text(context.tr('You')) : null,
            ),
          if (members.isEmpty)
            ListTile(title: Text(context.tr('Connect to the internet to see the members.'))),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final wallet = ref.watch(walletByIdProvider(widget.walletId));
    if (wallet == null) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(child: EmptyState(icon: Icons.info_outline_rounded, message: context.tr('This wallet is not on this phone.'))),
      );
    }
    final entries = ref.watch(walletTransactionsProvider(wallet.id)).value ?? const <FinanceTransaction>[];
    final members = ref.watch(walletMembersProvider(wallet.id)).value ?? const <String, WalletMember>{};
    final summary = ref.watch(walletMonthSummaryProvider(wallet.id));
    final categories = ref.watch(categoryByIdProvider);
    final me = currentUid;
    final myName = ref.watch(profileProvider).value?.name.trim() ?? '';
    final finance = FinanceColors.of(context);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(wallet.name),
        bottom: _busy ? const PreferredSize(preferredSize: Size.fromHeight(4), child: LinearProgressIndicator()) : null,
        actions: [
          IconButton(
            tooltip: context.tr('Invite'),
            icon: const Icon(Icons.person_add_alt_1_rounded),
            onPressed: _busy ? null : () => _invite(wallet),
          ),
          PopupMenuButton<String>(
            tooltip: context.tr('Options'),
            onSelected: (v) => v == 'members' ? _showMembers(members) : _leave(wallet),
            itemBuilder: (_) => [
              PopupMenuItem(value: 'members', child: Text(context.tr('Members'))),
              PopupMenuItem(value: 'leave', child: Text(context.tr('Leave wallet'))),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push(Routes.newWalletTransaction(wallet.id)),
        icon: const Icon(Icons.add_rounded),
        label: Text(context.tr('New entry')),
      ),
      body: RefreshIndicator(
        onRefresh: _sync,
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: Breakpoints.expanded),
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
              children: [
                Card(
                  color: theme.colorScheme.primaryContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(walletIcon(wallet.kind), color: theme.colorScheme.onPrimaryContainer),
                            const SizedBox(width: 8),
                            Text(
                              '${walletKindLabel(context, wallet.kind)} · ${context.tr('This month')}',
                              style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.onPrimaryContainer),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        if (summary != null) ...[
                          Text(
                            summary.net.format(),
                            style: theme.textTheme.headlineMedium?.copyWith(
                              color: theme.colorScheme.onPrimaryContainer,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 4),
                          WalletMonthLine(summary: summary),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(context.tr('History'), style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                if (entries.isEmpty)
                  EmptyState(icon: Icons.receipt_long_rounded, message: context.tr('No entries yet. Add the first one.')),
                for (final tx in entries)
                  _EntryRow(
                    key: ValueKey(tx.id),
                    transaction: tx,
                    category: categories[tx.categoryId],
                    member: members[tx.createdBy],
                    fallbackName: tx.createdBy != null && tx.createdBy == me
                        ? (myName.isEmpty ? context.tr('You') : myName)
                        : context.tr('Member'),
                    incomeColor: finance.income,
                    expenseColor: finance.expense,
                    onTap: () => context.push(Routes.editTransaction(tx.id)),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// History row: who recorded it on the left (photo, name below), the entry
/// on the right.
class _EntryRow extends StatelessWidget {
  const _EntryRow({
    super.key,
    required this.transaction,
    required this.category,
    required this.member,
    required this.fallbackName,
    required this.incomeColor,
    required this.expenseColor,
    required this.onTap,
  });

  final FinanceTransaction transaction;
  final FinanceCategory? category;
  final WalletMember? member;
  final String fallbackName;
  final Color incomeColor;
  final Color expenseColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tx = transaction;
    final isIncome = tx.type == TransactionType.income;
    final name = (member?.name.isNotEmpty ?? false) ? member!.name : fallbackName;
    final categoryName = category?.label(context) ?? context.tr('Uncategorized');
    final theme = Theme.of(context);
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              SizedBox(
                width: 64,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    MemberAvatar(member: member ?? WalletMember(uid: '', name: name)),
                    const SizedBox(height: 4),
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.labelSmall,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tx.description.isNotEmpty ? tx.description : categoryName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$categoryName · ${DateFormat.MMMd(context.lang).add_jm().format(tx.occurredAt)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${isIncome ? '+' : '−'}${tx.amount.format()}',
                style: TextStyle(color: isIncome ? incomeColor : expenseColor, fontWeight: FontWeight.w800, fontSize: 15),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
