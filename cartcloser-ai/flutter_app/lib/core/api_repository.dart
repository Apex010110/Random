import 'dart:async';

import 'package:dio/dio.dart';

import 'models.dart';
import 'repository.dart';

/// Talks to the FastAPI backend. Live updates: polls GET /changes (cheap) every second and
/// refetches when the change-feed version moves (SSE exists at /merchant/stream; polling is the
/// portable fallback that also works on Flutter web without extra packages).
class ApiRepository implements CartCloserRepository {
  final Dio _dio;
  final String merchantToken;
  final List<Persona> personas;
  final _ctrl = StreamController<Snapshot>.broadcast();
  Snapshot? _current;
  Timer? _poll;
  int _lastVersion = -1;
  String? lastError;

  ApiRepository({required String baseUrl, required this.merchantToken, required this.personas, Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              baseUrl: baseUrl,
              connectTimeout: const Duration(seconds: 4),
              receiveTimeout: const Duration(seconds: 10),
              headers: {'Content-Type': 'application/json'},
            )) {
    _poll = Timer.periodic(const Duration(seconds: 1), (_) => _checkVersion());
    refresh();
  }

  @override
  String get modeLabel => 'Backend: ${_dio.options.baseUrl}';
  @override
  bool get isOffline => false;
  @override
  Snapshot? get current => _current;

  @override
  Stream<Snapshot> watch() async* {
    if (_current != null) yield _current!;
    yield* _ctrl.stream;
  }

  Options get _m => Options(headers: {'Authorization': 'Bearer $merchantToken'});
  Options _s(String shopperId) => Options(headers: {'X-Shopper-Id': shopperId});

  Future<T> _call<T>(Future<Response> Function() f, T Function(dynamic) parse) async {
    try {
      final r = await f();
      final out = parse(r.data);
      unawaited(refresh());
      return out;
    } on DioException catch (e) {
      final data = e.response?.data;
      if (data is Map && data['error'] != null) throw ApiException(e.response!.statusCode ?? 500, data['error'], data['message'] ?? 'Error');
      throw ApiException(0, 'network', 'Backend unreachable: ${e.message ?? e.type.name}');
    }
  }

  Future<void> _checkVersion() async {
    try {
      final r = await _dio.get('/changes');
      final v = (r.data['version'] as num).toInt();
      if (v != _lastVersion) await refresh();
      lastError = null;
    } catch (e) {
      lastError = 'Backend unreachable';
    }
  }

  Future<void>? _inflight;
  bool _again = false;

  /// Coalesces concurrent refreshes but guarantees the returned future reflects state
  /// at least as new as the moment refresh() was called.
  @override
  Future<void> refresh() async {
    if (_inflight != null) {
      _again = true;
      while (_inflight != null) {
        await _inflight;
      }
      return;
    }
    do {
      _again = false;
      _inflight = _fetch();
      await _inflight;
      _inflight = null;
    } while (_again);
  }

  Future<void> _fetch() async {
    try {
      final results = await Future.wait([
        _dio.get('/changes'),
        _dio.get('/store'),
        _dio.get('/merchant/catalog', options: _m),
        _dio.get('/merchant/carts', queryParameters: {'limit': 200}, options: _m),
        _dio.get('/merchant/conversations', queryParameters: {'limit': 200}, options: _m),
        _dio.get('/merchant/orders', queryParameters: {'limit': 500}, options: _m),
        _dio.get('/merchant/metrics', options: _m),
        _dio.get('/merchant/settings', options: _m),
        _dio.get('/merchant/integrations', options: _m),
        for (final p in personas) _dio.get('/consents/me', options: _s(p.id)),
      ]);
      _lastVersion = (results[0].data['version'] as num).toInt();
      final catalog = results[2].data as Map;
      _current = Snapshot(
        version: _lastVersion,
        store: StoreInfo.fromJson(results[1].data),
        products: [for (final p in catalog['products'] as List) Product.fromJson(p)],
        carts: [for (final c in results[3].data['items'] as List) Cart.fromJson(c)],
        conversations: {for (final c in results[4].data['items'] as List) c['cart_id'] as String: Conversation.fromJson(c)},
        orders: {for (final o in results[5].data['items'] as List) o['id'] as String: Order.fromJson(o)},
        metrics: Metrics.fromJson(results[6].data),
        settings: Map<String, dynamic>.from(results[7].data['settings']),
        integrations: [for (final i in results[8].data as List) Integration.fromJson(i)],
        optedIn: {for (var i = 0; i < personas.length; i++) personas[i].id: results[9 + i].data['opted_in'] == true},
        catalogPolicy: Map<String, dynamic>.from(catalog['policy']),
        fetchedAt: DateTime.now().toUtc(),
      );
      if (!_ctrl.isClosed) _ctrl.add(_current!);
      lastError = null;
    } catch (e) {
      lastError = e is DioException ? 'Backend unreachable' : 'Unexpected backend data: $e';
      if (_current == null && !_ctrl.isClosed) _ctrl.addError(ApiException(0, 'backend', lastError!));
    }
  }

