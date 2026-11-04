// Offline demo engine: an in-memory port of backend/app/services/{commerce,metrics,seed}.py.
// It returns the same JSON shapes as the HTTP API, so the UI cannot tell the two apart.
// Used when the app runs in "Offline demo" mode (default) - no network, no AI key needed.
import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

import '../models.dart' show ApiException;
import 'assistant_rules.dart';

const _purpose = 'checkout_reminders';
const _channel = 'whatsapp_sim';
const _closed = {'recovered', 'ordered', 'expired'};
const _contacted = {'message_sent', 'replied', 'human_handoff'};
const _editable = {'active_cart', 'checkout_started', 'abandoned', 'not_eligible', 'eligible', 'scheduled', 'message_sent', 'replied', 'human_handoff'};
const linkSecret = 'dev-only-change-me';

class _Variant {
  final String id, size;
  int stock;
  _Variant(this.id, this.size, this.stock);
}

class _Product {
  final String id, name, category, description, imageKey, colorHex;
  String fitNotes;
  int price;
  bool cod, active = true;
  final List<_Variant> variants;
  _Product(this.id, this.name, this.category, this.description, this.fitNotes, this.price, this.cod, this.imageKey, this.colorHex, this.variants);
  Map<String, dynamic> toJson() => {
        'id': id, 'name': name, 'category': category, 'description': description, 'fit_notes': fitNotes, 'price_pkr': price,
        'cod_eligible': cod, 'image_key': imageKey, 'color_hex': colorHex, 'active': active,
        'variants': [for (final v in variants) {'size': v.size, 'stock': v.stock}],
      };
}

class _Shopper {
  final String id, city, ageBand;
  String firstName, phoneMasked;
  _Shopper(this.id, this.firstName, this.phoneMasked, this.city, this.ageBand);
}

class _Consent {
  final String id, shopperId, version, text, source;
  final DateTime createdAt;
  DateTime? revokedAt;
  _Consent(this.id, this.shopperId, this.version, this.text, this.source, this.createdAt);
}

class _Item {
  final String productId, variantId;
  int qty;
  final int unitPrice;
  _Item(this.productId, this.variantId, this.qty, this.unitPrice);
}

class _Checkout {
  String city, payment;
  bool optedIn;
  _Checkout(this.city, this.payment, this.optedIn);
}

class _Cart {
  final String id, shopperId;
  final String? sourceId;
  String status = 'active_cart';
  String? statusReason, promoCode;
  bool paused = false, holdout = false;
  DateTime? abandonedAt;
  final DateTime createdAt;
  List<_Item> items = [];
  _Checkout? checkout;
  _Cart(this.id, this.shopperId, this.createdAt, this.sourceId);
}

class _Msg {
  final String id, role, text;
  final int seq;
  final String? intent, language, source;
  final double? confidence;
  final Map<String, dynamic> meta;
  final DateTime createdAt;
  _Msg(this.id, this.seq, this.role, this.text, this.createdAt, {this.intent, this.confidence, this.language, this.source, this.meta = const {}});
}

class _Conv {
  final String cartId;
  String channel;
  bool takeover = false, escalated = false;
  final List<_Msg> messages = [];
  DateTime updatedAt;
  _Conv(this.cartId, this.channel, this.updatedAt);
}

class _Attempt {
  final String id, cartId, idem;
  String status;
  String? reason;
  DateTime scheduledFor;
  DateTime? sentAt;
  int estCost = 0;
  final DateTime createdAt;
  _Attempt(this.id, this.cartId, this.idem, this.status, this.scheduledFor, this.createdAt);
}

class _Discount {
  final String code;
  final int percent;
  final String? cartId;
  final bool singleUse;
  bool used = false;
  final String issuedBy;
  _Discount(this.code, this.percent, this.cartId, this.singleUse, this.issuedBy);
}

class _Order {
  final String id, cartId, idem, payment, city;
  String status = 'placed';
  final bool codConfirmed, viaLink;
  final int subtotal, discount, shipping, total;
  final String? discountCode;
  final List<Map<String, dynamic>> lines;
  final DateTime createdAt;
  _Order(this.id, this.cartId, this.idem, this.payment, this.codConfirmed, this.city, this.subtotal, this.discount, this.shipping, this.total,
      this.discountCode, this.viaLink, this.lines, this.createdAt);
}

class _Attribution {
  final String orderId, cartId, attemptId;
  final int revenue;
  final DateTime at;
  _Attribution(this.orderId, this.cartId, this.attemptId, this.revenue, this.at);
}

class _Audit {
  final String type;
  final String? cartId;
  final Map<String, dynamic> detail;
  final DateTime at;
  _Audit(this.type, this.cartId, this.detail, this.at);
}

class DemoEngine {
  final Map<String, dynamic> seed;
  final AssistantRules rules;
  DateTime Function() clock;
  final Random _rng;

  DemoEngine(this.seed, Map<String, dynamic> assistantCopy, {DateTime Function()? clock, Random? rng})
      : rules = AssistantRules(assistantCopy),
        clock = clock ?? (() => DateTime.now().toUtc()),
        _rng = rng ?? Random() {
    reset(notify: false);
  }

  // ------------------------------------------------------------- state
  late String tenantId, storeName;
  late Map<String, dynamic> settings, policy;
  late int policyVersion;
  final Map<String, _Product> _products = {};
  final Map<String, _Shopper> _shoppers = {};
  final List<_Consent> _consents = [];
  final Map<String, _Cart> _carts = {};
  final Map<String, _Conv> _convs = {};
  final List<_Attempt> _attempts = [];
  final Map<String, _Discount> _discounts = {};
  final Map<String, _Order> _orders = {};
  final List<_Attribution> _attributions = [];
  final List<_Audit> _audit = [];
  final Set<String> _idem = {};
  late List<Map<String, String>> _integrations;

  int version = 0;
  final _changes = StreamController<int>.broadcast();
  Stream<int> get changes => _changes.stream;
  Timer? _timer;

  DateTime now() => clock().toUtc();
  DateTime nowLocal() => now().add(const Duration(hours: 5)); // PKT wall time (no DST)

  void _bump() {
    version++;
    _changes.add(version);
  }

  String _id(String prefix) => '${prefix}_${List.generate(12, (_) => _rng.nextInt(16).toRadixString(16)).join()}';

  void startScheduler() {
    _timer ??= Timer.periodic(const Duration(seconds: 1), (_) => tick());
  }

