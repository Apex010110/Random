import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/api_repository.dart';
import '../../core/models.dart';
import '../../core/providers.dart';
import '../../shared/widgets.dart';

// ---------------------------------------------------------------- catalog & policy
class CatalogScreen extends ConsumerWidget {
  const CatalogScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => SnapshotGate(builder: (s) {
        final repo = ref.read(repositoryProvider);
        final pol = s.catalogPolicy;
        final cities = ref.watch(bootstrapProvider).cities;
        return ListView(padding: const EdgeInsets.all(18), children: [
          const Text('Catalog & policies', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          const Text('The AI answers only from this data. Change stock or COD here and ask the assistant again to see grounded answers update.',
              style: TextStyle(color: CC.dim, fontSize: 12)),
          const SizedBox(height: 14),
          for (final p in s.products) _ProductEditor(p),
          const SizedBox(height: 14),
          const SectionTitle('COD CITIES (FICTIONAL DEMO POLICY)'),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final c in cities)
              FilterChip(
                label: Text(c),
                selected: (pol['cod_cities'] as List).contains(c),
                selectedColor: CC.green.withValues(alpha: .2),
                onSelected: (on) {
                  final list = List<String>.from(pol['cod_cities'] as List);
                  on ? list.add(c) : list.remove(c);
                  guarded(context, () => repo.patchCatalog(policy: {'cod_cities': list}));
                },
              ),
          ]),
          const SizedBox(height: 14),
          const SectionTitle('DELIVERY WINDOWS (BUSINESS DAYS, ESTIMATES ONLY)'),
          for (final e in (pol['delivery_windows'] as Map).entries)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(children: [
                SizedBox(width: 120, child: Text(e.key == 'default' ? 'Other cities' : e.key as String)),
                Text('${(e.value as List)[0]}–${(e.value as List)[1]} days', style: const TextStyle(color: CC.cyan, fontWeight: FontWeight.w600)),
                const Spacer(),
                IconButton(
                  tooltip: 'Faster',
                  icon: const Icon(Icons.remove),
                  onPressed: (e.value as List)[0] <= 1
                      ? null
                      : () => guarded(context, () => repo.patchCatalog(policy: {
                            'delivery_windows': {...pol['delivery_windows'] as Map, e.key: [(e.value as List)[0] - 1, (e.value as List)[1] - 1]}
                          })),
                ),
                IconButton(
                  tooltip: 'Slower',
                  icon: const Icon(Icons.add),
                  onPressed: () => guarded(context, () => repo.patchCatalog(policy: {
                        'delivery_windows': {...pol['delivery_windows'] as Map, e.key: [(e.value as List)[0] + 1, (e.value as List)[1] + 1]}
                      })),
                ),
              ]),
            ),
          const SizedBox(height: 14),
          _PolicyText('Exchange policy', 'exchange_policy', pol['exchange_policy'] as String),
          const SizedBox(height: 10),
          _PolicyText('Returns policy', 'returns_policy', pol['returns_policy'] as String),
        ]);
      });
}

class _ProductEditor extends ConsumerWidget {
  final Product p;
  const _ProductEditor(this.p);
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.read(repositoryProvider);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Card(
        child: ExpansionTile(
          shape: const RoundedRectangleBorder(side: BorderSide.none),
          leading: SizedBox(width: 44, height: 44, child: ProductArt(p, radius: 10, iconSize: 22)),
          title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text('${pkr(p.pricePkr)} · stock ${p.totalStock} · ${p.codEligible ? 'COD' : 'prepaid only'}', style: const TextStyle(fontSize: 12.5)),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Cash on delivery eligible'),
              value: p.codEligible,
              onChanged: (v) => guarded(context, () => repo.patchCatalog(products: [{'id': p.id, 'cod_eligible': v}])),
            ),
            for (final v in p.variants)
              Row(children: [
                SizedBox(width: 110, child: Text('Size ${v.size}')),
                IconButton(
                  icon: const Icon(Icons.remove_circle_outline),
                  onPressed: v.stock == 0
                      ? null
                      : () => guarded(context, () => repo.patchCatalog(products: [{'id': p.id, 'variants': [{'size': v.size, 'stock': v.stock - 1}]}])),
                ),
                SizedBox(width: 36, child: Text('${v.stock}', textAlign: TextAlign.center, style: TextStyle(color: v.stock == 0 ? CC.coral : CC.white, fontWeight: FontWeight.w700))),
                IconButton(
                  icon: const Icon(Icons.add_circle_outline),
                  onPressed: () => guarded(context, () => repo.patchCatalog(products: [{'id': p.id, 'variants': [{'size': v.size, 'stock': v.stock + 1}]}])),
                ),
              ]),
          ],
        ),
      ),
    );
  }
}

