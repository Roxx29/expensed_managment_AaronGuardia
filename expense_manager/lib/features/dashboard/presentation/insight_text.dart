import 'package:flutter/widgets.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/money/money.dart';
import '../../../domain/entities/entities.dart';
import '../../../domain/insights/insights.dart';
import '../../../shared/widgets/common_widgets.dart';

/// Turns a structured [Insight] into user-facing text. Kept in presentation
/// so it can move to ARB localization files without touching the rules.
String insightMessage(BuildContext context, Insight insight, Map<String, FinanceCategory> categories) {
  String categoryName() {
    final id = insight.values['categoryId'] as String?;
    if (id == null) return context.tr('Your monthly budget');
    return categories[id]?.label(context) ?? context.tr('A category');
  }

  String money(String key) => (insight.values[key] as Money?)?.format() ?? '';

  return switch (insight.type) {
    InsightType.budgetExceeded =>
      context.tr('{category} is over budget by {amount}.', {'category': categoryName(), 'amount': money('over')}),
    InsightType.budgetNearLimit => context.tr('{category} is almost used up — {amount} left.',
        {'category': categoryName(), 'amount': money('remaining')},
      ),
    InsightType.spendingIncreased => context.tr('Spending is up {percent}% compared with last month.',
        {'percent': insight.values['percent']},
      ),
    InsightType.highSubscriptionCost => context.tr('Subscriptions cost {amount}/month ({percent}% of your income).',
        {'amount': money('monthly'), 'percent': insight.values['percentOfIncome']},
      ),
    InsightType.categoryAboveAverage => context.tr('{category} spending ({amount}) is well above its usual {average}.',
        {'category': categoryName(), 'amount': money('current'), 'average': money('average')},
      ),
  };
}
