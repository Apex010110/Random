// Green Logistics: merchant order fulfillment screens + the simulation-only metrics dashboard.
// See cartcloser-ai/docs (and the MRD) for the guardrails this UI follows: every number here is
// either an observed count from this demo session, or an illustrative estimate that only appears
// once the merchant explicitly sets the assumption behind it.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/models.dart';
import '../../core/providers.dart';
import '../../shared/widgets.dart';
import 'merchant_screens.dart' show Kpi;

Color fulfillmentColor(String s) => switch (s) {
      'ready_to_dispatch' || 'dispatched' => CC.cyan,
      'delivered' => CC.green,
      'pending_confirmation' || 'hold' => CC.amber,
      'failed_attempt' || 'returned' || 'cancelled' => CC.coral,
      _ => CC.muted,
    };

IconData fulfillmentIcon(String s) => switch (s) {
      'pending_confirmation' => Icons.hourglass_top,
      'hold' => Icons.pause_circle_outline,
      'ready_to_dispatch' => Icons.inventory_2_outlined,
      'dispatched' => Icons.local_shipping_outlined,
      'delivered' => Icons.check_circle_outline,
      'failed_attempt' => Icons.error_outline,
      'returned' => Icons.undo,
      'cancelled' => Icons.cancel_outlined,
      _ => Icons.circle,
    };

class FulfillmentChip extends StatelessWidget {
  final String status;
  const FulfillmentChip(this.status, {super.key});
  @override
  Widget build(BuildContext context) =>
      Pill(fulfillmentLabels[status] ?? status, color: fulfillmentColor(status), icon: fulfillmentIcon(status));
}

// ---------------------------------------------------------------- orders
class GreenOrdersScreen extends ConsumerStatefulWidget {
  const GreenOrdersScreen({super.key});
  @override
  ConsumerState<GreenOrdersScreen> createState() => _GreenOrdersScreenState();
}

class _GreenOrdersScreenState extends ConsumerState<GreenOrdersScreen> {
  String? _filter = 'pending_confirmation';
  @override
  Widget build(BuildContext context) {
    final selected = ref.watch(merchantNavProvider.select((s) => s.orderId));
    return SnapshotGate(builder: (s) {
      final all = s.orders.values.toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      final counts = {for (final t in fulfillmentTabs) t: all.where((o) => o.fulfillmentStatus == t).length};
      final orders = _filter == null ? all : all.where((o) => o.fulfillmentStatus == _filter).toList();
      final list = ListView(padding: const EdgeInsets.all(18), children: [
        const Row(children: [Text('Orders', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)), SizedBox(width: 10), DemoBadge()]),
        const SizedBox(height: 4),
        const Text('Dispatch decisions and the delivery state machine for every order.', style: TextStyle(color: CC.dim, fontSize: 12)),
        const SizedBox(height: 12),
        Wrap(spacing: 6, runSpacing: 6, children: [
          ChoiceChip(label: const Text('All'), selected: _filter == null, onSelected: (_) => setState(() => _filter = null)),
          for (final t in fulfillmentTabs)
            ChoiceChip(
              avatar: Icon(fulfillmentIcon(t), size: 16, color: _filter == t ? CC.ink : fulfillmentColor(t)),
              label: Text('${fulfillmentLabels[t]} (${counts[t]})'),
              selected: _filter == t,
              onSelected: (_) => setState(() => _filter = t),
            ),
        ]),
        const SizedBox(height: 14),
        if (orders.isEmpty)
          const Padding(padding: EdgeInsets.all(24), child: Text('No orders in this tab yet. Place a COD order from the shopper app to see it here.', style: TextStyle(color: CC.muted))),
        for (final o in orders) _OrderRow(o, s, selected: o.id == selected),
      ]);
      return LayoutBuilder(builder: (_, box) {
        final order = selected == null ? null : s.orders[selected];
        if (order == null) return list;
        if (box.maxWidth >= 1000) {
          return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: list),
            const VerticalDivider(width: 1),
            SizedBox(width: 460, child: OrderDetail(order, s)),
          ]);
        }
        return OrderDetail(order, s);
      });
    });
  }
}

