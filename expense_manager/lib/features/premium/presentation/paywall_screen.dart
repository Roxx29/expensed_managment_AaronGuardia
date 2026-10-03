import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import '../../../app/routes.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/layout/breakpoints.dart';
import '../../../core/theme/app_theme.dart';
import '../application/premium_providers.dart';

/// True if Premium is active; otherwise opens the paywall and returns false.
bool requirePremium(BuildContext context, WidgetRef ref) {
  if (ref.read(premiumProvider)) return true;
  context.push(Routes.premium);
  return false;
}

/// Free plan check before creating one more item: true while [count] is under
/// [limit] or Premium is active; otherwise opens the paywall.
bool withinFreeLimit(BuildContext context, WidgetRef ref, int count, int limit) =>
    count < limit || requirePremium(context, ref);

/// Shows [child] to Premium users and an upgrade card to everyone else.
class PremiumGate extends ConsumerWidget {
  const PremiumGate({super.key, required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) => ref.watch(premiumProvider)
      ? child
      : Scaffold(
          appBar: AppBar(title: Text(title)),
          body: const Center(child: Padding(padding: EdgeInsets.all(16), child: PremiumLockCard())),
        );
}

/// "This is a Premium feature" card with a button to the paywall.
class PremiumLockCard extends StatelessWidget {
  const PremiumLockCard({super.key, this.message});

  final String? message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.workspace_premium_rounded, size: 40, color: theme.colorScheme.primary),
            const SizedBox(height: 8),
            Text(
              message ?? context.tr('This is a Monchi Premium feature.'),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge,
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () => context.push(Routes.premium),
              child: Text(context.tr('See Premium')),
            ),
          ],
        ),
      ),
    );
  }
}

class PaywallScreen extends ConsumerWidget {
  const PaywallScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final premium = ref.watch(premiumProvider);
    final plans = ref.watch(premiumPlansProvider);
    final theme = Theme.of(context);
    final benefits = [
      (Icons.all_inclusive_rounded, context.tr('Unlimited budgets, savings goals, subscriptions and categories')),
      (Icons.insights_rounded, context.tr('Full statistics: yearly highlights, categories and history')),
      (Icons.document_scanner_rounded, context.tr('Scan receipts and import bank statements')),
      (Icons.auto_awesome_rounded, context.tr('Finance assistant')),
      (Icons.lock_rounded, context.tr('Automatic and encrypted backups, CSV export')),
    ];

    return Scaffold(
      appBar: AppBar(title: Text(context.tr('Monchi Premium'))),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: Breakpoints.expanded),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            children: [
              Image.asset('assets/brand/monchi_mark.png', height: 72),
              const SizedBox(height: 8),
              Text(
                premium ? context.tr('You have Monchi Premium. Thank you!') : context.tr('Do more with your money'),
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 16),
              for (final (icon, text) in benefits)
                ListTile(
                  leading: Icon(icon, color: theme.colorScheme.primary),
                  title: Text(text),
                  contentPadding: EdgeInsets.zero,
                ),
              const SizedBox(height: 8),
              if (premium)
                Text(
                  context.tr('Manage or cancel your subscription in Google Play › Payments & subscriptions.'),
                  style: theme.textTheme.bodySmall,
                )
              else
                ...plans.when(
                  loading: () => const [Center(child: CircularProgressIndicator())],
                  error: (_, _) => [_Unavailable(onRetry: () => ref.invalidate(premiumPlansProvider))],
                  data: (list) => list.isEmpty
                      ? [_Unavailable(onRetry: () => ref.invalidate(premiumPlansProvider))]
                      : [
                          for (final p in list) _PlanCard(product: p),
                          const SizedBox(height: 8),
                          Text(
                            context.tr(
                              'Subscriptions renew automatically until you cancel them in Google Play. Cancel at least 24 hours before the renewal date to avoid the next charge. Lifetime is a single payment.',
                            ),
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => ref.read(premiumProvider.notifier).refresh(),
                child: Text(context.tr('Restore purchases')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlanCard extends ConsumerWidget {
  const _PlanCard({required this.product});

  final ProductDetails product;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final price = regularPrice(product);
    final (title, priceText) = switch (product.id) {
      monthlyProductId => (context.tr('Monthly'), context.tr('{price}/month', {'price': price})),
      yearlyProductId => (context.tr('Yearly'), context.tr('{price}/year', {'price': price})),
      _ => (context.tr('Lifetime'), context.tr('{price} once', {'price': price})),
    };
    final yearly = product.id == yearlyProductId;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        shape: yearly
            ? RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: const BorderSide(color: Brand.yellow, width: 2),
              )
            : null,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.titleMedium),
                    Text(
                      hasFreeTrial(product)
                          ? context.tr('Free trial, then {price}', {'price': priceText})
                          : priceText,
                    ),
                    if (yearly)
                      Text(context.tr('Best value'), style: TextStyle(color: FinanceColors.of(context).income)),
                  ],
                ),
              ),
              FilledButton(
                onPressed: () async {
                  final failed = context.tr('Something went wrong. Try again.');
                  final messenger = ScaffoldMessenger.of(context);
                  if (!await ref.read(premiumProvider.notifier).buy(product)) {
                    messenger.showSnackBar(SnackBar(content: Text(failed)));
                  }
                },
                child: Text(hasFreeTrial(product) ? context.tr('Try free') : context.tr('Choose')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Unavailable extends StatelessWidget {
  const _Unavailable({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Column(
        children: [
          Text(
            context.tr('Purchases are not available right now. Install Monchi from Google Play and check your connection.'),
            textAlign: TextAlign.center,
          ),
          TextButton(onPressed: onRetry, child: Text(context.tr('Try again'))),
        ],
      );
}
