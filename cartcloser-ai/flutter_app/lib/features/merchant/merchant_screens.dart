import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/models.dart';
import '../../core/providers.dart';
import '../../shared/widgets.dart';

// ---------------------------------------------------------------- shared bits
class _DateFilter extends ConsumerWidget {
  const _DateFilter();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final days = ref.watch(merchantNavProvider.select((s) => s.days));
    return SegmentedButton<int>(
      showSelectedIcon: false,
      style: SegmentedButton.styleFrom(selectedBackgroundColor: CC.cyan.withValues(alpha: .2), visualDensity: VisualDensity.compact),
      segments: const [ButtonSegment(value: 1, label: Text('Today')), ButtonSegment(value: 7, label: Text('7 days')), ButtonSegment(value: 0, label: Text('All'))],
      selected: {days ?? 0},
      onSelectionChanged: (s) => ref.read(merchantNavProvider.notifier).days(s.first == 0 ? null : s.first),
    );
  }
}

class Kpi extends StatelessWidget {
  final String label;
  final num value;
  final String Function(num) fmt;
  final IconData icon;
  final Color color;
  final String? sub;
  const Kpi(this.label, this.value, {super.key, required this.icon, this.color = CC.cyan, this.fmt = _int, this.sub});
  static String _int(num v) => v.round().toString();
  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 6),
              Expanded(child: Text(label, style: const TextStyle(color: CC.muted, fontSize: 12.5), maxLines: 2)),
            ]),
            const SizedBox(height: 8),
            CountUp(value, format: fmt, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
            if (sub != null) Text(sub!, style: const TextStyle(color: CC.dim, fontSize: 11), maxLines: 2, overflow: TextOverflow.ellipsis),
          ]),
        ),
      );
}

Widget _grid(BuildContext context, List<Widget> children, {double minTile = 170}) => LayoutBuilder(builder: (_, c) {
      final cols = (c.maxWidth / minTile).floor().clamp(1, 6);
      final w = (c.maxWidth - (cols - 1) * 12) / cols;
      return Wrap(spacing: 12, runSpacing: 12, children: [for (final ch in children) SizedBox(width: w, child: ch)]);
    });

// ---------------------------------------------------------------- overview
class OverviewScreen extends ConsumerWidget {
  const OverviewScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final m = ref.watch(filteredMetricsProvider).value ?? ref.watch(snapshotProvider).value?.metrics;
    return SnapshotGate(builder: (s) {
      final mm = m ?? s.metrics;
      final eligibleNow = s.carts.where((c) => const {'eligible', 'scheduled'}.contains(c.status)).toList();
      return ListView(padding: const EdgeInsets.all(18), children: [
        Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 12, runSpacing: 10, children: [
          Text(s.store.name, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
          const DemoBadge(),
          const _DateFilter(),
        ]),
        const SizedBox(height: 6),
        const Text('Every number below is calculated from events in this demo session. Nothing is hardcoded.', style: TextStyle(color: CC.dim, fontSize: 12)),
        const SizedBox(height: 16),
        _grid(context, [
          Kpi('Eligible abandoned', mm.c('eligible_abandoned'), icon: Icons.remove_shopping_cart_outlined, color: CC.coral, sub: 'opted-in, safe to contact'),
          Kpi('Contacted', mm.c('contacted'), icon: Icons.send_outlined, sub: 'simulated WhatsApp'),
          Kpi('Replied', mm.c('replied'), icon: Icons.reply_outlined),
          Kpi('Recovered orders', mm.c('recovered'), icon: Icons.verified_outlined, color: CC.green, sub: 'order placed after contact'),
          Kpi('Attributed sales', (mm.money['attributed_recovered_sales_pkr'] as num?) ?? 0,
              icon: Icons.payments_outlined, color: CC.green, fmt: (v) => pkr(v.round()), sub: 'gross, not profit'),
          Kpi('Opt-outs', mm.c('opt_outs'), icon: Icons.block, color: CC.amber, sub: 'STOP or preferences'),
        ]),
        const SizedBox(height: 20),
        if (eligibleNow.isNotEmpty) ...[
          const SectionTitle('READY FOR RECOVERY'),
          for (final c in eligibleNow) _CartRow(c, highlight: true),
          const SizedBox(height: 12),
        ],
        LayoutBuilder(builder: (_, c) {
          final funnel = _FunnelCard(mm);
          final feed = _ActivityFeed(mm);
          if (c.maxWidth < 760) return Column(children: [funnel, const SizedBox(height: 12), feed]);
          return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(flex: 3, child: funnel), const SizedBox(width: 12), Expanded(flex: 2, child: feed)]);
        }),
      ]);
    });
  }
}

