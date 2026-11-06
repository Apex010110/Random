import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/engine/assistant_rules.dart';
import '../../core/models.dart';
import '../../core/providers.dart';
import '../../shared/widgets.dart';
import 'actions.dart';
import 'shopper_app.dart';

// ---------------------------------------------------------------- cart
class CartScreen extends ConsumerWidget {
  const CartScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final persona = ref.watch(currentPersonaProvider);
    return SnapshotGate(builder: (s) {
      final cart = s.openCartFor(persona.id);
      if (cart == null || cart.items.isEmpty) {
        return Scaffold(
          appBar: const ShopperHeader('Your cart'),
          body: Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.shopping_bag_outlined, size: 56, color: CC.dim),
              const SizedBox(height: 12),
              const Text('Your cart is empty', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              const SizedBox(height: 16),
              FilledButton(onPressed: () => ref.read(shopperNavProvider.notifier).root(const StorePage()), child: const Text('Browse the store')),
            ]),
          ),
        );
      }
      return Scaffold(
        appBar: const ShopperHeader('Your cart'),
        body: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 140), children: [
          for (final l in cart.items) _LineTile(cart, l, s.product(l.productId)),
          const SizedBox(height: 12),
          _PromoField(cart),
          const SizedBox(height: 16),
          TotalsCard(cart.totals),
          if (cart.status != 'active_cart' && cart.status != 'checkout_started') ...[
            const SizedBox(height: 12),
            Text('Saved cart · ${statusLabels[cart.status] ?? cart.status}', style: const TextStyle(color: CC.dim, fontSize: 12)),
          ],
        ]),
        bottomSheet: _BottomBar(
          child: FilledButton(
            onPressed: () => ref.read(shopperNavProvider.notifier).push(const CheckoutPage()),
            child: Text('Checkout · ${pkr(cart.totals.total)}'),
          ),
        ),
      );
    });
  }
}

class _LineTile extends ConsumerWidget {
  final Cart cart;
  final CartLine line;
  final Product? product;
  const _LineTile(this.cart, this.line, this.product);
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stock = product?.variants.where((v) => v.size == line.size).firstOrNull?.stock ?? 0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(children: [
            SizedBox(width: 64, height: 64, child: product == null ? const SizedBox() : ProductArt(product!, radius: 12, iconSize: 28)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(line.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                Text('Size ${line.size} · ${pkr(line.unitPricePkr)}', style: const TextStyle(color: CC.muted, fontSize: 13)),
              ]),
            ),
            IconButton(
              tooltip: 'Decrease',
              icon: const Icon(Icons.remove_circle_outline),
              onPressed: () => guarded(context, () => ShopperActions(ref).setQty(cart, line, line.quantity - 1)),
            ),
            Text('${line.quantity}', style: const TextStyle(fontWeight: FontWeight.w700)),
            IconButton(
              tooltip: 'Increase',
              icon: const Icon(Icons.add_circle_outline),
              onPressed: line.quantity >= stock ? null : () => guarded(context, () => ShopperActions(ref).setQty(cart, line, line.quantity + 1)),
            ),
          ]),
        ),
      ),
    );
  }
}

class _PromoField extends ConsumerStatefulWidget {
  final Cart cart;
  const _PromoField(this.cart);
  @override
  ConsumerState<_PromoField> createState() => _PromoFieldState();
}

class _PromoFieldState extends ConsumerState<_PromoField> {
  final _c = TextEditingController();
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final code = widget.cart.promoCode;
    if (code != null) {
      return Row(children: [
        Pill('Code $code applied', color: CC.green, icon: Icons.local_offer_outlined),
        const Spacer(),
        TextButton(onPressed: () => guarded(context, () => ShopperActions(ref).applyPromo(widget.cart, '')), child: const Text('Remove')),
      ]);
    }
    return Row(children: [
      Expanded(child: TextField(controller: _c, textCapitalization: TextCapitalization.characters, decoration: const InputDecoration(hintText: 'Promo code (try WELCOME5)', isDense: true))),
      const SizedBox(width: 8),
      OutlinedButton(
        onPressed: () => guarded(context, () => ShopperActions(ref).applyPromo(widget.cart, _c.text.trim()), success: 'Promo applied'),
        child: const Text('Apply'),
      ),
    ]);
  }
}