  void dispose() {
    _timer?.cancel();
    _changes.close();
  }

  void reset({bool notify = true}) {
    final t = seed['tenant'] as Map;
    tenantId = t['id'];
    storeName = t['name'];
    settings = Map<String, dynamic>.from(seed['settings']);
    policy = jsonDecode(jsonEncode(seed['policy'])) as Map<String, dynamic>;
    policyVersion = 1;
    for (final c in [_products, _shoppers, _carts, _convs, _discounts, _orders]) {
      c.clear();
    }
    for (final l in [_consents, _attempts, _attributions, _audit]) {
      l.clear();
    }
    _idem.clear();
    for (final p in seed['products'] as List) {
      _products[p['id']] = _Product(p['id'], p['name'], p['category'], p['description'], p['fit_notes'], p['price_pkr'], p['cod_eligible'],
          p['image_key'], p['color_hex'], [
        for (final v in p['variants'] as List) _Variant('${p['id']}__${(v[0] as String).replaceAll(' ', '_').toLowerCase()}', v[0], v[1])
      ]);
    }
    for (final s in seed['personas'] as List) {
      _shoppers[s['id']] = _Shopper(s['id'], s['first_name'], s['phone_masked'], s['city'], s['age_band']);
    }
    for (final d in seed['discount_codes'] as List) {
      _discounts[d['code']] = _Discount(d['code'], d['percent'], null, d['single_use'], 'merchant');
    }
    _integrations = [
      {'provider': 'simulator', 'status': 'connected', 'detail': 'Built-in WhatsApp-style simulator (no real messages are sent).'},
      {'provider': 'shopify', 'status': 'not_connected', 'detail': 'Not connected. Needs app install, OAuth and webhook secret.'},
      {'provider': 'woocommerce', 'status': 'not_connected', 'detail': 'Not connected. Needs REST keys and webhook secret.'},
      {
        'provider': 'whatsapp',
        'status': 'not_connected',
        'detail': 'Not connected. Needs WhatsApp Business Platform verification, approved templates and credentials.'
      },
    ];
    _audit.add(_Audit('demo_seeded', null, {}, now()));
    if (notify) _bump();
  }

  void _log(String type, [String? cartId, Map<String, dynamic> detail = const {}]) {
    _audit.add(_Audit(type, cartId, _redact(detail), now()));
  }

  bool _logOnce(String key, String type, [String? cartId, Map<String, dynamic> detail = const {}]) {
    if (!_idem.add(key)) return false;
    _log(type, cartId, detail);
    return true;
  }

  static final _phone = RegExp(r'\+?\d[\d\s-]{7,}\d');
  Map<String, dynamic> _redact(Map<String, dynamic> d) => {
        for (final e in d.entries)
          if (!const {'text', 'phone', 'body'}.contains(e.key)) e.key: e.value is String ? (e.value as String).replaceAll(_phone, '[redacted-phone]') : e.value
      };

  static Never _err(int status, String code, String msg) => throw ApiException(status, code, msg);

  // ------------------------------------------------------------- lookups
  _Cart _cart(String id, [String? shopperId]) {
    final c = _carts[id];
    if (c == null || (shopperId != null && c.shopperId != shopperId)) _err(404, 'cart_not_found', 'Cart not found');
    return c;
  }

  _Shopper _shopper(String id) => _shoppers[id] ?? _err(404, 'shopper_not_found', 'Unknown shopper');

  (_Product, _Variant) _variant(String productId, String size) {
    final p = _products[productId];
    if (p == null || !p.active) _err(404, 'product_not_found', 'Product $productId not found');
    final v = p.variants.where((v) => v.size == size).firstOrNull ?? _err(422, 'size_not_found', 'Size $size does not exist for ${p.name}');
    return (p, v);
  }

  _Variant _variantById(String id) => _products.values.expand((p) => p.variants).firstWhere((v) => v.id == id);

  List<Map<String, dynamic>> _catalog() => [
        for (final p in _products.values)
          if (p.active)
            {
              'id': p.id, 'name': p.name, 'category': p.category, 'price_pkr': p.price, 'cod_eligible': p.cod, 'fit_notes': p.fitNotes,
              'variants': [for (final v in p.variants) {'size': v.size, 'stock': v.stock}],
            }
      ];

  String recoveryToken(String cartId) =>
      Hmac(sha256, utf8.encode(linkSecret)).convert(utf8.encode(cartId)).toString().substring(0, 20);

  // ------------------------------------------------------------- pricing
  _Discount _validDiscount(_Cart cart, String code) {
    final d = _discounts[code.trim().toUpperCase()];
    if (d == null) _err(422, 'invalid_discount', 'Discount code not valid');
    if (d.cartId != null && d.cartId != cart.id) _err(422, 'invalid_discount', 'Discount code belongs to another cart');
    if (d.singleUse && d.used) _err(422, 'discount_used', 'Discount code already used');
    if (d.issuedBy == 'ai' && d.percent > (settings['discount_ceiling_pct'] as num)) {
      _err(422, 'discount_over_ceiling', 'Discount exceeds the merchant ceiling');
    }
    return d;
  }

  Map<String, dynamic> _totals(_Cart cart, {String? discountCode}) {
    final subtotal = cart.items.fold<int>(0, (a, i) => a + i.unitPrice * i.qty);
    var pct = 0;
    final code = discountCode ?? cart.promoCode;
    if (code != null && code.isNotEmpty) pct = _validDiscount(cart, code).percent;
    final discount = (subtotal * pct / 100).round();
    final city = cart.checkout?.city ?? _shopper(cart.shopperId).city;
    final ship = cart.items.isEmpty ? 0 : AssistantRules.shippingFee(policy, city, subtotal - discount);
    return {
      'subtotal_pkr': subtotal, 'discount_pct': pct, 'discount_pkr': discount, 'shipping_pkr': ship, 'total_pkr': subtotal - discount + ship,
      'city': city, 'discount_code': pct > 0 ? code : null,
    };
  }

  Map<String, dynamic> _safeTotals(_Cart c) {
    try {
      return _totals(c);
    } on ApiException {
      return _totals(c, discountCode: '');
    }
  }