class _FunnelCard extends ConsumerWidget {
  final Metrics m;
  const _FunnelCard(this.m);
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = [CC.muted, CC.coral, CC.amber, CC.cyan, CC.cyan, CC.green];
    final maxY = m.funnel.fold<int>(1, (a, f) => (f['count'] as int) > a ? f['count'] as int : a).toDouble();
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Recovery funnel', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
          const SizedBox(height: 4),
          const Text('Cart created → abandoned → opted in → contacted → replied → recovered', style: TextStyle(color: CC.dim, fontSize: 11.5)),
          const SizedBox(height: 14),
          SizedBox(
            height: 210,
            child: BarChart(
              BarChartData(
                maxY: maxY * 1.25,
                alignment: BarChartAlignment.spaceAround,
                barTouchData: BarTouchData(enabled: true),
                gridData: FlGridData(show: true, drawVerticalLine: false, horizontalInterval: (maxY / 4).clamp(1, double.infinity), getDrawingHorizontalLine: (_) => const FlLine(color: CC.line, strokeWidth: 1)),
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(
                  leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  topTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 22,
                      getTitlesWidget: (v, _) => Text('${m.funnel[v.toInt()]['count']}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 34,
                      getTitlesWidget: (v, _) => Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(const ['Created', 'Abandoned', 'Opted in', 'Contacted', 'Replied', 'Recovered'][v.toInt()],
                            style: const TextStyle(color: CC.muted, fontSize: 10.5)),
                      ),
                    ),
                  ),
                ),
                barGroups: [
                  for (var i = 0; i < m.funnel.length; i++)
                    BarChartGroupData(x: i, barRods: [
                      BarChartRodData(toY: (m.funnel[i]['count'] as int).toDouble(), width: 22, color: colors[i], borderRadius: BorderRadius.circular(6)),
                    ]),
                ],
              ),
              duration: motion(context, ref, 400),
            ),
          ),
        ]),
      ),
    );
  }
}

const eventLabels = {
  'cart_created': 'Cart created',
  'cart_updated': 'Cart updated',
  'checkout_started': 'Checkout started',
  'consent_granted': 'Opt-in recorded',
  'consent_revoked': 'Opt-out (consent revoked)',
  'cart_abandoned': 'Checkout abandoned',
  'recovery_blocked': 'Outbound blocked',
  'recovery_scheduled': 'Recovery scheduled',
  'recovery_sent': 'Recovery message sent (simulated)',
  'recovery_cancelled': 'Scheduled send cancelled',
  'recovery_deferred_quiet_hours': 'Deferred: quiet hours',
  'ai_reply': 'AI replied',
  'human_handoff': 'Escalated to human',
  'human_reply': 'Team member replied',
  'discount_issued': 'Discount issued (within ceiling)',
  'order_placed': 'Order placed',
  'demo_seeded': 'Demo data loaded',
  'settings_updated': 'Campaign settings changed',
  'catalog_updated': 'Catalog / policy updated',
  'takeover_on': 'Human took over chat',
  'takeover_off': 'AI resumed chat',
  'cart_paused': 'Recovery paused for cart',
  'cart_resumed': 'Recovery resumed for cart',
  'holdout_assigned': 'Assigned to holdout',
  'shopper_message': 'Shopper message',
  'shopper_data_deleted': 'Shopper data deleted',
  'cart_expired': 'Cart expired',
};

class _ActivityFeed extends StatelessWidget {
  final Metrics m;
  const _ActivityFeed(this.m);
  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Row(children: [
              Text('Live activity', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
              SizedBox(width: 8),
              _LiveDot(),
            ]),
            const SizedBox(height: 8),
            for (final e in m.recentEvents.take(9))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(_icon(e['type'] as String), size: 16, color: _color(e['type'] as String)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${eventLabels[e['type']] ?? e['type']}${e['detail']?['reason'] != null ? ' · ${reasonLabels[e['detail']['reason']] ?? e['detail']['reason']}' : ''}',
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                  Text(hhmm(DateTime.parse(e['at'] as String)), style: const TextStyle(color: CC.dim, fontSize: 11)),
                ]),
              ),
          ]),
        ),
      );
  IconData _icon(String t) => t.contains('order') ? Icons.check_circle : (t.contains('blocked') || t.contains('revoked') ? Icons.block : Icons.circle);
  Color _color(String t) => t.contains('order') ? CC.green : (t.contains('blocked') || t.contains('revoked') || t.contains('cancel') ? CC.coral : CC.cyan);
}