class _PolicyText extends ConsumerStatefulWidget {
  final String label, field, value;
  const _PolicyText(this.label, this.field, this.value);
  @override
  ConsumerState<_PolicyText> createState() => _PolicyTextState();
}

class _PolicyTextState extends ConsumerState<_PolicyText> {
  late final _c = TextEditingController(text: widget.value);
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: TextField(controller: _c, maxLines: 3, decoration: InputDecoration(labelText: widget.label))),
        const SizedBox(width: 8),
        OutlinedButton(
          onPressed: () => guarded(context, () => ref.read(repositoryProvider).patchCatalog(policy: {widget.field: _c.text.trim()}), success: 'Policy saved'),
          child: const Text('Save'),
        ),
      ]);
}

// ---------------------------------------------------------------- campaign settings
class CampaignScreen extends ConsumerWidget {
  const CampaignScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => SnapshotGate(builder: (s) {
        final st = s.settings;
        final repo = ref.read(repositoryProvider);
        void set(String k, Object v) => guarded(context, () => repo.patchSettings({k: v}));
        num n(String k) => (st[k] as num?) ?? 0;
        return ListView(padding: const EdgeInsets.all(18), children: [
          const Text('Campaign settings', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          Card(
            child: Column(children: [
              SwitchListTile(
                title: const Text('Recovery campaign enabled'),
                subtitle: const Text('Pause to stop every outbound message immediately'),
                value: st['campaign_enabled'] == true,
                onChanged: (v) => set('campaign_enabled', v),
              ),
              const Divider(),
              _Stepper('Delay after abandonment', '${n('delay_minutes')} min', () => set('delay_minutes', (n('delay_minutes') - 5).clamp(1, 1440)),
                  () => set('delay_minutes', (n('delay_minutes') + 5).clamp(1, 1440))),
              SwitchListTile(
                title: const Text('Accelerated demo timing'),
                subtitle: Text('Send ${n('demo_delay_seconds')} s after abandonment instead of ${n('delay_minutes')} min (demo only)'),
                value: st['accelerated_demo'] == true,
                onChanged: (v) => set('accelerated_demo', v),
              ),
              _Stepper('Max messages per cart', '${n('max_messages_per_cart')}', () => set('max_messages_per_cart', (n('max_messages_per_cart') - 1).clamp(0, 3)),
                  () => set('max_messages_per_cart', (n('max_messages_per_cart') + 1).clamp(0, 3))),
              const Divider(),
              SwitchListTile(
                title: const Text('Quiet hours'),
                subtitle: Text('No sends ${n('quiet_start_hour')}:00–${n('quiet_end_hour')}:00 Pakistan time (sends are deferred)'),
                value: st['quiet_hours_enabled'] == true,
                onChanged: (v) => set('quiet_hours_enabled', v),
              ),
              const Divider(),
              SwitchListTile(
                title: const Text('Allow AI to offer a discount'),
                subtitle: const Text('Only when the shopper asks, single-use, never above the ceiling'),
                value: st['discount_enabled'] == true,
                onChanged: (v) => set('discount_enabled', v),
              ),
              ListTile(
                title: Text('Discount ceiling: ${n('discount_ceiling_pct')}%'),
                subtitle: Slider(
                  value: n('discount_ceiling_pct').toDouble(),
                  min: 0,
                  max: 30,
                  divisions: 30,
                  label: '${n('discount_ceiling_pct')}%',
                  onChanged: (_) {},
                  onChangeEnd: (v) => set('discount_ceiling_pct', v.round()),
                ),
              ),
              const Divider(),
              _Stepper('Attribution window', '${n('attribution_window_days')} days', () => set('attribution_window_days', (n('attribution_window_days') - 1).clamp(1, 30)),
                  () => set('attribution_window_days', (n('attribution_window_days') + 1).clamp(1, 30))),
              _Stepper('Holdout (no-message) cohort', '${n('holdout_pct')}%', () => set('holdout_pct', (n('holdout_pct') - 5).clamp(0, 50)),
                  () => set('holdout_pct', (n('holdout_pct') + 5).clamp(0, 50))),
              _Stepper('Assumed cost per message', pkr(n('est_cost_per_message_pkr')), () => set('est_cost_per_message_pkr', (n('est_cost_per_message_pkr') - 1).clamp(0, 1000)),
                  () => set('est_cost_per_message_pkr', (n('est_cost_per_message_pkr') + 1).clamp(0, 1000))),
            ]),
          ),
          const SizedBox(height: 16),
          const SectionTitle('APPROVED RECOVERY TEMPLATE'),
          _TemplateEditor(st['template_recovery'] as String),
          const SizedBox(height: 10),
          const Text('Opt-out handling: replying STOP (or the in-chat "Stop messages" action) revokes consent immediately and cancels pending sends.',
              style: TextStyle(color: CC.dim, fontSize: 12)),
        ]);
      });
}

class _Stepper extends StatelessWidget {
  final String title, value;
  final VoidCallback minus, plus;
  const _Stepper(this.title, this.value, this.minus, this.plus);
  @override
  Widget build(BuildContext context) => ListTile(
        title: Text(title),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          IconButton(icon: const Icon(Icons.remove), onPressed: minus),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w700, color: CC.cyan)),
          IconButton(icon: const Icon(Icons.add), onPressed: plus),
        ]),
      );
}

