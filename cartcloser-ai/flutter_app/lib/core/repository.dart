import 'dart:async';

import 'models.dart';

/// One interface, two implementations:
///  * [LocalRepository]  - offline in-memory engine (default; works with no network).
///  * [ApiRepository]    - the FastAPI backend over HTTP (LAN / cloud).
/// Both return identical shapes, so every screen works in either mode.
abstract class CartCloserRepository {
  String get modeLabel;
  bool get isOffline;
  Stream<Snapshot> watch();
  Snapshot? get current;
  Future<void> refresh();
  Future<void> dispose();

  // shopper
  Future<Cart> createCart(String shopperId, List<Map<String, dynamic>> items, {String? idempotencyKey});
  Future<Cart> patchCart(String shopperId, String cartId, {List<Map<String, dynamic>>? items, String? promoCode});
  Future<Cart> checkoutStarted(String shopperId, String cartId, {required String city, required String paymentMethod, required bool optIn});
  Future<Cart> abandon(String shopperId, String cartId, {String? idempotencyKey});
  Future<Cart> openRecoveryLink(String cartId, String token);
  Future<void> grantConsent(String shopperId);
  Future<void> revokeConsent(String shopperId);
  Future<List<ChatMessage>> sendMessage(String shopperId, String cartId, String text, {String? idempotencyKey});
  Future<Order> placeOrder({
    required String cartId,
    required String paymentMethod,
    required bool codConfirmed,
    required String idempotencyKey,
    String? discountCode,
    String? recoveryToken,
    String? shopperId,
  });

  // merchant
  Future<String> triggerRecovery(String cartId);
  Future<void> scheduleRecovery(String cartId);
  Future<void> setCartPaused(String cartId, bool paused);
  Future<void> humanReply(String cartId, String text);
  Future<void> setTakeover(String cartId, bool on);
  Future<void> patchSettings(Map<String, dynamic> patch);
  Future<void> patchCatalog({List<Map<String, dynamic>> products = const [], Map<String, dynamic>? policy});
  Future<Map<String, dynamic>> exportData();
  Future<Map<String, dynamic>> deleteShopperData(String shopperId);
  Future<Metrics> metrics({int? days});

  // demo
  Future<void> reset();
}
