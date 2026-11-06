import 'dart:async';

import 'engine/demo_engine.dart';
import 'models.dart';
import 'repository.dart';

class LocalRepository implements CartCloserRepository {
  final DemoEngine engine;
  final List<Persona> personas;
  final _ctrl = StreamController<Snapshot>.broadcast();
  StreamSubscription<int>? _sub;
  Snapshot? _current;

  LocalRepository(this.engine, this.personas, {bool runScheduler = true}) {
    _current = _build();
    _sub = engine.changes.listen((_) => _emit());
    if (runScheduler) engine.startScheduler();
  }

  @override
  String get modeLabel => 'Offline demo';
  @override
  bool get isOffline => true;
  @override
  Snapshot? get current => _current;

  @override
  Stream<Snapshot> watch() async* {
    if (_current != null) yield _current!;
    yield* _ctrl.stream;
  }

  void _emit() {
    _current = _build();
    if (!_ctrl.isClosed) _ctrl.add(_current!);
  }

  Snapshot _build() {
    final carts = [for (final c in engine.merchantCarts()) Cart.fromJson(c)];
    final convs = {for (final c in engine.merchantConversations()) c['cart_id'] as String: Conversation.fromJson(c)};
    final orders = {for (final o in engine.merchantOrders()) o['id'] as String: Order.fromJson(o)};
    return Snapshot(
      version: engine.version,
      store: StoreInfo.fromJson(engine.store()),
      products: [for (final p in engine.getCatalog()['products'] as List) Product.fromJson(p)],
      carts: carts,
      conversations: convs,
      orders: orders,
      optedIn: engine.optedInByShopper(),
      metrics: Metrics.fromJson(engine.metrics()),
      settings: Map<String, dynamic>.from(engine.getSettings()['settings']),
      integrations: [for (final i in engine.integrations()) Integration.fromJson(i)],
      catalogPolicy: Map<String, dynamic>.from(engine.policy),
      fetchedAt: engine.now(),
    );
  }

  Future<T> _run<T>(T Function() f) async => f();

  @override
  Future<void> refresh() async => _emit();

  @override
  Future<void> dispose() async {
    await _sub?.cancel();
    engine.dispose();
    await _ctrl.close();
  }

  @override
  Future<Cart> createCart(String shopperId, List<Map<String, dynamic>> items, {String? idempotencyKey}) =>
      _run(() => Cart.fromJson(engine.createCart(shopperId, items, idempotencyKey: idempotencyKey)));

  @override
  Future<Cart> patchCart(String shopperId, String cartId, {List<Map<String, dynamic>>? items, String? promoCode}) =>
      _run(() => Cart.fromJson(engine.patchCart(shopperId, cartId, items: items, promoCode: promoCode)));

  @override
  Future<Cart> checkoutStarted(String shopperId, String cartId, {required String city, required String paymentMethod, required bool optIn}) =>
      _run(() => Cart.fromJson(engine.checkoutStarted(shopperId, cartId, city: city, paymentMethod: paymentMethod, whatsappOptIn: optIn)));

  @override
  Future<Cart> abandon(String shopperId, String cartId, {String? idempotencyKey}) =>
      _run(() => Cart.fromJson(engine.abandon(shopperId, cartId, idempotencyKey: idempotencyKey)));

  @override
  Future<Cart> openRecoveryLink(String cartId, String token) => _run(() => Cart.fromJson(engine.openRecoveryLink(cartId, token)));

  @override
  Future<void> grantConsent(String shopperId) => _run(() => engine.grantConsent(shopperId));

  @override
  Future<void> revokeConsent(String shopperId) => _run(() => engine.revokeConsent(shopperId));

  @override
  Future<List<ChatMessage>> sendMessage(String shopperId, String cartId, String text, {String? idempotencyKey}) =>
      _run(() => [for (final m in engine.postMessage(shopperId, cartId, text, idempotencyKey: idempotencyKey)) ChatMessage.fromJson(m)]);