class _OrderRow extends ConsumerWidget {
  final Order o;
  final Snapshot s;
  final bool selected;
  const _OrderRow(this.o, this.s, {required this.selected});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cart = s.cart(o.cartId);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: selected ? CC.cyan.withValues(alpha: .6) : CC.line)),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => ref.read(merchantNavProvider.notifier).openOrder(o.id),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${cart?.shopper?.firstName ?? 'Shopper'} · ${o.id}', style: const TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text('${o.lines.length} item(s) · ${pkr(o.total)} · ${o.paymentMethod == 'cod' ? 'COD' : 'Online'} · ${o.deliveryZone ?? o.city}',
                      style: const TextStyle(color: CC.muted, fontSize: 12)),
                  const SizedBox(height: 6),
                  Wrap(spacing: 6, runSpacing: 4, children: [
                    FulfillmentChip(o.fulfillmentStatus),
                    if (o.sizeQuestionResolved) const Pill('Size clarified', color: CC.cyan, icon: Icons.straighten),
                    if (o.wasHeld) const Pill('Was held', color: CC.amber),
                  ]),
                ]),
              ),
              const Icon(Icons.chevron_right, color: CC.dim),
            ]),
          ),
        ),
      ),
    );
  }
}

class OrderDetail extends ConsumerWidget {
  final Order order;
  final Snapshot s;
  const OrderDetail(this.order, this.s, {super.key});

