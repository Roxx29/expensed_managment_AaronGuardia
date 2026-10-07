import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/layout/breakpoints.dart';
import '../../../core/utils/ids.dart';
import '../../../domain/entities/entities.dart';
import '../../../shared/providers/providers.dart';
import '../../../shared/widgets/common_widgets.dart';
import '../../premium/application/premium_providers.dart';
import '../../premium/presentation/paywall_screen.dart';
import '../application/catalog_providers.dart';

/// Manage custom categories and payment methods.
class CategoriesScreen extends ConsumerWidget {
  const CategoriesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 2,
      child: Builder(
        builder: (context) => Scaffold(
          appBar: AppBar(
            title: Text(context.tr('Categories & payment methods')),
            bottom: TabBar(
              tabs: [Tab(text: context.tr('Categories')), Tab(text: context.tr('Payment methods'))],
            ),
          ),
          floatingActionButton: FloatingActionButton.extended(
            heroTag: null,
            label: Text(context.tr('New')),
            onPressed: () {
              if (DefaultTabController.of(context).index != 0) {
                _editPaymentMethod(context, ref, null);
              } else if (withinFreeLimit(
                context,
                ref,
                (ref.read(categoriesProvider).value ?? const []).where((c) => !c.isDefault).length,
                FreeLimits.customCategories,
              )) {
                _editCategory(context, ref, null);
              }
            },
          ),
          body: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: Breakpoints.expanded),
              child: const TabBarView(children: [_CategoryList(), _PaymentMethodList()]),
            ),
          ),
        ),
      ),
    );
  }
}

String _kindLabel(BuildContext context, CategoryKind kind) => switch (kind) {
      CategoryKind.expense => context.tr('Expenses'),
      CategoryKind.income => context.tr('Income'),
      CategoryKind.both => context.tr('Expenses & income'),
    };

String _methodTypeLabel(BuildContext context, PaymentMethodType type) => switch (type) {
      PaymentMethodType.cash => context.tr('Cash'),
      PaymentMethodType.debitCard => context.tr('Debit card'),
      PaymentMethodType.creditCard => context.tr('Credit card'),
      PaymentMethodType.bankTransfer => context.tr('Bank transfer'),
      PaymentMethodType.digitalWallet => context.tr('Digital wallet'),
      PaymentMethodType.other => context.tr('Other'),
    };

IconData _methodIcon(PaymentMethodType type) => switch (type) {
      PaymentMethodType.cash => Icons.payments_outlined,
      PaymentMethodType.debitCard || PaymentMethodType.creditCard => Icons.credit_card_rounded,
      PaymentMethodType.bankTransfer => Icons.account_balance_rounded,
      PaymentMethodType.digitalWallet => Icons.account_balance_wallet_rounded,
      PaymentMethodType.other => Icons.more_horiz_rounded,
    };

Future<bool> _confirmArchive(BuildContext context, String name) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.tr('Archive "{name}"?', {'name': name})),
        content: Text(
          context.tr('It will no longer be offered for new transactions. Existing transactions keep it.'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(context.tr('Cancel'))),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(context.tr('Archive'))),
        ],
      ),
    ) ??
    false;

class _CategoryList extends ConsumerWidget {
  const _CategoryList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categories = ref.watch(categoriesProvider).value ?? const <FinanceCategory>[];
    return ListView(
      padding: const EdgeInsets.only(bottom: 96),
      children: [
        for (final c in categories)
          ListTile(
            leading: CircleAvatar(
              backgroundColor: Color(c.color).withValues(alpha: 0.15),
              child: Icon(iconForKey(c.iconKey), color: Color(c.color)),
            ),
            title: Text(c.label(context)),
            subtitle: Text(_kindLabel(context, c.kind)),
            onTap: () => _editCategory(context, ref, c),
            trailing: IconButton(
              tooltip: context.tr('Archive'),
              icon: const Icon(Icons.archive_outlined),
              onPressed: () async {
                if (await _confirmArchive(context, c.label(context))) {
                  await ref.read(catalogActionsProvider).archiveCategory(c.id);
                }
              },
            ),
          ),
      ],
    );
  }
}

class _PaymentMethodList extends ConsumerWidget {
  const _PaymentMethodList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final methods = ref.watch(paymentMethodsProvider).value ?? const <PaymentMethod>[];
    return ListView(
      padding: const EdgeInsets.only(bottom: 96),
      children: [
        for (final m in methods)
          ListTile(
            leading: Icon(_methodIcon(m.type)),
            title: Text(m.label(context)),
            subtitle: Text(_methodTypeLabel(context, m.type)),
            onTap: () => _editPaymentMethod(context, ref, m),
            trailing: IconButton(
              tooltip: context.tr('Archive'),
              icon: const Icon(Icons.archive_outlined),
              onPressed: () async {
                if (await _confirmArchive(context, m.label(context))) {
                  await ref.read(catalogActionsProvider).archivePaymentMethod(m.id);
                }
              },
            ),
          ),
      ],
    );
  }
}

Future<void> _editCategory(BuildContext context, WidgetRef ref, FinanceCategory? existing) async {
  final result = await showDialog<FinanceCategory>(
    context: context,
    builder: (_) => _CategoryDialog(existing: existing),
  );
  if (result != null) await ref.read(catalogActionsProvider).saveCategory(result);
}

