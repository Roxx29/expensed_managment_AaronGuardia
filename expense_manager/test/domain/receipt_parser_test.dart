import 'package:expense_manager/core/money/currency.dart';
import 'package:expense_manager/core/money/money.dart';
import 'package:expense_manager/domain/import/receipt_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 10, 1, 12);

  test('Spanish supermarket receipt', () {
    final r = parseReceipt([
      'SUPERMERCADO LA ECONOMÍA',
      'RUC 155-1-2345 DV 12',
      'Av. Central 45, Panamá',
      'FACTURA 001-0004567',
      'FECHA: 28/09/2026 14:35',
      '1 LECHE ENTERA 1L 1,25',
      '2 PAN BLANCO 3,50',
      'SUBTOTAL 4,75',
      'ITBMS 7% 0,33',
      'TOTAL A PAGAR 5,08',
      'EFECTIVO 10,00',
      'CAMBIO 4,92',
    ], Currency.pab, now: now);
    expect(r.merchant, 'SUPERMERCADO LA ECONOMÍA');
    expect(r.date, DateTime(2026, 9, 28));
    expect(r.total, const Money(508, Currency.pab));
  });

  test('English receipt with US date and tax total', () {
    final r = parseReceipt([
      'Walmart',
      'Store #1234 (555) 123-4567',
      '09/27/26 10:42 AM',
      'MILK 2% GAL 3.98',
      'BREAD 2.50',
      'SUBTOTAL 6.48',
      'TAX 1 8.25% 0.53',
      'TOTAL TAX 0.53',
      'TOTAL 7.01',
      'VISA TEND 20.00',
    ], Currency.usd, now: now);
    expect(r.merchant, 'Walmart');
    expect(r.date, DateTime(2026, 9, 27));
    expect(r.total, const Money(701, Currency.usd));
  });

  test('label and amount on separate lines; month names', () {
    final r = parseReceipt([
      'Thank you for visiting',
      'Blue Bottle Coffee',
      'Sep 29, 2026',
      'Latte 5.25',
      'Croissant 4.00',
      'GRAND TOTAL',
      r'$ 9.25',
      'CASH 20.00',
    ], Currency.usd, now: now);
    expect(r.merchant, 'Blue Bottle Coffee');
    expect(r.date, DateTime(2026, 9, 29));
    expect(r.total, const Money(925, Currency.usd));
  });

  test('IMPORTE with thousands separators and day-month-name date', () {
    final r = parseReceipt([
      'FERRETERÍA EL CLAVO',
      '15 AGO 2026',
      'IMPORTE: 1.234,50 EUR',
    ], Currency.eur, now: now);
    expect(r.date, DateTime(2026, 8, 15));
    expect(r.total, const Money(123450, Currency.eur));
  });

  test('falls back to the largest amount; ignores future dates', () {
    final r = parseReceipt(['12.00', '3.40', '01/01/2030'], Currency.usd, now: now);
    expect(r.total, const Money(1200, Currency.usd));
    expect(r.date, isNull);
    expect(r.merchant, isNull);
  });

  test('ambiguous dates are day-first unless month-first is preferred', () {
    expect(parseReceipt(['03/04/2026'], Currency.usd, now: now).date, DateTime(2026, 4, 3));
    expect(
      parseReceipt(['03/04/2026'], Currency.usd, now: now, preferMonthFirst: true).date,
      DateTime(2026, 3, 4),
    );
  });

  test('nothing useful', () {
    expect(parseReceipt(['', '  ', '***'], Currency.usd, now: now).isEmpty, isTrue);
  });
}
