import '../../core/money/currency.dart';
import '../../core/money/money.dart';
import '../../core/time/year_month.dart';
import '../entities/entities.dart';
import '../finance/dashboard.dart';
import '../finance/recurring_poster.dart';
import '../insights/insights.dart';

/// The user's data an assistant may look at. Never leaves the device with the
/// rule-based implementation.
class AssistantContext {
  const AssistantContext({
    required this.transactions,
    required this.categories,
    required this.recurringItems,
    required this.dashboard,
    required this.currency,
    required this.today,
  });

  final List<FinanceTransaction> transactions;

  /// By id, archived included. Names of built-in categories are English.
  final Map<String, FinanceCategory> categories;
  final List<RecurringItem> recurringItems;

  /// Balance, current-month budgets, upcoming charges and insights.
  final DashboardSnapshot dashboard;
  final Currency currency;
  final DateTime today;
}

/// Display helpers supplied by the UI so the domain stays Flutter-free.
class AssistantLocale {
  const AssistantLocale({
    required String Function(String en, Map<String, Object?> args) translate,
    required this.formatDate,
    required this.categoryLabel,
    required this.insightText,
  }) : _translate = translate;

  final String Function(String en, Map<String, Object?> args) _translate;
  final String Function(DateTime date) formatDate;
  final String Function(FinanceCategory category) categoryLabel;
  final String Function(Insight insight) insightText;

  String tr(String en, [Map<String, Object?> args = const {}]) => _translate(en, args);
}

class AssistantReply {
  const AssistantReply(this.text, {this.suggestions});

  final String text;

  /// Follow-up questions to offer as chips; null = keep the current ones.
  final List<String>? suggestions;
}

/// Swap for an LLM-backed implementation later via a provider override.
abstract interface class FinanceAssistant {
  Future<AssistantReply> ask(String question, AssistantContext data, AssistantLocale l);
}

/// Example questions, phrased so [RuleBasedAssistant] understands them.
List<String> exampleQuestions(AssistantLocale l) => [
      l.tr('How much did I spend this month?'),
      l.tr('Where do I spend the most?'),
      l.tr('How is my budget?'),
      l.tr('What are my upcoming payments?'),
      l.tr('How much do I pay in subscriptions?'),
    ];

/// Lowercase, no accents, no punctuation, single spaces.
String normalizeQuestion(String text) {
  const from = 'áàäâãéèëêíìïîóòöôõúùüûñç';
  const to = 'aaaaaeeeeiiiiooooouuuunc';
  final buffer = StringBuffer();
  for (final ch in text.toLowerCase().split('')) {
    final i = from.indexOf(ch);
    buffer.write(i >= 0 ? to[i] : ch);
  }
  return buffer.toString().replaceAll(RegExp('[^a-z0-9]+'), ' ').trim();
}

enum _Period { today, thisWeek, thisMonth, lastMonth, thisYear, lastYear }

// Words too generic to identify a category by prefix ("month" ≠ "Monthly fees").
const _stopWords = {
  'much', 'spend', 'spent', 'this', 'that', 'month', 'year', 'week', 'today', 'last', 'have', 'what', 'where',
  'money', 'income', 'cuanto', 'cuanta', 'gaste', 'gasto', 'gastos', 'este', 'esta', 'semana', 'pasado', 'dinero',
  'mucho', 'tengo', 'como', 'cual', 'cuales', 'gastado', 'entre', 'para', 'sobre', 'with', 'from', 'about',
};

/// Deterministic keyword matching in English and Spanish. No network.
class RuleBasedAssistant implements FinanceAssistant {
  const RuleBasedAssistant();

  static const _topCount = 3;

  @override
  Future<AssistantReply> ask(String question, AssistantContext data, AssistantLocale l) async {
    final q = ' ${normalizeQuestion(question)} ';
    bool has(List<String> keywords) => keywords.any((k) => q.contains(' $k'));

    if (has(['upcoming', 'next payment', 'next bill', 'due', 'proxim', 'vencimiento', 'por pagar'])) {
      return _upcoming(data, l);
    }
    if (has(['subscription', 'suscrip'])) return _subscriptions(data, l);
    if (has(['budget', 'presupuesto'])) return _budget(data, l);
    if (has(['balance', 'saldo', 'disponible', 'available', 'how much money do i have', 'cuanto dinero tengo'])) {
      return _balance(data, l);
    }
    final period = _period(q);
    if (has(['biggest', 'largest', 'most expensive', 'mayor gasto', 'mayores gastos', 'gasto mas grande', 'gastos mas grandes', 'mas caro'])) {
      return _biggest(data, l, period);
    }
    if (has(['where do i spend', 'spend the most', 'spend most', 'top categor', 'en que gasto', 'gasto mas', 'categories', 'categorias'])) {
      return _topCategories(data, l, period);
    }
    if (has(['tip', 'advice', 'recommend', 'insight', 'how can i save', 'consejo', 'recomend', 'como ahorr'])) {
      return _tip(data, l);
    }
    final category = _matchCategory(q, data, l);
    if (category != null) return _categorySpent(data, l, period, category);
    if (has(['earn', 'income', 'receive', 'made', 'gane', 'ingres', 'recibi', 'cobre'])) {
      return _income(data, l, period);
    }
    if (has(['spen', 'expens', 'pay', 'paid', 'gast', 'pague'])) return _spent(data, l, period);
    return AssistantReply(
      l.tr('I can answer questions about your own data. Try one of these:'),
      suggestions: exampleQuestions(l),
    );
  }