  Future<void> _reasonDialog(BuildContext context, WidgetRef ref, {required String title, required Future<void> Function(String reason) onSubmit}) async {
    final c = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: CC.navy,
        title: Text(title),
        content: TextField(controller: c, decoration: const InputDecoration(labelText: 'Reason (optional)'), autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Confirm')),
        ],
      ),
    );
    if (ok == true && context.mounted) await guarded(context, () => onSubmit(c.text.trim()));
  }

  Future<void> _addressDialog(BuildContext context, WidgetRef ref) async {
    final addr = TextEditingController(text: order.addressRedacted ?? '');
    final zone = TextEditingController(text: order.deliveryZone ?? order.city);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: CC.navy,
        title: const Text('Correct address'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: addr, decoration: const InputDecoration(labelText: 'Address (redacted / area only)'), autofocus: true),
          const SizedBox(height: 10),
          TextField(controller: zone, decoration: const InputDecoration(labelText: 'Delivery zone / city')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
        ],
      ),
    );
    if (ok == true && context.mounted) {
      await guarded(context, () => ref.read(repositoryProvider).correctAddress(order.id, addr.text.trim(), zone.text.trim()));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.read(repositoryProvider);
    final cart = s.cart(order.cartId);
    final st = order.fulfillmentStatus;
    Widget actions() {
      switch (st) {
        case 'pending_confirmation':
          return Column(children: [
            Row(children: [
              Expanded(
                child: FilledButton.icon(
                  key: const ValueKey('confirm-cod'),
                  style: FilledButton.styleFrom(backgroundColor: CC.green),
                  icon: const Icon(Icons.check),
                  label: const Text('Shopper confirmed'),
                  onPressed: () => guarded(context, () => repo.confirmCod(order.id, true), success: 'Confirmed · ready to dispatch'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  key: const ValueKey('reject-cod'),
                  icon: const Icon(Icons.close, color: CC.coral),
                  label: const Text('No response / rejected'),
                  onPressed: () => guarded(context, () => repo.confirmCod(order.id, false)),
                ),
              ),
            ]),
            const SizedBox(height: 8),
            Text('Simulated pre-dispatch confirmation request sent ${cart?.optedIn == true ? 'over WhatsApp (sim)' : 'on-site (no opt-in)'}.',
                style: const TextStyle(color: CC.dim, fontSize: 11.5)),
          ]);
        case 'hold':
          return Row(children: [
            Expanded(
              child: OutlinedButton.icon(icon: const Icon(Icons.edit_location_alt_outlined), label: const Text('Correct address'), onPressed: () => _addressDialog(context, ref)),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton.icon(
                key: const ValueKey('release-order'),
                icon: const Icon(Icons.play_arrow),
                label: const Text('Release'),
                onPressed: () => guarded(context, () => repo.releaseOrder(order.id), success: 'Released · ready to dispatch'),
              ),
            ),
          ]);
        case 'ready_to_dispatch':
          return Row(children: [
            Expanded(
              child: FilledButton.icon(
                key: const ValueKey('dispatch-order'),
                icon: const Icon(Icons.local_shipping_outlined),
                label: const Text('Dispatch'),
                onPressed: () => guarded(context, () => repo.dispatchOrder(order.id), success: 'Dispatched'),
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton(
              onPressed: () => _reasonDialog(context, ref, title: 'Hold this order', onSubmit: (r) => repo.holdOrder(order.id, reason: r)),
              child: const Text('Hold'),
            ),
          ]);
        case 'dispatched':
          return Row(children: [
            Expanded(
              child: FilledButton.icon(
                key: const ValueKey('mark-delivered'),
                style: FilledButton.styleFrom(backgroundColor: CC.green),
                icon: const Icon(Icons.check_circle_outline),
                label: const Text('Delivered'),
                onPressed: () => guarded(context, () => repo.markDelivered(order.id)),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                key: const ValueKey('mark-failed'),
                icon: const Icon(Icons.error_outline, color: CC.coral),
                label: const Text('Failed attempt'),
                onPressed: () => _reasonDialog(context, ref, title: 'Failed delivery attempt', onSubmit: (r) => repo.markFailedAttempt(order.id, reason: r)),
              ),
            ),
          ]);
        case 'failed_attempt':
          return Row(children: [
            Expanded(
              child: FilledButton.icon(icon: const Icon(Icons.replay), label: const Text('Retry dispatch'), onPressed: () => guarded(context, () => repo.retryDispatchOrder(order.id))),
            ),
            const SizedBox(width: 8),
            OutlinedButton(
              onPressed: () => _reasonDialog(context, ref, title: 'Mark returned', onSubmit: (r) => repo.markReturned(order.id, reason: r)),
              child: const Text('Returned'),
            ),
          ]);
        case 'delivered':
          return OutlinedButton(
            onPressed: () => _reasonDialog(context, ref, title: 'Mark returned', onSubmit: (r) => repo.markReturned(order.id, reason: r)),
            child: const Text('Mark returned'),
          );
        default:
          return Text('${fulfillmentLabels[st] ?? st} · no further action.', style: const TextStyle(color: CC.dim));
      }
    }

    return ListView(padding: const EdgeInsets.all(18), children: [
      Row(children: [
        Expanded(child: Text('Order ${order.id}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800))),
        IconButton(tooltip: 'Close', icon: const Icon(Icons.close), onPressed: () => ref.read(merchantNavProvider.notifier).closeOrder()),
      ]),
      const SizedBox(height: 6),
      FulfillmentChip(order.fulfillmentStatus),
      const SizedBox(height: 16),
      actions(),
      if (!const {'cancelled'}.contains(st) && st != 'returned')
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: TextButton.icon(
            icon: const Icon(Icons.cancel_outlined, size: 18, color: CC.coral),
            label: const Text('Cancel order', style: TextStyle(color: CC.coral)),
            onPressed: () => _reasonDialog(context, ref, title: 'Cancel order', onSubmit: (r) => repo.cancelOrder(order.id, reason: r)),
          ),
        ),
      const SizedBox(height: 18),
      const SectionTitle('ITEMS'),
      for (final l in order.lines) Text('• ${l['name']} (${l['size']}) × ${l['quantity']}'),
      Text('Total ${pkr(order.total)} · ${order.paymentMethod == 'cod' ? 'Cash on delivery' : 'Online (demo)'}', style: const TextStyle(fontWeight: FontWeight.w700)),
      const SizedBox(height: 18),
      const SectionTitle('DELIVERY'),
      Text('Zone: ${order.deliveryZone ?? order.city}'),
      if (order.addressRedacted != null) Text('Address: ${order.addressRedacted}'),
      Text('Size question resolved before shipping: ${order.sizeQuestionResolved ? 'Yes' : 'No'}'),
      const SizedBox(height: 18),
      const SectionTitle('EVENT LOG'),
      _EventLog(order.id),
    ]);
  }
}

class _EventLog extends ConsumerWidget {
  final String orderId;
  const _EventLog(this.orderId);
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(repositoryProvider);
    ref.watch(snapshotProvider); // rebuild the (async) event list on every change
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: repo.merchantEvents(orderId: orderId),
      builder: (_, snap) {
        final events = snap.data ?? const [];
        if (events.isEmpty) return const Text('No events yet.', style: TextStyle(color: CC.muted));
        return Column(
          children: [
            for (final e in events)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(children: [
                  Expanded(child: Text('${e['type']}'.replaceAll('_', ' '))),
                  Pill(e['source'] ?? 'simulated', color: CC.dim),
                  const SizedBox(width: 6),
                  Text(hhmm(DateTime.parse(e['at'] as String)), style: const TextStyle(color: CC.dim, fontSize: 11)),
                ]),
              ),
          ],
        );
      },
    );
  }
}