  // ------------------------------------------------------------- serializers (match backend serialize.py)
  Map<String, dynamic> _cartJson(_Cart c, {bool withShopper = false, bool includeLink = false}) {
    final consent = _activeConsent(c.shopperId);
    final order = _orders.values.where((o) => o.cartId == c.id).firstOrNull;
    final sh = _shoppers[c.shopperId]!;
    final conv = _convs[c.id];
    return {
      'id': c.id, 'shopper_id': c.shopperId, 'status': c.status, 'status_reason': c.statusReason,
      'items': [
        for (final i in c.items)
          {
            'product_id': i.productId, 'name': _products[i.productId]!.name, 'size': _variantById(i.variantId).size, 'quantity': i.qty,
            'unit_price_pkr': i.unitPrice, 'cod_eligible': _products[i.productId]!.cod,
          }
      ],
      'totals': _safeTotals(c), 'promo_code': c.promoCode,
      'checkout': c.checkout == null ? null : {'city': c.checkout!.city, 'payment_method': c.checkout!.payment, 'opted_in_at_checkout': c.checkout!.optedIn},
      'consent': consent == null
          ? null
          : {'granted': true, 'version': consent.version, 'source': consent.source, 'at': consent.createdAt.toIso8601String(), 'channel': _channel},
      'recovery_paused': c.paused, 'holdout': c.holdout, 'abandoned_at': c.abandonedAt?.toIso8601String(), 'created_at': c.createdAt.toIso8601String(),
      'recovery_attempts': [
        for (final a in _attempts.where((a) => a.cartId == c.id))
          {
            'id': a.id, 'status': a.status, 'reason': a.reason, 'channel': _channel, 'scheduled_for': a.scheduledFor.toIso8601String(),
            'sent_at': a.sentAt?.toIso8601String(),
          }
      ],
      'order_id': order?.id,
      'recovery_link': includeLink ? '/r/${c.id}?t=${recoveryToken(c.id)}' : null,
      if (withShopper) 'shopper': {'id': sh.id, 'first_name': sh.firstName, 'phone_masked': sh.phoneMasked, 'age_band': sh.ageBand},
      if (withShopper) 'message_count': conv?.messages.length ?? 0,
      if (withShopper) 'attribution_source': c.status == 'recovered' ? 'recovery_contact' : null,
    };
  }

  Map<String, dynamic> _msgJson(_Msg m) => {
        'id': m.id, 'seq': m.seq, 'role': m.role, 'text': m.text, 'intent': m.intent, 'confidence': m.confidence, 'language': m.language,
        'source': m.source, 'meta': m.meta, 'created_at': m.createdAt.toIso8601String(),
      };

  Map<String, dynamic> _convJson(String cartId) {
    final c = _convs[cartId];
    if (c == null) return {'cart_id': cartId, 'channel': 'none', 'human_takeover': false, 'escalated': false, 'messages': []};
    return {
      'cart_id': cartId, 'channel': c.channel, 'human_takeover': c.takeover, 'escalated': c.escalated,
      'messages': [for (final m in c.messages) _msgJson(m)],
    };
  }

  Map<String, dynamic> _orderJson(_Order o) => {
        'id': o.id, 'cart_id': o.cartId, 'status': o.status, 'payment_method': o.payment, 'cod_confirmed': o.codConfirmed, 'city': o.city,
        'subtotal_pkr': o.subtotal, 'discount_pkr': o.discount, 'shipping_pkr': o.shipping, 'total_pkr': o.total, 'discount_code': o.discountCode,
        'via_recovery_link': o.viaLink, 'lines': o.lines, 'created_at': o.createdAt.toIso8601String(),
        'attributed': _attributions.any((a) => a.orderId == o.id),
      };

  // ------------------------------------------------------------- public API (mirrors HTTP routes)
  Map<String, dynamic> store() => {
        'tenant_id': tenantId, 'name': storeName, 'currency': 'PKR', 'is_demo': true, 'policy': policy, 'consent_text': settings['consent_text'],
        'consent_version': settings['consent_version'], 'discount_ceiling_pct': settings['discount_ceiling_pct'],
      };

  List<Map<String, dynamic>> products() => [for (final p in _products.values) if (p.active) p.toJson()];

  void _applyItems(_Cart cart, List<Map<String, dynamic>> items) {
    final merged = <String, int>{};
    final found = <String, (_Product, _Variant)>{};
    for (final it in items) {
      final pv = _variant(it['product_id'], it['size']);
      merged[pv.$2.id] = (merged[pv.$2.id] ?? 0) + (it['quantity'] as num).toInt();
      found[pv.$2.id] = pv;
    }
    for (final e in merged.entries) {
      final (p, v) = found[e.key]!;
      if (e.value < 1) _err(422, 'invalid_quantity', 'Quantity must be at least 1');
      if (e.value > v.stock) _err(409, 'insufficient_stock', 'Only ${v.stock} left of ${p.name} (${v.size})');
    }
    cart.items = [
      for (final e in merged.entries) _Item(found[e.key]!.$1.id, e.key, e.value, found[e.key]!.$1.price),
    ];
  }

  Map<String, dynamic> createCart(String shopperId, List<Map<String, dynamic>> items, {String? idempotencyKey}) {
    _shopper(shopperId);
    if (items.isEmpty) _err(422, 'validation_error', 'items: at least one item required');
    if (idempotencyKey != null) {
      final existing = _carts.values.where((c) => c.sourceId == 'idem:$idempotencyKey').firstOrNull;
      if (existing != null) return _cartJson(existing);
    }
    final cart = _Cart(_id('cart'), shopperId, now(), idempotencyKey == null ? null : 'idem:$idempotencyKey');
    _applyItems(cart, items);
    _carts[cart.id] = cart;
    _log('cart_created', cart.id, {'items': items.length});
    _bump();
    return _cartJson(cart);
  }

  Map<String, dynamic> getCart(String shopperId, String cartId) => _cartJson(_cart(cartId, shopperId));

  Map<String, dynamic> patchCart(String shopperId, String cartId, {List<Map<String, dynamic>>? items, String? promoCode}) {
    final cart = _cart(cartId, shopperId);
    if (!_editable.contains(cart.status)) _err(409, 'cart_closed', 'Cart is ${cart.status} and can no longer be edited');
    if (items != null) {
      if (items.isEmpty) {
        cart.items = [];
      } else {
        _applyItems(cart, items);
      }
    }
    if (promoCode != null) {
      if (promoCode.isEmpty) {
        cart.promoCode = null;
      } else {
        _validDiscount(cart, promoCode);
        cart.promoCode = promoCode.trim().toUpperCase();
      }
    }
    _log('cart_updated', cart.id);
    _bump();
    return _cartJson(cart);
  }