class _TemplateEditor extends ConsumerStatefulWidget {
  final String value;
  const _TemplateEditor(this.value);
  @override
  ConsumerState<_TemplateEditor> createState() => _TemplateEditorState();
}

class _TemplateEditorState extends ConsumerState<_TemplateEditor> {
  late final _c = TextEditingController(text: widget.value);
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
        TextField(controller: _c, maxLines: 4, decoration: const InputDecoration(helperText: 'Placeholders: {first_name} {store} {item}. Keep the STOP instruction.')),
        const SizedBox(height: 8),
        OutlinedButton(
          onPressed: () {
            if (!_c.text.contains('STOP')) {
              toast(context, 'Template must tell shoppers how to opt out (STOP).', error: true);
              return;
            }
            guarded(context, () => ref.read(repositoryProvider).patchSettings({'template_recovery': _c.text.trim()}), success: 'Template saved');
          },
          child: const Text('Save template'),
        ),
      ]);
}

// ---------------------------------------------------------------- integrations
class IntegrationsScreen extends ConsumerWidget {
  const IntegrationsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => SnapshotGate(builder: (s) {
        const names = {'simulator': 'Messaging simulator', 'shopify': 'Shopify', 'woocommerce': 'WooCommerce', 'whatsapp': 'WhatsApp Business Platform'};
        const icons = {'simulator': Icons.science_outlined, 'shopify': Icons.shopping_bag_outlined, 'woocommerce': Icons.store_outlined, 'whatsapp': Icons.chat_outlined};
        return ListView(padding: const EdgeInsets.all(18), children: [
          const Text('Integrations', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          const Text('Only the local simulator is connected. Platform integrations stay "Not connected" until real credentials pass an integration test.',
              style: TextStyle(color: CC.dim, fontSize: 12)),
          const SizedBox(height: 14),
          for (final i in s.integrations)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Card(
                child: ListTile(
                  leading: Icon(icons[i.provider], color: i.connected ? CC.green : CC.dim),
                  title: Text(names[i.provider] ?? i.provider),
                  subtitle: Text(i.detail),
                  trailing: Pill(i.connected ? 'Connected' : 'Not connected', color: i.connected ? CC.green : CC.muted),
                ),
              ),
            ),
        ]);
      });
}

