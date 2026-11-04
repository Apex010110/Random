import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app/theme.dart';
import 'core/providers.dart';
import 'features/judge/judge_screen.dart';
import 'features/merchant/merchant_app.dart';
import 'features/shopper/shopper_app.dart';
import 'features/welcome/welcome_screen.dart';

Future<Bootstrap> loadBootstrap({bool withPrefs = true}) async {
  final seed = jsonDecode(await rootBundle.loadString('assets/seed/demo_seed.json')) as Map<String, dynamic>;
  final copy = jsonDecode(await rootBundle.loadString('assets/seed/assistant_copy.json')) as Map<String, dynamic>;
  SharedPreferences? prefs;
  if (withPrefs) {
    try {
      prefs = await SharedPreferences.getInstance(); // non-sensitive settings only
    } catch (_) {}
  }
  return Bootstrap(seed, copy, prefs);
}

GoRouter buildRouter() => GoRouter(routes: [
      GoRoute(path: '/', builder: (_, _) => const WelcomeScreen()),
      GoRoute(path: '/shop', builder: (_, _) => const _Back(child: ShopperApp())),
      GoRoute(path: '/merchant', builder: (_, _) => const _Back(child: MerchantApp())),
      GoRoute(path: '/judge', builder: (_, _) => const JudgeScreen()),
      // Recovery deep link: /r/<cartId>?t=<signed token>
      GoRoute(
        path: '/r/:cartId',
        builder: (_, st) => _DeepLink(cartId: st.pathParameters['cartId']!, token: st.uri.queryParameters['t'] ?? ''),
      ),
    ]);

class CartCloserApp extends StatelessWidget {
  final GoRouter router;
  const CartCloserApp({super.key, required this.router});
  @override
  Widget build(BuildContext context) => MaterialApp.router(
        title: 'CartCloser AI',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        darkTheme: buildTheme(),
        themeMode: ThemeMode.dark,
        routerConfig: router,
      );
}

/// Adds a floating "home" affordance to full-screen role views.
class _Back extends StatelessWidget {
  final Widget child;
  const _Back({required this.child});
  @override
  Widget build(BuildContext context) => Stack(children: [
        child,
        Positioned(
          right: 12,
          bottom: 84,
          child: SafeArea(
            child: FloatingActionButton.small(
              heroTag: null,
              tooltip: 'Back to role switcher',
              backgroundColor: CC.navy2,
              foregroundColor: CC.white,
              onPressed: () => context.go('/'),
              child: const Icon(Icons.apps),
            ),
          ),
        ),
      ]);
}

class _DeepLink extends ConsumerStatefulWidget {
  final String cartId, token;
  const _DeepLink({required this.cartId, required this.token});
  @override
  ConsumerState<_DeepLink> createState() => _DeepLinkState();
}

class _DeepLinkState extends ConsumerState<_DeepLink> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => ref.read(shopperNavProvider.notifier).root(RecoverPage(widget.cartId, widget.token)));
  }

  @override
  Widget build(BuildContext context) => const _Back(child: ShopperApp());
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final boot = await loadBootstrap();
  runApp(ProviderScope(
    overrides: [bootstrapProvider.overrideWithValue(boot)],
    child: CartCloserApp(router: buildRouter()),
  ));
}
