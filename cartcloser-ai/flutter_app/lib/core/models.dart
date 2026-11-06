// Typed models. Both repositories (offline engine and HTTP backend) produce the same JSON
// shapes (see backend/app/api/serialize.py), so the UI is identical in both modes.

DateTime? _dt(dynamic v) => v == null ? null : DateTime.parse(v as String).toUtc();
int _i(dynamic v) => (v as num?)?.toInt() ?? 0;

class Variant {
  final String size;
  final int stock;
  const Variant(this.size, this.stock);
  factory Variant.fromJson(Map j) => Variant(j['size'] as String, _i(j['stock']));
}

class Product {
  final String id, name, category, description, fitNotes, imageKey, colorHex;
  final int pricePkr;
  final bool codEligible, active;
  final List<Variant> variants;
  const Product({
    required this.id,
    required this.name,
    required this.category,
    required this.description,
    required this.fitNotes,
    required this.imageKey,
    required this.colorHex,
    required this.pricePkr,
    required this.codEligible,
    required this.active,
    required this.variants,
  });
  factory Product.fromJson(Map j) => Product(
        id: j['id'],
        name: j['name'],
        category: j['category'],
        description: j['description'] ?? '',
        fitNotes: j['fit_notes'] ?? '',
        imageKey: j['image_key'] ?? 'kurta',
        colorHex: j['color_hex'] ?? '#3CE7E2',
        pricePkr: _i(j['price_pkr']),
        codEligible: j['cod_eligible'] == true,
        active: j['active'] != false,
        variants: [for (final v in (j['variants'] as List)) Variant.fromJson(v)],
      );
  int get totalStock => variants.fold(0, (a, v) => a + v.stock);
  bool get inStock => totalStock > 0;
  List<String> get inStockSizes => [for (final v in variants) if (v.stock > 0) v.size];
}

class StoreInfo {
  final String tenantId, name, consentText, consentVersion;
  final bool isDemo;
  final Map<String, dynamic> policy;
  final int discountCeilingPct;
  const StoreInfo(this.tenantId, this.name, this.isDemo, this.policy, this.consentText, this.consentVersion, this.discountCeilingPct);
  factory StoreInfo.fromJson(Map j) => StoreInfo(j['tenant_id'], j['name'], j['is_demo'] == true,
      Map<String, dynamic>.from(j['policy']), j['consent_text'] ?? '', j['consent_version'] ?? 'v1', _i(j['discount_ceiling_pct']));
  List<String> get codCities => List<String>.from(policy['cod_cities'] ?? const []);
  List<int> deliveryWindow(String city) {
    final w = Map<String, dynamic>.from(policy['delivery_windows']);
    return List<int>.from(w[city] ?? w['default']);
  }

  int shippingFee(String city, int subtotal) {
    if (subtotal >= _i(policy['free_shipping_threshold_pkr'])) return 0;
    final f = Map<String, dynamic>.from(policy['shipping_fees']);
    return _i(f[city] ?? f['default']);
  }
}

class CartLine {
  final String productId, name, size;
  final int quantity, unitPricePkr;
  final bool codEligible;
  const CartLine(this.productId, this.name, this.size, this.quantity, this.unitPricePkr, this.codEligible);
  factory CartLine.fromJson(Map j) =>
      CartLine(j['product_id'], j['name'], j['size'], _i(j['quantity']), _i(j['unit_price_pkr']), j['cod_eligible'] == true);
  Map<String, dynamic> toItem() => {'product_id': productId, 'size': size, 'quantity': quantity};
}

class Totals {
  final int subtotal, discountPct, discount, shipping, total;
  final String city;
  final String? discountCode;
  const Totals(this.subtotal, this.discountPct, this.discount, this.shipping, this.total, this.city, this.discountCode);
  factory Totals.fromJson(Map j) => Totals(_i(j['subtotal_pkr']), _i(j['discount_pct']), _i(j['discount_pkr']), _i(j['shipping_pkr']),
      _i(j['total_pkr']), j['city'] ?? '', j['discount_code']);
}

class RecoveryAttempt {
  final String id, status, channel;
  final String? reason;
  final DateTime scheduledFor;
  final DateTime? sentAt;
  const RecoveryAttempt(this.id, this.status, this.reason, this.channel, this.scheduledFor, this.sentAt);
  factory RecoveryAttempt.fromJson(Map j) =>
      RecoveryAttempt(j['id'], j['status'], j['reason'], j['channel'] ?? 'whatsapp_sim', _dt(j['scheduled_for'])!, _dt(j['sent_at']));
}