  Map<String, dynamic> checkoutStarted(String shopperId, String cartId, {required String city, String paymentMethod = 'cod', bool whatsappOptIn = false}) {
    final cart = _cart(cartId, shopperId);
    if (_closed.contains(cart.status)) _err(409, 'cart_closed', 'Cart already completed');
    if (cart.items.isEmpty) _err(422, 'empty_cart', 'Cart is empty');
    if (cart.checkout != null) {
      cart.checkout!
        ..city = city
        ..payment = paymentMethod
        ..optedIn = cart.checkout!.optedIn || whatsappOptIn;
    } else {
      cart.checkout = _Checkout(city, paymentMethod, whatsappOptIn);
    }
    if (whatsappOptIn) _grant(cart.shopperId, 'checkout_form');
    if (cart.status == 'active_cart') cart.status = 'checkout_started';
    _log('checkout_started', cart.id, {'opt_in': whatsappOptIn, 'city': city});
    _bump();
    return _cartJson(cart);
  }

  // consent
  _Consent? _activeConsent(String shopperId) {
    final recs = _consents.where((r) => r.shopperId == shopperId).toList();
    if (recs.isEmpty) return null;
    final last = recs.last;
    return last.revokedAt == null ? last : null;
  }

  bool _everRevoked(String shopperId) => _consents.any((r) => r.shopperId == shopperId && r.revokedAt != null);

  _Consent _grant(String shopperId, String source) {
    _shopper(shopperId);
    final existing = _activeConsent(shopperId);
    if (existing != null) return existing;
    final rec = _Consent(_id('con'), shopperId, settings['consent_version'] ?? 'v1', settings['consent_text'] ?? '', source, now());
    _consents.add(rec);
    _log('consent_granted', null, {'shopper': shopperId, 'source': source, 'version': rec.version});
    return rec;
  }

  Map<String, dynamic> _consentJson(_Consent r) => {
        'id': r.id, 'shopper_id': r.shopperId, 'channel': _channel, 'purpose': _purpose, 'granted': true, 'consent_version': r.version,
        'consent_text': r.text, 'source': r.source, 'created_at': r.createdAt.toIso8601String(), 'revoked_at': r.revokedAt?.toIso8601String(),
      };

  Map<String, dynamic> grantConsent(String shopperId, {String source = 'preferences'}) {
    final r = _grant(shopperId, source);
    _bump();
    return _consentJson(r);
  }

  void _revoke(String shopperId, String source) {
    var n = 0;
    for (final r in _consents.where((r) => r.shopperId == shopperId && r.revokedAt == null)) {
      r.revokedAt = now();
      n++;
    }
    for (final c in _carts.values.where((c) => c.shopperId == shopperId)) {
      for (final a in _attempts.where((a) => a.cartId == c.id && a.status == 'scheduled')) {
        a
          ..status = 'cancelled'
          ..reason = 'opted_out';
      }
      if (!_closed.contains(c.status) && c.status != 'active_cart') {
        c
          ..status = 'opted_out'
          ..statusReason = 'opted_out';
      }
    }
    _log('consent_revoked', null, {'shopper': shopperId, 'source': source, 'records': n});
  }

  Map<String, dynamic> revokeConsent(String shopperId, {String source = 'preferences'}) {
    _revoke(shopperId, source);
    _bump();
    return {'revoked': true};
  }

  Map<String, dynamic> consentMe(String shopperId) {
    final r = _activeConsent(shopperId);
    return {'opted_in': r != null, 'record': r == null ? null : _consentJson(r)};
  }

  // eligibility & recovery
  bool _inQuietHours() {
    if (settings['quiet_hours_enabled'] != true) return false;
    final h = nowLocal().hour;
    final start = (settings['quiet_start_hour'] as num).toInt(), end = (settings['quiet_end_hour'] as num).toInt();
    return start > end ? (start <= h || h < end) : (start <= h && h < end);
  }

  DateTime _quietEnd() {
    final loc = nowLocal();
    var end = DateTime.utc(loc.year, loc.month, loc.day, (settings['quiet_end_hour'] as num).toInt());
    if (!end.isAfter(loc)) end = end.add(const Duration(days: 1));
    return end.subtract(const Duration(hours: 5)); // back to UTC
  }

  String? _eligibility(_Cart cart) {
    final sh = _shopper(cart.shopperId);
    if (_orders.values.any((o) => o.cartId == cart.id)) return 'already_purchased';
    if (cart.items.isEmpty) return 'empty_cart';
    if (_activeConsent(cart.shopperId) == null) return _everRevoked(cart.shopperId) ? 'opted_out' : 'no_consent';
    if (sh.ageBand == 'under_18') return 'under_18_safeguard';
    if (settings['campaign_enabled'] == false) return 'campaign_paused';
    if (cart.paused) return 'cart_paused';
    final sent = _attempts.where((a) => a.cartId == cart.id && a.status == 'sent').length;
    if (sent >= (settings['max_messages_per_cart'] as num? ?? 1)) return 'contact_cap';
    return null;
  }

  Map<String, dynamic> abandon(String shopperId, String cartId, {String? idempotencyKey}) {
    final cart = _cart(cartId, shopperId);
    if (!_logOnce('abandon:${cart.id}:${idempotencyKey ?? 'default'}', 'cart_abandoned', cart.id)) return _cartJson(cart);
    if (cart.status == 'active_cart') _err(409, 'checkout_not_started', 'Only carts that reached checkout can be abandoned');
    if (cart.status != 'checkout_started') {
      _bump();
      return _cartJson(cart);
    }
    cart
      ..status = 'abandoned'
      ..abandonedAt = now();
    final reason = _eligibility(cart);
    if (reason != null) {
      cart
        ..status = 'not_eligible'
        ..statusReason = reason;
      _log('recovery_blocked', cart.id, {'reason': reason});
    } else {
      cart
        ..status = 'eligible'
        ..statusReason = null;
      if (_rng.nextDouble() * 100 < (settings['holdout_pct'] as num? ?? 0)) {
        cart
          ..holdout = true
          ..statusReason = 'holdout_control';
        _log('holdout_assigned', cart.id);
      } else {
        _schedule(cart);
      }
    }
    _bump();
    return _cartJson(cart);
  }