class _LiveDot extends StatefulWidget {
  const _LiveDot();
  @override
  State<_LiveDot> createState() => _LiveDotState();
}

class _LiveDotState extends State<_LiveDot> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))..repeat(reverse: true);
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
        opacity: Tween(begin: .3, end: 1.0).animate(_c),
        child: Container(width: 8, height: 8, decoration: const BoxDecoration(color: CC.green, shape: BoxShape.circle)),
      );
}

// ---------------------------------------------------------------- analytics
class AnalyticsScreen extends ConsumerWidget {
  const AnalyticsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fm = ref.watch(filteredMetricsProvider).value;
    return SnapshotGate(builder: (s) {
      final m = fm ?? s.metrics;
      Widget rate(String k, String label) => _RateCard(label, m.rates[k]!, m.definitions[k] ?? '');
      final lift = m.lift;
      return ListView(padding: const EdgeInsets.all(18), children: [
        Wrap(spacing: 12, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: const [
          Text('Analytics', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
          DemoBadge(),
          _DateFilter(),
        ]),
        const SizedBox(height: 16),
        _grid(context, [
          rate('opt_in_rate', 'Opt-in rate'),
          rate('contact_rate', 'Contact rate'),
          rate('reply_rate', 'Reply rate'),
          rate('observed_recovery_rate', 'Observed recovery rate'),
        ], minTile: 220),
        const SizedBox(height: 16),
        _grid(context, [
          Kpi('Attributed recovered sales', (m.money['attributed_recovered_sales_pkr'] as num?) ?? 0,
              icon: Icons.payments_outlined, color: CC.green, fmt: (v) => pkr(v.round()), sub: m.money['note'] as String?),
          Kpi('Estimated messaging cost', (m.money['estimated_messaging_cost_pkr'] as num?) ?? 0,
              icon: Icons.receipt_outlined, color: CC.amber, fmt: (v) => pkr(v.round()), sub: m.money['cost_assumption'] as String?),
          Kpi('Messages sent', m.c('messages_sent'), icon: Icons.outbox_outlined),
          Kpi('AI replies', m.c('ai_replies'), icon: Icons.smart_toy_outlined),
          Kpi('Blocked / cancelled sends', m.c('blocked_or_cancelled'), icon: Icons.shield_outlined, color: CC.coral, sub: 'consent & safety checks working'),
        ], minTile: 220),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Why sends were blocked', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
              const SizedBox(height: 8),
              if (m.blockedReasons.isEmpty) const Text('Nothing blocked yet.', style: TextStyle(color: CC.muted)),
              for (final e in m.blockedReasons.entries)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(children: [
                    Expanded(child: Text(reasonLabels[e.key] ?? e.key)),
                    Text('${e.value}', style: const TextStyle(fontWeight: FontWeight.w700)),
                  ]),
                ),
            ]),
          ),
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Control group (holdout) comparison', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
              const SizedBox(height: 8),
              Text(lift['measured'] == true ? 'Incremental lift: ${((lift['value'] as num) * 100).toStringAsFixed(1)} pts' : 'Not measured',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: lift['measured'] == true ? CC.green : CC.muted)),
              const SizedBox(height: 4),
              Text('Holdout carts: ${lift['holdout_carts']} · contacted carts: ${lift['treated_carts']}. ${m.definitions['incremental_lift'] ?? ''}',
                  style: const TextStyle(color: CC.dim, fontSize: 12)),
            ]),
          ),
        ),
      ]);
    });
  }
}

class _RateCard extends StatelessWidget {
  final String label, definition;
  final Rate rate;
  const _RateCard(this.label, this.rate, this.definition);
  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: const TextStyle(color: CC.muted, fontSize: 12.5)),
            const SizedBox(height: 6),
            Text(rate.pct, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
            Text('${rate.numerator} / ${rate.denominator}', style: const TextStyle(color: CC.cyan, fontSize: 12, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(definition, style: const TextStyle(color: CC.dim, fontSize: 11)),
          ]),
        ),
      );
}

