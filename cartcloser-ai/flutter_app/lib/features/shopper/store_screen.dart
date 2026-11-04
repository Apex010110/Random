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

class StoreScreen extends ConsumerStatefulWidget {
  const StoreScreen({super.key});
  @override
  ConsumerState<StoreScreen> createState() => _StoreScreenState();
}

class _StoreScreenState extends ConsumerState<StoreScreen> {
  String _q = '';
  String? _cat;

  @override
  Widget build(BuildContext context) {
    final persona = ref.watch(currentPersonaProvider);
    return SnapshotGate(builder: (s) {
      final cats = {for (final p in s.products) p.category}.toList()..sort();
      final items = s.products
          .where((p) => p.active && (_cat == null || p.category == _cat) && (_q.isEmpty || p.name.toLowerCase().contains(_q.toLowerCase())))
          .toList();
      return CustomScrollView(slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
            child: Row(children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(color: CC.navy2, borderRadius: BorderRadius.circular(12), border: Border.all(color: CC.line)),
                child: const Icon(Icons.storefront, color: CC.cyan),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(s.store.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                  Text('Hi ${persona.firstName} · delivering to ${persona.city}', style: const TextStyle(color: CC.muted, fontSize: 12.5)),
                ]),
              ),
              const DemoBadge(text: 'DEMO'),
            ]),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
            child: TextField(
              decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search kurtas, suits, bags…', isDense: true),
              onChanged: (v) => setState(() => _q = v),
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: SizedBox(
            height: 46,
            child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12), children: [
              for (final c in [null, ...cats])
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                  child: ChoiceChip(
                    label: Text(c ?? 'All'),
                    selected: _cat == c,
                    selectedColor: CC.cyan.withValues(alpha: .2),
                    onSelected: (_) => setState(() => _cat = c),
                  ),
                ),
            ]),
          ),
        ),
        if (items.isEmpty)
          const SliverFillRemaining(hasScrollBody: false, child: Center(child: Text('No products match your search.', style: TextStyle(color: CC.muted)))),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 24),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 220, mainAxisSpacing: 14, crossAxisSpacing: 14, childAspectRatio: .68),
            delegate: SliverChildBuilderDelegate((_, i) => _ProductCard(items[i]), childCount: items.length),
          ),
        ),
      ]);
    });
  }
}

class _ProductCard extends ConsumerWidget {
  final Product p;
  const _ProductCard(this.p);
  @override
  Widget build(BuildContext context, WidgetRef ref) => Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => ref.read(shopperNavProvider.notifier).push(ProductPage(p.id)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: ProductArt(p, radius: 0)),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(p.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, height: 1.25)),
                const SizedBox(height: 6),
                Row(children: [
                  Expanded(child: Text(pkr(p.pricePkr), style: const TextStyle(color: CC.cyan, fontWeight: FontWeight.w700))),
                  if (p.codEligible) const Pill('COD', color: CC.green),
                ]),
              ]),
            ),
          ]),
        ),
      );
}

class ProductScreen extends ConsumerStatefulWidget {
  final String productId;
  const ProductScreen({super.key, required this.productId});
  @override
  ConsumerState<ProductScreen> createState() => _ProductScreenState();
}

class _ProductScreenState extends ConsumerState<ProductScreen> {
  String? _size;
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final persona = ref.watch(currentPersonaProvider);
    return SnapshotGate(builder: (s) {
      final p = s.product(widget.productId);
      if (p == null) return const Center(child: Text('Product not found'));
      _size ??= p.inStockSizes.contains('M') ? 'M' : p.inStockSizes.firstOrNull;
      final today = DateTime.now().toUtc().add(const Duration(hours: 5));
      final w = s.store.deliveryWindow(persona.city);
      final start = AssistantRules.addBusinessDays(today, w[0]), end = AssistantRules.addBusinessDays(today, w[1]);
      final codCity = s.store.codCities.contains(persona.city);
      return Scaffold(
        appBar: ShopperHeader(p.category),
        body: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 120), children: [
          AspectRatio(aspectRatio: 1.25, child: ProductArt(p, iconSize: 96)),
          const SizedBox(height: 6),
          const Text('Image placeholder · demo catalog', style: TextStyle(color: CC.dim, fontSize: 11)),
          const SizedBox(height: 10),
          Text(p.name, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(pkr(p.pricePkr), style: const TextStyle(fontSize: 20, color: CC.cyan, fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          Text(p.description, style: const TextStyle(color: CC.muted, height: 1.4)),
          const SizedBox(height: 18),
          const SectionTitle('SIZE'),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final v in p.variants)
              ChoiceChip(
                label: Text(v.stock == 0 ? '${v.size} · sold out' : (v.stock <= 2 ? '${v.size} · only ${v.stock} left' : v.size)),
                selected: _size == v.size,
                selectedColor: CC.cyan.withValues(alpha: .22),
                onSelected: v.stock == 0 ? null : (_) => setState(() => _size = v.size),
              ),
          ]),
          const SizedBox(height: 8),
          Text(p.fitNotes, style: const TextStyle(color: CC.muted, fontSize: 13, height: 1.4)),
          const SizedBox(height: 18),
          _InfoRow(Icons.local_shipping_outlined, 'Estimated delivery to ${persona.city}',
              '${_d(start)} – ${_d(end)} (${w[0]}–${w[1]} business days). Estimate, not a guarantee.'),
          _InfoRow(Icons.payments_outlined, 'Cash on delivery',
              !p.codEligible ? 'Not available for this item (prepaid only).' : (codCity ? 'Available in ${persona.city} up to ${pkr(s.store.policy['cod_max_order_pkr'])}.' : 'Not offered in ${persona.city}.'),
              ok: p.codEligible && codCity),
          _InfoRow(Icons.swap_horiz, 'Exchanges & returns', '${s.store.policy['exchange_policy']} ${s.store.policy['returns_policy']}'),
        ]),
        bottomSheet: Container(
          color: CC.ink,
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
          child: SafeArea(
            top: false,
            child: FilledButton.icon(
              key: const ValueKey('add-to-cart'),
              icon: _busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.add_shopping_cart),
              label: Text(p.inStock ? 'Add to cart${_size == null ? '' : ' · $_size'}' : 'Out of stock'),
              onPressed: !p.inStock || _size == null || _busy
                  ? null
                  : () async {
                      setState(() => _busy = true);
                      final c = await guarded(context, () => ShopperActions(ref).addToCart(p.id, _size!));
                      if (mounted) setState(() => _busy = false);
                      if (c != null && context.mounted) {
                        HapticFeedback.lightImpact();
                        toast(context, 'Added ${p.name} ($_size) to cart');
                      }
                    },
            ),
          ),
        ),
      );
    });
  }

  String _d(DateTime d) => '${const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][d.weekday - 1]} ${d.day} '
      '${const ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'][d.month - 1]}';
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String title, body;
  final bool? ok;
  const _InfoRow(this.icon, this.title, this.body, {this.ok});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(color: CC.navy2, borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, size: 19, color: ok == false ? CC.coral : CC.cyan),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text(body, style: const TextStyle(color: CC.muted, fontSize: 13, height: 1.35)),
            ]),
          ),
        ]),
      );
}