class ShopperBrief {
  final String id, firstName, phoneMasked, ageBand;
  const ShopperBrief(this.id, this.firstName, this.phoneMasked, this.ageBand);
  factory ShopperBrief.fromJson(Map j) => ShopperBrief(j['id'], j['first_name'], j['phone_masked'], j['age_band']);
}

class Cart {
  final String id, shopperId, status;
  final String? statusReason, promoCode, orderId, recoveryLink;
  final List<CartLine> items;
  final Totals totals;
  final Map<String, dynamic>? checkout, consent;
  final bool recoveryPaused, holdout;
  final DateTime createdAt;
  final DateTime? abandonedAt;
  final List<RecoveryAttempt> attempts;
  final ShopperBrief? shopper;
  final int messageCount;
  const Cart({
    required this.id,
    required this.shopperId,
    required this.status,
    this.statusReason,
    this.promoCode,
    this.orderId,
    this.recoveryLink,
    required this.items,
    required this.totals,
    this.checkout,
    this.consent,
    required this.recoveryPaused,
    required this.holdout,
    required this.createdAt,
    this.abandonedAt,
    required this.attempts,
    this.shopper,
    this.messageCount = 0,
  });
  factory Cart.fromJson(Map j) => Cart(
        id: j['id'],
        shopperId: j['shopper_id'],
        status: j['status'],
        statusReason: j['status_reason'],
        promoCode: j['promo_code'],
        orderId: j['order_id'],
        recoveryLink: j['recovery_link'],
        items: [for (final i in (j['items'] as List)) CartLine.fromJson(i)],
        totals: Totals.fromJson(j['totals']),
        checkout: j['checkout'] == null ? null : Map<String, dynamic>.from(j['checkout']),
        consent: j['consent'] == null ? null : Map<String, dynamic>.from(j['consent']),
        recoveryPaused: j['recovery_paused'] == true,
        holdout: j['holdout'] == true,
        createdAt: _dt(j['created_at'])!,
        abandonedAt: _dt(j['abandoned_at']),
        attempts: [for (final a in (j['recovery_attempts'] as List? ?? const [])) RecoveryAttempt.fromJson(a)],
        shopper: j['shopper'] == null ? null : ShopperBrief.fromJson(j['shopper']),
        messageCount: _i(j['message_count']),
      );
  int get itemCount => items.fold(0, (a, i) => a + i.quantity);
  bool get isClosed => const {'recovered', 'ordered', 'expired'}.contains(status);
  bool get optedIn => consent != null;
  RecoveryAttempt? get sentAttempt => attempts.where((a) => a.status == 'sent').firstOrNull;
  RecoveryAttempt? get scheduledAttempt => attempts.where((a) => a.status == 'scheduled').firstOrNull;
  Duration age(DateTime now) => now.difference(createdAt);
}

class ChatMessage {
  final String id, role, text;
  final int seq;
  final String? intent, language, source;
  final double? confidence;
  final Map<String, dynamic> meta;
  final DateTime createdAt;
  const ChatMessage(this.id, this.seq, this.role, this.text, this.intent, this.confidence, this.language, this.source, this.meta, this.createdAt);
  factory ChatMessage.fromJson(Map j) => ChatMessage(j['id'], _i(j['seq']), j['role'], j['text'], j['intent'],
      (j['confidence'] as num?)?.toDouble(), j['language'], j['source'], Map<String, dynamic>.from(j['meta'] ?? {}), _dt(j['created_at'])!);
  bool get hasCheckoutLink => meta['checkout_link'] == true;
  bool get isUrdu => language == 'ur';
}

class Conversation {
  final String cartId, channel;
  final bool humanTakeover, escalated;
  final List<ChatMessage> messages;
  const Conversation(this.cartId, this.channel, this.humanTakeover, this.escalated, this.messages);
  factory Conversation.fromJson(Map j) => Conversation(j['cart_id'], j['channel'] ?? 'none', j['human_takeover'] == true,
      j['escalated'] == true, [for (final m in (j['messages'] as List)) ChatMessage.fromJson(m)]);
  bool get isWhatsAppSim => channel == 'whatsapp_sim';
  ChatMessage? get last => messages.isEmpty ? null : messages.last;
}