// ---------------------------------------------------------------- carts
class CartsScreen extends ConsumerStatefulWidget {
  const CartsScreen({super.key});
  @override
  ConsumerState<CartsScreen> createState() => _CartsScreenState();
}

class _CartsScreenState extends ConsumerState<CartsScreen> {
  String? _filter;
  @override
  Widget build(BuildContext context) {
    final selected = ref.watch(merchantNavProvider.select((s) => s.cartId));
    return SnapshotGate(builder: (s) {
      final carts = s.carts.where((c) => _filter == null || c.status == _filter).toList();
      final statuses = {for (final c in s.carts) c.status}.toList()..sort();
      final list = ListView(padding: const EdgeInsets.all(18), children: [
        const Text('Carts', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
        const SizedBox(height: 10),
        Wrap(spacing: 6, runSpacing: 6, children: [
          ChoiceChip(label: const Text('All'), selected: _filter == null, onSelected: (_) => setState(() => _filter = null)),
          for (final st in statuses) ChoiceChip(label: Text(statusLabels[st] ?? st), selected: _filter == st, onSelected: (_) => setState(() => _filter = st)),
        ]),
        const SizedBox(height: 12),
        if (carts.isEmpty)
          const Padding(padding: EdgeInsets.all(24), child: Text('No carts yet. Start the shopper demo to create one.', style: TextStyle(color: CC.muted))),
        for (final c in carts) _CartRow(c, selected: c.id == selected),
      ]);
      return LayoutBuilder(builder: (_, box) {
        final cart = selected == null ? null : s.cart(selected);
        if (cart == null) return list;
        if (box.maxWidth >= 1000) {
          return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: list),
            const VerticalDivider(width: 1),
            SizedBox(width: 440, child: CartDetail(cart)),
          ]);
        }
        return CartDetail(cart);
      });
    });
  }
}