  /// Connectivity check used by Settings before switching modes.
  static Future<Map<String, dynamic>> probe(String baseUrl) async {
    final d = Dio(BaseOptions(baseUrl: baseUrl, connectTimeout: const Duration(seconds: 3), receiveTimeout: const Duration(seconds: 3)));
    final r = await d.get('/health');
    return Map<String, dynamic>.from(r.data);
  }

  @override
  Future<void> dispose() async {
    _poll?.cancel();
    await _ctrl.close();
  }

  @override
  Future<Cart> createCart(String shopperId, List<Map<String, dynamic>> items, {String? idempotencyKey}) =>
      _call(() => _dio.post('/carts', data: {'items': items, 'idempotency_key': idempotencyKey}, options: _s(shopperId)), (d) => Cart.fromJson(d));

  @override
  Future<Cart> patchCart(String shopperId, String cartId, {List<Map<String, dynamic>>? items, String? promoCode}) => _call(
      () => _dio.patch('/carts/$cartId', data: {'items': ?items, 'promo_code': ?promoCode}, options: _s(shopperId)),
      (d) => Cart.fromJson(d));

  @override
  Future<Cart> checkoutStarted(String shopperId, String cartId, {required String city, required String paymentMethod, required bool optIn}) =>
      _call(
          () => _dio.post('/carts/$cartId/checkout-started',
              data: {'city': city, 'payment_method': paymentMethod, 'whatsapp_opt_in': optIn}, options: _s(shopperId)),
          (d) => Cart.fromJson(d));

  @override
  Future<Cart> abandon(String shopperId, String cartId, {String? idempotencyKey}) =>
      _call(() => _dio.post('/carts/$cartId/abandon', data: {'idempotency_key': idempotencyKey}, options: _s(shopperId)), (d) => Cart.fromJson(d));

  @override
  Future<Cart> openRecoveryLink(String cartId, String token) =>
      _call(() => _dio.get('/r/$cartId', queryParameters: {'t': token}), (d) => Cart.fromJson(d));

  @override
  Future<void> grantConsent(String shopperId) => _call(
      () => _dio.post('/consents', data: {'shopper_id': shopperId, 'source': 'preferences', 'affirmative': true}, options: _s(shopperId)),
      (_) {});

  @override
  Future<void> revokeConsent(String shopperId) =>
      _call(() => _dio.post('/consents/revoke', data: {'shopper_id': shopperId, 'source': 'preferences'}, options: _s(shopperId)), (_) {});

  @override
  Future<List<ChatMessage>> sendMessage(String shopperId, String cartId, String text, {String? idempotencyKey}) => _call(
      () => _dio.post('/conversations/$cartId/messages', data: {'text': text, 'idempotency_key': idempotencyKey}, options: _s(shopperId)),
      (d) => [for (final m in d as List) ChatMessage.fromJson(m)]);

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
      _call(
          () => _dio.post('/orders',
              data: {
                'cart_id': cartId,
                'payment_method': paymentMethod,
                'cod_confirmed': codConfirmed,
                'idempotency_key': idempotencyKey,
                'discount_code': ?discountCode,
                'recovery_token': ?recoveryToken,
              },
              options: shopperId == null ? null : _s(shopperId)),
          (d) => Order.fromJson(d));

  @override
  Future<String> triggerRecovery(String cartId) =>
      _call(() => _dio.post('/recovery/$cartId/trigger-demo', options: _m), (d) => d['status'] as String);

  @override
  Future<void> scheduleRecovery(String cartId) => _call(() => _dio.post('/recovery/$cartId/schedule', options: _m), (_) {});

  @override
  Future<void> setCartPaused(String cartId, bool paused) =>
      _call(() => _dio.post('/merchant/carts/$cartId/pause', data: {'on': paused}, options: _m), (_) {});

  @override
  Future<void> humanReply(String cartId, String text) =>
      _call(() => _dio.post('/merchant/conversations/$cartId/reply', data: {'text': text}, options: _m), (_) {});