class Order {
  final String id, cartId, status, paymentMethod, city;
  final bool codConfirmed, viaRecoveryLink, attributed;
  final int subtotal, discount, shipping, total;
  final String? discountCode;
  final List<Map<String, dynamic>> lines;
  final DateTime createdAt;
  // Green Logistics fulfillment lifecycle
  final String fulfillmentStatus;
  final String? deliveryZone, addressRedacted, scenarioId;
  final bool sizeQuestionResolved, codPredispatchConfirmed, hadFailedAttempt, everDelivered, wasHeld, deliveryConsolidationSelected;
  const Order(this.id, this.cartId, this.status, this.paymentMethod, this.city, this.codConfirmed, this.viaRecoveryLink, this.attributed,
      this.subtotal, this.discount, this.shipping, this.total, this.discountCode, this.lines, this.createdAt,
      {this.fulfillmentStatus = 'ready_to_dispatch', this.deliveryZone, this.addressRedacted, this.scenarioId,
      this.sizeQuestionResolved = false, this.codPredispatchConfirmed = false, this.hadFailedAttempt = false, this.everDelivered = false,
      this.wasHeld = false, this.deliveryConsolidationSelected = false});
  factory Order.fromJson(Map j) => Order(
      j['id'],
      j['cart_id'],
      j['status'],
      j['payment_method'],
      j['city'],
      j['cod_confirmed'] == true,
      j['via_recovery_link'] == true,
      j['attributed'] == true,
      _i(j['subtotal_pkr']),
      _i(j['discount_pkr']),
      _i(j['shipping_pkr']),
      _i(j['total_pkr']),
      j['discount_code'],
      [for (final l in (j['lines'] as List)) Map<String, dynamic>.from(l)],
      _dt(j['created_at'])!,
      fulfillmentStatus: j['fulfillment_status'] ?? 'ready_to_dispatch',
      deliveryZone: j['delivery_zone'],
      addressRedacted: j['address_redacted'],
      scenarioId: j['scenario_id'],
      sizeQuestionResolved: j['size_question_resolved'] == true,
      codPredispatchConfirmed: j['cod_predispatch_confirmed'] == true,
      hadFailedAttempt: j['had_failed_attempt'] == true,
      everDelivered: j['ever_delivered'] == true,
      wasHeld: j['was_held'] == true,
      deliveryConsolidationSelected: j['delivery_consolidation_selected'] == true);
}

const fulfillmentTabs = ['pending_confirmation', 'ready_to_dispatch', 'hold', 'cancelled', 'delivered', 'returned', 'failed_attempt'];
const fulfillmentLabels = {
  'pending_confirmation': 'Needs confirmation',
  'ready_to_dispatch': 'Ready to dispatch',
  'hold': 'Hold',
  'cancelled': 'Cancelled',
  'delivered': 'Delivered',
  'returned': 'Returned',
  'failed_attempt': 'Failed attempt',
  'dispatched': 'Dispatched',
};

class Rate {
  final int numerator, denominator;
  final double? value;
  const Rate(this.numerator, this.denominator, this.value);
  factory Rate.fromJson(Map j) => Rate(_i(j['numerator']), _i(j['denominator']), (j['value'] as num?)?.toDouble());
  String get pct => value == null ? '—' : '${(value! * 100).toStringAsFixed(0)}%';
}

class Metrics {
  final Map<String, int> counts;
  final Map<String, Rate> rates;
  final Map<String, dynamic> money, lift;
  final Map<String, int> blockedReasons;
  final List<Map<String, dynamic>> funnel, recentEvents;
  final Map<String, String> definitions;
  final bool isDemoData;
  final Map<String, dynamic> green;
  const Metrics(this.counts, this.rates, this.money, this.lift, this.blockedReasons, this.funnel, this.recentEvents, this.definitions,
      this.isDemoData, this.green);
  factory Metrics.fromJson(Map j) => Metrics(
        {for (final e in (j['counts'] as Map).entries) e.key as String: _i(e.value)},
        {for (final e in (j['rates'] as Map).entries) e.key as String: Rate.fromJson(e.value)},
        Map<String, dynamic>.from(j['money']),
        Map<String, dynamic>.from(j['incremental_lift']),
        {for (final e in ((j['blocked_reasons'] ?? {}) as Map).entries) e.key as String: _i(e.value)},
        [for (final f in (j['funnel'] as List)) Map<String, dynamic>.from(f)],
        [for (final f in ((j['recent_events'] ?? const []) as List)) Map<String, dynamic>.from(f)],
        Map<String, String>.from(j['definitions'] ?? {}),
        j['is_demo_data'] == true,
        Map<String, dynamic>.from(j['green'] ?? {}),
      );
  int c(String k) => counts[k] ?? 0;
}

