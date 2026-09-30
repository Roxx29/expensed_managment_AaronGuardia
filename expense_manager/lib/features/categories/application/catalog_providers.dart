import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/entities/entities.dart';
import '../../../shared/providers/providers.dart';

final catalogActionsProvider = Provider<CatalogActions>(CatalogActions.new);

/// Write-side use cases for categories and payment methods.
class CatalogActions {
  CatalogActions(this._ref);

  final Ref _ref;

  Future<void> saveCategory(FinanceCategory category) =>
      _ref.read(categoryRepositoryProvider).save(category);

  /// Archived categories disappear from pickers but keep labelling history.
  Future<void> archiveCategory(String id) => _ref.read(categoryRepositoryProvider).archive(id);

  Future<void> savePaymentMethod(PaymentMethod method) =>
      _ref.read(paymentMethodRepositoryProvider).save(method);

  Future<void> archivePaymentMethod(String id) =>
      _ref.read(paymentMethodRepositoryProvider).archive(id);
}
