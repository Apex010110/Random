import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models.dart';
import '../../core/providers.dart';

String idemKey(String prefix) => '$prefix-${DateTime.now().microsecondsSinceEpoch}-${Random().nextInt(0x3fffffff)}';

/// Shopper actions shared by the UI and the guided judge demo.
class ShopperActions {
  final WidgetRef ref;
  ShopperActions(this.ref);

  String get shopperId => ref.read(personaProvider);
  Snapshot? get snap => ref.read(repositoryProvider).current;
  Cart? get openCart => snap?.openCartFor(shopperId);

  Future<Cart> addToCart(String productId, String size, {int qty = 1}) async {
    final repo = ref.read(repositoryProvider);
    final cart = openCart;
    if (cart == null) return repo.createCart(shopperId, [{'product_id': productId, 'size': size, 'quantity': qty}], idempotencyKey: idemKey('cart'));
    final items = [for (final l in cart.items) l.toItem()];
    final i = items.indexWhere((e) => e['product_id'] == productId && e['size'] == size);
    if (i >= 0) {
      items[i] = {...items[i], 'quantity': (items[i]['quantity'] as int) + qty};
    } else {
      items.add({'product_id': productId, 'size': size, 'quantity': qty});
    }
    return repo.patchCart(shopperId, cart.id, items: items);
  }

  Future<Cart> setQty(Cart cart, CartLine line, int qty) {
    final items = [
      for (final l in cart.items)
        if (!(l.productId == line.productId && l.size == line.size)) l.toItem() else if (qty > 0) {...l.toItem(), 'quantity': qty}
    ];
    return ref.read(repositoryProvider).patchCart(shopperId, cart.id, items: items);
  }

  Future<Cart> applyPromo(Cart cart, String code) => ref.read(repositoryProvider).patchCart(shopperId, cart.id, promoCode: code);

  Future<Cart> startCheckout(Cart cart, {required String city, required String payment, required bool optIn}) =>
      ref.read(repositoryProvider).checkoutStarted(shopperId, cart.id, city: city, paymentMethod: payment, optIn: optIn);

  Future<Cart> abandon(Cart cart) => ref.read(repositoryProvider).abandon(shopperId, cart.id, idempotencyKey: 'leave-${cart.id}');

  Future<List<ChatMessage>> say(String cartId, String text) =>
      ref.read(repositoryProvider).sendMessage(shopperId, cartId, text, idempotencyKey: idemKey('msg'));

  Future<Order> placeOrder(Cart cart, {required String payment, required bool codConfirmed, String? token}) =>
      ref.read(repositoryProvider).placeOrder(
          cartId: cart.id,
          paymentMethod: payment,
          codConfirmed: codConfirmed,
          idempotencyKey: 'order-${cart.id}',
          recoveryToken: token,
          shopperId: shopperId);
}