  _Attempt _schedule(_Cart cart, {DateTime? when}) {
    final existing = _attempts.where((a) => a.cartId == cart.id && a.status == 'scheduled').firstOrNull;
    if (existing != null) return existing;
    final n = _attempts.where((a) => a.cartId == cart.id).length + 1;
    when ??= settings['accelerated_demo'] == true
        ? now().add(Duration(seconds: (settings['demo_delay_seconds'] as num? ?? 5).toInt()))
        : now().add(Duration(minutes: (settings['delay_minutes'] as num? ?? 20).toInt()));
    final att = _Attempt(_id('rec'), cart.id, 'send:${cart.id}:$n', 'scheduled', when, now());
    _attempts.add(att);
    cart.status = 'scheduled';
    _log('recovery_scheduled', cart.id, {'scheduled_for': when.toIso8601String()});
    return att;
  }

  Map<String, dynamic> schedule(String cartId) {
    final cart = _cart(cartId);
    if (!{'eligible', 'scheduled'}.contains(cart.status)) {
      _err(409, 'not_eligible', 'Cart is ${cart.status} (${cart.statusReason ?? 'n/a'}); cannot schedule');
    }
    final reason = _eligibility(cart);
    if (reason != null) _err(409, 'not_eligible', 'Blocked: $reason');
    final att = _schedule(cart);
    _bump();
    return {'attempt_id': att.id, 'status': att.status, 'scheduled_for': att.scheduledFor.toIso8601String()};
  }

  /// Demo only: bypasses the wait, never the consent / safety checks.
  Map<String, dynamic> triggerDemo(String cartId) {
    final cart = _cart(cartId);
    var att = _attempts.where((a) => a.cartId == cart.id && a.status == 'scheduled').firstOrNull;
    if (att == null) {
      if (cart.status == 'eligible') {
        att = _schedule(cart, when: now());
      } else {
        final reason = cart.statusReason ?? _eligibility(cart) ?? cart.status;
        _err(409, 'not_eligible', 'No outbound message: $reason');
      }
    }
    att.scheduledFor = now();
    _deliver(att);
    _bump();
    return {'attempt_id': att.id, 'status': att.status, 'reason': att.reason};
  }

  String _deliver(_Attempt att) {
    final cart = _carts[att.cartId]!;
    final reason = _eligibility(cart);
    if (reason == 'already_purchased') {
      att
        ..status = 'cancelled'
        ..reason = reason;
      _log('recovery_cancelled', cart.id, {'reason': reason});
      return att.status;
    }
    if (reason != null) {
      att
        ..status = 'blocked'
        ..reason = reason;
      if (!_closed.contains(cart.status)) {
        cart
          ..status = reason == 'opted_out' ? 'opted_out' : 'not_eligible'
          ..statusReason = reason;
      }
      _log('recovery_blocked', cart.id, {'reason': reason});
      return att.status;
    }
    if (_inQuietHours()) {
      att.scheduledFor = _quietEnd();
      _log('recovery_deferred_quiet_hours', cart.id, {'until': att.scheduledFor.toIso8601String()});
      return att.status;
    }
    if (att.status != 'scheduled') return 'duplicate';
    att
      ..status = 'sent'
      ..sentAt = now()
      ..estCost = (settings['est_cost_per_message_pkr'] as num? ?? 0).toInt();
    final sh = _shopper(cart.shopperId);
    final conv = _conversation(cart, _channel);
    final item = cart.items.isEmpty ? 'item' : _products[cart.items.first.productId]!.name;
    final text = (settings['template_recovery'] as String).replaceAll('{first_name}', sh.firstName).replaceAll('{store}', storeName).replaceAll('{item}', item);
    _addMessage(conv, 'ai', text,
        intent: 'recovery_template',
        source: 'template',
        language: 'en',
        confidence: 1.0,
        meta: {'checkout_link': true, 'link_label': 'Complete checkout', 'token': recoveryToken(cart.id)});
    cart
      ..status = 'message_sent'
      ..statusReason = null;
    _log('recovery_sent', cart.id, {'channel': _channel, 'attempt': att.id});
    return 'sent';
  }

  /// Scheduler tick: deliver due attempts, expire stale contacts.
  int tick() {
    final t = now();
    var n = 0;
    var changed = false;
    for (final att in _attempts.where((a) => a.status == 'scheduled' && !a.scheduledFor.isAfter(t)).toList()) {
      changed = true;
      if (_deliver(att) == 'sent') n++;
    }
    final window = Duration(days: (settings['attribution_window_days'] as num? ?? 7).toInt());
    for (final c in _carts.values.where((c) => _contacted.contains(c.status))) {
      final sent = _attempts.where((a) => a.cartId == c.id && a.sentAt != null).map((a) => a.sentAt!).toList()..sort();
      if (sent.isNotEmpty && sent.last.isBefore(t.subtract(window))) {
        c.status = 'expired';
        _log('cart_expired', c.id);
        changed = true;
      }
    }
    if (changed) _bump();
    return n;
  }

  // conversations
  _Conv _conversation(_Cart cart, String channel) {
    var c = _convs[cart.id];
    if (c == null) {
      c = _Conv(cart.id, channel, now());
      _convs[cart.id] = c;
    } else if (channel == _channel && c.channel != _channel) {
      c.channel = _channel;
    }
    return c;
  }

  _Msg _addMessage(_Conv conv, String role, String text,
      {String? intent, double? confidence, String? language, String? source, Map<String, dynamic> meta = const {}}) {
    final m = _Msg(_id('msg'), conv.messages.length + 1, role, text, now(),
        intent: intent, confidence: confidence, language: language, source: source, meta: meta);
    conv.messages.add(m);
    conv.updatedAt = now();
    return m;
  }

  Map<String, dynamic> conversation(String shopperId, String cartId) => _convJson(_cart(cartId, shopperId).id);

