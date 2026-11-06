import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_repository.dart';
import 'engine/demo_engine.dart';
import 'local_repository.dart';
import 'models.dart';
import 'repository.dart';

/// Loaded once in main() from bundled assets (works offline).
class Bootstrap {
  final Map<String, dynamic> seed, assistantCopy;
  final SharedPreferences? prefs;
  Bootstrap(this.seed, this.assistantCopy, this.prefs);
  List<Persona> get personas => [for (final p in seed['personas'] as List) Persona.fromJson(p)];
  List<String> get cities => List<String>.from(seed['cities'] as List);
}

final bootstrapProvider = Provider<Bootstrap>((ref) => throw UnimplementedError('override in main'));

// ---------------------------------------------------------------- app mode
@immutable
class AppMode {
  final bool offline;
  final String backendUrl;
  final String merchantToken;
  const AppMode({this.offline = true, this.backendUrl = 'http://localhost:8000', this.merchantToken = 'demo-merchant-token'});
  AppMode copyWith({bool? offline, String? backendUrl, String? merchantToken}) =>
      AppMode(offline: offline ?? this.offline, backendUrl: backendUrl ?? this.backendUrl, merchantToken: merchantToken ?? this.merchantToken);
}

class AppModeNotifier extends Notifier<AppMode> {
  @override
  AppMode build() {
    final prefs = ref.read(bootstrapProvider).prefs;
    return AppMode(
      offline: prefs?.getBool('offline') ?? true,
      backendUrl: prefs?.getString('backend_url') ?? 'http://localhost:8000',
    );
  }

  void set(AppMode m) {
    state = m;
    final prefs = ref.read(bootstrapProvider).prefs;
    prefs?.setBool('offline', m.offline);
    prefs?.setString('backend_url', m.backendUrl);
  }
}

final appModeProvider = NotifierProvider<AppModeNotifier, AppMode>(AppModeNotifier.new);

/// Test seam: a fixed clock for the offline engine.
final engineClockProvider = Provider<DateTime Function()?>((ref) => null);
final runSchedulerProvider = Provider<bool>((ref) => true);

final repositoryProvider = Provider<CartCloserRepository>((ref) {
  final mode = ref.watch(appModeProvider);
  final boot = ref.read(bootstrapProvider);
  final CartCloserRepository repo = mode.offline
      ? LocalRepository(DemoEngine(boot.seed, boot.assistantCopy, clock: ref.read(engineClockProvider)), boot.personas,
          runScheduler: ref.read(runSchedulerProvider))
      : ApiRepository(baseUrl: mode.backendUrl, merchantToken: mode.merchantToken, personas: boot.personas);
  ref.onDispose(repo.dispose);
  return repo;
});

final snapshotProvider = StreamProvider<Snapshot>((ref) => ref.watch(repositoryProvider).watch());

// ---------------------------------------------------------------- preferences
class ReducedMotionNotifier extends Notifier<bool> {
  @override
  bool build() => ref.read(bootstrapProvider).prefs?.getBool('reduced_motion') ?? false;
  void set(bool v) {
    state = v;
    ref.read(bootstrapProvider).prefs?.setBool('reduced_motion', v);
  }
}

final reducedMotionProvider = NotifierProvider<ReducedMotionNotifier, bool>(ReducedMotionNotifier.new);

// ---------------------------------------------------------------- session: who is shopping
class PersonaNotifier extends Notifier<String> {
  @override
  String build() => 'shp_ayesha';
  void set(String id) => state = id;
}

final personaProvider = NotifierProvider<PersonaNotifier, String>(PersonaNotifier.new);

final currentPersonaProvider = Provider<Persona>((ref) {
  final id = ref.watch(personaProvider);
  return ref.watch(bootstrapProvider).personas.firstWhere((p) => p.id == id);
});

// ---------------------------------------------------------------- shopper navigation (data-driven, so the guided demo can drive it)
sealed class ShopperPage {
  const ShopperPage();
  String get key;
}

class StorePage extends ShopperPage {
  const StorePage();
  @override
  String get key => 'store';
}

class ProductPage extends ShopperPage {
  final String productId;
  const ProductPage(this.productId);
  @override
  String get key => 'product:$productId';
}

class CartPageRoute extends ShopperPage {
  const CartPageRoute();
  @override
  String get key => 'cart';
}

class CheckoutPage extends ShopperPage {
  const CheckoutPage();
  @override
  String get key => 'checkout';
}

class InboxPage extends ShopperPage {
  const InboxPage();
  @override
  String get key => 'inbox';
}

class ChatPage extends ShopperPage {
  final String cartId;
  const ChatPage(this.cartId);
  @override
  String get key => 'chat:$cartId';
}

class RecoverPage extends ShopperPage {
  final String cartId, token;
  const RecoverPage(this.cartId, this.token);
  @override
  String get key => 'recover:$cartId';
}

class ReceiptPage extends ShopperPage {
  final String orderId;
  const ReceiptPage(this.orderId);
  @override
  String get key => 'receipt:$orderId';
}

class ProfilePage extends ShopperPage {
  const ProfilePage();
  @override
  String get key => 'profile';
}

class ShopperNav extends Notifier<List<ShopperPage>> {
  @override
  List<ShopperPage> build() => const [StorePage()];
  void push(ShopperPage p) {
    if (state.last.key == p.key) return;
    state = [...state, p];
  }

  void pop() {
    if (state.length > 1) state = state.sublist(0, state.length - 1);
  }

  void root(ShopperPage p) => state = [p];
  void replaceTop(ShopperPage p) => state = [...state.sublist(0, state.length - 1), p];
  ShopperPage get top => state.last;
}

final shopperNavProvider = NotifierProvider<ShopperNav, List<ShopperPage>>(ShopperNav.new);

// ---------------------------------------------------------------- merchant navigation
enum MerchantTab { overview, analytics, carts, inbox, orders, green, catalog, campaign, integrations, settings }

@immutable
class MerchantNavState {
  final MerchantTab tab;
  final String? cartId, orderId;
  final int? days; // date filter: null = all time
  const MerchantNavState({this.tab = MerchantTab.overview, this.cartId, this.orderId, this.days});
}

class MerchantNav extends Notifier<MerchantNavState> {
  @override
  MerchantNavState build() => const MerchantNavState();
  void tab(MerchantTab t) => state = MerchantNavState(
      tab: t, cartId: t == MerchantTab.carts || t == MerchantTab.inbox ? state.cartId : null,
      orderId: t == MerchantTab.orders ? state.orderId : null, days: state.days);
  void openCart(String id, {MerchantTab tab = MerchantTab.carts}) => state = MerchantNavState(tab: tab, cartId: id, days: state.days);
  void closeCart() => state = MerchantNavState(tab: state.tab, days: state.days);
  void openOrder(String id) => state = MerchantNavState(tab: MerchantTab.orders, orderId: id, days: state.days);
  void closeOrder() => state = MerchantNavState(tab: state.tab, days: state.days);
  void days(int? d) => state = MerchantNavState(tab: state.tab, cartId: state.cartId, orderId: state.orderId, days: d);
}

final merchantNavProvider = NotifierProvider<MerchantNav, MerchantNavState>(MerchantNav.new);

/// Date-filtered metrics. "All time" comes straight from the live snapshot.
final filteredMetricsProvider = FutureProvider<Metrics?>((ref) async {
  final days = ref.watch(merchantNavProvider.select((s) => s.days));
  final snap = ref.watch(snapshotProvider).value;
  if (snap == null) return null;
  if (days == null) return snap.metrics;
  return ref.read(repositoryProvider).metrics(days: days);
});
