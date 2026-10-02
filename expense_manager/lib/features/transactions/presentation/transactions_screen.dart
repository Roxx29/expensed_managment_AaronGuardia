import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/routes.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/layout/breakpoints.dart';
import '../../../core/money/currency.dart';
import '../../../core/money/money.dart';
import '../../../core/time/year_month.dart';
import '../../../domain/entities/entities.dart';
import '../../../domain/finance/transaction_filter.dart';
import '../../../shared/providers/providers.dart';
import '../../../shared/widgets/common_widgets.dart';
import '../../../shared/widgets/transaction_tile.dart';
import '../application/transaction_providers.dart';

/// Transaction history with search, filters and sorting.
class TransactionsScreen extends ConsumerStatefulWidget {
  const TransactionsScreen({super.key});

  @override
  ConsumerState<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends ConsumerState<TransactionsScreen> {
  late final TextEditingController _search =
      TextEditingController(text: ref.read(transactionFilterProvider).query);

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  TransactionFilter get _filter => ref.read(transactionFilterProvider);
  void _setFilter(TransactionFilter f) => ref.read(transactionFilterProvider.notifier).set(f);

  @override
  Widget build(BuildContext context) {
    final filter = ref.watch(transactionFilterProvider);
    final results = ref.watch(filteredTransactionsProvider);
    final hasAny = (ref.watch(allTransactionsProvider).value ?? const []).isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('Transactions')),
        actions: [
          PopupMenuButton<TransactionSort>(
            tooltip: context.tr('Sort'),
            icon: const Icon(Icons.sort_rounded),
            initialValue: filter.sort,
            onSelected: (sort) => _setFilter(_filter.copyWith(sort: sort)),
            itemBuilder: (_) => [
              PopupMenuItem(value: TransactionSort.newest, child: Text(context.tr('Newest first'))),
              PopupMenuItem(value: TransactionSort.oldest, child: Text(context.tr('Oldest first'))),
              PopupMenuItem(value: TransactionSort.highest, child: Text(context.tr('Highest amount'))),
              PopupMenuItem(value: TransactionSort.lowest, child: Text(context.tr('Lowest amount'))),
            ],
          ),
        ],
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: Breakpoints.expanded),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: SearchBar(
                  controller: _search,
                  hintText: context.tr('Search description, notes, category…'),
                  leading: const Icon(Icons.search_rounded),
                  elevation: const WidgetStatePropertyAll(0),
                  trailing: [
                    if (filter.query.isNotEmpty)
                      IconButton(
                        tooltip: context.tr('Clear search'),
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () {
                          _search.clear();
                          _setFilter(_filter.copyWith(query: ''));
                        },
                      ),
                  ],
                  onChanged: (q) => _setFilter(_filter.copyWith(query: q)),
                ),
              ),
              _FilterBar(filter: filter, onChanged: _setFilter, onClear: () {
                _search.clear();
                ref.read(transactionFilterProvider.notifier).reset();
              }),
              Expanded(
                child: results.when(
                  skipLoadingOnReload: true,
                  loading: () => const Center(child: CircularProgressIndicator()),
                  error: (_, _) => Center(
                    child: EmptyState(
                      icon: Icons.error_outline_rounded,
                      message: context.tr('Could not load transactions.'),
                    ),
                  ),
                  data: (list) => list.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.all(24),
                          child: EmptyState(
                            icon: hasAny ? Icons.search_off_rounded : Icons.receipt_long_outlined,
                            message: hasAny
                                ? context.tr('No transactions match these filters.')
                                : context.tr('No transactions yet. Tap Add to record your first expense or income.'),
                          ),
                        )
                      : _TransactionList(transactions: list, groupByDay: _isDateSort(filter.sort)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static bool _isDateSort(TransactionSort s) =>
      s == TransactionSort.newest || s == TransactionSort.oldest;
}

class _TransactionList extends ConsumerStatefulWidget {
  const _TransactionList({required this.transactions, required this.groupByDay});

  final List<FinanceTransaction> transactions;
  final bool groupByDay;

  @override
  ConsumerState<_TransactionList> createState() => _TransactionListState();
}

class _TransactionListState extends ConsumerState<_TransactionList> {
  /// Swiped rows are hidden at once: a dismissed Dismissible must leave the
  /// tree before the database stream emits the new list.
  final _hidden = <String>{};

  @override
  Widget build(BuildContext context) {
    final transactions = widget.transactions.where((t) => !_hidden.contains(t.id)).toList();
    final groupByDay = widget.groupByDay;
    final categories = ref.watch(categoryByIdProvider);
    final headerStyle = Theme.of(context).textTheme.labelLarge?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        );
    final dayFormat = DateFormat.yMMMEd(context.lang);

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 96), // room for the FAB
      itemCount: transactions.length,
      itemBuilder: (context, i) {
        final tx = transactions[i];
        final showHeader = groupByDay &&
            (i == 0 || dateOnly(transactions[i - 1].occurredAt) != dateOnly(tx.occurredAt));
        final tile = Dismissible(
          key: ValueKey(tx.id),
          direction: DismissDirection.endToStart,
          background: Container(
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.symmetric(horizontal: 24),
            color: Theme.of(context).colorScheme.errorContainer,
            child: Icon(Icons.delete_outline_rounded, color: Theme.of(context).colorScheme.onErrorContainer),
          ),
          onDismissed: (_) => _deleteWithUndo(tx),
          child: TransactionTile(
            transaction: tx,
            category: categories[tx.categoryId],
            showTime: groupByDay,
            onTap: () => context.push(Routes.editTransaction(tx.id)),
          ),
        );
        if (!showHeader) return tile;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Text(dayFormat.format(tx.occurredAt), style: headerStyle),
            ),
            tile,
          ],
        );
      },
    );
  }

  void _deleteWithUndo(FinanceTransaction tx) {
    setState(() => _hidden.add(tx.id));
    final actions = ref.read(transactionActionsProvider);
    actions.delete(tx.id);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(context.tr('Transaction deleted')),
        action: SnackBarAction(
          label: context.tr('Undo'),
          onPressed: () {
            actions.restore(tx);
            if (mounted) setState(() => _hidden.remove(tx.id));
          },
        ),
      ));
  }
}

