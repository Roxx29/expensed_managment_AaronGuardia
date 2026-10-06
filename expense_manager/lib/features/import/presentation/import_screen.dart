import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/layout/breakpoints.dart';
import '../../../core/theme/app_theme.dart';
import '../../../domain/entities/entities.dart';
import '../../../domain/import/statement_import.dart';
import '../../../shared/providers/providers.dart';
import '../../../shared/widgets/common_widgets.dart';
import '../../premium/application/premium_providers.dart';
import '../../premium/presentation/paywall_screen.dart';
import '../application/import_providers.dart';

/// Imports a bank statement or another app's CSV: pick file → map columns →
/// import. The first import is free; later ones need Premium.
class ImportScreen extends ConsumerStatefulWidget {
  const ImportScreen({super.key});

  @override
  ConsumerState<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends ConsumerState<ImportScreen> {
  PickedStatement? _file;
  int _loads = 0; // Resets the dropdowns when another file is picked.
  int? _date, _description, _amount, _debit, _credit, _type, _category;
  StatementDateFormat _format = StatementDateFormat.ymd;
  StatementImportResult? _result;
  bool _busy = false;

  List<String> get _header => _file?.rows.first ?? const [];
  List<List<String>> get _dataRows => _file?.rows.skip(1).toList() ?? const [];

  ColumnMapping get _mapping =>
      ColumnMapping(
        date: _date,
        description: _description,
        amount: _amount,
        debit: _debit,
        credit: _credit,
        type: _type,
        category: _category,
      );

  void _detectFormat() {
    final col = _date;
    if (col == null) return;
    _format = StatementDateFormat.detect(
      _dataRows.take(50).map((r) => col < r.length ? r[col] : ''),
      preferMonthFirst: ref.read(importActionsProvider).prefersMonthFirst,
    );
  }

  void _recompute() {
    final mapping = _mapping;
    _result = mapping.isComplete ? mapStatement(_dataRows, mapping, _format, ref.read(currencyProvider)) : null;
  }

  Future<void> _pick() async {
    final messenger = ScaffoldMessenger.of(context);
    final invalidText = context.tr('This file could not be read as CSV. Maximum 5 MB and 20,000 rows.');
    final emptyText = context.tr('The file has no rows to import.');
    setState(() => _busy = true);
    try {
      final picked = await ref.read(importActionsProvider).pickStatement();
      if (picked == null || !mounted) return;
      if (picked.rows.length < 2) {
        messenger.showSnackBar(SnackBar(content: Text(emptyText)));
        return;
      }
      final guess = ColumnMapping.guess(picked.rows.first);
      setState(() {
        _file = picked;
        _loads++;
        _date = guess.date;
        _description = guess.description;
        _amount = guess.amount;
        _debit = guess.debit;
        _credit = guess.credit;
        _type = guess.type;
        _category = guess.category;
        _detectFormat();
        _recompute();
      });
    } on Object {
      messenger.showSnackBar(SnackBar(content: Text(invalidText)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _import(List<ImportedTransaction> transactions) async {
    if ((ref.read(importNeedsPremiumProvider).value ?? false) && !requirePremium(context, ref)) return;
    final messenger = ScaffoldMessenger.of(context);
    final doneText = context.tr('Imported {count} transactions', {'count': transactions.length});
    final failedText = context.tr('Could not import. Nothing was changed.');
    setState(() => _busy = true);
    try {
      await ref.read(importActionsProvider).importAll(transactions);
      messenger.showSnackBar(SnackBar(content: Text(doneText)));
      if (mounted) Navigator.of(context).maybePop();
    } on Object {
      messenger.showSnackBar(SnackBar(content: Text(failedText)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _update(VoidCallback change) => setState(() {
        change();
        _recompute();
      });

  Widget _columnField(String label, int? value, ValueChanged<int?> onChanged) {
    final header = _header;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DropdownButtonFormField<int?>(
        key: ValueKey('$label-$_loads'),
        initialValue: value,
        isExpanded: true,
        decoration: InputDecoration(labelText: label),
        items: [
          DropdownMenuItem(value: null, child: Text(context.tr('None'))),
          for (var i = 0; i < header.length; i++)
            DropdownMenuItem(
              value: i,
              child: Text(
                header[i].trim().isEmpty ? context.tr('Column {n}', {'n': i + 1}) : header[i].trim(),
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
        onChanged: (v) => _update(() => onChanged(v)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final file = _file;
    final result = _result;
    final finance = FinanceColors.of(context);
    final dateFormat = DateFormat.yMMMd(context.lang);
    final ready = result?.transactions ?? const <ImportedTransaction>[];

    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('Import bank statement')),
        bottom: _busy ? const PreferredSize(preferredSize: Size.fromHeight(4), child: LinearProgressIndicator()) : null,
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: Breakpoints.expanded),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (!ref.watch(premiumProvider)) ...[
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.card_giftcard_rounded),
                    title: Text(
                      (ref.watch(importNeedsPremiumProvider).value ?? false)
                          ? context.tr('You already used your free import. More imports are part of Monchi Premium.')
                          : context.tr('Your first import is free, to bring your history from another app or your bank.'),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
              SectionCard(
                title: context.tr('1. Choose a file'),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      context.tr(
                        'Export your statement from your bank, or your data from Monefy, Spendee, Wallet, Money Manager or Excel, as CSV (separated by commas, semicolons or tabs). The first row must contain the column names. Negative amounts, a debit column or a type column saying expense are imported as expenses; the rest as income. Categories are kept, or learned from your earlier transactions. Rows you already imported are skipped.',
                      ),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: OutlinedButton.icon(
                        onPressed: _busy ? null : _pick,
                        icon: const Icon(Icons.upload_file_rounded),
                        label: Text(file == null ? context.tr('Choose CSV file') : file.fileName),
                      ),
                    ),
                  ],
                ),
              ),
              if (file != null) ...[
                const SizedBox(height: 16),
                SectionCard(
                  title: context.tr('2. Match the columns'),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _columnField(context.tr('Date'), _date, (v) {
                        _date = v;
                        _detectFormat();
                      }),
                      DropdownButtonFormField<StatementDateFormat>(
                        key: ValueKey('format-$_loads-$_date-$_format'),
                        initialValue: _format,
                        decoration: InputDecoration(labelText: context.tr('Date format')),
                        items: [
                          for (final f in StatementDateFormat.values) DropdownMenuItem(value: f, child: Text(f.pattern)),
                        ],
                        onChanged: (f) {
                          if (f != null) _update(() => _format = f);
                        },
                      ),
                      const SizedBox(height: 12),
                      _columnField(context.tr('Description'), _description, (v) => _description = v),
                      _columnField(context.tr('Amount (negative = expense)'), _amount, (v) => _amount = v),
                      Text(
                        context.tr('Or, if your bank uses separate columns:'),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 8),
                      _columnField(context.tr('Debit (expenses)'), _debit, (v) => _debit = v),
                      _columnField(context.tr('Credit (income)'), _credit, (v) => _credit = v),
                      Text(
                        context.tr('Optional, for exports from other apps:'),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 8),
                      _columnField(context.tr('Type (expense / income)'), _type, (v) => _type = v),
                      _columnField(context.tr('Category'), _category, (v) => _category = v),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                SectionCard(
                  title: context.tr('3. Preview'),
                  child: result == null
                      ? EmptyState(
                          icon: Icons.info_outline_rounded,
                          message: context.tr('Choose at least the date column and an amount column.'),
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(context.tr('{valid} rows ready, {skipped} skipped (invalid date or amount)', {
                              'valid': ready.length,
                              'skipped': result.skipped,
                            })),
                            for (final t in ready.take(10))
                              ListTile(
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                title: Text(
                                  t.description.isEmpty ? context.tr('No description') : t.description,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle: Text(
                                  t.categoryName.isEmpty
                                      ? dateFormat.format(t.date)
                                      : '${dateFormat.format(t.date)} · ${t.categoryName}',
                                ),
                                trailing: Text(
                                  '${t.type == TransactionType.expense ? '-' : '+'}${t.amount.format()}',
                                  style: TextStyle(
                                    color: t.type == TransactionType.expense ? finance.expense : finance.income,
                                  ),
                                ),
                              ),
                            const SizedBox(height: 12),
                            Align(
                              alignment: Alignment.centerRight,
                              child: FilledButton.icon(
                                onPressed: _busy || ready.isEmpty ? null : () => _import(ready),
                                icon: const Icon(Icons.download_done_rounded),
                                label: Text(context.tr('Import {count} transactions', {'count': ready.length})),
                              ),
                            ),
                          ],
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