// ---------------------------------------------------------------- dashboard
class GreenDashboardScreen extends ConsumerWidget {
  const GreenDashboardScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SnapshotGate(builder: (s) {
      final g = s.green;
      return ListView(padding: const EdgeInsets.all(18), children: [
        const Row(children: [Text('Green Logistics', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)), SizedBox(width: 10), DemoBadge()]),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: CC.amber.withValues(alpha: .1), borderRadius: BorderRadius.circular(12), border: Border.all(color: CC.amber.withValues(alpha: .4))),
          child: Row(children: [
            const Icon(Icons.info_outline, color: CC.amber, size: 18),
            const SizedBox(width: 8),
            Expanded(child: Text(g.banner, style: const TextStyle(color: CC.amber, fontSize: 12.5, fontWeight: FontWeight.w600))),
          ]),
        ),
        const SizedBox(height: 18),
        const SectionTitle('OBSERVED (from events in this session)'),
        LayoutBuilder(builder: (_, c) {
          final cols = (c.maxWidth / 190).floor().clamp(1, 6);
          final w = (c.maxWidth - (cols - 1) * 12) / cols;
          final tiles = [
            _GreenRate('COD confirmation rate', g.rates['cod_confirmation_rate'], g.definitions['cod_confirmation_rate']),
            _GreenRate('Failed delivery rate', g.rates['failed_delivery_rate'], g.definitions['failed_delivery_rate']),
            _GreenRate('Return rate', g.rates['return_rate'], g.definitions['return_rate']),
            Kpi('Held or cancelled', g.c('held_or_cancelled'), icon: Icons.pause_circle_outline, color: CC.amber),
            Kpi('Size questions resolved', g.c('size_questions_resolved'), icon: Icons.straighten, color: CC.cyan),
          ];
          return Wrap(spacing: 12, runSpacing: 12, children: [for (final t in tiles) SizedBox(width: w, child: t)]);
        }),
        const SizedBox(height: 20),
        const SectionTitle('BASELINE COMPARISON (illustrative — assumption-driven)'),
        const _AssumptionsForm(),
        const SizedBox(height: 12),
        _EstimatesCard(g),
      ]);
    });
  }
}

class _GreenRate extends StatelessWidget {
  final String label;
  final Rate? rate;
  final String? definition;
  const _GreenRate(this.label, this.rate, this.definition);
  @override
  Widget build(BuildContext context) {
    final def = definition;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(color: CC.muted, fontSize: 12.5)),
          const SizedBox(height: 6),
          Text(rate?.pct ?? '—', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
          Text('${rate?.numerator ?? 0} / ${rate?.denominator ?? 0}', style: const TextStyle(color: CC.cyan, fontSize: 12, fontWeight: FontWeight.w600)),
          if (def != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text(def, style: const TextStyle(color: CC.dim, fontSize: 10.5))),
        ]),
      ),
    );
  }
}