  List<Map<String, dynamic>> postMessage(String shopperId, String cartId, String rawText, {String? idempotencyKey}) {
    final cart = _cart(cartId, shopperId);
    final text = rules.sanitize(rawText);
    if (text.isEmpty) _err(422, 'empty_message', 'Message is empty');
    if (idempotencyKey != null && !_logOnce('msg:${cart.id}:$idempotencyKey', 'shopper_message', cart.id, {'len': text.length})) {
      final conv = _convs[cart.id];
      if (conv == null) return [];
      return [for (final m in conv.messages.skip(max(0, conv.messages.length - 2))) _msgJson(m)];
    }
    final conv = _convs[cart.id] ?? _conversation(cart, 'onsite_chat');
    final out = [_addMessage(conv, 'shopper', text)];
    if (cart.status == 'message_sent') cart.status = 'replied';
    if (conv.takeover) {
      _bump();
      return [for (final m in out) _msgJson(m)];
    }
    final sh = _shopper(cart.shopperId);
    final tot = _safeTotals(cart);
    final existing = _discounts.values.where((d) => d.cartId == cart.id && !d.used).firstOrNull;
    final ctx = AssistantContext(
      storeName: storeName,
      firstName: sh.firstName,
      city: tot['city'],
      lines: [
        for (final i in cart.items)
          Line(i.productId, _products[i.productId]!.name, _variantById(i.variantId).size, i.qty, i.unitPrice, _products[i.productId]!.cod)
      ],
      subtotalPkr: tot['subtotal_pkr'],
      policy: policy,
      settings: settings,
      catalog: _catalog(),
      nowLocal: nowLocal(),
      existingDiscount: existing == null ? null : (existing.code, existing.percent),
      candidateCode: 'CC-${List.generate(4, (_) => _rng.nextInt(16).toRadixString(16)).join().toUpperCase()}',
    );
    final reply = rules.answer(text, ctx);
    final meta = Map<String, dynamic>.from(reply.meta);
    if (meta['checkout_link'] == true) meta['token'] = recoveryToken(cart.id);
    switch (reply.action) {
      case 'opt_out':
        _revoke(cart.shopperId, 'stop_keyword');
      case 'handoff':
        conv.escalated = true;
        if (!_closed.contains(cart.status) && cart.status != 'opted_out') cart.status = 'human_handoff';
        _log('human_handoff', cart.id, {'intent': reply.intent});
      case 'issue_discount':
        final ceiling = (settings['discount_ceiling_pct'] as num).toInt();
        final pct = min((meta['discount_pct'] as num).toInt(), ceiling);
        _discounts[meta['discount_code']] = _Discount(meta['discount_code'], pct, cart.id, true, 'ai');
        cart.promoCode = meta['discount_code'];
        _log('discount_issued', cart.id, {'pct': pct});
    }
    out.add(_addMessage(conv, 'ai', reply.text, intent: reply.intent, confidence: reply.confidence, language: reply.language, source: 'rules', meta: meta));
    _log('ai_reply', cart.id, {'intent': reply.intent, 'source': 'rules', 'lang': reply.language});
    _bump();
    return [for (final m in out) _msgJson(m)];
  }

  Map<String, dynamic> humanReply(String cartId, String text) {
    final cart = _cart(cartId);
    final conv = _convs[cart.id] ?? _conversation(cart, 'onsite_chat');
    conv.takeover = true;
    final m = _addMessage(conv, 'human', rules.sanitize(text), source: 'human');
    _log('human_reply', cart.id);
    _bump();
    return _msgJson(m);
  }

  Map<String, dynamic> setTakeover(String cartId, bool on) {
    final cart = _cart(cartId);
    final conv = _convs[cart.id] ?? _conversation(cart, 'onsite_chat');
    conv.takeover = on;
    if (!on) {
      conv.escalated = false;
      if (cart.status == 'human_handoff') cart.status = 'replied';
    }
    _addMessage(conv, 'system', on ? 'A team member joined the chat.' : 'The AI assistant is back.', source: 'system');
    _log(on ? 'takeover_on' : 'takeover_off', cart.id);
    _bump();
    return _convJson(cart.id);
  }

  Map<String, dynamic> setCartPaused(String cartId, bool paused) {
    final cart = _cart(cartId);
    cart.paused = paused;
    if (paused) {
      for (final a in _attempts.where((a) => a.cartId == cart.id && a.status == 'scheduled')) {
        a
          ..status = 'cancelled'
          ..reason = 'cart_paused';
      }
      if (cart.status == 'scheduled') {
        cart
          ..status = 'eligible'
          ..statusReason = 'cart_paused';
      }
    }
    _log(paused ? 'cart_paused' : 'cart_resumed', cart.id);
    _bump();
    return _cartJson(cart);
  }

  Map<String, dynamic> openRecoveryLink(String cartId, String token) {
    if (token != recoveryToken(cartId)) _err(403, 'invalid_link', 'Recovery link is invalid');
    return _cartJson(_cart(cartId), includeLink: true);
  }

  // orders
  Map<String, dynamic> placeOrder({
    required String cartId,
    required String paymentMethod,
    required bool codConfirmed,
    required String idempotencyKey,
    String? discountCode,
    String? recoveryToken,
    String? shopperId,
  }) {
    final cart = _cart(cartId);
    if (recoveryToken == null && shopperId != cart.shopperId) _err(404, 'cart_not_found', 'Cart not found');
    final existing = _orders.values.where((o) => o.idem == idempotencyKey).firstOrNull;
    if (existing != null) {
      if (existing.cartId != cart.id) _err(409, 'idempotency_conflict', 'Idempotency key used for another cart');
      return _orderJson(existing);
    }
    if (_orders.values.any((o) => o.cartId == cart.id)) _err(409, 'already_ordered', 'This cart already has an order');
    if (cart.status == 'active_cart' || cart.checkout == null) _err(409, 'checkout_not_started', 'Start checkout first');
    if (cart.items.isEmpty) _err(422, 'empty_cart', 'Cart is empty');
    if (!const {'cod', 'online_demo'}.contains(paymentMethod)) _err(422, 'invalid_payment', 'payment_method must be cod or online_demo');
    final viaLink = recoveryToken != null;
    if (viaLink && recoveryToken != this.recoveryToken(cart.id)) _err(403, 'invalid_link', 'Recovery link is invalid');
    for (final i in cart.items) {
      final v = _variantById(i.variantId);
      if (i.qty > v.stock) _err(409, 'insufficient_stock', '${_products[i.productId]!.name} (${v.size}) is no longer in stock');
    }
    final code = discountCode ?? cart.promoCode;
    final tot = _totals(cart, discountCode: code ?? '');
    if (paymentMethod == 'cod') {
      final lines = [for (final i in cart.items) Line(i.productId, '', '', i.qty, i.unitPrice, _products[i.productId]!.cod)];
      final res = AssistantRules.codCheck(policy, tot['city'], lines, tot['total_pkr']);
      if (res != 'cod_yes') _err(422, res, 'Cash on delivery is not available for this order');
      if (!codConfirmed) _err(422, 'cod_not_confirmed', 'Please confirm the cash-on-delivery order');
    }
    final t = now();
    final order = _Order(_id('ord'), cart.id, idempotencyKey, paymentMethod, codConfirmed && paymentMethod == 'cod', tot['city'], tot['subtotal_pkr'],
        tot['discount_pkr'], tot['shipping_pkr'], tot['total_pkr'], tot['discount_code'], viaLink, [
      for (final i in cart.items)
        {
          'product_id': i.productId, 'name': _products[i.productId]!.name, 'size': _variantById(i.variantId).size, 'quantity': i.qty,
          'unit_price_pkr': i.unitPrice,
        }
    ], t);
    _orders[order.id] = order;
    for (final i in cart.items) {
      _variantById(i.variantId).stock -= i.qty;
    }
    if (tot['discount_code'] != null) {
      final d = _discounts[tot['discount_code']]!;
      if (d.singleUse) d.used = true;
    }
    for (final a in _attempts.where((a) => a.cartId == cart.id && a.status == 'scheduled')) {
      a
        ..status = 'cancelled'
        ..reason = 'already_purchased';
      _log('recovery_cancelled', cart.id, {'reason': 'already_purchased'});
    }
    final window = Duration(days: (settings['attribution_window_days'] as num? ?? 7).toInt());
    final sent = _attempts.where((a) => a.cartId == cart.id && a.status == 'sent').toList()..sort((a, b) => b.sentAt!.compareTo(a.sentAt!));
    if (sent.isNotEmpty && t.difference(sent.first.sentAt!) <= window) {
      cart.status = 'recovered';
      _attributions.add(_Attribution(order.id, cart.id, sent.first.id, order.total, t));
      final conv = _convs[cart.id];
      if (conv != null) _addMessage(conv, 'system', 'Order ${order.id} placed. Thank you!', source: 'system', meta: {'order_id': order.id});
    } else {
      cart.status = 'ordered';
    }
    _log('order_placed', cart.id, {'order': order.id, 'total': order.total, 'attributed': cart.status == 'recovered'});
    _bump();
    return _orderJson(order);
  }