// ---------------------------------------------------------------- settings
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});
  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  late final _url = TextEditingController(text: ref.read(appModeProvider).backendUrl);
  String? _probe;

  @override
  void dispose() {
    _url.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mode = ref.watch(appModeProvider);
    final personas = ref.watch(bootstrapProvider).personas;
    final repo = ref.read(repositoryProvider);
    return ListView(padding: const EdgeInsets.all(18), children: [
      const Text('Settings', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
      const SizedBox(height: 12),
      const Card(child: ListTile(leading: Icon(Icons.storefront, color: CC.cyan), title: Text('Tenant: UrbanThread PK'), subtitle: Text('Demo tenant · fictional merchant'))),
      const SizedBox(height: 16),
      const SectionTitle('DATA SOURCE'),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            RadioGroup<bool>(
              groupValue: mode.offline,
              onChanged: (v) => v == true ? ref.read(appModeProvider.notifier).set(mode.copyWith(offline: true)) : null,
              child: const RadioListTile<bool>(
                value: true,
                title: Text('Offline demo (recommended on stage)'),
                subtitle: Text('In-app engine, rule-based assistant, no network needed'),
              ),
            ),
            const SizedBox(height: 6),
            TextField(controller: _url, decoration: const InputDecoration(labelText: 'Backend URL', helperText: 'e.g. http://192.168.1.20:8000 for a laptop on the same Wi-Fi')),
            const SizedBox(height: 8),
            Row(children: [
              OutlinedButton(
                onPressed: () async {
                  setState(() => _probe = 'Testing…');
                  try {
                    final h = await ApiRepository.probe(_url.text.trim());
                    setState(() => _probe = 'OK · mode ${h['mode']} · AI ${h['ai']} · messaging ${h['messaging']}');
                  } catch (e) {
                    setState(() => _probe = 'Not reachable. Staying offline is safe.');
                  }
                },
                child: const Text('Test connection'),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _probe?.startsWith('OK') == true ? () => ref.read(appModeProvider.notifier).set(mode.copyWith(offline: false, backendUrl: _url.text.trim())) : null,
                child: const Text('Use backend'),
              ),
            ]),
            if (_probe != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_probe!, style: const TextStyle(color: CC.muted, fontSize: 12.5))),
            const SizedBox(height: 6),
            Text('Current: ${repo.modeLabel}', style: const TextStyle(color: CC.cyan, fontSize: 12.5)),
          ]),
        ),
      ),
      const SizedBox(height: 16),
      const SectionTitle('ACCESSIBILITY'),
      Card(
        child: SwitchListTile(
          title: const Text('Reduce motion'),
          subtitle: const Text('Also follows the device setting'),
          value: ref.watch(reducedMotionProvider),
          onChanged: (v) => ref.read(reducedMotionProvider.notifier).set(v),
        ),
      ),
      const SizedBox(height: 16),
      const SectionTitle('DATA CONTROLS'),
      Card(
        child: Column(children: [
          ListTile(
            leading: const Icon(Icons.download_outlined),
            title: const Text('Export tenant data (JSON)'),
            subtitle: const Text('Carts, conversations and orders. No card data exists.'),
            onTap: () async {
              final data = await guarded(context, repo.exportData);
              if (data == null || !context.mounted) return;
              final text = const JsonEncoder.withIndent('  ').convert(data);
              showDialog<void>(
                context: context,
                builder: (c) => AlertDialog(
                  backgroundColor: CC.navy,
                  title: const Text('Export'),
                  content: SizedBox(width: 520, height: 360, child: SingleChildScrollView(child: SelectableText(text, style: const TextStyle(fontSize: 11)))),
                  actions: [
                    TextButton(
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: text));
                        Navigator.pop(c);
                      },
                      child: const Text('Copy'),
                    ),
                  ],
                ),
              );
            },
          ),
          const Divider(),
          for (final p in personas)
            ListTile(
              leading: const Icon(Icons.delete_outline, color: CC.coral),
              title: Text('Delete data for ${p.firstName}'),
              subtitle: const Text('Erases carts, chats and consent records; orders kept anonymised'),
              onTap: () => guarded(context, () => repo.deleteShopperData(p.id), success: 'Deleted ${p.firstName}\'s data'),
            ),
        ]),
      ),
      const SizedBox(height: 16),
      FilledButton.icon(icon: const Icon(Icons.restart_alt), label: const Text('Reset demo data'), onPressed: () => confirmReset(context, ref)),
    ]);
  }
}