  @override
  Future<Order> placeOrder({
    required String cartId,
    required String paymentMethod,
    required bool codConfirmed,
    required String idempotencyKey,
    String? discountCode,
    String? recoveryToken,
    String? shopperId,
  }) =>
      _run(() => Order.fromJson(engine.placeOrder(
          cartId: cartId,
          paymentMethod: paymentMethod,
          codConfirmed: codConfirmed,
          idempotencyKey: idempotencyKey,
          discountCode: discountCode,
          recoveryToken: recoveryToken,
          shopperId: shopperId)));

  @override
  Future<String> triggerRecovery(String cartId) => _run(() => engine.triggerDemo(cartId)['status'] as String);

  @override
  Future<void> scheduleRecovery(String cartId) => _run(() => engine.schedule(cartId));

  @override
  Future<void> setCartPaused(String cartId, bool paused) => _run(() => engine.setCartPaused(cartId, paused));

  @override
  Future<void> humanReply(String cartId, String text) => _run(() => engine.humanReply(cartId, text));

  @override
  Future<void> setTakeover(String cartId, bool on) => _run(() => engine.setTakeover(cartId, on));

  @override
  Future<void> patchSettings(Map<String, dynamic> patch) => _run(() => engine.patchSettings(patch));

  @override
  Future<void> patchCatalog({List<Map<String, dynamic>> products = const [], Map<String, dynamic>? policy}) =>
      _run(() => engine.patchCatalog(products: products, policyPatch: policy));

  @override
  Future<Map<String, dynamic>> exportData() => _run(engine.export);

  @override
  Future<Map<String, dynamic>> deleteShopperData(String shopperId) => _run(() => engine.deleteShopperData(shopperId));

  @override
  Future<Metrics> metrics({int? days}) => _run(() => Metrics.fromJson(engine.metrics(days: days)));

  @override
  Future<void> reset() => _run(engine.reset);

  @override
  Future<List<Order>> merchantOrders({String? fulfillmentStatus}) =>
      _run(() => [for (final o in engine.merchantOrders(fulfillmentStatus: fulfillmentStatus)) Order.fromJson(o)]);

  @override
  Future<Order> confirmCod(String orderId, bool confirmed, {bool deliveryZoneOk = true, bool availabilityOk = true}) =>
      _run(() => Order.fromJson(engine.confirmCod(orderId, confirmed, deliveryZoneOk: deliveryZoneOk, availabilityOk: availabilityOk)));

  @override
  Future<Order> correctAddress(String orderId, String addressRedacted, String deliveryZone) =>
      _run(() => Order.fromJson(engine.correctAddress(orderId, addressRedacted, deliveryZone)));

  @override
  Future<Order> holdOrder(String orderId, {String reason = ''}) => _run(() => Order.fromJson(engine.holdOrder(orderId, reason)));

  @override
  Future<Order> releaseOrder(String orderId) => _run(() => Order.fromJson(engine.releaseOrder(orderId)));

  @override
  Future<Order> dispatchOrder(String orderId) => _run(() => Order.fromJson(engine.dispatchOrder(orderId)));

  @override
  Future<Order> retryDispatchOrder(String orderId) => _run(() => Order.fromJson(engine.retryDispatchOrder(orderId)));

  @override
  Future<Order> markDelivered(String orderId) => _run(() => Order.fromJson(engine.markDelivered(orderId)));

  @override
  Future<Order> markFailedAttempt(String orderId, {String reason = ''}) =>
      _run(() => Order.fromJson(engine.markFailedAttempt(orderId, reason)));

  @override
  Future<Order> markReturned(String orderId, {String reason = ''}) => _run(() => Order.fromJson(engine.markReturned(orderId, reason)));

  @override
  Future<Order> cancelOrder(String orderId, {String reason = ''}) => _run(() => Order.fromJson(engine.cancelOrder(orderId, reason)));

  @override
  Future<Map<String, dynamic>> patchAssumptions(Map<String, dynamic> patch) => _run(() => engine.patchAssumptions(patch));

  @override
  Future<List<Map<String, dynamic>>> merchantEvents({String? orderId}) => _run(() => engine.merchantEvents(orderId: orderId));
}