class TotalsCard extends StatelessWidget {
  final Totals t;
  const TotalsCard(this.t, {super.key});
  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(children: [
            _row('Subtotal', pkr(t.subtotal)),
            if (t.discount > 0) _row('Discount (${t.discountPct}% · ${t.discountCode})', '− ${pkr(t.discount)}', color: CC.green),
            _row('Shipping to ${t.city}', t.shipping == 0 ? 'Free' : pkr(t.shipping)),
            const Divider(height: 22),
            _row('Total', pkr(t.total), bold: true),
          ]),
        ),
      );
  Widget _row(String a, String b, {bool bold = false, Color? color}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [
          Expanded(child: Text(a, style: TextStyle(color: bold ? CC.white : CC.muted, fontWeight: bold ? FontWeight.w700 : null))),
          Text(b, style: TextStyle(fontWeight: bold ? FontWeight.w800 : FontWeight.w600, fontSize: bold ? 17 : 14, color: color)),
        ]),
      );
}

class _BottomBar extends StatelessWidget {
  final Widget child;
  const _BottomBar({required this.child});
  @override
  Widget build(BuildContext context) => Container(
        color: CC.ink,
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
        child: SafeArea(top: false, child: SizedBox(width: double.infinity, child: child)),
      );
}

// ---------------------------------------------------------------- checkout
class CheckoutScreen extends ConsumerStatefulWidget {
  const CheckoutScreen({super.key});
  @override
  ConsumerState<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends ConsumerState<CheckoutScreen> {
  String? _city;
  String _payment = 'cod';
  bool _optIn = false; // never pre-checked
  bool _codConfirmed = false;
  bool _busy = false;

  Future<Cart?> _ensureStarted(Cart cart) async {
    final a = ShopperActions(ref);
    final c = await guarded(context, () => a.startCheckout(cart, city: _city!, payment: _payment, optIn: _optIn));
    return c;
  }

  @override
  Widget build(BuildContext context) {
    final persona = ref.watch(currentPersonaProvider);
    final cities = ref.watch(bootstrapProvider).cities;
    return SnapshotGate(builder: (s) {
      final cart = s.openCartFor(persona.id);
      if (cart == null || cart.items.isEmpty) {
        return const Scaffold(appBar: ShopperHeader('Checkout'), body: Center(child: Text('Your cart is empty.')));
      }
      _city ??= cart.checkout?['city'] ?? persona.city;
      if (cart.checkout?['opted_in_at_checkout'] == true) _optIn = true;
      final lines = [for (final l in cart.items) Line(l.productId, l.name, l.size, l.quantity, l.unitPricePkr, l.codEligible)];
      final shipping = s.store.shippingFee(_city!, cart.totals.subtotal - cart.totals.discount);
      final total = cart.totals.subtotal - cart.totals.discount + shipping;
      final cod = AssistantRules.codCheck(s.store.policy, _city!, lines, total);
      if (cod != 'cod_yes' && _payment == 'cod') _payment = 'online_demo';
      final w = s.store.deliveryWindow(_city!);
      return Scaffold(
        appBar: ShopperHeader('Checkout', actions: [
          TextButton.icon(
            onPressed: () => _askQuestion(cart),
            icon: const Icon(Icons.support_agent, size: 18),
            label: const Text('Ask a question'),
          ),
        ]),
        body: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 180), children: [
          const SectionTitle('CONTACT'),
          Card(
            child: ListTile(
              leading: const CircleAvatar(backgroundColor: CC.navy2, child: Icon(Icons.person, color: CC.cyan)),
              title: Text(persona.firstName),
              subtitle: Text('${persona.phoneMasked} · demo shopper (fictional)'),
            ),
          ),
          const SizedBox(height: 16),
          const SectionTitle('DELIVERY'),
          DropdownButtonFormField<String>(
            initialValue: _city,
            decoration: const InputDecoration(labelText: 'City'),
            items: [for (final c in cities) DropdownMenuItem(value: c, child: Text(c))],
            onChanged: (v) => setState(() => _city = v),
          ),
          const SizedBox(height: 8),
          Text('Estimated ${w[0]}–${w[1]} business days. Shipping ${shipping == 0 ? 'free' : pkr(shipping)}. Estimates are not guarantees.',
              style: const TextStyle(color: CC.muted, fontSize: 12.5)),
          const SizedBox(height: 16),
          const SectionTitle('PAYMENT'),
          RadioGroup<String>(
            groupValue: _payment,
            onChanged: (v) => setState(() => _payment = v!),
            child: Column(children: [
              RadioListTile<String>(
                value: 'cod',
                enabled: cod == 'cod_yes',
                title: const Text('Cash on delivery'),
                subtitle: Text(cod == 'cod_yes' ? 'Pay the courier when it arrives' : _codReason(cod, _city!), style: const TextStyle(fontSize: 12.5)),
              ),
              const RadioListTile<String>(
                value: 'online_demo',
                title: Text('Online payment (demo)'),
                subtitle: Text('No card details are collected in this demo', style: TextStyle(fontSize: 12.5)),
              ),
            ]),
          ),
          if (_payment == 'cod')
            CheckboxListTile(
              value: _codConfirmed,
              onChanged: (v) => setState(() => _codConfirmed = v ?? false),
              title: const Text('I confirm this cash-on-delivery order'),
              controlAffinity: ListTileControlAffinity.leading,
            ),
          const SizedBox(height: 12),
          // ---- separate, unbundled, unchecked-by-default consent
          Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(4, 6, 12, 10),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                CheckboxListTile(
                  key: const ValueKey('optin'),
                  value: _optIn,
                  onChanged: cart.checkout?['opted_in_at_checkout'] == true ? null : (v) => setState(() => _optIn = v ?? false),
                  controlAffinity: ListTileControlAffinity.leading,
                  title: const Text('WhatsApp checkout reminders (optional)', style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(s.store.consentText, style: const TextStyle(fontSize: 12.5, height: 1.35)),
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 16),
                  child: Text('Consent ${s.store.consentVersion} · not required to order · your phone number alone is never treated as consent',
                      style: const TextStyle(color: CC.dim, fontSize: 11)),
                ),
                if (persona.isMinor)
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 8, 0, 0),
                    child: Text('Under-18 safeguard: the store will not send promotional reminders to this account.',
                        style: TextStyle(color: CC.amber, fontSize: 12)),
                  ),
              ]),
            ),
          ),
          const SizedBox(height: 16),
          TotalsCard(Totals(cart.totals.subtotal, cart.totals.discountPct, cart.totals.discount, shipping, total, _city!, cart.totals.discountCode)),
        ]),
        bottomSheet: _BottomBar(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                key: const ValueKey('place-order'),
                onPressed: _busy || (_payment == 'cod' && !_codConfirmed)
                    ? null
                    : () async {
                        setState(() => _busy = true);
                        final c = await _ensureStarted(cart);
                        if (c == null || !context.mounted) return setState(() => _busy = false);
                        final o = await guarded(context, () => ShopperActions(ref).placeOrder(c, payment: _payment, codConfirmed: _codConfirmed));
                        if (mounted) setState(() => _busy = false);
                        if (o != null) {
                          HapticFeedback.mediumImpact();
                          ref.read(shopperNavProvider.notifier).root(ReceiptPage(o.id));
                        }
                      },
                child: Text('Place order · ${pkr(total)}'),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                key: const ValueKey('leave-checkout'),
                icon: const Icon(Icons.logout, size: 18, color: CC.coral),
                label: const Text('Leave checkout (simulate closing the tab)'),
                onPressed: _busy
                    ? null
                    : () async {
                        // Record checkout details (incl. the shopper's explicit opt-in choice), then the explicit abandon event.
                        final c = await _ensureStarted(cart);
                        if (c == null || !context.mounted) return;
                        final r = await guarded(context, () => ShopperActions(ref).abandon(c));
                        if (r != null && context.mounted) {
                          ref.read(shopperNavProvider.notifier).root(const StorePage());
                          toast(context, _optIn ? 'You left checkout. The store may send one reminder (opted in).' : 'You left checkout. No reminder will be sent (no opt-in).');
                        }
                      },
              ),
            ),
          ]),
        ),
      );
    });
  }

  Future<void> _askQuestion(Cart cart) async {
    final c = cart.checkout == null ? await _ensureStarted(cart) : cart;
    if (c != null) ref.read(shopperNavProvider.notifier).push(ChatPage(c.id));
  }

  String _codReason(String key, String city) => switch (key) {
        'cod_no_product' => 'Not available for an item in your cart',
        'cod_no_city' => 'Not offered in $city',
        'cod_over_limit' => 'Order is over the COD limit',
        _ => '',
      };
}

