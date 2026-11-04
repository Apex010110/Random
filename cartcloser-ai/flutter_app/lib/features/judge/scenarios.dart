import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models.dart';
import '../../core/providers.dart';
import '../shopper/actions.dart';

enum GuideFocus { shopper, merchant }

class GuideStep {
  final String title, body;
  final GuideFocus focus;
  final Future<String?> Function(GuideCtx g)? run; // returns an optional note to show
  const GuideStep(this.title, this.body, {this.focus = GuideFocus.shopper, this.run});
}

class Scenario {
  final String id, title, summary, personaId;
  final List<GuideStep> steps;
  const Scenario(this.id, this.title, this.summary, this.personaId, this.steps);
}

/// Helpers the scripted steps use. Each step makes its own prerequisites true, so the
/// presenter can jump around (Next/Back) without breaking the demo.
class GuideCtx {
  final WidgetRef ref;
  final String personaId;
  GuideCtx(this.ref, this.personaId);

  ShopperActions get a => ShopperActions(ref);
  Snapshot get s => ref.read(repositoryProvider).current!;
  ShopperNav get nav => ref.read(shopperNavProvider.notifier);
  MerchantNav get mnav => ref.read(merchantNavProvider.notifier);
  Cart? get cart => s.openCartFor(personaId);
  Cart? get lastCart => (s.cartsFor(personaId)..sort((x, y) => y.createdAt.compareTo(x.createdAt))).firstOrNull;

  void persona() {
    if (ref.read(personaProvider) != personaId) ref.read(personaProvider.notifier).set(personaId);
  }

  Future<Cart> ensureCart({String product = 'p_linen_kurta', String size = 'M'}) async {
    persona();
    final c = cart;
    if (c != null && c.items.isNotEmpty) return c;
    return a.addToCart(product, size);
  }

  Future<Cart> ensureCheckout({required bool optIn, String? city}) async {
    final c = await ensureCart();
    if (c.status != 'active_cart') return c;
    final persona = ref.read(bootstrapProvider).personas.firstWhere((p) => p.id == personaId);
    return a.startCheckout(c, city: city ?? persona.city, payment: 'cod', optIn: optIn);
  }

  Future<Cart> ensureAbandoned({required bool optIn}) async {
    final c = await ensureCheckout(optIn: optIn);
    if (c.status != 'checkout_started') return c;
    return a.abandon(c);
  }

  Future<Cart> ensureSent() async {
    final c = await ensureAbandoned(optIn: true);
    if (c.status == 'eligible' || c.status == 'scheduled') {
      await ref.read(repositoryProvider).triggerRecovery(c.id);
    }
    return s.cart(c.id)!;
  }

  String? tokenFor(String cartId) {
    final conv = s.conversations[cartId];
    if (conv == null) return null;
    for (final m in conv.messages.reversed) {
      if (m.meta['token'] != null) return m.meta['token'] as String;
    }
    return null;
  }

  Future<void> say(String cartId, String text) async {
    nav.root(const InboxPage());
    nav.push(ChatPage(cartId));
    await a.say(cartId, text);
  }
}

const _kurta = 'p_linen_kurta';