Future<void> _editPaymentMethod(BuildContext context, WidgetRef ref, PaymentMethod? existing) async {
  final result = await showDialog<PaymentMethod>(
    context: context,
    builder: (_) => _PaymentMethodDialog(existing: existing),
  );
  if (result != null) await ref.read(catalogActionsProvider).savePaymentMethod(result);
}

class _CategoryDialog extends StatefulWidget {
  const _CategoryDialog({this.existing});

  final FinanceCategory? existing;

  @override
  State<_CategoryDialog> createState() => _CategoryDialogState();
}

class _CategoryDialogState extends State<_CategoryDialog> {
  final _formKey = GlobalKey<FormState>();
  // Late: first read in build(), where context can look up the locale.
  late final _name = TextEditingController(text: widget.existing?.label(context) ?? '');
  late CategoryKind _kind = widget.existing?.kind ?? CategoryKind.expense;
  late String _iconKey = widget.existing?.iconKey ?? 'other';
  late int _color = widget.existing?.color ?? categoryColors.first;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final e = widget.existing;
    final name = _name.text.trim();
    Navigator.pop(
      context,
      FinanceCategory(
        id: e?.id ?? newId(),
        // Unchanged translated default name: keep the stored English name.
        name: e != null && name == e.label(context) ? e.name : name,
        iconKey: _iconKey,
        color: _color,
        kind: _kind,
        isDefault: e?.isDefault ?? false,
        // Custom categories go after the defaults.
        sortOrder: e?.sortOrder ?? 1000,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: Text(widget.existing == null ? context.tr('New category') : context.tr('Edit category')),
      scrollable: true,
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextFormField(
              controller: _name,
              autofocus: widget.existing == null,
              maxLength: 50,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(labelText: context.tr('Name')),
              validator: (v) => (v ?? '').trim().isEmpty ? context.tr('Enter a name') : null,
            ),
            const SizedBox(height: 8),
            SegmentedButton<CategoryKind>(
              showSelectedIcon: false,
              segments: [
                ButtonSegment(value: CategoryKind.expense, label: Text(context.tr('Expense'))),
                ButtonSegment(value: CategoryKind.income, label: Text(context.tr('Income'))),
                ButtonSegment(value: CategoryKind.both, label: Text(context.tr('Both'))),
              ],
              selected: {_kind},
              onSelectionChanged: (s) => setState(() => _kind = s.first),
            ),
            const SizedBox(height: 16),
            Text(context.tr('Icon'), style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 8),
            Wrap(
              spacing: 4,
              runSpacing: 4,
              children: [
                for (final entry in categoryIcons.entries)
                  IconButton(
                    tooltip: entry.key,
                    isSelected: entry.key == _iconKey,
                    style: IconButton.styleFrom(
                      backgroundColor: entry.key == _iconKey ? scheme.secondaryContainer : null,
                    ),
                    icon: Icon(entry.value, color: Color(_color)),
                    onPressed: () => setState(() => _iconKey = entry.key),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Text(context.tr('Color'), style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final color in categoryColors)
                  Semantics(
                    button: true,
                    selected: color == _color,
                    label: context.tr('Color'),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: () => setState(() => _color = color),
                      child: CircleAvatar(
                        radius: 16,
                        backgroundColor: Color(color),
                        child: color == _color
                            ? const Icon(Icons.check_rounded, size: 18, color: Colors.white)
                            : null,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(context.tr('Cancel'))),
        FilledButton(onPressed: _submit, child: Text(context.tr('Save'))),
      ],
    );
  }
}

class _PaymentMethodDialog extends StatefulWidget {
  const _PaymentMethodDialog({this.existing});

  final PaymentMethod? existing;

  @override
  State<_PaymentMethodDialog> createState() => _PaymentMethodDialogState();
}

class _PaymentMethodDialogState extends State<_PaymentMethodDialog> {
  final _formKey = GlobalKey<FormState>();
  // Late: first read in build(), where context can look up the locale.
  late final _name = TextEditingController(text: widget.existing?.label(context) ?? '');
  late PaymentMethodType _type = widget.existing?.type ?? PaymentMethodType.debitCard;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final e = widget.existing;
    final name = _name.text.trim();
    Navigator.pop(
      context,
      PaymentMethod(
        id: e?.id ?? newId(),
        // Unchanged translated default name: keep the stored English name.
        name: e != null && name == e.label(context) ? e.name : name,
        type: _type,
        isDefault: e?.isDefault ?? false,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      scrollable: true,
      title: Text(widget.existing == null ? context.tr('New payment method') : context.tr('Edit payment method')),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _name,
              autofocus: widget.existing == null,
              maxLength: 50,
              decoration: InputDecoration(labelText: context.tr('Name'), hintText: context.tr('e.g. Visa ending 1234')),
              validator: (v) => (v ?? '').trim().isEmpty ? context.tr('Enter a name') : null,
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<PaymentMethodType>(
              initialValue: _type,
              isExpanded: true,
              decoration: InputDecoration(labelText: context.tr('Type')),
              items: [
                for (final t in PaymentMethodType.values)
                  DropdownMenuItem(value: t, child: Text(_methodTypeLabel(context, t))),
              ],
              onChanged: (t) => setState(() => _type = t ?? _type),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(context.tr('Cancel'))),
        FilledButton(onPressed: _submit, child: Text(context.tr('Save'))),
      ],
    );
  }
}
