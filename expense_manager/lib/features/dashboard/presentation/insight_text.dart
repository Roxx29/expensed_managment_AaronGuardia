import '../../../core/money/money.dart';
import '../../../domain/entities/entities.dart';
import '../../../domain/insights/insights.dart';

/// Turns a structured [Insight] into user-facing text. Kept in presentation
/// so it can move to ARB localization files without touching the rules.
String insightMessage(Insight insight, Map<String, FinanceCategory> categories) {
  String categoryName() {
    final id = insight.values['categoryId'] as String?;
    return id == null ? 'Your monthly budget' : (categories[id]?.name ?? 'A category');
  }

  String money(String key) => (insight.values[key] as Money?)?.format() ?? '';

  return switch (insight.type) {
    InsightType.budgetExceeded => '${categoryName()} is over budget by ${money('over')}.',
    InsightType.budgetNearLimit =>
      '${categoryName()} is almost used up — ${money('remaining')} left.',
    InsightType.spendingIncreased =>
      'Spending is up ${insight.values['percent']}% compared with last month.',
    InsightType.highSubscriptionCost =>
      'Subscriptions cost ${money('monthly')}/month '
          '(${insight.values['percentOfIncome']}% of your income).',
    InsightType.categoryAboveAverage =>
      '${categoryName()} spending (${money('current')}) is well above its '
          'usual ${money('average')}.',
  };
}
