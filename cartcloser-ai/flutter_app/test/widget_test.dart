import 'package:cartcloser_ai/core/providers.dart';
import 'package:cartcloser_ai/features/judge/scenarios.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'acceptance_flow.dart';

void main() {
  testWidgets('welcome shows the three roles and honest demo labels', (t) async {
    await pumpApp(t);
    expect(find.text('Shopper demo'), findsOneWidget);
    expect(find.text('Merchant dashboard'), findsOneWidget);
    expect(find.text('Guided judge demo'), findsOneWidget);
    expect(find.text('SIMULATED WHATSAPP'), findsOneWidget);
    expect(find.text('OFFLINE DEMO MODE'), findsOneWidget);
  });

  testWidgets('storefront lists products with PKR prices; search filters', (t) async {
    final (router, _) = await pumpApp(t);
    router.go('/shop');
    await settle(t);
    expect(find.text('Linen Kurta - Sage'), findsOneWidget);
    expect(find.text('PKR 4,490'), findsOneWidget);
    await t.enterText(find.byType(TextField).first, 'dupatta');
    await settle(t);
    expect(find.text('Block-Print Dupatta'), findsOneWidget);
    expect(find.text('Linen Kurta - Sage'), findsNothing);
    expect(find.text('Out of stock'), findsOneWidget);
  });

  testWidgets('product page: sold-out sizes cannot be selected', (t) async {
    final (router, _) = await pumpApp(t);
    router.go('/shop');
    await settle(t);
    await tap(t, find.text('Linen Kurta - Sage'));
    expect(find.text('L · sold out'), findsOneWidget);
    final chip = t.widget<ChoiceChip>(find.ancestor(of: find.text('L · sold out'), matching: find.byType(ChoiceChip)));
    expect(chip.onSelected, isNull);
    expect(find.textContaining('Estimate, not a guarantee'), findsOneWidget);
  });

  testWidgets('cart badge and quantity controls update totals', (t) async {
    final (router, c) = await pumpApp(t);
    router.go('/shop');
    await settle(t);
    await tap(t, find.text('Linen Kurta - Sage'));
    await tap(t, find.byKey(const ValueKey('add-to-cart')));
    await tap(t, find.text('Cart'));
    expect(find.textContaining('Checkout · PKR 4,690'), findsOneWidget);
    await tap(t, find.byTooltip('Increase'));
    expect(find.textContaining('Checkout · PKR 8,980'), findsOneWidget); // free shipping over 6,000
    expect(c.read(repositoryProvider).current!.openCartFor('shp_ayesha')!.itemCount, 2);
  });

  testWidgets('guided judge demo: scenario E blocks teen outbound', (t) async {
    final (router, c) = await pumpApp(t);
    router.go('/judge');
    await settle(t);
    c.read(personaProvider.notifier).set('shp_zara');
    final e = scenarios.indexWhere((s) => s.id == 'E');
    await tap(t, find.byKey(const ValueKey('scenario-picker')));
    await tap(t, find.text(scenarios[e].title).last);
    for (var i = 0; i < scenarios[e].steps.length; i++) {
      await tap(t, find.byKey(const ValueKey('guide-run')), ms: 1200);
    }
    final zara = c.read(repositoryProvider).current!.cartsFor('shp_zara').single;
    expect(zara.statusReason, 'under_18_safeguard');
    expect(find.textContaining('Blocked as expected'), findsOneWidget);
    await settle(t, 4500);
  });

  testWidgets('guided judge demo: scenario A runs all 13 steps to a recovered order', (t) async {
    final (router, c) = await pumpApp(t);
    router.go('/judge');
    await settle(t);
    for (var i = 0; i < 13; i++) {
      await tap(t, find.byKey(const ValueKey('guide-run')), ms: 1300);
    }
    final m = c.read(repositoryProvider).current!.metrics;
    expect(m.c('recovered'), 1);
    expect(m.c('contacted'), 1);
    expect(m.c('replied'), 1);
    expect(find.text('Thank you! Your order is placed.'), findsOneWidget);
    await settle(t, 4500);
  });

  testWidgets('merchant settings: integrations stay "Not connected"', (t) async {
    final (router, c) = await pumpApp(t);
    router.go('/merchant');
    await settle(t);
    c.read(merchantNavProvider.notifier).tab(MerchantTab.integrations);
    await settle(t);
    expect(find.text('Not connected'), findsNWidgets(3));
    expect(find.text('Connected'), findsOneWidget);
  });
}
