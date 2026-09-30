/// Supported currencies. No conversion is performed between them (MVP rule).
enum Currency {
  usd('USD', r'$', 'US Dollar', 2),
  eur('EUR', '€', 'Euro', 2),
  gbp('GBP', '£', 'British Pound', 2),
  cad('CAD', r'CA$', 'Canadian Dollar', 2),
  mxn('MXN', r'MX$', 'Mexican Peso', 2),
  pab('PAB', 'B/.', 'Panamanian Balboa', 2);

  const Currency(this.code, this.symbol, this.displayName, this.decimalDigits);

  /// ISO 4217 code, persisted in the database.
  final String code;
  final String symbol;
  final String displayName;

  /// Number of minor-unit digits (2 → cents).
  final int decimalDigits;

  /// 10^decimalDigits, e.g. 100 for cents.
  int get minorPerMajor {
    var factor = 1;
    for (var i = 0; i < decimalDigits; i++) {
      factor *= 10;
    }
    return factor;
  }

  static const Currency fallback = Currency.usd;

  static Currency fromCode(String? code) {
    for (final c in Currency.values) {
      if (c.code == code) return c;
    }
    return fallback;
  }
}
