import 'package:expense_manager/core/l10n/strings_es.dart';
import 'package:expense_manager/core/money/currency.dart';
import 'package:expense_manager/core/money/money.dart';
import 'package:expense_manager/core/time/year_month.dart';
import 'package:expense_manager/data/database/default_data.dart';
import 'package:expense_manager/domain/assistant/assistant.dart';
import 'package:expense_manager/domain/entities/entities.dart';
import 'package:expense_manager/domain/finance/dashboard.dart';
import 'package:expense_manager/domain/finance/recurrence.dart';
import 'package:expense_manager/domain/insights/insights.dart';
import 'package:flutter_test/flutter_test.dart';

const usd = Currency.usd;
String m(int minor) => Money(minor, usd).format();

void main() {
  final today = DateTime(2026, 9, 15); // Tuesday; week = Sep 14–20

  FinanceTransaction tx(String id, TransactionType type, int minor, DateTime at, {String? cat, String desc = ''}) =>
      FinanceTransaction(id: id, type: type, amount: Money(minor, usd), occurredAt: at, categoryId: cat, description: desc);

  final transactions = [
    tx('e1', TransactionType.expense, 5000, DateTime(2026, 9, 15, 10), cat: 'cat_food', desc: 'Groceries'),
    tx('e2', TransactionType.expense, 3000, DateTime(2026, 9, 14), cat: 'cat_gas', desc: 'Fuel'),
    tx('e3', TransactionType.expense, 500, DateTime(2026, 9, 13)),
    tx('e4', TransactionType.expense, 2000, DateTime(2026, 8, 5), cat: 'cat_food', desc: 'Lunch'),
    tx('e5', TransactionType.expense, 100000, DateTime(2026, 2, 1), cat: 'cat_home', desc: 'Rent'),
    tx('i1', TransactionType.income, 200000, DateTime(2026, 9, 1), cat: 'cat_salary'),
    tx('i2', TransactionType.income, 50000, DateTime(2026, 8, 1), cat: 'cat_salary'),
  ];
  final netflix = RecurringItem(
    id: 'r1',
    kind: RecurringKind.subscription,
    name: 'Netflix',
    amount: const Money(1500, usd),
    rule: const RecurrenceRule(Frequency.monthly),
    anchorDate: DateTime(2026, 1, 20),
  );

  AssistantContext context({List<RecurringItem> recurring = const [], List<Budget>? budgets}) => AssistantContext(
        transactions: transactions,
        categories: {for (final c in defaultCategories) c.id: c},
        recurringItems: recurring,
        currency: usd,
        today: today,
        dashboard: DashboardComposer.compose(
          today: today,
          currency: usd,
          transactions: transactions,
          budgets: budgets ??
              const [
                Budget(id: 'b1', amount: Money(100000, usd), startMonth: YearMonth(2026, 1)),
                Budget(id: 'b2', amount: Money(4000, usd), startMonth: YearMonth(2026, 1), categoryId: 'cat_food'),
              ],
          recurringItems: recurring,
          totalsByType: {
            TransactionType.income: const Money(250000, usd),
            TransactionType.expense: const Money(110500, usd),
          },
          insightsEngine: RuleBasedInsightsEngine.withDefaultRules(),
        ),
      );

  AssistantLocale locale(String lang) => AssistantLocale(
        translate: (en, args) {
          var text = lang == 'es' ? (esStrings[en] ?? en) : en;
          for (final e in args.entries) {
            text = text.replaceAll('{${e.key}}', '${e.value}');
          }
          return text;
        },
        formatDate: (d) => '${d.month}/${d.day}',
        categoryLabel: (c) => lang == 'es' && c.isDefault ? (esDefaultNames[c.name] ?? c.name) : c.name,
        insightText: (i) => 'TIP:${i.type.name}',
      );

  Future<AssistantReply> ask(String q, String lang, {AssistantContext? data}) =>
      const RuleBasedAssistant().ask(q, data ?? context(recurring: [netflix]), locale(lang));

  Future<void> expectReply(String q, String lang, List<String> parts) async {
    final reply = await ask(q, lang);
    for (final p in parts) {
      expect(reply.text, contains(p), reason: q);
    }
  }

  test('normalizes case, accents and punctuation', () {
    expect(normalizeQuestion('¿Cuánto GASTÉ en el año?'), 'cuanto gaste en el ano');
  });

  test('total spent per period', () async {
    await expectReply('How much did I spend this month?', 'en', [m(8500), 'this month', '3 expenses']);
    await expectReply('How much did I spend last month', 'en', [m(2000), 'last month']);
    await expectReply('how much did I spend this year', 'en', [m(110500)]);
    await expectReply('how much did I spend today', 'en', [m(5000), 'today']);
    await expectReply('how much did I spend this week', 'en', [m(8000), 'this week']);
    await expectReply('¿Cuánto gasté este mes?', 'es', [m(8500), 'este mes']);
    await expectReply('cuánto gasté el mes pasado', 'es', [m(2000)]);
    await expectReply('Cuánto gasté este año', 'es', [m(110500)]);
    await expectReply('cuanto gaste hoy', 'es', [m(5000)]);
    await expectReply('cuánto gasté esta semana', 'es', [m(8000)]);
  });

  test('spent in a category, by name, translated label or prefix', () async {
    await expectReply('How much on food this month?', 'en', ['Food', m(5000)]);
    await expectReply('how much on food last month', 'en', [m(2000)]);
    await expectReply('how much on transport', 'en', ['Transportation', m(0)]);
    await expectReply('¿Cuánto gasté en comida?', 'es', ['Comida', m(5000)]);
    await expectReply('cuanto en gasolina', 'es', ['Gasolina', m(3000)]);
  });

  test('income', () async {
    await expectReply('How much did I earn this month?', 'en', [m(200000)]);
    await expectReply('¿Cuánto gané el mes pasado?', 'es', [m(50000)]);
    await expectReply('ingresos', 'es', [m(200000)]);
  });

  test('balance', () async {
    await expectReply('What is my balance?', 'en', [m(139500)]);
    await expectReply('dinero disponible', 'es', [m(139500)]);
    await expectReply('saldo', 'es', [m(139500)]);
  });

  test('biggest expenses', () async {
    final reply = await ask('What was my biggest expense?', 'en');
    expect(reply.text.split('\n')[1], '• ${m(5000)} — Groceries (9/15)');
    await expectReply('mayor gasto este año', 'es', ['Rent', m(100000)]);
  });

  test('top categories', () async {
    final reply = await ask('Where do I spend the most?', 'en');
    expect(reply.text.split('\n')[1], startsWith('• Food: ${m(5000)} (59%)'));
    expect(reply.text, contains('Uncategorized'));
    await expectReply('¿En qué gasto más?', 'es', ['Comida', 'Sin categoría']);
  });

  test('budget status', () async {
    await expectReply('How is my budget?', 'en', [m(8500), m(100000), m(91500), '• Food: ${m(5000)} / ${m(4000)}']);
    await expectReply('¿Cómo va mi presupuesto?', 'es', ['Comida']);
    final none = await ask('budget', 'en', data: context(budgets: const []));
    expect(none.text, 'You have no budget set for this month.');
  });

  test('subscriptions', () async {
    await expectReply('How much do I pay in subscriptions?', 'en', ['Active subscriptions: 1', m(1500), m(18000), 'Netflix']);
    await expectReply('suscripciones', 'es', ['Netflix', m(18000)]);
    final none = await ask('subscriptions', 'en', data: context());
    expect(none.text, 'You have no active subscriptions.');
  });

  test('upcoming payments', () async {
    await expectReply('What are my upcoming payments?', 'en', ['9/20', 'Netflix', m(1500)]);
    await expectReply('próximos pagos', 'es', ['9/20', 'Netflix']);
  });

  test('tips come from the top insight', () async {
    await expectReply('Any tips?', 'en', ['TIP:${InsightType.budgetExceeded.name}']);
    await expectReply('dame un consejo', 'es', ['TIP:${InsightType.budgetExceeded.name}']);
  });

  test('unknown questions get help with example questions that are understood', () async {
    for (final lang in ['en', 'es']) {
      final help = await ask('hello there', lang);
      expect(help.suggestions, hasLength(5));
      for (final q in help.suggestions!) {
        expect((await ask(q, lang)).suggestions, isNull, reason: q);
      }
    }
  });
}
