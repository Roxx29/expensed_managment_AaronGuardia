import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/money/money.dart';
import '../../../core/time/year_month.dart';
import '../../../domain/finance/statistics_calculator.dart';
import '../../../shared/providers/providers.dart';

/// Year shown on the Statistics screen.
final statisticsYearProvider = NotifierProvider<StatisticsYearNotifier, int>(StatisticsYearNotifier.new);

class StatisticsYearNotifier extends Notifier<int> {
  @override
  int build() => ref.watch(clockProvider)().year;

  void select(int year) => state = year;
}

/// Month selected in the chart (1–12). Defaults to the current month for the
/// current year, December for past years.
final statisticsMonthProvider = NotifierProvider<StatisticsMonthNotifier, int>(StatisticsMonthNotifier.new);

class StatisticsMonthNotifier extends Notifier<int> {
  @override
  int build() {
    final today = ref.watch(clockProvider)();
    return ref.watch(statisticsYearProvider) == today.year ? today.month : 12;
  }

  void select(int month) => state = month;
}

class StatisticsView {
  const StatisticsView({required this.years, required this.year, required this.history});

  final List<int> years;
  final YearStatistics year;
  final Map<int, Money> history;
}

/// Year-level statistics. Does not depend on the selected month, so tapping a
/// bar only recomputes [statisticsComparisonProvider].
final statisticsProvider = Provider<AsyncValue<StatisticsView>>((ref) {
  final year = ref.watch(statisticsYearProvider);
  final currency = ref.watch(currencyProvider);
  final today = ref.watch(clockProvider)();
  return ref.watch(allTransactionsProvider).whenData(
        (all) => StatisticsView(
          // Always contains the selected year, even if its data was deleted.
          years: ({...StatisticsCalculator.availableYears(all, today), year}.toList()
            ..sort((a, b) => b.compareTo(a))),
          year: StatisticsCalculator.year(transactions: all, year: year, currency: currency, today: today),
          history: StatisticsCalculator.expensesByYear(all, currency),
        ),
      );
});

/// Selected month vs the previous one.
final statisticsComparisonProvider = Provider<MonthComparison?>((ref) {
  final month = YearMonth(ref.watch(statisticsYearProvider), ref.watch(statisticsMonthProvider));
  final currency = ref.watch(currencyProvider);
  final all = ref.watch(allTransactionsProvider).value;
  if (all == null) return null;
  return StatisticsCalculator.compareWithPrevious(transactions: all, month: month, currency: currency);
});