class _CartRow extends ConsumerWidget {
  final Cart c;
  final bool highlight, selected;
  const _CartRow(this.c, {this.highlight = false, this.selected = false});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = DateTime.now().toUtc();
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Card(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16), side: BorderSide(color: selected || highlight ? CC.cyan.withValues(alpha: .6) : CC.line)),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => ref.read(merchantNavProvider.notifier).openCart(c.id),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(children: [
              CircleAvatar(backgroundColor: CC.navy2, child: Text(c.shopper?.firstName.substring(0, 1) ?? '?')),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${c.shopper?.firstName ?? c.shopperId} · ${c.shopper?.phoneMasked ?? ''}', style: const TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text('${c.id} · ${c.itemCount} item(s) · ${pkr(c.totals.total)} · ${ago(c.createdAt, now)}',
                      style: const TextStyle(color: CC.muted, fontSize: 12), overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 6),
                  Wrap(spacing: 6, runSpacing: 4, children: [
                    StatusChip(c.status, reason: c.statusReason),
                    Pill(c.optedIn ? 'Opted in' : 'No opt-in', color: c.optedIn ? CC.green : CC.dim, icon: c.optedIn ? Icons.verified_user_outlined : Icons.do_not_disturb_alt),
                    if (c.shopper?.ageBand == 'under_18') const Pill('Under 18', color: CC.amber),
                    if (c.messageCount > 0) Pill('${c.messageCount} msgs', color: CC.cyan, icon: Icons.chat_bubble_outline),
                    if (c.status == 'recovered') const Pill('Attributed: recovery contact', color: CC.green),
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

class CartDetail extends ConsumerWidget {
  final Cart cart;
  const CartDetail(this.cart, {super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.read(repositoryProvider);
    final canTrigger = const {'eligible', 'scheduled'}.contains(cart.status);
    return ListView(padding: const EdgeInsets.all(18), children: [
      Row(children: [
        Expanded(child: Text('Cart ${cart.id}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800))),
        IconButton(tooltip: 'Close', icon: const Icon(Icons.close), onPressed: () => ref.read(merchantNavProvider.notifier).closeCart()),
      ]),
      const SizedBox(height: 6),
      StatusChip(cart.status, reason: cart.statusReason),
      const SizedBox(height: 16),
      FilledButton.icon(
        key: const ValueKey('trigger-recovery'),
        style: FilledButton.styleFrom(backgroundColor: CC.green),
        icon: const Icon(Icons.bolt),
        label: const Text('Trigger recovery now (demo)'),
        onPressed: () async {
          final st = await guarded(context, () => repo.triggerRecovery(cart.id));
          if (st != null && context.mounted) {
            toast(context, st == 'sent' ? 'Simulated WhatsApp message sent' : 'Not sent: $st (checks run at send time)', error: st != 'sent');
          }
        },
      ),
      const SizedBox(height: 6),
      Text(
          canTrigger
              ? 'Skips the ${ref.watch(snapshotProvider).value?.settings['delay_minutes']}-minute wait only. Consent, age, quiet-hours and duplicate checks still run.'
              : cart.sentAttempt != null
                  ? 'Already contacted once. The contact cap blocks further outbound messages; the shopper can still reply.'
                  : 'Not eligible for outbound messages. Pressing the button shows the reason; nothing is sent.',
          style: const TextStyle(color: CC.dim, fontSize: 11.5)),
      const SizedBox(height: 10),
      OutlinedButton.icon(
        icon: Icon(cart.recoveryPaused ? Icons.play_arrow : Icons.pause),
        label: Text(cart.recoveryPaused ? 'Resume recovery for this cart' : 'Pause recovery for this cart'),
        onPressed: () => guarded(context, () => repo.setCartPaused(cart.id, !cart.recoveryPaused)),
      ),
      const SizedBox(height: 6),
      OutlinedButton.icon(
        icon: const Icon(Icons.forum_outlined),
        label: const Text('Open conversation'),
        onPressed: () => ref.read(merchantNavProvider.notifier).openCart(cart.id, tab: MerchantTab.inbox),
      ),
      const SizedBox(height: 18),
      const SectionTitle('ITEMS'),
      for (final l in cart.items) Text('• ${l.name} (${l.size}) × ${l.quantity} · ${pkr(l.unitPricePkr * l.quantity)}'),
      const SizedBox(height: 6),
      Text('Total ${pkr(cart.totals.total)}${cart.promoCode != null ? ' · code ${cart.promoCode}' : ''}', style: const TextStyle(fontWeight: FontWeight.w700)),
      const SizedBox(height: 18),
      const SectionTitle('CONSENT'),
      Text(cart.consent == null
          ? 'No active consent for checkout reminders. Outbound WhatsApp is blocked.'
          : 'Opted in · ${cart.consent!['version']} · source ${cart.consent!['source']} · ${dayTime(DateTime.parse(cart.consent!['at']))} · channel ${cart.consent!['channel']}'),
      const SizedBox(height: 18),
      const SectionTitle('RECOVERY ATTEMPTS'),
      if (cart.attempts.isEmpty) const Text('None', style: TextStyle(color: CC.muted)),
      for (final a in cart.attempts)
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(a.status == 'sent' ? Icons.check_circle : (a.status == 'scheduled' ? Icons.schedule : Icons.block),
              color: a.status == 'sent' ? CC.green : (a.status == 'scheduled' ? CC.cyan : CC.coral)),
          title: Text('${a.status}${a.reason != null ? ' · ${reasonLabels[a.reason] ?? a.reason}' : ''}'),
          subtitle: Text(a.sentAt != null ? 'Sent ${dayTime(a.sentAt!)}' : 'Scheduled for ${dayTime(a.scheduledFor)}'),
        ),
      const SizedBox(height: 10),
      const SectionTitle('ATTRIBUTION'),
      Text(cart.status == 'recovered'
          ? 'Recovered: order ${cart.orderId} placed within the attribution window after a recovery contact.'
          : cart.orderId != null
              ? 'Ordered without a recovery contact (not attributed).'
              : 'No order yet. Replies and link clicks are not counted as recovered.'),
    ]);
  }
}

// ---------------------------------------------------------------- inbox
class MerchantInboxScreen extends ConsumerStatefulWidget {
  const MerchantInboxScreen({super.key});
  @override
  ConsumerState<MerchantInboxScreen> createState() => _MerchantInboxScreenState();
}

class _MerchantInboxScreenState extends ConsumerState<MerchantInboxScreen> {
  final _reply = TextEditingController();
  @override
  void dispose() {
    _reply.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selected = ref.watch(merchantNavProvider.select((s) => s.cartId));
    return SnapshotGate(builder: (s) {
      final convs = s.conversations.values.where((c) => c.messages.isNotEmpty).toList()..sort((a, b) => b.last!.createdAt.compareTo(a.last!.createdAt));
      final current = selected == null ? null : s.conversations[selected];
      final list = ListView(padding: const EdgeInsets.all(18), children: [
        const Text('Conversation inbox', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
        const SizedBox(height: 12),
        if (convs.isEmpty) const Text('No conversations yet.', style: TextStyle(color: CC.muted)),
        for (final c in convs)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: c.cartId == selected ? CC.cyan : CC.line)),
              child: ListTile(
                onTap: () => ref.read(merchantNavProvider.notifier).openCart(c.cartId, tab: MerchantTab.inbox),
                title: Text('${s.cart(c.cartId)?.shopper?.firstName ?? 'Shopper'} · ${c.isWhatsAppSim ? 'WhatsApp sim' : 'On-site chat'}'),
                subtitle: Text(c.last!.text, maxLines: 1, overflow: TextOverflow.ellipsis),
                trailing: c.escalated
                    ? const Pill('Needs human', color: CC.amber, icon: Icons.flag)
                    : (c.humanTakeover ? const Pill('Human', color: CC.cyan) : null),
              ),
            ),
          ),
      ]);
      Widget detail(Conversation conv) => Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 6),
              child: Row(children: [
                Expanded(child: Text('Transcript · ${conv.cartId}', style: const TextStyle(fontWeight: FontWeight.w700))),
                if (conv.escalated) const Pill('Escalated', color: CC.amber, icon: Icons.flag),
                const SizedBox(width: 6),
                TextButton(
                  onPressed: () => guarded(context, () => ref.read(repositoryProvider).setTakeover(conv.cartId, !conv.humanTakeover)),
                  child: Text(conv.humanTakeover ? 'Hand back to AI' : 'Take over'),
                ),
                IconButton(tooltip: 'Close', icon: const Icon(Icons.close), onPressed: () => ref.read(merchantNavProvider.notifier).closeCart()),
              ]),
            ),
            const Divider(),
            Expanded(
              child: ListView(padding: const EdgeInsets.all(14), children: [
                for (final m in conv.messages)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Text(m.role == 'shopper' ? 'Shopper' : (m.role == 'human' ? 'Team' : (m.role == 'system' ? 'System' : 'AI')),
                            style: TextStyle(fontWeight: FontWeight.w700, color: m.role == 'shopper' ? CC.white : CC.cyan, fontSize: 12.5)),
                        const SizedBox(width: 8),
                        if (m.intent != null) Pill(m.intent!, color: CC.muted),
                        if (m.confidence != null) ...[
                          const SizedBox(width: 6),
                          Pill('conf ${(m.confidence! * 100).round()}%', color: m.confidence! < .5 ? CC.amber : CC.green),
                        ],
                        if (m.source != null && m.role == 'ai') ...[const SizedBox(width: 6), Pill(m.source!, color: CC.cyan)],
                        if (m.language != null && m.role == 'ai') ...[const SizedBox(width: 6), Pill(m.language!, color: CC.dim)],
                        const Spacer(),
                        Text(hhmm(m.createdAt), style: const TextStyle(color: CC.dim, fontSize: 11)),
                      ]),
                      const SizedBox(height: 4),
                      Directionality(
                        textDirection: RegExp(r'[؀-ۿ]').hasMatch(m.text) ? TextDirection.rtl : TextDirection.ltr,
                        child: Text(m.text, style: const TextStyle(height: 1.4)),
                      ),
                    ]),
                  ),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.all(10),
              child: Row(children: [
                Expanded(child: TextField(controller: _reply, decoration: const InputDecoration(hintText: 'Reply as a team member (takes over from AI)', isDense: true))),
                const SizedBox(width: 6),
                IconButton.filled(
                  icon: const Icon(Icons.send),
                  onPressed: () async {
                    final t = _reply.text.trim();
                    if (t.isEmpty) return;
                    _reply.clear();
                    await guarded(context, () => ref.read(repositoryProvider).humanReply(conv.cartId, t));
                  },
                ),
              ]),
            ),
          ]);
      return LayoutBuilder(builder: (_, box) {
        if (current == null) return list;
        if (box.maxWidth >= 1000) {
          return Row(children: [Expanded(child: list), const VerticalDivider(width: 1), SizedBox(width: 480, child: detail(current))]);
        }
        return detail(current);
      });
    });
  }
}
