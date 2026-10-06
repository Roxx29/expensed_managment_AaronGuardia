import 'package:expense_manager/shared/widgets/monchi_background.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget app(bool premium, {bool reduceMotion = false}) => MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: reduceMotion),
          child: MonchiBackground(isPremium: premium),
        ),
      );

  testWidgets('free is static, Premium animates, reduce motion keeps it still', (tester) async {
    await tester.pumpWidget(app(false));
    expect(find.byType(StaticMonchiBackground), findsOneWidget);
    expect(find.byType(AnimatedMonchiBackground), findsNothing);

    await tester.pumpWidget(app(true));
    expect(find.byType(AnimatedMonchiBackground), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    expect(tester.binding.hasScheduledFrame, isTrue, reason: 'the ambient loop keeps ticking');

    await tester.pumpWidget(app(true, reduceMotion: true));
    expect(find.byType(AnimatedMonchiBackground), findsNothing);
    expect(find.byType(StaticMonchiBackground), findsOneWidget);
  });
}
