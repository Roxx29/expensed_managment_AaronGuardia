import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../../../app/routes.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/layout/breakpoints.dart';
import '../../../core/money/currency.dart';
import '../../../core/money/money.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/time/year_month.dart';
import '../../../domain/entities/entities.dart';
import '../../../domain/finance/budget_calculator.dart';
import '../../../domain/finance/statistics_calculator.dart';
import '../../../domain/finance/summary_calculator.dart';
import '../../../domain/wallets/wallet_stats.dart';
import '../../../shared/providers/providers.dart';
import '../../../shared/widgets/charts.dart';
import '../../../shared/widgets/common_widgets.dart';
import '../../../shared/widgets/money_input.dart';
import '../../backup/application/backup_providers.dart';
import '../../premium/presentation/paywall_screen.dart';
import '../application/wallet_cloud.dart';
import '../application/wallet_providers.dart';
import 'wallet_widgets.dart';
import 'wallets_screen.dart' show WalletEditDialog, walletErrorMessage;

/// One shared wallet: a Summary tab (month, budget, who spent, categories,
/// year chart) and a History tab (search and filters), plus invite, members,
/// edit, budget, main wallet, export and leave.
class WalletScreen extends ConsumerStatefulWidget {
  const WalletScreen({super.key, required this.walletId});

  final String walletId;