  // --- Parsing ----------------------------------------------------------------

  _Period _period(String q) {
    bool has(List<String> keywords) => keywords.any((k) => q.contains(' $k'));
    if (has(['last month', 'previous month', 'mes pasado', 'mes anterior'])) return _Period.lastMonth;
    if (has(['last year', 'previous year', 'ano pasado', 'ano anterior'])) return _Period.lastYear;
    if (has(['this year', 'este ano', 'en el ano', 'year', 'ano '])) return _Period.thisYear;
    if (has(['today', 'hoy'])) return _Period.today;
    if (has(['week', 'semana'])) return _Period.thisWeek;
    return _Period.thisMonth;
  }

  /// Full label/name first, then a word that is a prefix of it, or it plus a
  /// plural ending ("gifts" → Gift; not "gastado" → Gas).
  FinanceCategory? _matchCategory(String q, AssistantContext data, AssistantLocale l) {
    final words = q.trim().split(' ').where((w) => w.length >= 4 && !_stopWords.contains(w)).toList();
    FinanceCategory? partial;
    for (final c in data.categories.values) {
      for (final name in {normalizeQuestion(l.categoryLabel(c)), normalizeQuestion(c.name)}) {
        if (name.isEmpty) continue;
        if (q.contains(' $name ')) return c;
        if (partial == null && words.any((w) => name.startsWith(w) || (w.startsWith(name) && w.length - name.length <= 2))) partial = c;
      }
    }
    return partial;
  }

  ({DateTime from, DateTime to, String label}) _range(_Period p, DateTime today, AssistantLocale l) {
    final day = dateOnly(today);
    final month = YearMonth.fromDate(today);
    return switch (p) {
      _Period.today => (from: day, to: DateTime(day.year, day.month, day.day + 1), label: l.tr('today')),
      _Period.thisWeek => (
          from: DateTime(day.year, day.month, day.day - (day.weekday - 1)),
          to: DateTime(day.year, day.month, day.day - (day.weekday - 1) + 7),
          label: l.tr('this week'),
        ),
      _Period.thisMonth => (from: month.start, to: month.endExclusive, label: l.tr('this month')),
      _Period.lastMonth => (from: month.previous.start, to: month.previous.endExclusive, label: l.tr('last month')),
      _Period.thisYear => (from: DateTime(day.year), to: DateTime(day.year + 1), label: l.tr('this year')),
      _Period.lastYear => (from: DateTime(day.year - 1), to: DateTime(day.year), label: l.tr('last year')),
    };
  }

  /// Transactions of [type] in the period and main currency, highest first.
  List<FinanceTransaction> _select(
    AssistantContext data,
    TransactionType type,
    ({DateTime from, DateTime to, String label}) r, {
    String? categoryId,
  }) =>
      data.transactions
          .where((t) =>
              t.type == type &&
              t.amount.currency == data.currency &&
              !t.occurredAt.isBefore(r.from) &&
              t.occurredAt.isBefore(r.to) &&
              (categoryId == null || t.categoryId == categoryId))
          .toList()
        ..sort((a, b) => b.amount.compareTo(a.amount));

  Money _sum(AssistantContext data, List<FinanceTransaction> items) =>
      Money.sum(items.map((t) => t.amount), data.currency);

  String _categoryName(AssistantContext data, AssistantLocale l, String? id) {
    final c = id == null ? null : data.categories[id];
    return c == null ? l.tr('Uncategorized') : l.categoryLabel(c);
  }

  // --- Intents ----------------------------------------------------------------

  AssistantReply _spent(AssistantContext data, AssistantLocale l, _Period p) {
    final r = _range(p, data.today, l);
    final items = _select(data, TransactionType.expense, r);
    if (items.isEmpty) return AssistantReply(l.tr('You have no expenses recorded {period}.', {'period': r.label}));
    return AssistantReply(l.tr('You spent {amount} {period} in {count} expenses.',
        {'amount': _sum(data, items).format(), 'period': r.label, 'count': items.length}));
  }

  AssistantReply _categorySpent(AssistantContext data, AssistantLocale l, _Period p, FinanceCategory c) {
    final r = _range(p, data.today, l);
    final isIncome = c.kind == CategoryKind.income;
    final items =
        _select(data, isIncome ? TransactionType.income : TransactionType.expense, r, categoryId: c.id);
    final args = {'category': l.categoryLabel(c), 'amount': _sum(data, items).format(), 'period': r.label};
    return AssistantReply(isIncome
        ? l.tr('{category}: you received {amount} {period}.', args)
        : l.tr('{category}: you spent {amount} {period}.', args));
  }

