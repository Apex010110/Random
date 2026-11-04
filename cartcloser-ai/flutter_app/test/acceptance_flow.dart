// Shared UI acceptance flow (MRD section 1), used by test/acceptance_test.dart (headless)
// and integration_test/app_test.dart (device / browser).
import 'package:cartcloser_ai/core/providers.dart';
import 'package:cartcloser_ai/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

/// Wednesday 12:00 Pakistan time: outside quiet hours, so the demo send is not deferred.
DateTime fixedNow() => DateTime.utc(2026, 11, 4, 7);

Future<void> settle(WidgetTester t, [int ms = 900]) async {
  for (var i = 0; i < ms ~/ 100; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

Future<void> tap(WidgetTester t, Finder f, {int ms = 700}) async {
  // Toasts are floating snackbars; clear them so they never sit on top of the next target.
  for (final m in t.stateList<ScaffoldMessengerState>(find.byType(ScaffoldMessenger))) {
    m.removeCurrentSnackBar();
  }
  await t.pump();
  await t.ensureVisible(f);
  await t.pump();
  await t.tap(f, warnIfMissed: false);
  await settle(t, ms);
}

Bootstrap? _boot;

Future<(GoRouter, ProviderContainer)> pumpApp(WidgetTester t) async {
  t.view.physicalSize = const Size(1600, 1000);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  // Real async I/O must run outside the fake-async test zone; load once and reuse.
  final boot = _boot ??= (await t.runAsync(() => loadBootstrap(withPrefs: false)))!;
  final router = buildRouter();
  final container = ProviderContainer(overrides: [
    bootstrapProvider.overrideWithValue(boot),
    engineClockProvider.overrideWithValue(fixedNow),
    runSchedulerProvider.overrideWithValue(false),
  ]);
  addTearDown(container.dispose);
  await t.pumpWidget(UncontrolledProviderScope(container: container, child: CartCloserApp(router: router)));
  await settle(t);
  return (router, container);
}

Future<void> runAcceptance(WidgetTester t) async {
  final (router, c) = await pumpApp(t);
  final repo = c.read(repositoryProvider);

  // 1. choose shopper
  await tap(t, find.byKey(const ValueKey('role-shopper')));
  // 2. browse + open the linen kurta
  await tap(t, find.text('Linen Kurta - Sage'));
  // 3. add to cart (size M preselected)
  await tap(t, find.byKey(const ValueKey('add-to-cart')));
  expect(repo.current!.openCartFor('shp_ayesha')!.itemCount, 1);
  // 4. checkout
  await tap(t, find.text('Cart'));
  await tap(t, find.textContaining('Checkout ·'));
  // 5. consent box is NOT pre-checked; shopper ticks it
  final box = t.widget<CheckboxListTile>(find.byKey(const ValueKey('optin')));
  expect(box.value, isFalse, reason: 'consent must never be pre-checked');
  await tap(t, find.byKey(const ValueKey('optin')));
  // 6. abandon
  await tap(t, find.byKey(const ValueKey('leave-checkout')), ms: 1200);
  final cart = repo.current!.cartsFor('shp_ayesha').single;
  expect(cart.status, 'scheduled');
  expect(cart.optedIn, isTrue);

  // 7. merchant sees the eligible abandoned cart and triggers the simulated recovery
  router.go('/merchant');
  await settle(t);
  expect(find.text('READY FOR RECOVERY'), findsOneWidget);
  await tap(t, find.textContaining('Ayesha ·').first);
  await tap(t, find.byKey(const ValueKey('trigger-recovery')), ms: 1200);
  expect(repo.current!.cart(cart.id)!.status, 'message_sent');

  // 8. shopper inbox
  router.go('/shop');
  await settle(t);
  await tap(t, find.text('Messages'));
  await tap(t, find.text('UrbanThread PK').last);
  // 9. delivery question: grounded answer with honest no-guarantee
  await t.enterText(find.byKey(const ValueKey('chat-input')), 'Will it arrive in Karachi by Friday?');
  await tap(t, find.byKey(const ValueKey('chat-send')), ms: 1600);
  expect(find.textContaining("can't guarantee Friday"), findsOneWidget);
  // 10. COD question: policy-grounded answer
  await t.enterText(find.byKey(const ValueKey('chat-input')), 'Can I pay COD?');
  await tap(t, find.byKey(const ValueKey('chat-send')), ms: 1600);
  expect(find.textContaining('cash on delivery is available'), findsOneWidget);
  expect(repo.current!.metrics.c('recovered'), 0, reason: 'a reply is not a recovery');
  // 11. open the checkout link in the app
  await tap(t, find.text('Complete checkout').last, ms: 1200);
  expect(find.text('Secure checkout link'), findsOneWidget);
  expect(repo.current!.metrics.c('recovered'), 0, reason: 'a link click is not a recovery');
  // 12. confirm COD order
  await tap(t, find.byKey(const ValueKey('confirm-cod')));
  await tap(t, find.byKey(const ValueKey('confirm-order')), ms: 1500);
  expect(find.text('Thank you! Your order is placed.'), findsOneWidget);
  // 13. dashboard updates recovered orders + attributed revenue
  final m = repo.current!.metrics;
  expect(m.c('recovered'), 1);
  expect(m.money['attributed_recovered_sales_pkr'], 4690);
  router.go('/merchant');
  c.read(merchantNavProvider.notifier).tab(MerchantTab.overview);
  await settle(t, 1500);
  expect(find.text('PKR 4,690'), findsWidgets);

  // Repeat with NO opt-in (Bilal): no outbound recovery is sent.
  router.go('/shop');
  await settle(t);
  await tap(t, find.text('Profile'));
  await tap(t, find.text('Bilal, adult, Lahore'));
  await tap(t, find.text('Shop'));
  await tap(t, find.text('Linen Kurta - Sage'));
  await tap(t, find.byKey(const ValueKey('add-to-cart')));
  await tap(t, find.text('Cart'));
  await tap(t, find.textContaining('Checkout ·'));
  expect(t.widget<CheckboxListTile>(find.byKey(const ValueKey('optin'))).value, isFalse);
  await tap(t, find.byKey(const ValueKey('leave-checkout')), ms: 1200);
  final bilal = repo.current!.cartsFor('shp_bilal').single;
  expect(bilal.status, 'not_eligible');
  expect(bilal.statusReason, 'no_consent');
  router.go('/merchant');
  c.read(merchantNavProvider.notifier).tab(MerchantTab.carts);
  await settle(t);
  await tap(t, find.textContaining('Bilal ·').first);
  await tap(t, find.byKey(const ValueKey('trigger-recovery')), ms: 1200);
  expect(repo.current!.conversations[bilal.id], isNull, reason: 'no message may exist without consent');
  expect(repo.current!.metrics.c('contacted'), 1);
  await settle(t, 4500); // let toasts expire
}