class _AssumptionsForm extends ConsumerStatefulWidget {
  const _AssumptionsForm();
  @override
  ConsumerState<_AssumptionsForm> createState() => _AssumptionsFormState();
}

class _AssumptionsFormState extends ConsumerState<_AssumptionsForm> {
  final _fail = TextEditingController();
  final _km = TextEditingController();
  final _co2 = TextEditingController();
  bool _loaded = false;

  @override
  Widget build(BuildContext context) {
    final g = ref.watch(snapshotProvider).value?.green;
    if (g != null && !_loaded) {
      _fail.text = _fmt(g.assumptions['assumed_failure_probability_without_intervention']);
      _km.text = _fmt(g.assumptions['assumed_km_per_avoided_attempt']);
      _co2.text = _fmt(g.assumptions['assumed_kgco2e_per_km']);
      _loaded = true;
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Editable counterfactual assumptions', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          const SizedBox(height: 4),
          const Text('Leave blank to show no estimate. These are merchant-set assumptions, not measured results.',
              style: TextStyle(color: CC.dim, fontSize: 11.5)),
          const SizedBox(height: 12),
          Wrap(spacing: 10, runSpacing: 10, children: [
            _num('Failure probability without intervention (0–1)', _fail, 220),
            _num('Km per avoided delivery attempt', _km, 220),
            _num('kg CO2e per km', _co2, 180),
          ]),
          const SizedBox(height: 10),
          FilledButton(
            key: const ValueKey('save-assumptions'),
            onPressed: () => guarded(
              context,
              () => ref.read(repositoryProvider).patchAssumptions({
                'assumed_failure_probability_without_intervention': _parse(_fail.text),
                'assumed_km_per_avoided_attempt': _parse(_km.text),
                'assumed_kgco2e_per_km': _parse(_co2.text),
              }),
              success: 'Assumptions updated',
            ),
            child: const Text('Apply assumptions'),
          ),
        ]),
      ),
    );
  }

  Widget _num(String label, TextEditingController c, double width) =>
      SizedBox(width: width, child: TextField(controller: c, decoration: InputDecoration(labelText: label, isDense: true), keyboardType: TextInputType.number));

  static String _fmt(dynamic v) => v == null ? '' : '$v';
  static double? _parse(String s) => s.trim().isEmpty ? null : double.tryParse(s.trim());
}

class _EstimatesCard extends StatelessWidget {
  final GreenMetrics g;
  const _EstimatesCard(this.g);
  @override
  Widget build(BuildContext context) {
    final avoided = g.estimates['estimated_avoided_attempts'] as num?;
    final co2 = g.estimates['illustrative_co2e_kg'] as num?;
    final sens = g.estimates['estimated_avoided_attempts_sensitivity'] as Map?;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Illustrative estimates', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          const SizedBox(height: 10),
          _row('Estimated avoided delivery attempts', avoided == null ? 'No estimate (set an assumption above)' : avoided.toStringAsFixed(1)),
          if (sens != null && avoided != null)
            Padding(
              padding: const EdgeInsets.only(top: 2, bottom: 6),
              child: Text('Sensitivity range: ${(sens['low'] as num).toStringAsFixed(1)} – ${(sens['high'] as num).toStringAsFixed(1)}',
                  style: const TextStyle(color: CC.dim, fontSize: 11.5)),
            ),
          _row('Illustrative CO2e (kg)', co2 == null ? 'No estimate (set km + kg CO2e/km above)' : co2.toStringAsFixed(1)),
          const SizedBox(height: 8),
          Text(g.definitions['estimated_avoided_attempts'] ?? '', style: const TextStyle(color: CC.dim, fontSize: 11)),
        ]),
      ),
    );
  }

  Widget _row(String a, String b) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [
          Expanded(child: Text(a)),
          Text(b, style: const TextStyle(fontWeight: FontWeight.w700)),
        ]),
      );
}