  @override
  Future<void> setTakeover(String cartId, bool on) =>
      _call(() => _dio.post('/merchant/conversations/$cartId/takeover', data: {'on': on}, options: _m), (_) {});

  @override
  Future<void> patchSettings(Map<String, dynamic> patch) => _call(() => _dio.patch('/merchant/settings', data: patch, options: _m), (_) {});

  @override
  Future<void> patchCatalog({List<Map<String, dynamic>> products = const [], Map<String, dynamic>? policy}) =>
      _call(() => _dio.patch('/merchant/catalog', data: {'products': products, 'policy': ?policy}, options: _m), (_) {});

  @override
  Future<Map<String, dynamic>> exportData() =>
      _call(() => _dio.get('/merchant/export', options: _m), (d) => Map<String, dynamic>.from(d));

  @override
  Future<Map<String, dynamic>> deleteShopperData(String shopperId) =>
      _call(() => _dio.delete('/merchant/shoppers/$shopperId', options: _m), (d) => Map<String, dynamic>.from(d));

  @override
  Future<Metrics> metrics({int? days}) =>
      _call(() => _dio.get('/merchant/metrics', queryParameters: {'days': ?days}, options: _m), (d) => Metrics.fromJson(d));

  @override
  Future<void> reset() => _call(() => _dio.post('/demo/reset'), (_) {});

  @override
  Future<List<Order>> merchantOrders({String? fulfillmentStatus}) => _call(
      () => _dio.get('/merchant/orders', queryParameters: {'fulfillment_status': ?fulfillmentStatus, 'limit': 500}, options: _m),
      (d) => [for (final o in d['items'] as List) Order.fromJson(o)]);

  @override
  Future<Order> confirmCod(String orderId, bool confirmed, {bool deliveryZoneOk = true, bool availabilityOk = true}) => _call(
      () => _dio.post('/orders/$orderId/confirm-cod',
          data: {'confirmed': confirmed, 'delivery_zone_ok': deliveryZoneOk, 'availability_ok': availabilityOk}, options: _m),
      (d) => Order.fromJson(d));

  @override
  Future<Order> correctAddress(String orderId, String addressRedacted, String deliveryZone) => _call(
      () => _dio.post('/orders/$orderId/correct-address',
          data: {'address_redacted': addressRedacted, 'delivery_zone': deliveryZone}, options: _m),
      (d) => Order.fromJson(d));

  @override
  Future<Order> holdOrder(String orderId, {String reason = ''}) =>
      _call(() => _dio.post('/orders/$orderId/hold', data: {'reason': reason}, options: _m), (d) => Order.fromJson(d));

  @override
  Future<Order> releaseOrder(String orderId) => _call(() => _dio.post('/orders/$orderId/release', options: _m), (d) => Order.fromJson(d));

  @override
  Future<Order> dispatchOrder(String orderId) => _call(() => _dio.post('/orders/$orderId/dispatch', options: _m), (d) => Order.fromJson(d));

  @override
  Future<Order> retryDispatchOrder(String orderId) =>
      _call(() => _dio.post('/orders/$orderId/retry-dispatch', options: _m), (d) => Order.fromJson(d));

  @override
  Future<Order> markDelivered(String orderId) => _call(() => _dio.post('/orders/$orderId/delivered', options: _m), (d) => Order.fromJson(d));

  @override
  Future<Order> markFailedAttempt(String orderId, {String reason = ''}) =>
      _call(() => _dio.post('/orders/$orderId/failed-attempt', data: {'reason': reason}, options: _m), (d) => Order.fromJson(d));

  @override
  Future<Order> markReturned(String orderId, {String reason = ''}) =>
      _call(() => _dio.post('/orders/$orderId/returned', data: {'reason': reason}, options: _m), (d) => Order.fromJson(d));

  @override
  Future<Order> cancelOrder(String orderId, {String reason = ''}) =>
      _call(() => _dio.post('/orders/$orderId/cancel', data: {'reason': reason}, options: _m), (d) => Order.fromJson(d));

  @override
  Future<Map<String, dynamic>> patchAssumptions(Map<String, dynamic> patch) =>
      _call(() => _dio.post('/merchant/assumptions', data: patch, options: _m), (d) => Map<String, dynamic>.from(d));

  @override
  Future<List<Map<String, dynamic>>> merchantEvents({String? orderId}) => _call(
      () => _dio.get('/merchant/events', queryParameters: {'order_id': ?orderId}, options: _m),
      (d) => [for (final e in d['items'] as List) Map<String, dynamic>.from(e)]);
}
