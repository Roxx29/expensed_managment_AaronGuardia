import 'package:flutter/material.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/theme/app_theme.dart';
import '../../../domain/entities/entities.dart';
import '../../../domain/finance/summary_calculator.dart';
import '../application/wallet_cloud.dart';

IconData walletIcon(WalletKind kind) => switch (kind) {
      WalletKind.business => Icons.storefront_rounded,
      WalletKind.family => Icons.family_restroom_rounded,
      WalletKind.other => Icons.account_balance_wallet_rounded,
    };

String walletKindLabel(BuildContext context, WalletKind kind) => switch (kind) {
      WalletKind.business => context.tr('Business'),
      WalletKind.family => context.tr('Family'),
      WalletKind.other => context.tr('Other'),
    };

/// A member's photo, or the initial of their name.
class MemberAvatar extends StatelessWidget {
  const MemberAvatar({super.key, required this.member, this.radius = 18});

  final WalletMember? member;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final photo = member?.photo;
    final name = member?.name.trim() ?? '';
    final scheme = Theme.of(context).colorScheme;
    return CircleAvatar(
      radius: radius,
      backgroundColor: scheme.secondaryContainer,
      // Decoded at display size: a member's file can't make a huge bitmap.
      foregroundImage: photo == null ? null : ResizeImage(MemoryImage(photo), width: (radius * 4).round()),
      child: Text(
        name.isEmpty ? '?' : name.characters.first.toUpperCase(),
        style: TextStyle(color: scheme.onSecondaryContainer, fontWeight: FontWeight.w700),
      ),
    );
  }
}

/// "Income +$x · Expenses −$y" and the month's balance, for one wallet.
class WalletMonthLine extends StatelessWidget {
  const WalletMonthLine({super.key, required this.summary});

  final MonthSummary? summary;

  @override
  Widget build(BuildContext context) {
    final s = summary;
    if (s == null) return const SizedBox.shrink();
    final finance = FinanceColors.of(context);
    return Text.rich(
      TextSpan(children: [
        TextSpan(text: '+${s.income.format()}', style: TextStyle(color: finance.income, fontWeight: FontWeight.w700)),
        const TextSpan(text: '   '),
        TextSpan(text: '−${s.expenses.format()}', style: TextStyle(color: finance.expense, fontWeight: FontWeight.w700)),
      ]),
    );
  }
}
