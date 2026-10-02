import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/l10n/l10n.dart';
import '../../core/theme/app_theme.dart';
import '../../domain/entities/entities.dart';
import 'common_widgets.dart';

/// One transaction row. Used by the dashboard and the history screen.
class TransactionTile extends StatelessWidget {
  const TransactionTile({
    super.key,
    required this.transaction,
    required this.category,
    this.onTap,
    this.showTime = false,
  });

  final FinanceTransaction transaction;
  final FinanceCategory? category;
  final VoidCallback? onTap;
  final bool showTime;

  @override
  Widget build(BuildContext context) {
    final tx = transaction;
    final finance = FinanceColors.of(context);
    // Money coming back into the available balance shows as positive.
    final isIncome = tx.type == TransactionType.income || tx.type == TransactionType.savingsWithdrawal;
    final color = Color(category?.color ?? 0xFF757575);
    final date = showTime ? DateFormat.jm(context.lang).format(tx.occurredAt) : DateFormat.MMMd(context.lang).format(tx.occurredAt);
    final subtitle = [category?.label(context) ?? context.tr('Uncategorized'), date].join(' · ');

    return ListTile(
      onTap: onTap,
      contentPadding: onTap == null ? EdgeInsets.zero : null,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      leading: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Icon(iconForKey(category?.iconKey ?? ''), color: color, size: 22),
      ),
      title: Text(
        tx.description.isNotEmpty ? tx.description : (category?.label(context) ?? _typeLabel(context, tx.type)),
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
      subtitle: Text(subtitle, overflow: TextOverflow.ellipsis),
      trailing: Text(
        '${isIncome ? '+' : '−'}${tx.amount.format()}',
        style: TextStyle(
          color: isIncome ? finance.income : finance.expense,
          fontWeight: FontWeight.w800,
          fontSize: 15,
        ),
      ),
    );
  }

  static String _typeLabel(BuildContext context, TransactionType type) => switch (type) {
        TransactionType.expense => context.tr('Expense'),
        TransactionType.income => context.tr('Income'),
        TransactionType.transfer => context.tr('Transfer'),
        TransactionType.savings => context.tr('Savings'),
        TransactionType.savingsWithdrawal => context.tr('Savings withdrawal'),
      };
}