final scenarios = <Scenario>[
  Scenario('A', 'A · Recovered order (opted in)', 'Opted-in shopper abandons, asks delivery + COD questions, completes the order; dashboard counts the recovery.',
      'shp_ayesha', [
    GuideStep('Meet Ayesha, an adult shopper in Karachi', 'She browses UrbanThread PK, a fictional Pakistani apparel store. Everything runs offline in demo mode.',
        run: (g) async {
      g.persona();
      g.nav.root(const StorePage());
      g.mnav.tab(MerchantTab.overview);
      return null;
    }),
    GuideStep('Open the linen kurta', 'Product page shows sizes, stock, city delivery estimate, COD availability and the exchange policy.', run: (g) async {
      g.persona();
      g.nav.root(const StorePage());
      g.nav.push(const ProductPage(_kurta));
      return null;
    }),
    GuideStep('Add size M to the cart', 'Watch the cart badge.', run: (g) async {
      await g.ensureCart();
      g.nav.root(const CartPageRoute());
      return null;
    }),
    GuideStep('Checkout and opt in to WhatsApp reminders', 'The reminder checkbox is separate, optional and unticked by default. Ayesha ticks it herself; the consent version, time, source and purpose are recorded.',
        run: (g) async {
      await g.ensureCheckout(optIn: true);
      g.nav.root(const CartPageRoute());
      g.nav.push(const CheckoutPage());
      return null;
    }),
    GuideStep('Ayesha leaves checkout', 'An explicit abandonment event (like closing the tab). Viewing a cart never counts as abandonment.', run: (g) async {
      await g.ensureAbandoned(optIn: true);
      g.nav.root(const StorePage());
      return null;
    }),
    GuideStep('Merchant dashboard: an eligible abandoned cart', 'Eligible = opted in, adult, not purchased, campaign on. A send is scheduled after the configured delay.',
        focus: GuideFocus.merchant, run: (g) async {
      final c = await g.ensureAbandoned(optIn: true);
      g.mnav.openCart(c.id);
      return null;
    }),
    GuideStep('Trigger the simulated recovery now', 'Demo mode skips the 20-minute wait only. Consent, age, quiet hours and duplicate checks run again at send time.',
        focus: GuideFocus.merchant, run: (g) async {
      final c = await g.ensureSent();
      g.mnav.openCart(c.id);
      return c.status == 'message_sent' || c.status == 'replied' ? null : 'Not sent: ${c.statusReason ?? c.status}';
    }),
    GuideStep('Ayesha receives one approved message', 'Simulated WhatsApp, clearly labelled. It includes how to opt out (STOP).', run: (g) async {
      final c = await g.ensureSent();
      g.nav.root(const InboxPage());
      g.nav.push(ChatPage(c.id));
      return null;
    }),
    GuideStep('She asks: "Will it arrive in Karachi by Friday?"', 'The AI shows the store\'s estimated window and says plainly that it cannot guarantee Friday.', run: (g) async {
      final c = await g.ensureSent();
      await g.say(c.id, 'Will it arrive in Karachi by Friday?');
      return null;
    }),
    GuideStep('She asks: "Can I pay COD?"', 'Answer is checked against product COD eligibility, Karachi\'s COD policy and the order limit. Try "COD hai?" too.', run: (g) async {
      final c = await g.ensureSent();
      await g.say(c.id, 'Can I pay COD?');
      return null;
    }),
    GuideStep('Open the secure checkout link', 'A signed link returns her to the saved cart. Opening the link is NOT counted as a recovery.', run: (g) async {
      final c = await g.ensureSent();
      final t = g.tokenFor(c.id);
      if (t == null) return 'No link yet. Ask a question first.';
      g.nav.root(const InboxPage());
      g.nav.push(ChatPage(c.id));
      g.nav.push(RecoverPage(c.id, t));
      return null;
    }),
    GuideStep('Confirm the cash-on-delivery order', 'Recovery is counted only when an order is actually placed.', run: (g) async {
      final c = g.cart ?? g.lastCart;
      if (c == null) return 'No cart';
      if (c.orderId != null) {
        g.nav.root(ReceiptPage(c.orderId!));
        return null;
      }
      final t = g.tokenFor(c.id);
      final o = await g.a.placeOrder(c, payment: 'cod', codConfirmed: true, token: t);
      g.nav.root(ReceiptPage(o.id));
      return null;
    }),
    GuideStep('Dashboard updates: recovered order + attributed sales', 'Counts come from real demo events. Attributed sales are gross, not profit, and not proven incremental.',
        focus: GuideFocus.merchant, run: (g) async {
      g.mnav.closeCart();
      g.mnav.tab(MerchantTab.overview);
      return null;
    }),
  ]),
  Scenario('B', 'B · No opt-in: no outbound message', 'Shopper does not tick the reminder box. Nothing is sent; the on-site assistant still helps.', 'shp_bilal', [
    GuideStep('Bilal (Lahore) adds the kurta to his cart', '', run: (g) async {
      await g.ensureCart();
      g.nav.root(const CartPageRoute());
      return null;
    }),
    GuideStep('Checkout WITHOUT ticking WhatsApp reminders', 'A phone number alone is never treated as consent.', run: (g) async {
      await g.ensureCheckout(optIn: false);
      g.nav.root(const CartPageRoute());
      g.nav.push(const CheckoutPage());
      return null;
    }),
    GuideStep('Bilal leaves checkout', '', run: (g) async {
      await g.ensureAbandoned(optIn: false);
      g.nav.root(const StorePage());
      return null;
    }),
    GuideStep('Merchant: Not eligible · No opt-in', 'Pressing "Trigger recovery now" is refused; no message exists.', focus: GuideFocus.merchant, run: (g) async {
      final c = await g.ensureAbandoned(optIn: false);
      g.mnav.openCart(c.id);
      try {
        await g.ref.read(repositoryProvider).triggerRecovery(c.id);
        return 'Unexpected: sent';
      } on ApiException catch (e) {
        return 'Blocked as expected: ${e.message}';
      }
    }),
    GuideStep('On-site chat still works (shopper-initiated)', 'Bilal opens "Ask a question" himself. This is inbound help, not outbound marketing.', run: (g) async {
      final c = await g.ensureAbandoned(optIn: false);
      await g.say(c.id, 'Is cash on delivery available in Lahore?');
      return null;
    }),
    GuideStep('Analytics: the block is counted', '', focus: GuideFocus.merchant, run: (g) async {
      g.mnav.tab(MerchantTab.analytics);
      return null;
    }),
  ]),
  Scenario('C', 'C · STOP blocks future sends', 'After a recovery message, the shopper replies STOP; consent is revoked and later carts cannot be contacted.', 'shp_ayesha', [
    GuideStep('Set up: Ayesha has received a recovery message', '', run: (g) async {
      final c = await g.ensureSent();
      g.nav.root(const InboxPage());
      g.nav.push(ChatPage(c.id));
      return null;
    }),
    GuideStep('She replies STOP', 'Consent is revoked immediately and pending sends are cancelled.', run: (g) async {
      final c = await g.ensureSent();
      await g.say(c.id, 'STOP');
      return null;
    }),
    GuideStep('A later abandoned cart is blocked: "Opted out"', '', focus: GuideFocus.merchant, run: (g) async {
      final old = g.cart;
      if (old != null && old.orderId == null) {
        await g.a.placeOrder(old, payment: 'online_demo', codConfirmed: false);
      }
      final c = await g.a.addToCart('p_waistcoat', 'M');
      final c2 = await g.a.startCheckout(c, city: 'Karachi', payment: 'cod', optIn: false);
      final c3 = await g.a.abandon(c2);
      g.mnav.openCart(c3.id);
      return 'New cart status: ${c3.status} (${c3.statusReason})';
    }),
  ]),
  Scenario('D', 'D · Out of stock: no fabricated availability', 'The assistant never invents stock; it suggests an in-stock alternative or a human.', 'shp_ayesha', [
    GuideStep('Ask about the block-print dupatta (sold out)', '', run: (g) async {
      final c = await g.ensureCheckout(optIn: false);
      await g.say(c.id, 'Is the dupatta in stock?');
      return null;
    }),
    GuideStep('Ask about kurta size L (sold out in L)', '', run: (g) async {
      final c = await g.ensureCheckout(optIn: false);
      await g.say(c.id, 'Is L available?');
      return null;
    }),
    GuideStep('Merchant can restock in Catalog; answers update instantly', '', focus: GuideFocus.merchant, run: (g) async {
      g.mnav.tab(MerchantTab.catalog);
      return null;
    }),
  ]),
  Scenario('E', 'E · Teen safeguard', 'A 16-year-old persona opts in, but outbound promotional recovery stays blocked.', 'shp_zara', [
    GuideStep('Zara (16) checks out and ticks reminders', '', run: (g) async {
      await g.ensureCheckout(optIn: true);
      g.nav.root(const CartPageRoute());
      g.nav.push(const CheckoutPage());
      return null;
    }),
    GuideStep('She leaves checkout', '', run: (g) async {
      await g.ensureAbandoned(optIn: true);
      g.nav.root(const StorePage());
      return null;
    }),
    GuideStep('Merchant: Not eligible · Under-18 safeguard', '', focus: GuideFocus.merchant, run: (g) async {
      final c = await g.ensureAbandoned(optIn: true);
      g.mnav.openCart(c.id);
      try {
        await g.ref.read(repositoryProvider).triggerRecovery(c.id);
        return 'Unexpected: sent';
      } on ApiException catch (e) {
        return 'Blocked as expected: ${e.message}';
      }
    }),
  ]),
  Scenario('F', 'F · Purchased before the scheduled send', 'The shopper comes back and buys before the reminder fires, so the send is cancelled.', 'shp_bilal', [
    GuideStep('Bilal opts in and leaves checkout; a send is scheduled', '', focus: GuideFocus.merchant, run: (g) async {
      final c = await g.ensureAbandoned(optIn: true);
      g.mnav.openCart(c.id);
      return 'Status: ${c.status}';
    }),
    GuideStep('He returns on his own and places the order', '', run: (g) async {
      final c = g.cart;
      if (c == null) return 'No open cart';
      final o = await g.a.placeOrder(c, payment: 'online_demo', codConfirmed: false);
      g.nav.root(ReceiptPage(o.id));
      return null;
    }),
    GuideStep('Merchant: send cancelled (already purchased), not attributed', '', focus: GuideFocus.merchant, run: (g) async {
      final c = g.lastCart;
      if (c != null) g.mnav.openCart(c.id);
      return null;
    }),
  ]),
  Scenario('G', 'G · Human handoff', 'An unsupported question is escalated; a team member takes over and the AI stops replying.', 'shp_ayesha', [
    GuideStep('Ask something the store data cannot answer', '', run: (g) async {
      final c = await g.ensureSent();
      await g.say(c.id, 'Can you embroider my name on the sleeve?');
      return null;
    }),
    GuideStep('Merchant inbox: flagged "Needs human" with low AI confidence', '', focus: GuideFocus.merchant, run: (g) async {
      final c = g.cart ?? g.lastCart;
      if (c != null) g.mnav.openCart(c.id, tab: MerchantTab.inbox);
      return null;
    }),
    GuideStep('A team member replies (takes over)', '', focus: GuideFocus.merchant, run: (g) async {
      final c = g.cart ?? g.lastCart;
      if (c == null) return null;
      await g.ref.read(repositoryProvider).humanReply(c.id, 'Hi Ayesha, I\'ll check with our tailor and confirm the price here today.');
      g.nav.root(const InboxPage());
      g.nav.push(ChatPage(c.id));
      return null;
    }),
  ]),
  Scenario('H', 'H · Duplicate events', 'The same abandon webhook arrives 3 times and the send is triggered twice: one attempt, one message, one order.', 'shp_bilal', [
    GuideStep('Send the same abandonment event three times', '', focus: GuideFocus.merchant, run: (g) async {
      final c = await g.ensureCheckout(optIn: true);
      final repo = g.ref.read(repositoryProvider);
      for (var i = 0; i < 3; i++) {
        await repo.abandon(g.personaId, c.id, idempotencyKey: 'webhook-evt-1');
      }
      g.mnav.openCart(c.id);
      return 'Recovery attempts: ${g.s.cart(c.id)!.attempts.length}';
    }),
    GuideStep('Trigger twice: the second is refused (contact cap)', '', focus: GuideFocus.merchant, run: (g) async {
      final c = g.cart;
      if (c == null) return null;
      final repo = g.ref.read(repositoryProvider);
      await repo.triggerRecovery(c.id);
      try {
        await repo.triggerRecovery(c.id);
      } on ApiException catch (e) {
        return 'Second trigger refused: ${e.message}';
      }
      return 'Second trigger did not send (already sent)';
    }),
    GuideStep('Place the same order twice: one order', '', run: (g) async {
      final c = g.cart;
      if (c == null) return null;
      final o1 = await g.a.placeOrder(c, payment: 'online_demo', codConfirmed: false, token: g.tokenFor(c.id));
      final o2 = await g.a.placeOrder(c, payment: 'online_demo', codConfirmed: false, token: g.tokenFor(c.id));
      g.nav.root(ReceiptPage(o1.id));
      return o1.id == o2.id ? 'Same order returned: ${o1.id}' : 'Duplicate order!';
    }),
  ]),
];
