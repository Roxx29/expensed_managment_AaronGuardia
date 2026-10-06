import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/routes.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/layout/breakpoints.dart';
import '../../../core/theme/app_theme.dart';
import '../../../domain/premium/premium_status.dart';
import '../../../shared/widgets/motion.dart';
import '../../backup/application/cloud_backup.dart';
import '../application/gift_providers.dart';
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
    final status = ref.watch(premiumStatusProvider);
    final premium = status != null;
    // A gift can end; buying keeps Premium afterwards. Play buyers manage it in Play.
    final showPlans = status == null || status.plan == PremiumPlan.gift;
    final plans = ref.watch(premiumPlansProvider);
    final theme = Theme.of(context);
    final benefits = [
      (Icons.all_inclusive_rounded, context.tr('Unlimited budgets, savings goals, subscriptions and categories')),
      (Icons.insights_rounded, context.tr('Full statistics: yearly highlights, categories and history')),
      (Icons.document_scanner_rounded, context.tr('Scan receipts and import bank statements')),
      (Icons.auto_awesome_rounded, context.tr('Finance assistant')),
      (Icons.sync_rounded, context.tr('Sync between your phones or with your partner (encrypted)')),
      (Icons.lock_rounded, context.tr('Automatic backups and CSV export')),
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
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.6, end: 1),
                duration: const Duration(milliseconds: 700),
                curve: Curves.elasticOut,
                builder: (context, t, child) => Transform.scale(scale: t, child: child),
                child: Image.asset('assets/brand/monchi_mark.png', height: 72),
              ),
              const SizedBox(height: 8),
              Text(
                premium ? context.tr('You have Monchi Premium. Thank you!') : context.tr('Do more with your money'),
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 16),
              if (status != null) FadeSlideIn(child: PremiumStatusCard(status: status)),
              for (final (i, (icon, text)) in benefits.indexed)
                FadeSlideIn(
                  index: i + 1,
                  child: ListTile(
                    leading: Icon(icon, color: theme.colorScheme.primary),
                    title: Text(text),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              const SizedBox(height: 8),
              if (showPlans)
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
              if (cloudAvailable) const _GiftCard(),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => ref.read(playPremiumProvider.notifier).refresh(),
                child: Text(context.tr('Restore purchases')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One line for menus: "Free plan", "Active · renews Nov 4, 2026", ...
String premiumSummary(BuildContext context, PremiumStatus? status) {
  if (status == null) return context.tr('Free plan');
  final until = status.until;
  if (until == null) return context.tr('Active · never expires');
  final date = DateFormat.yMMMd(context.lang).format(until);
  return status.renews
      ? context.tr('Active · renews {date}', {'date': date})
      : context.tr('Active until {date}', {'date': date});
}

/// Plan, renewal or end date, days left and a link to manage it in Google Play.
class PremiumStatusCard extends StatelessWidget {
  const PremiumStatusCard({super.key, required this.status});

  final PremiumStatus status;

  static const _package = 'com.nubiksoft.monchi';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final now = DateTime.now();
    final dateFormat = DateFormat.yMMMd(context.lang);
    final until = status.until;
    final daysLeft = status.daysLeft(now);
    final warn = status.endsSoon(now);
    const warnColor = Brand.coral; // readable on the ink card
    final subscription = status.plan == PremiumPlan.monthly || status.plan == PremiumPlan.yearly;
    final planName = switch (status.plan) {
      PremiumPlan.monthly => context.tr('Monthly'),
      PremiumPlan.yearly => context.tr('Yearly'),
      PremiumPlan.lifetime => context.tr('Lifetime'),
      PremiumPlan.gift => context.tr('Gift from Monchi'),
      PremiumPlan.unknown => context.tr('Monchi Premium'),
    };
    final main = until == null
        ? context.tr('Never expires')
        : status.renews
            ? context.tr('Renews on {date}', {'date': dateFormat.format(until)})
            : context.tr('Active until {date}', {'date': dateFormat.format(until)});

    return Card(
      color: Brand.ink,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.workspace_premium_rounded, color: Brand.yellow),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    context.tr('Your plan'),
                    style: theme.textTheme.labelLarge?.copyWith(color: Colors.white70),
                  ),
                ),
                Chip(
                  label: Text(planName),
                  backgroundColor: Brand.yellow,
                  labelStyle: const TextStyle(color: Brand.ink, fontWeight: FontWeight.w700),
                  side: BorderSide.none,
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              main,
              style: theme.textTheme.titleLarge?.copyWith(color: Colors.white, fontWeight: FontWeight.w800),
            ),
            if (daysLeft != null) ...[
              const SizedBox(height: 4),
              Text(
                switch (daysLeft) {
                  <= 0 => context.tr('Ends today'),
                  1 => context.tr('1 day left'),
                  _ => context.tr('{days} days left', {'days': daysLeft}),
                },
                style: TextStyle(color: warn ? warnColor : Colors.white70, fontWeight: warn ? FontWeight.w700 : null),
              ),
            ],
            if (status.purchasedAt case final since?) ...[
              const SizedBox(height: 4),
              Text(
                context.tr('Premium since {date}', {'date': dateFormat.format(since)}),
                style: const TextStyle(color: Colors.white70),
              ),
            ],
            if (subscription && !status.renews) ...[
              const SizedBox(height: 8),
              Text(
                context.tr('Your subscription is canceled. You keep Premium until that date.'),
                style: const TextStyle(color: warnColor),
              ),
            ],
            if (subscription) ...[
              const SizedBox(height: 12),
              FilledButton.tonalIcon(
                onPressed: () => launchUrl(
                  Uri.parse(
                    'https://play.google.com/store/account/subscriptions?sku=${status.plan == PremiumPlan.monthly ? monthlyProductId : yearlyProductId}&package=$_package',
                  ),
                  mode: LaunchMode.externalApplication,
                ),
                icon: const Icon(Icons.open_in_new_rounded),
                label: Text(context.tr('Manage subscription')),
              ),
              const SizedBox(height: 8),
              Text(
                context.tr('Dates are estimated from your purchase; Google Play shows the exact ones.'),
                style: theme.textTheme.bodySmall?.copyWith(color: Colors.white60),
              ),
            ],
          ],
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
    // Lifetime is highlighted: no renewals, the plan families prefer.
    final lifetime = product.id == lifetimeProductId;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        shape: lifetime
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
                    if (product.id == yearlyProductId)
                      Text(context.tr('One payment a year'), style: Theme.of(context).textTheme.bodySmall),
                    if (lifetime)
                      Text(
                        context.tr('Best value: pay once, no renewals'),
                        style: TextStyle(color: FinanceColors.of(context).income, fontWeight: FontWeight.w700),
                      ),
                  ],
                ),
              ),
              FilledButton(
                onPressed: () async {
                  final failed = context.tr('Something went wrong. Try again.');
                  final messenger = ScaffoldMessenger.of(context);
                  if (!await ref.read(playPremiumProvider.notifier).buy(product)) {
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

/// Premium given by Monchi (e-mail gift or promo code) needs a Google account.
class _GiftCard extends ConsumerStatefulWidget {
  const _GiftCard();

  @override
  ConsumerState<_GiftCard> createState() => _GiftCardState();
}

class _GiftCardState extends ConsumerState<_GiftCard> {
  bool _busy = false;

  Future<void> _run(Future<String?> Function() task) async {
    if (_busy) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    final failed = context.tr('Could not connect to the cloud. Check your internet connection and try again.');
    try {
      final message = await task();
      if (message != null) messenger.showSnackBar(SnackBar(content: Text(message)));
    } on Object {
      messenger.showSnackBar(SnackBar(content: Text(failed)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String?> _askCode() => showDialog<String>(context: context, builder: (_) => const _CodeDialog());

  @override
  Widget build(BuildContext context) {
    final email = ref.watch(cloudUserProvider).value;
    final texts = {
      RedeemResult.redeemed: context.tr('Code redeemed. Enjoy Monchi Premium!'),
      RedeemResult.invalid: context.tr('This code does not exist or has expired.'),
      RedeemResult.used: context.tr('This code was already used.'),
      RedeemResult.alreadyRedeemed: context.tr('You already redeemed a code.'),
    };
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(context.tr('Have a code or a gift?'), style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              email == null
                  ? context.tr('Sign in to receive Premium gifted by Monchi or to redeem a code.')
                  : context.tr('Signed in as {email}', {'email': email}),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            if (email == null)
              FilledButton.tonalIcon(
                onPressed: _busy
                    ? null
                    : () => context.push(Routes.welcome),
                icon: const Icon(Icons.login_rounded),
                label: Text(context.tr('Sign in')),
              )
            else
              FilledButton.tonalIcon(
                onPressed: _busy
                    ? null
                    : () => _run(() async {
                          final code = await _askCode();
                          if (code == null || code.trim().isEmpty) return null;
                          return texts[await ref.read(giftActionsProvider).redeem(code)];
                        }),
                icon: const Icon(Icons.redeem_rounded),
                label: Text(context.tr('Redeem a code')),
              ),
          ],
        ),
      ),
    );
  }
}

class _CodeDialog extends StatefulWidget {
  const _CodeDialog();

  @override
  State<_CodeDialog> createState() => _CodeDialogState();
}

class _CodeDialogState extends State<_CodeDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(context.tr('Redeem a code')),
        content: TextField(
          controller: _controller,
          autofocus: true,
          textCapitalization: TextCapitalization.characters,
          decoration: InputDecoration(labelText: context.tr('Code')),
          onSubmitted: (v) => Navigator.pop(context, v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(context.tr('Cancel'))),
          FilledButton(onPressed: () => Navigator.pop(context, _controller.text), child: Text(context.tr('Redeem'))),
        ],
      );
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
