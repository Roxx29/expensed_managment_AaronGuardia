import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

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
    final isIncome = tx.type == TransactionType.income;
    final color = Color(category?.color ?? 0xFF757575);
    final date = showTime ? DateFormat.jm().format(tx.occurredAt) : DateFormat.MMMd().format(tx.occurredAt);
    final subtitle = [category?.name ?? 'Uncategorized', date].join(' · ');

    return ListTile(
      onTap: onTap,
      contentPadding: onTap == null ? EdgeInsets.zero : null,
      leading: CircleAvatar(
        backgroundColor: color.withValues(alpha: 0.15),
        child: Icon(iconForKey(category?.iconKey ?? ''), color: color, size: 20),
      ),
      title: Text(
        tx.description.isNotEmpty ? tx.description : (category?.name ?? _typeLabel(tx.type)),
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(subtitle, overflow: TextOverflow.ellipsis),
      trailing: Text(
        '${isIncome ? '+' : '−'}${tx.amount.format()}',
        style: TextStyle(
          color: isIncome ? finance.income : finance.expense,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  static String _typeLabel(TransactionType type) => switch (type) {
        TransactionType.expense => 'Expense',
        TransactionType.income => 'Income',
        TransactionType.transfer => 'Transfer',
        TransactionType.savings => 'Savings',
      };
}