  AssistantReply _income(AssistantContext data, AssistantLocale l, _Period p) {
    final r = _range(p, data.today, l);
    final items = _select(data, TransactionType.income, r);
    if (items.isEmpty) return AssistantReply(l.tr('You have no income recorded {period}.', {'period': r.label}));
    return AssistantReply(
        l.tr('You received {amount} in income {period}.', {'amount': _sum(data, items).format(), 'period': r.label}));
  }

  AssistantReply _balance(AssistantContext data, AssistantLocale l) {
    final d = data.dashboard;
    return AssistantReply(l.tr(
      'Your available money is {amount}. This month you received {income} and spent {expenses}.',
      {
        'amount': d.availableBalance.format(),
        'income': d.summary.income.format(),
        'expenses': d.summary.expenses.format(),
      },
    ));
  }

  AssistantReply _biggest(AssistantContext data, AssistantLocale l, _Period p) {
    final r = _range(p, data.today, l);
    final items = _select(data, TransactionType.expense, r).take(_topCount);
    if (items.isEmpty) return AssistantReply(l.tr('You have no expenses recorded {period}.', {'period': r.label}));
    return AssistantReply([
      l.tr('Your biggest expenses {period}:', {'period': r.label}),
      for (final t in items)
        '• ${t.amount.format()} — ${t.description.isEmpty ? _categoryName(data, l, t.categoryId) : t.description} '
            '(${l.formatDate(t.occurredAt)})',
    ].join('\n'));
  }

  AssistantReply _topCategories(AssistantContext data, AssistantLocale l, _Period p) {
    final r = _range(p, data.today, l);
    final items = _select(data, TransactionType.expense, r);
    if (items.isEmpty) return AssistantReply(l.tr('You have no expenses recorded {period}.', {'period': r.label}));
    final total = _sum(data, items);
    final byCategory = <String?, Money>{};
    for (final t in items) {
      byCategory[t.categoryId] = (byCategory[t.categoryId] ?? Money.zero(data.currency)) + t.amount;
    }
    final top = byCategory.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return AssistantReply([
      l.tr('Where your money went {period}:', {'period': r.label}),
      for (final e in top.take(_topCount))
        '• ${_categoryName(data, l, e.key)}: ${e.value.format()} (${divideRounded(e.value.minor * 100, total.minor)}%)',
    ].join('\n'));
  }

  AssistantReply _budget(AssistantContext data, AssistantLocale l) {
    final report = data.dashboard.budgets;
    final global = report.global;
    if (global == null && report.byCategory.isEmpty) {
      return AssistantReply(l.tr('You have no budget set for this month.'));
    }
    final lines = <String>[
      if (global != null)
        global.remaining.isNegative
            ? l.tr('Monthly budget: {spent} of {budgeted} spent, over by {amount}.',
                {'spent': global.spent.format(), 'budgeted': global.budgeted.format(), 'amount': (-global.remaining).format()})
            : l.tr('Monthly budget: {spent} of {budgeted} spent, {amount} left.',
                {'spent': global.spent.format(), 'budgeted': global.budgeted.format(), 'amount': global.remaining.format()}),
      for (final e in report.byCategory.entries)
        '• ${_categoryName(data, l, e.key)}: ${e.value.spent.format()} / ${e.value.budgeted.format()}',
    ];
    if (!report.hasAlerts) lines.add(l.tr('Everything is on track.'));
    return AssistantReply(lines.join('\n'));
  }

  AssistantReply _subscriptions(AssistantContext data, AssistantLocale l) {
    final active = data.recurringItems
        .where((i) => i.isActive && i.kind == RecurringKind.subscription && i.amount.currency == data.currency)
        .toList()
      ..sort((a, b) => b.monthlyCost.compareTo(a.monthlyCost));
    if (active.isEmpty) return AssistantReply(l.tr('You have no active subscriptions.'));
    final totals = RecurringPoster.totals(active, data.currency);
    return AssistantReply([
      l.tr('Active subscriptions: {count}. They cost {monthly} per month ({yearly} per year).', {
        'count': totals.count,
        'monthly': totals.monthly.format(),
        'yearly': totals.yearly.format(),
      }),
      for (final i in active) '• ${i.name}: ${i.monthlyCost.format()}',
    ].join('\n'));
  }

  AssistantReply _upcoming(AssistantContext data, AssistantLocale l) {
    final charges = data.dashboard.upcomingCharges;
    final days = {'days': DashboardComposer.upcomingWindowDays};
    if (charges.isEmpty) return AssistantReply(l.tr('No payments due in the next {days} days.', days));
    return AssistantReply([
      l.tr('Payments due in the next {days} days:', days),
      for (final c in charges) '• ${l.formatDate(c.dueDate)} — ${c.item.name}: ${c.item.amount.format()}',
    ].join('\n'));
  }

  AssistantReply _tip(AssistantContext data, AssistantLocale l) {
    final insights = data.dashboard.insights;
    if (insights.isNotEmpty) return AssistantReply(l.insightText(insights.first));
    return AssistantReply(
        l.tr('No warnings right now. A good habit: set aside part of your income as soon as you receive it.'));
  }
}