/// Typed read of Metrics.green, so dashboard widgets don't sprinkle raw map casts.
class GreenMetrics {
  final String? scenarioId;
  final Map<String, dynamic> assumptions;
  final Map<String, int> counts;
  final Map<String, Rate> rates;
  final Map<String, dynamic> estimates;
  final Map<String, String> definitions;
  final String banner;
  const GreenMetrics(this.scenarioId, this.assumptions, this.counts, this.rates, this.estimates, this.definitions, this.banner);
  factory GreenMetrics.fromJson(Map<String, dynamic> j) => GreenMetrics(
        j['scenario_id'],
        Map<String, dynamic>.from(j['assumptions'] ?? {}),
        {for (final e in ((j['counts'] ?? {}) as Map).entries) e.key as String: _i(e.value)},
        {for (final e in ((j['rates'] ?? {}) as Map).entries) e.key as String: Rate.fromJson(e.value)},
        Map<String, dynamic>.from(j['estimates'] ?? {}),
        Map<String, String>.from(j['definitions'] ?? {}),
        j['banner'] ?? 'Simulation only — no verified environmental impact or pilot outcomes.',
      );
  int c(String k) => counts[k] ?? 0;
}

class Persona {
  final String id, firstName, phoneMasked, city, ageBand, label;
  const Persona(this.id, this.firstName, this.phoneMasked, this.city, this.ageBand, this.label);
  factory Persona.fromJson(Map j) => Persona(j['id'], j['first_name'], j['phone_masked'], j['city'], j['age_band'], j['label']);
  bool get isMinor => ageBand == 'under_18';
}

class Integration {
  final String provider, status, detail;
  const Integration(this.provider, this.status, this.detail);
  factory Integration.fromJson(Map j) => Integration(j['provider'], j['status'], j['detail'] ?? '');
  bool get connected => status == 'connected';
}

class ApiException implements Exception {
  final int status;
  final String code, message;
  const ApiException(this.status, this.code, this.message);
  @override
  String toString() => message;
}

/// Everything the UI renders, refreshed after every change.
class Snapshot {
  final int version;
  final StoreInfo store;
  final List<Product> products;
  final List<Cart> carts; // merchant view, includes shopper brief
  final Map<String, Conversation> conversations; // by cart id
  final Map<String, Order> orders; // by order id
  final Map<String, bool> optedIn; // shopper id -> active consent
  final Metrics metrics;
  final Map<String, dynamic> settings;
  final List<Integration> integrations;
  final Map<String, dynamic> catalogPolicy;
  final DateTime fetchedAt;
  const Snapshot({
    required this.version,
    required this.store,
    required this.products,
    required this.carts,
    required this.conversations,
    required this.orders,
    required this.optedIn,
    required this.metrics,
    required this.settings,
    required this.integrations,
    required this.catalogPolicy,
    required this.fetchedAt,
  });
  Product? product(String id) => products.where((p) => p.id == id).firstOrNull;
  Cart? cart(String id) => carts.where((c) => c.id == id).firstOrNull;
  GreenMetrics get green => GreenMetrics.fromJson(metrics.green);
  List<Cart> cartsFor(String shopperId) => [for (final c in carts) if (c.shopperId == shopperId) c];

  /// The shopper's current open cart (most recent not completed).
  Cart? openCartFor(String shopperId) {
    final list = cartsFor(shopperId).where((c) => !c.isClosed).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list.firstOrNull;
  }

  List<Conversation> conversationsFor(String shopperId) {
    final ids = {for (final c in cartsFor(shopperId)) c.id};
    final list = [for (final c in conversations.values) if (ids.contains(c.cartId) && c.messages.isNotEmpty) c];
    list.sort((a, b) => b.last!.createdAt.compareTo(a.last!.createdAt));
    return list;
  }
}