  Map<String, dynamic> getOrder(String shopperId, String orderId) {
    final o = _orders[orderId];
    if (o == null || _carts[o.cartId]!.shopperId != shopperId) _err(404, 'order_not_found', 'Order not found');
    return _orderJson(o);
  }

  // ------------------------------------------------------------- merchant
  List<Map<String, dynamic>> merchantCarts() {
    final list = _carts.values.toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return [for (final c in list) _cartJson(c, withShopper: true)];
  }

  List<Map<String, dynamic>> merchantConversations() => [for (final id in _convs.keys) _convJson(id)];
  List<Map<String, dynamic>> merchantOrders() => [for (final o in _orders.values) _orderJson(o)];
  Map<String, bool> optedInByShopper() => {for (final id in _shoppers.keys) id: _activeConsent(id) != null};

  Map<String, dynamic> getSettings() => {'tenant_id': tenantId, 'name': storeName, 'is_demo': true, 'settings': settings};

  Map<String, dynamic> patchSettings(Map<String, dynamic> patch) {
    const ranges = {
      'delay_minutes': (1, 1440), 'demo_delay_seconds': (1, 120), 'max_messages_per_cart': (0, 3), 'quiet_start_hour': (0, 23),
      'quiet_end_hour': (0, 23), 'discount_ceiling_pct': (0, 30), 'attribution_window_days': (1, 30), 'holdout_pct': (0, 50),
      'est_cost_per_message_pkr': (0, 1000),
    };
    for (final e in patch.entries) {
      final r = ranges[e.key];
      if (r != null && (e.value is! num || e.value < r.$1 || e.value > r.$2)) _err(422, 'validation_error', '${e.key}: must be ${r.$1}-${r.$2}');
      if (!settings.containsKey(e.key) && e.key != 'accelerated_demo') _err(422, 'validation_error', '${e.key}: unknown setting');
    }
    settings = {...settings, ...patch};
    _log('settings_updated', null, {'keys': patch.keys.toList()..sort()});
    _bump();
    return getSettings();
  }

  Map<String, dynamic> getCatalog() => {'products': [for (final p in _products.values) p.toJson()], 'policy': policy};

  Map<String, dynamic> patchCatalog({List<Map<String, dynamic>> products = const [], Map<String, dynamic>? policyPatch}) {
    for (final pp in products) {
      final p = _products[pp['id']] ?? _err(404, 'product_not_found', 'Product ${pp['id']} not found');
      if (pp['price_pkr'] != null) p.price = pp['price_pkr'];
      if (pp['cod_eligible'] != null) p.cod = pp['cod_eligible'];
      if (pp['active'] != null) p.active = pp['active'];
      if (pp['fit_notes'] != null) p.fitNotes = pp['fit_notes'];
      for (final vp in (pp['variants'] as List? ?? const [])) {
        final v = p.variants.where((v) => v.size == vp['size']).firstOrNull ?? _err(422, 'size_not_found', 'Size ${vp['size']} not found');
        v.stock = vp['stock'];
      }
    }
    if (policyPatch != null) {
      policy = {...policy, ...policyPatch};
      policyVersion++;
    }
    _log('catalog_updated', null, {'products': products.length, 'policy': policyPatch != null});
    _bump();
    return getCatalog();
  }

  List<Map<String, String>> integrations() => _integrations;

  Map<String, dynamic> export() => {
        'tenant_id': tenantId,
        'carts': [for (final c in _carts.values) _cartJson(c)],
        'conversations': merchantConversations(),
        'orders': merchantOrders(),
      };

  Map<String, dynamic> deleteShopperData(String shopperId) {
    final sh = _shopper(shopperId);
    final ids = [for (final c in _carts.values) if (c.shopperId == sh.id) c.id];
    var kept = 0;
    for (final id in ids) {
      _convs.remove(id);
      if (_orders.values.any((o) => o.cartId == id)) {
        kept++;
        _carts[id]!.items = [];
        continue;
      }
      _attempts.removeWhere((a) => a.cartId == id);
      _discounts.removeWhere((k, d) => d.cartId == id);
      _carts.remove(id);
    }
    _consents.removeWhere((r) => r.shopperId == sh.id);
    _log('shopper_data_deleted', null, {'carts': ids.length, 'orders_kept': kept});
    _bump();
    return {'deleted_carts': ids.length - kept, 'orders_kept_anonymised': kept};
  }

  // ------------------------------------------------------------- metrics (port of services/metrics.py)
  static const minArm = 30;

