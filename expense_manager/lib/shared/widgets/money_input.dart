import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/l10n/l10n.dart';
import '../../core/money/currency.dart';
import '../../core/money/money.dart';

/// Validator for amount fields. [allowZero] for budgets.
String? validateMoneyInput(BuildContext context, String? text, Currency currency, {bool allowZero = false}) {
  final money = Money.tryParse(text ?? '', currency);
  if (money == null) return context.tr('Enter a valid amount');
  if (money.isNegative || (!allowZero && money.isZero)) return context.tr('Amount must be greater than zero');
  return null;
}

/// Amount text field with currency prefix and numeric keyboard.
class MoneyFormField extends StatelessWidget {
  const MoneyFormField({
    super.key,
    required this.controller,
    required this.currency,
    this.label,
    this.autofocus = false,
    this.allowZero = false,
    this.large = false,
    this.enabled = true,
  });

  final TextEditingController controller;
  final Currency currency;
  final String? label;
  final bool autofocus;
  final bool allowZero;
  final bool large;
  final bool enabled;

  @override
  Widget build(BuildContext context) => TextFormField(
        controller: controller,
        autofocus: autofocus,
        enabled: enabled,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp('[0-9.,]'))],
        style: large ? Theme.of(context).textTheme.headlineMedium : null,
        decoration: InputDecoration(labelText: label ?? context.tr('Amount'), prefixText: '${currency.symbol} '),
        validator: (text) => validateMoneyInput(context, text, currency, allowZero: allowZero),
      );
}

/// Asks for one amount. Returns null when cancelled.
Future<Money?> showMoneyDialog(
  BuildContext context, {
  required String title,
  required Currency currency,
  Money? initial,
  String? message,
}) =>
    showDialog<Money>(
      context: context,
      builder: (_) => _MoneyDialog(title: title, currency: currency, initial: initial, message: message),
    );

class _MoneyDialog extends StatefulWidget {
  const _MoneyDialog({required this.title, required this.currency, this.initial, this.message});

  final String title;
  final Currency currency;
  final Money? initial;
  final String? message;

  @override
  State<_MoneyDialog> createState() => _MoneyDialogState();
}

class _MoneyDialogState extends State<_MoneyDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _controller = TextEditingController(text: widget.initial?.toDecimalString() ?? '');

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.pop(context, Money.tryParse(_controller.text, widget.currency));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        scrollable: true,
        title: Text(widget.title),
        content: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.message != null) ...[Text(widget.message!), const SizedBox(height: 12)],
              MoneyFormField(controller: _controller, currency: widget.currency, autofocus: true),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(context.tr('Cancel'))),
          FilledButton(onPressed: _submit, child: Text(context.tr('Save'))),
        ],
      );
}