  @override
  ConsumerState<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends ConsumerState<WalletScreen> {
  bool _busy = false;
  YearMonth? _month;

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
    final done = context.tr('Wallet up to date');
    try {
      await ref.read(walletCloudProvider).sync(wallet);
      if (!mounted) return;
      ref.invalidate(walletMembersProvider(wallet.id));
      if (!quiet) messenger.showSnackBar(SnackBar(content: Text(done)));
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

  void _copyInvite(Wallet wallet) {
    final messenger = ScaffoldMessenger.of(context);
    final copied = context.tr('Invite code copied. It works for 7 days.');
    _run(() async {
      final code = await ref.read(walletCloudProvider).invite(wallet);
      await Clipboard.setData(ClipboardData(text: code));
      messenger.showSnackBar(SnackBar(content: Text(copied)));
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

  Future<void> _edit(Wallet wallet) async {
    final result = await showDialog<(String, WalletKind)>(
      context: context,
      builder: (_) => WalletEditDialog(initialName: wallet.name, initialKind: wallet.kind),
    );
    if (result == null || !mounted) return;
    await _run(() => ref.read(walletCloudProvider).edit(wallet, result.$1, result.$2));
  }

  Future<void> _editBudget(Wallet wallet) async {
    final currency = ref.read(currencyProvider);
    final current = ref.read(walletBudgetProvider(wallet.id)).value;
    final result = await showDialog<String>(
      context: context,
      builder: (_) => _BudgetDialog(
        currency: currency,
        initial: current == null || current.currency != currency ? '' : current.toDecimalString(),
      ),
    );
    if (result == null || !mounted) return;
    final amount = result.isEmpty ? null : Money.tryParse(result, currency);
    await ref
        .read(settingsRepositoryProvider)
        .write(walletBudgetKey(wallet.id), amount == null ? '' : '${amount.minor}|${currency.code}');
  }

  Future<void> _setMain(Wallet wallet, bool isMain) async {
    final messenger = ScaffoldMessenger.of(context);
    final text = isMain ? context.tr('Personal is your main wallet again.') : context.tr('Main wallet changed.');
    await ref.read(settingsRepositoryProvider).write(mainWalletKey, isMain ? '' : wallet.id);
    messenger.showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _export(Wallet wallet) async {
    if (!requirePremium(context, ref)) return;
    // Labels resolved now, in the current UI language (no context after awaits).
    final categories = {for (final c in ref.read(categoryByIdProvider).values) c.id: c.label(context)};
    final methods = {for (final m in ref.read(paymentMethodByIdProvider).values) m.id: m.label(context)};
    final origin = _shareOrigin();
    await _run(() => ref.read(backupActionsProvider).exportTransactionsCsv(
          categoryName: (id) => categories[id] ?? '',
          paymentMethodName: (id) => methods[id] ?? '',
          walletId: wallet.id,
          origin: origin,
        ));
  }

  void _showMembers(Wallet wallet, Map<String, WalletMember> members) {
    final me = currentUid;
    final isOwner = me != null && wallet.ownerUid == me;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          ListTile(
            title: Text(context.tr('Members'), style: Theme.of(context).textTheme.titleMedium),
            trailing: TextButton.icon(
              onPressed: () {
                Navigator.pop(sheetContext);
                _invite(wallet);
              },
              icon: const Icon(Icons.person_add_alt_1_rounded),
              label: Text(context.tr('Invite')),
            ),
          ),
          for (final m in members.values)
            ListTile(
              leading: MemberAvatar(member: m),
              title: Text(m.name.isEmpty ? context.tr('Member') : m.name),
              subtitle: Text([
                if (m.uid == me) context.tr('You'),
                if (m.uid == wallet.ownerUid) context.tr('Owner'),
              ].join(' · ')),
              trailing: isOwner && m.uid != me
                  ? IconButton(
                      tooltip: context.tr('Remove from the wallet'),
                      icon: const Icon(Icons.person_remove_rounded),
                      onPressed: () {
                        Navigator.pop(sheetContext);
                        _removeMember(wallet, m);
                      },
                    )
                  : null,
            ),
          if (members.isEmpty) ListTile(title: Text(context.tr('Connect to the internet to see the members.'))),
        ],
      ),
    );
  }

  Future<void> _removeMember(Wallet wallet, WalletMember member) async {
    final name = member.name.isEmpty ? context.tr('Member') : member.name;
    final ok = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(context.tr('Remove {name}?', {'name': name})),
            content: Text(
              context.tr(
                'They stop receiving new entries. What they already downloaded stays on their phone. To share again, send a new invite code.',
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: Text(context.tr('Cancel'))),
              FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(context.tr('Remove'))),
            ],
          ),
        ) ??
        false;
    if (!ok || !mounted) return;
    await _run(() async {
      await ref.read(walletCloudProvider).removeMember(wallet, member.uid);
      if (mounted) ref.invalidate(walletMembersProvider(wallet.id));
    });
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
    final entriesAsync = ref.watch(walletTransactionsProvider(wallet.id));
    if (!entriesAsync.hasValue) {
      return Scaffold(appBar: AppBar(title: Text(wallet.name)), body: const Center(child: CircularProgressIndicator()));
    }
    final entries = entriesAsync.requireValue;
    final members = ref.watch(walletMembersProvider(wallet.id)).value ?? const <String, WalletMember>{};
    final isMain = ref.watch(mainWalletIdProvider) == wallet.id;
    final me = currentUid;
    final myName = ref.watch(profileProvider).value?.name.trim() ?? '';
    String nameOf(String? uid) {
      final published = members[uid]?.name ?? '';
      if (published.isNotEmpty) return published;
      if (uid != null && uid == me) return myName.isEmpty ? context.tr('You') : myName;
      return context.tr('Member');
    }

    final today = ref.watch(clockProvider)();
    final month = _month ?? YearMonth.fromDate(today);
    final theme = Theme.of(context);

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(wallet.name, overflow: TextOverflow.ellipsis),
              Text(
                [walletKindLabel(context, wallet.kind), if (isMain) context.tr('Main wallet')].join(' · '),
                style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
          ),
          actions: [
            IconButton(
              tooltip: context.tr('Members'),
              icon: const Icon(Icons.group_rounded),
              onPressed: () => _showMembers(wallet, members),
            ),
            PopupMenuButton<String>(
              tooltip: context.tr('Options'),
              enabled: !_busy,
              onSelected: (v) {
                switch (v) {
                  case 'invite':
                    _invite(wallet);
                  case 'copy':
                    _copyInvite(wallet);
                  case 'edit':
                    _edit(wallet);
                  case 'budget':
                    _editBudget(wallet);
                  case 'main':
                    _setMain(wallet, isMain);
                  case 'export':
                    _export(wallet);
                  case 'sync':
                    _run(() => _sync());
                  default:
                    _leave(wallet);
                }
              },
              itemBuilder: (_) => [
                _menuItem('invite', Icons.share_rounded, context.tr('Share invite')),
                _menuItem('copy', Icons.copy_rounded, context.tr('Copy invite code')),
                _menuItem('edit', Icons.edit_rounded, context.tr('Rename or change type')),
                _menuItem('budget', Icons.savings_rounded, context.tr('Monthly budget')),
                _menuItem(
                  'main',
                  isMain ? Icons.star_rounded : Icons.star_outline_rounded,
                  isMain ? context.tr('Stop using as main wallet') : context.tr('Make it my main wallet'),
                ),
                _menuItem('export', Icons.table_view_rounded, context.tr('Export to spreadsheet (CSV)')),
                _menuItem('sync', Icons.sync_rounded, context.tr('Sync now')),
                const PopupMenuDivider(),
                _menuItem('leave', Icons.logout_rounded, context.tr('Leave wallet')),
              ],
            ),
          ],
          bottom: TabBar(tabs: [Tab(text: context.tr('Summary')), Tab(text: context.tr('History'))]),
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => context.push(Routes.newWalletTransaction(wallet.id)),
          icon: const Icon(Icons.add_rounded),
          label: Text(context.tr('New entry')),
        ),
        body: Column(
          children: [
            if (_busy) const LinearProgressIndicator(minHeight: 3),
            Expanded(
              child: TabBarView(
                children: [
                  RefreshIndicator(
                    onRefresh: _sync,
                    child: _SummaryTab(
                      wallet: wallet,
                      entries: entries,
                      month: month,
                      today: today,
                      members: members,
                      nameOf: nameOf,
                      onMonth: (m) => setState(() => _month = m),
                      onBudget: () => _editBudget(wallet),
                    ),
                  ),
                  RefreshIndicator(
                    onRefresh: _sync,
                    child: _HistoryTab(entries: entries, members: members, nameOf: nameOf),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  PopupMenuItem<String> _menuItem(String value, IconData icon, String label) => PopupMenuItem(
        value: value,
        child: Row(children: [Icon(icon, size: 20), const SizedBox(width: 12), Flexible(child: Text(label))]),
      );
}

/// Centered, width-limited scroll list shared by both tabs.
class _TabList extends StatelessWidget {
  const _TabList({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: Breakpoints.expanded),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
            children: children,
          ),
        ),
      );
}

class _SummaryTab extends ConsumerWidget {
  const _SummaryTab({
    required this.wallet,
    required this.entries,
    required this.month,
    required this.today,
    required this.members,
    required this.nameOf,
    required this.onMonth,
    required this.onBudget,
  });

  final Wallet wallet;
  final List<FinanceTransaction> entries;
  final YearMonth month;
  final DateTime today;
  final Map<String, WalletMember> members;
  final String Function(String? uid) nameOf;
  final ValueChanged<YearMonth> onMonth;
  final VoidCallback onBudget;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currency = ref.watch(currencyProvider);
    final categories = ref.watch(categoryByIdProvider);
    final comparison = StatisticsCalculator.compareWithPrevious(transactions: entries, month: month, currency: currency);
    final summary = comparison.current;
    final byMember = WalletStats.byMember(entries, month, currency);
    final year = StatisticsCalculator.year(transactions: entries, year: month.year, currency: currency, today: today);
    // A budget saved in another currency doesn't apply (amounts aren't converted).
    final budget = ref.watch(walletBudgetProvider(wallet.id)).value;
    final budgetMinor = budget != null && budget.currency == currency ? budget.minor : null;
    final syncedAt = ref.watch(walletSyncedAtProvider(wallet.id)).value;
    final monthName = DateFormat.MMMM(context.lang);
    final finance = FinanceColors.of(context);
    final theme = Theme.of(context);
    final first = WalletStats.firstMonth(entries, today);
    final current = YearMonth.fromDate(today);

    return _TabList(
      children: [
        _MonthCard(
          wallet: wallet,
          summary: summary,
          comparison: comparison,
          balance: WalletStats.balance(entries, currency),
          syncedAt: syncedAt,
          onPrevious: month.compareTo(first) > 0 ? () => onMonth(month.previous) : null,
          onNext: month.compareTo(current) < 0 ? () => onMonth(month.next) : null,
        ),
        const SizedBox(height: 16),
        SectionCard(
          title: context.tr('Monthly budget'),
          trailing: TextButton(
            onPressed: onBudget,
            child: Text(budgetMinor == null ? context.tr('Set') : context.tr('Change')),
          ),
          child: budgetMinor == null
              ? Text(
                  context.tr('Set a spending limit for this wallet and see how much is left each month.'),
                  style: theme.textTheme.bodySmall,
                )
              : _BudgetProgress(
                  progress: BudgetCalculator.progress(budgeted: Money(budgetMinor, currency), spent: summary.expenses),
                ),
        ),
        const SizedBox(height: 16),
        SectionCard(
          title: context.tr('Who recorded what'),
          child: byMember.isEmpty
              ? EmptyState(icon: Icons.group_outlined, message: context.tr('No entries this month.'))
              : Column(
                  children: [
                    for (final m in byMember)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Row(
                          children: [
                            MemberAvatar(member: members[m.uid] ?? WalletMember(uid: '', name: nameOf(m.uid))),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(nameOf(m.uid), overflow: TextOverflow.ellipsis),
                                  const SizedBox(height: 4),
                                  LinearProgressIndicator(
                                    value: m.expenses.ratioOf(summary.expenses).clamp(0.0, 1.0).toDouble(),
                                    minHeight: 4,
                                    color: finance.expense,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text('−${m.expenses.format()}', style: TextStyle(color: finance.expense, fontWeight: FontWeight.w700)),
                                Text(
                                  m.income.isPositive
                                      ? '+${m.income.format()} · ${context.tr('{count} entries', {'count': m.count})}'
                                      : context.tr('{count} entries', {'count': m.count}),
                                  style: theme.textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
        ),
        const SizedBox(height: 16),
        SectionCard(
          title: context.tr('Spending by category'),
          child: summary.expensesByCategory.isEmpty
              ? EmptyState(icon: Icons.pie_chart_outline_rounded, message: context.tr('No expenses this month.'))
              : Column(
                  children: [
                    for (final c in summary.expensesByCategory)
                      CategoryAmountRow(
                        category: categories[c.categoryId],
                        amount: c.amount,
                        share: c.amount.ratioOf(summary.expenses),
                        note: '${(c.amount.ratioOf(summary.expenses) * 100).round()}%',
                      ),
                  ],
                ),
        ),
        const SizedBox(height: 16),
        SectionCard(
          title: context.tr('Monthly spending {year}', {'year': month.year}),
          child: MoneyBarChart(
            values: year.monthlyExpenses,
            labels: [for (var m = 1; m <= 12; m++) monthName.format(DateTime(2000, m)).substring(0, 1)],
            readoutLabels: [for (var m = 1; m <= 12; m++) monthName.format(DateTime(month.year, m))],
            selectedIndex: month.month - 1,
            onSelected: (i) {
              final picked = YearMonth(month.year, i + 1);
              if (picked.compareTo(current) <= 0) onMonth(picked);
            },
          ),
        ),
      ],
    );
  }
}

/// Month picker, the month's balance, change vs the previous month and the
/// wallet's all-time balance.
class _MonthCard extends StatelessWidget {
  const _MonthCard({
    required this.wallet,
    required this.summary,
    required this.comparison,
    required this.balance,
    required this.syncedAt,
    required this.onPrevious,
    required this.onNext,
  });

  final Wallet wallet;
  final MonthSummary summary;
  final MonthComparison comparison;
  final Money balance;
  final DateTime? syncedAt;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final on = theme.colorScheme.onPrimaryContainer;
    final finance = FinanceColors.of(context);
    final change = comparison.expenseChangePercent;
    final previousName = DateFormat.MMMM(context.lang).format(comparison.previous.month.start);
    final small = theme.textTheme.bodySmall?.copyWith(color: on);
    return Card(
      color: theme.colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 16),
        child: Column(
          children: [
            Row(
              children: [
                IconButton(
                  tooltip: context.tr('Previous month'),
                  onPressed: onPrevious,
                  icon: Icon(Icons.chevron_left_rounded, color: on),
                ),
                Expanded(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(walletIcon(wallet.kind), size: 18, color: on),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          DateFormat.yMMMM(context.lang).format(summary.month.start),
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall?.copyWith(color: on),
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: context.tr('Next month'),
                  onPressed: onNext,
                  icon: Icon(Icons.chevron_right_rounded, color: on),
                ),
              ],
            ),
            Text(
              summary.net.format(),
              style: theme.textTheme.headlineMedium?.copyWith(color: on, fontWeight: FontWeight.w800),
            ),
            Text(
              summary.month == YearMonth.fromDate(DateTime.now())
                  ? context.tr('Left this month')
                  : context.tr('Balance of the month'),
              style: small,
            ),
            const SizedBox(height: 8),
            WalletMonthLine(summary: summary),
            if (change != null) ...[
              const SizedBox(height: 6),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    change > 0 ? Icons.trending_up_rounded : Icons.trending_down_rounded,
                    size: 16,
                    color: change > 0 ? finance.expense : finance.income,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    change > 0
                        ? context.tr('{pct}% more than {month}', {'pct': change.abs(), 'month': previousName})
                        : context.tr('{pct}% less than {month}', {'pct': change.abs(), 'month': previousName}),
                    style: small,
                  ),
                ],
              ),
            ],
            const Divider(height: 24, indent: 16, endIndent: 16),
            Text(context.tr('Wallet balance (all time): {amount}', {'amount': balance.format()}), style: small),
            if (syncedAt != null)
              Text(
                context.tr('Updated {time}', {'time': DateFormat.MMMd(context.lang).add_jm().format(syncedAt!)}),
                style: small?.copyWith(color: on.withValues(alpha: 0.87)),
              ),
          ],
        ),
      ),
    );
  }
}

class _BudgetProgress extends StatelessWidget {
  const _BudgetProgress({required this.progress});

  final BudgetProgress progress;

  @override
  Widget build(BuildContext context) {
    final finance = FinanceColors.of(context);
    final over = progress.remaining.isNegative;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(context.tr('Spent {spent} of {budget}', {
          'spent': progress.spent.format(),
          'budget': progress.budgeted.format(),
        })),
        const SizedBox(height: 8),
        BudgetProgressBar(progress: progress),
        const SizedBox(height: 6),
        Text(
          over
              ? context.tr('Over by {amount}', {'amount': progress.remaining.abs().format()})
              : context.tr('{amount} left', {'amount': progress.remaining.format()}),
          style: TextStyle(color: over ? finance.expense : finance.income, fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}

class _HistoryTab extends ConsumerStatefulWidget {
  const _HistoryTab({required this.entries, required this.members, required this.nameOf});

  final List<FinanceTransaction> entries;
  final Map<String, WalletMember> members;
  final String Function(String? uid) nameOf;

  @override
  ConsumerState<_HistoryTab> createState() => _HistoryTabState();
}

// Kept alive so the search and filters survive switching tabs.
class _HistoryTabState extends ConsumerState<_HistoryTab> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  final _search = TextEditingController();
  TransactionType? _type;
  String _member = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final categories = ref.watch(categoryByIdProvider);
    final finance = FinanceColors.of(context);
    String categoryName(String? id) => categories[id]?.label(context) ?? context.tr('Uncategorized');
    // Authors who appear in this wallet's entries, for the member chips.
    final authors = {for (final t in widget.entries) if (t.createdBy != null) t.createdBy!}.toList();
    // A filter on someone whose chip is gone (only one author left) is dropped.
    final member = authors.length > 1 && authors.contains(_member) ? _member : '';
    final filtered = WalletStats.filter(
      widget.entries,
      type: _type,
      member: member,
      query: _search.text,
      categoryName: categoryName,
    );
    final monthFormat = DateFormat.yMMMM(context.lang);
    final rows = <Object>[];
    String? lastMonth;
    for (final t in filtered) {
      final label = monthFormat.format(t.occurredAt);
      if (label != lastMonth) rows.add(label);
      lastMonth = label;
      rows.add(t);
    }

    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: Breakpoints.expanded),
        child: ListView.builder(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
          itemCount: rows.length + 1,
          itemBuilder: (context, i) {
            if (i == 0) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: _search,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      hintText: context.tr('Search in this wallet'),
                      prefixIcon: const Icon(Icons.search_rounded),
                      suffixIcon: _search.text.isEmpty
                          ? null
                          : IconButton(
                              tooltip: context.tr('Clear'),
                              icon: const Icon(Icons.close_rounded),
                              onPressed: () => setState(_search.clear),
                            ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (final (type, label) in [
                          (null, context.tr('All')),
                          (TransactionType.expense, context.tr('Expenses')),
                          (TransactionType.income, context.tr('Income')),
                        ])
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ChoiceChip(
                              label: Text(label),
                              selected: _type == type,
                              onSelected: (_) => setState(() => _type = type),
                            ),
                          ),
                        if (authors.length > 1)
                          for (final uid in authors)
                            Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: FilterChip(
                                avatar: MemberAvatar(
                                  member: widget.members[uid] ?? WalletMember(uid: uid, name: widget.nameOf(uid)),
                                  radius: 12,
                                ),
                                label: Text(widget.nameOf(uid)),
                                selected: member == uid,
                                onSelected: (on) => setState(() => _member = on ? uid : ''),
                              ),
                            ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (filtered.isEmpty)
                    EmptyState(
                      icon: Icons.receipt_long_rounded,
                      message: widget.entries.isEmpty
                          ? context.tr('No entries yet. Add the first one.')
                          : context.tr('Nothing matches these filters.'),
                    ),
                ],
              );
            }
            final row = rows[i - 1];
            if (row is String) {
              return Padding(
                padding: const EdgeInsets.fromLTRB(4, 16, 4, 6),
                child: Text(row, style: Theme.of(context).textTheme.titleSmall),
              );
            }
            final tx = row as FinanceTransaction;
            return _EntryRow(
              key: ValueKey(tx.id),
              transaction: tx,
              categoryName: categoryName(tx.categoryId),
              member: widget.members[tx.createdBy],
              name: widget.nameOf(tx.createdBy),
              incomeColor: finance.income,
              expenseColor: finance.expense,
              onTap: () => context.push(Routes.editTransaction(tx.id)),
            );
          },
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
    required this.categoryName,
    required this.member,
    required this.name,
    required this.incomeColor,
    required this.expenseColor,
    required this.onTap,
  });