// ---------------------------------------------------------------- recovery link checkout
class RecoverScreen extends ConsumerStatefulWidget {
  final String cartId, token;
  const RecoverScreen({super.key, required this.cartId, required this.token});
  @override
  ConsumerState<RecoverScreen> createState() => _RecoverScreenState();
}

class _RecoverScreenState extends ConsumerState<RecoverScreen> {
  late final Future<Cart> _link = ref.read(repositoryProvider).openRecoveryLink(widget.cartId, widget.token);
  String? _payment;
  bool _codConfirmed = false;
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const ShopperHeader('Secure checkout link'),
      body: FutureBuilder<Cart>(
        future: _link,
        builder: (context, f) {
          if (f.hasError) {
            return Center(child: Padding(padding: const EdgeInsets.all(24), child: Text('This link is not valid: ${f.error}', textAlign: TextAlign.center)));
          }
          if (!f.hasData) return const Padding(padding: EdgeInsets.all(20), child: Skeleton(height: 200));
          return SnapshotGate(builder: (s) {
            final cart = s.cart(widget.cartId) ?? f.data!;
            if (cart.orderId != null) {
              return Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Text('This cart has already been ordered.'),
                  const SizedBox(height: 12),
                  FilledButton(onPressed: () => ref.read(shopperNavProvider.notifier).root(ReceiptPage(cart.orderId!)), child: const Text('View receipt')),
                ]),
              );
            }
            final lines = [for (final l in cart.items) Line(l.productId, l.name, l.size, l.quantity, l.unitPricePkr, l.codEligible)];
            final cod = AssistantRules.codCheck(s.store.policy, cart.totals.city, lines, cart.totals.total);
            _payment ??= cod == 'cod_yes' ? 'cod' : 'online_demo';
            return ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 140), children: [
              const Row(children: [
                Icon(Icons.lock_outline, size: 16, color: CC.green),
                SizedBox(width: 6),
                Flexible(child: Text('Signed link · your saved cart', style: TextStyle(color: CC.green, fontSize: 12.5))),
              ]),
              const SizedBox(height: 12),
              for (final l in cart.items)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: SizedBox(width: 48, height: 48, child: s.product(l.productId) == null ? null : ProductArt(s.product(l.productId)!, radius: 10, iconSize: 22)),
                  title: Text(l.name),
                  subtitle: Text('Size ${l.size} × ${l.quantity}'),
                  trailing: Text(pkr(l.unitPricePkr * l.quantity)),
                ),
              const SizedBox(height: 8),
              TotalsCard(cart.totals),
              const SizedBox(height: 16),
              RadioGroup<String>(
                groupValue: _payment,
                onChanged: (v) => setState(() => _payment = v),
                child: Column(children: [
                  RadioListTile<String>(value: 'cod', enabled: cod == 'cod_yes', title: const Text('Cash on delivery'), subtitle: Text('Delivering to ${cart.totals.city}')),
                  const RadioListTile<String>(value: 'online_demo', title: Text('Online payment (demo, no card collected)')),
                ]),
              ),
              if (_payment == 'cod')
                CheckboxListTile(
                  key: const ValueKey('confirm-cod'),
                  value: _codConfirmed,
                  onChanged: (v) => setState(() => _codConfirmed = v ?? false),
                  controlAffinity: ListTileControlAffinity.leading,
                  title: const Text('I confirm this cash-on-delivery order'),
                  subtitle: const Text('Confirming helps the store avoid failed deliveries.'),
                ),
              const SizedBox(height: 70),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  key: const ValueKey('confirm-order'),
                  onPressed: _busy || (_payment == 'cod' && !_codConfirmed)
                      ? null
                      : () async {
                          setState(() => _busy = true);
                          final o = await guarded(
                              context, () => ShopperActions(ref).placeOrder(cart, payment: _payment!, codConfirmed: _codConfirmed, token: widget.token));
                          if (mounted) setState(() => _busy = false);
                          if (o != null) {
                            HapticFeedback.mediumImpact();
                            ref.read(shopperNavProvider.notifier).root(ReceiptPage(o.id));
                          }
                        },
                  child: Text('Confirm order · ${pkr(cart.totals.total)}'),
                ),
              ),
            ]);
          });
        },
      ),
    );
  }
}