/// Horizontal row of filter chips.
class _FilterBar extends ConsumerWidget {
  const _FilterBar({required this.filter, required this.onChanged, required this.onClear});

  final TransactionFilter filter;
  final ValueChanged<TransactionFilter> onChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categories = ref.watch(categoryByIdProvider);
    final currency = ref.watch(currencyProvider);
    final dateFormat = DateFormat.MMMd(context.lang);

    void toggleType(TransactionType type) {
      final types = {...filter.types};
      if (!types.remove(type)) types.add(type);
      onChanged(filter.copyWith(types: types));
    }

    String? amountLabel() {
      final min = filter.minAmount, max = filter.maxAmount;
      if (min == null && max == null) return null;
      if (min != null && max != null) return '${min.format()} – ${max.format()}';
      return min != null ? '≥ ${min.format()}' : '≤ ${max!.format()}';
    }

    final dateLabel = filter.from == null
        ? null
        : '${dateFormat.format(filter.from!)} – '
            '${dateFormat.format(_dayBefore(filter.toExclusive!))}';

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        spacing: 8,
        children: [
          FilterChip(
            label: Text(context.tr('Expenses')),
            selected: filter.types.contains(TransactionType.expense),
            onSelected: (_) => toggleType(TransactionType.expense),
          ),
          FilterChip(
            label: Text(context.tr('Income')),
            selected: filter.types.contains(TransactionType.income),
            onSelected: (_) => toggleType(TransactionType.income),
          ),
          FilterChip(
            label: Text(categories[filter.categoryId]?.label(context) ?? context.tr('Category')),
            selected: filter.categoryId != null,
            onSelected: (_) async {
              final picked = await _pickCategory(context, categories.values.toList());
              if (picked == null) return;
              onChanged(picked.isEmpty
                  ? filter.copyWith(clearCategory: true)
                  : filter.copyWith(categoryId: picked));
            },
          ),
          FilterChip(
            label: Text(dateLabel ?? context.tr('Date')),
            selected: dateLabel != null,
            onSelected: (_) async {
              final now = DateTime.now();
              final range = await showDateRangePicker(
                context: context,
                firstDate: DateTime(2000),
                lastDate: DateTime(now.year + 1, 12, 31),
                initialDateRange: filter.from == null
                    ? DateTimeRange(start: YearMonth.fromDate(now).start, end: dateOnly(now))
                    : DateTimeRange(
                        start: filter.from!,
                        end: _dayBefore(filter.toExclusive!),
                      ),
              );
              if (range == null) return;
              final end = range.end;
              onChanged(filter.copyWith(
                from: dateOnly(range.start),
                toExclusive: DateTime(end.year, end.month, end.day + 1),
              ));
            },
          ),
          FilterChip(
            label: Text(amountLabel() ?? context.tr('Amount')),
            selected: amountLabel() != null,
            onSelected: (_) async {
              final result = await showDialog<(Money?, Money?)>(
                context: context,
                builder: (_) => _AmountRangeDialog(currency: currency, initialMin: filter.minAmount, initialMax: filter.maxAmount),
              );
              if (result == null) return;
              final (min, max) = result;
              onChanged(filter.copyWith(clearAmounts: true).copyWith(minAmount: min, maxAmount: max));
            },
          ),
          if (filter.isActive)
            ActionChip(
              avatar: const Icon(Icons.filter_alt_off_rounded, size: 18),
              label: Text(context.tr('Clear')),
              onPressed: onClear,
            ),
        ],
      ),
    );
  }

  static DateTime _dayBefore(DateTime d) => DateTime(d.year, d.month, d.day - 1);

  /// Returns a category id, '' for "any category", or null if dismissed.
  static Future<String?> _pickCategory(BuildContext context, List<FinanceCategory> categories) {
    final visible = categories.where((c) => !c.archived).toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    return showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(
              leading: const Icon(Icons.clear_all_rounded),
              title: Text(context.tr('Any category')),
              onTap: () => Navigator.pop(context, ''),
            ),
            for (final c in visible)
              ListTile(
                leading: Icon(iconForKey(c.iconKey), color: Color(c.color)),
                title: Text(c.label(context)),
                onTap: () => Navigator.pop(context, c.id),
              ),
          ],
        ),
      ),
    );
  }
}