  final FinanceTransaction transaction;
  final String categoryName;
  final WalletMember? member;
  final String name;
  final Color incomeColor;
  final Color expenseColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tx = transaction;
    final isIncome = tx.type == TransactionType.income;
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

/// Monthly limit for a wallet; returns the typed amount, '' to remove it.
class _BudgetDialog extends StatefulWidget {
  const _BudgetDialog({required this.currency, required this.initial});

  final Currency currency;
  final String initial;

  @override
  State<_BudgetDialog> createState() => _BudgetDialogState();
}

class _BudgetDialogState extends State<_BudgetDialog> {
  final _form = GlobalKey<FormState>();
  late final _amount = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        scrollable: true,
        title: Text(context.tr('Monthly budget')),
        content: Form(
          key: _form,
          child: MoneyFormField(controller: _amount, currency: widget.currency, autofocus: true),
        ),
        actions: [
          if (widget.initial.isNotEmpty)
            TextButton(onPressed: () => Navigator.pop(context, ''), child: Text(context.tr('Remove'))),
          TextButton(onPressed: () => Navigator.pop(context), child: Text(context.tr('Cancel'))),
          FilledButton(
            onPressed: () {
              if (_form.currentState!.validate()) Navigator.pop(context, _amount.text);
            },
            child: Text(context.tr('Save')),
          ),
        ],
      );
}