  Map<String, dynamic> _rate(int n, int d) => {'numerator': n, 'denominator': d, 'value': d == 0 ? null : n / d};

  Map<String, dynamic> metrics({int? days}) {
    final since = days == null ? null : now().subtract(Duration(days: days));
    final carts = [for (final c in _carts.values) if (since == null || !c.createdAt.isBefore(since)) c];
    final ids = {for (final c in carts) c.id};
    final checkout = [for (final c in carts) if (c.checkout != null) c];
    final opted = [for (final c in checkout) if (c.checkout!.optedIn) c];
    final abandoned = [for (final c in carts) if (c.abandonedAt != null) c];
    final attempts = [for (final a in _attempts) if (ids.contains(a.cartId)) a];
    final sentBy = <String, DateTime>{};
    for (final a in attempts) {
      if (a.status == 'sent') sentBy.putIfAbsent(a.cartId, () => a.sentAt!);
    }
    final contacted = sentBy.keys.toSet();
    final eligible = {
      for (final c in abandoned)
        if (!const {'no_consent', 'under_18_safeguard', 'opted_out'}.contains(c.statusReason) && !c.holdout) c.id,
      ...contacted,
    };
    final replied = <String>{};
    for (final conv in _convs.values) {
      if (contacted.contains(conv.cartId) && conv.messages.any((m) => m.role == 'shopper' && !m.createdAt.isBefore(sentBy[conv.cartId]!))) {
        replied.add(conv.cartId);
      }
    }
    final atts = [for (final e in _attributions) if (ids.contains(e.cartId) && !const {'canceled', 'refunded'}.contains(_orders[e.orderId]!.status)) e];
    final recovered = {for (final e in atts) e.cartId};
    final allOrders = [for (final o in _orders.values) if (ids.contains(o.cartId)) o];
    final blocked = <String, int>{};
    for (final c in carts) {
      if (c.status == 'not_eligible' && c.statusReason != null) blocked[c.statusReason!] = (blocked[c.statusReason!] ?? 0) + 1;
    }
    for (final a in attempts) {
      if ((a.status == 'blocked' || a.status == 'cancelled') && a.reason != null) blocked[a.reason!] = (blocked[a.reason!] ?? 0) + 1;
    }
    final optOuts = _consents.where((r) => r.revokedAt != null && (since == null || !r.revokedAt!.isBefore(since))).length;
    final sentCount = attempts.where((a) => a.status == 'sent').length;
    final aiMsgs = _convs.values.expand((c) => c.messages).where((m) => m.role == 'ai').length;
    final cost = attempts.where((a) => a.status == 'sent').fold<int>(0, (s, a) => s + a.estCost);
    final holdout = [for (final c in carts) if (c.holdout) c];
    final treated = [for (final c in carts) if (contacted.contains(c.id)) c];
    final Map<String, dynamic> lift;
    if (holdout.length >= minArm && treated.length >= minArm) {
      final h = holdout.where((c) => c.status == 'ordered' || c.status == 'recovered').length / holdout.length;
      lift = {'measured': true, 'value': recovered.length / treated.length - h, 'holdout_carts': holdout.length, 'treated_carts': treated.length};
    } else {
      lift = {'measured': false, 'value': null, 'label': 'Not measured', 'holdout_carts': holdout.length, 'treated_carts': treated.length};
    }
    final recent = _audit.reversed.take(25).toList();
    return {
      'tenant_id': tenantId, 'is_demo_data': true, 'window_days': days, 'generated_at': now().toIso8601String(),
      'counts': {
        'carts_created': carts.length, 'checkouts_started': checkout.length, 'opted_in': opted.length, 'abandoned': abandoned.length,
        'eligible_abandoned': eligible.length, 'contacted': contacted.length, 'replied': replied.length, 'recovered': recovered.length,
        'orders_total': allOrders.length, 'opt_outs': optOuts, 'messages_sent': sentCount, 'ai_replies': aiMsgs,
        'human_handoffs': carts.where((c) => c.status == 'human_handoff').length, 'blocked_or_cancelled': blocked.values.fold(0, (a, b) => a + b),
      },
      'blocked_reasons': blocked,
      'rates': {
        'opt_in_rate': _rate(opted.length, checkout.length),
        'contact_rate': _rate(contacted.length, eligible.length),
        'reply_rate': _rate(replied.length, contacted.length),
        'observed_recovery_rate': _rate(recovered.length, contacted.length),
      },
      'money': {
        'currency': 'PKR',
        'attributed_recovered_sales_pkr': atts.fold<int>(0, (s, e) => s + e.revenue),
        'all_order_sales_pkr': allOrders.where((o) => o.status == 'placed').fold<int>(0, (s, o) => s + o.total),
        'estimated_messaging_cost_pkr': cost,
        'cost_assumption': 'PKR ${settings['est_cost_per_message_pkr']} per sent message (merchant-set assumption, not a quote)',
        'note': 'Attributed sales are gross order totals, not profit and not proven incremental.',
      },
      'incremental_lift': lift,
      'funnel': [
        {'stage': 'cart_created', 'label': 'Cart created', 'count': carts.length},
        {'stage': 'abandoned', 'label': 'Abandoned at checkout', 'count': abandoned.length},
        {'stage': 'opted_in', 'label': 'Opted in (of abandoned)', 'count': abandoned.where((c) => c.checkout?.optedIn == true).length},
        {'stage': 'contacted', 'label': 'Contacted', 'count': contacted.length},
        {'stage': 'replied', 'label': 'Replied', 'count': replied.length},
        {'stage': 'recovered', 'label': 'Recovered (order placed)', 'count': recovered.length},
      ],
      'definitions': {
        'opt_in_rate': 'Opted-in checkout shoppers / checkout shoppers',
        'contact_rate': 'Contacted carts / eligible opted-in abandoned carts',
        'reply_rate': 'Carts with a shopper reply after contact / contacted carts',
        'observed_recovery_rate': 'Recovered carts / contacted carts (not incremental)',
        'attributed_recovered_sales':
            'Sum of completed order totals placed within the attribution window after a recovery contact; excludes canceled/refunded',
        'incremental_lift': 'Treatment minus holdout recovery rate. Needs a randomized holdout with at least 30 carts per arm',
      },
      'recent_events': [for (final e in recent) {'type': e.type, 'cart_id': e.cartId, 'at': e.at.toIso8601String(), 'detail': e.detail}],
    };
  }
}