// ---------------------------------------------------------------- receipt
class ReceiptScreen extends ConsumerWidget {
  final String orderId;
  const ReceiptScreen({super.key, required this.orderId});
  @override
  Widget build(BuildContext context, WidgetRef ref) => SnapshotGate(builder: (s) {
        final o = s.orders[orderId];
        if (o == null) return const Center(child: Text('Order not found'));
        final w = s.store.deliveryWindow(o.city);
        return Scaffold(
          appBar: const ShopperHeader('Order confirmed'),
          body: ListView(padding: const EdgeInsets.all(20), children: [
            const Center(child: AnimatedCheck()),
            const SizedBox(height: 18),
            const Center(child: Text('Thank you! Your order is placed.', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800))),
            const SizedBox(height: 6),
            Center(child: Text('Order ${o.id}', style: const TextStyle(color: CC.muted))),
            const SizedBox(height: 20),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  for (final l in o.lines) Text('${l['name']} · ${l['size']} × ${l['quantity']}'),
                  const Divider(height: 20),
                  Text('Total ${pkr(o.total)} · ${o.paymentMethod == 'cod' ? 'Cash on delivery${o.codConfirmed ? ' (confirmed)' : ''}' : 'Online (demo)'}',
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  Text('Estimated delivery to ${o.city}: ${w[0]}–${w[1]} business days (estimate, not a guarantee).',
                      style: const TextStyle(color: CC.muted, fontSize: 13)),
                ]),
              ),
            ),
            if (o.fulfillmentStatus == 'pending_confirmation') ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: CC.amber.withValues(alpha: .1), borderRadius: BorderRadius.circular(12), border: Border.all(color: CC.amber.withValues(alpha: .4))),
                child: const Row(children: [
                  Icon(Icons.hourglass_top, color: CC.amber, size: 18),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text("We'll confirm this cash-on-delivery order with you before it ships, to avoid a failed delivery.",
                        style: TextStyle(color: CC.amber, fontSize: 12.5, fontWeight: FontWeight.w600)),
                  ),
                ]),
              ),
            ],
            const SizedBox(height: 16),
            FilledButton(onPressed: () => ref.read(shopperNavProvider.notifier).root(const StorePage()), child: const Text('Continue shopping')),
          ]),
        );
      });
}