class _AmountRangeDialog extends StatefulWidget {
  const _AmountRangeDialog({required this.currency, this.initialMin, this.initialMax});

  final Currency currency;
  final Money? initialMin;
  final Money? initialMax;

  @override
  State<_AmountRangeDialog> createState() => _AmountRangeDialogState();
}

class _AmountRangeDialogState extends State<_AmountRangeDialog> {
  late final _min = TextEditingController(text: widget.initialMin?.toDecimalString() ?? '');
  late final _max = TextEditingController(text: widget.initialMax?.toDecimalString() ?? '');
  String? _error;

  @override
  void dispose() {
    _min.dispose();
    _max.dispose();
    super.dispose();
  }

  Money? _parse(TextEditingController c) =>
      c.text.trim().isEmpty ? null : Money.tryParse(c.text, widget.currency);

  void _apply() {
    final min = _parse(_min), max = _parse(_max);
    if ((_min.text.trim().isNotEmpty && min == null) || (_max.text.trim().isNotEmpty && max == null)) {
      setState(() => _error = context.tr('Enter valid amounts'));
      return;
    }
    if (min != null && max != null && min > max) {
      setState(() => _error = context.tr('Minimum is greater than maximum'));
      return;
    }
    Navigator.pop(context, (min, max));
  }

  @override
  Widget build(BuildContext context) {
    const keyboard = TextInputType.numberWithOptions(decimal: true);
    return AlertDialog(
      title: Text(context.tr('Amount range')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(controller: _min, keyboardType: keyboard, decoration: InputDecoration(labelText: context.tr('Minimum'))),
          const SizedBox(height: 12),
          TextField(controller: _max, keyboardType: keyboard, decoration: InputDecoration(labelText: context.tr('Maximum'))),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, (null, null)), child: Text(context.tr('Clear'))),
        FilledButton(onPressed: _apply, child: Text(context.tr('Apply'))),
      ],
    );
  }
}
