import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/providers.dart';
import '../../shared/widgets.dart';
import 'shopper_app.dart';

/// Order status + consent management (preferences). Includes the demo persona switcher.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final persona = ref.watch(currentPersonaProvider);
    final personas = ref.watch(bootstrapProvider).personas;
    return SnapshotGate(builder: (s) {
      final opted = s.optedIn[persona.id] == true;
      final orders = s.orders.values.where((o) => s.cart(o.cartId)?.shopperId == persona.id).toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return Scaffold(
        appBar: ShopperHeader('Profile', actions: [
          IconButton(tooltip: 'Reset demo', icon: const Icon(Icons.restart_alt), onPressed: () => confirmReset(context, ref)),
        ]),
        body: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 32), children: [
          const SectionTitle('DEMO SHOPPER'),
          Card(
            child: Column(children: [
              for (final p in personas)
                ListTile(
                  onTap: () {
                    ref.read(personaProvider.notifier).set(p.id);
                    ref.read(shopperNavProvider.notifier).root(const ProfilePage());
                  },
                  leading: CircleAvatar(backgroundColor: p.id == persona.id ? CC.cyan : CC.navy2, child: Text(p.firstName[0], style: TextStyle(color: p.id == persona.id ? CC.ink : CC.white))),
                  title: Text(p.label),
                  subtitle: Text('${p.phoneMasked} · ${p.city}'),
                  trailing: p.id == persona.id ? const Icon(Icons.check_circle, color: CC.cyan) : null,
                ),
            ]),
          ),
          const SizedBox(height: 6),
          const Text('All shoppers are fictional. Teen persona is for safeguard demonstration only.', style: TextStyle(color: CC.dim, fontSize: 11.5)),
          const SizedBox(height: 18),
          const SectionTitle('MESSAGE PREFERENCES'),
          Card(
            child: SwitchListTile(
              key: const ValueKey('consent-switch'),
              value: opted,
              title: const Text('WhatsApp checkout reminders'),
              subtitle: Text(opted ? 'On. You can turn this off anytime, or reply STOP.' : 'Off. The store will not message you.', style: const TextStyle(fontSize: 12.5)),
              onChanged: (v) async {
                if (!v) {
                  await guarded(context, () => ref.read(repositoryProvider).revokeConsent(persona.id), success: 'Unsubscribed. Future reminders are blocked.');
                  return;
                }
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (c) => AlertDialog(
                    backgroundColor: CC.navy,
                    title: const Text('Turn on reminders?'),
                    content: Text('${s.store.consentText}\n\nConsent ${s.store.consentVersion}'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Not now')),
                      FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('I agree')),
                    ],
                  ),
                );
                if (ok == true && context.mounted) {
                  await guarded(context, () => ref.read(repositoryProvider).grantConsent(persona.id), success: 'Reminders turned on');
                }
              },
            ),
          ),
          if (persona.isMinor)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text('Under-18 safeguard: even with this on, outbound promotional recovery is blocked in the demo unless guardian authorization exists.',
                  style: TextStyle(color: CC.amber, fontSize: 12)),
            ),
          const SizedBox(height: 18),
          const SectionTitle('ORDERS'),
          if (orders.isEmpty) const Text('No orders yet.', style: TextStyle(color: CC.muted)),
          for (final o in orders)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Card(
                child: ListTile(
                  onTap: () => ref.read(shopperNavProvider.notifier).push(ReceiptPage(o.id)),
                  leading: const Icon(Icons.receipt_long, color: CC.green),
                  title: Text('${o.lines.length} item(s) · ${pkr(o.total)}'),
                  subtitle: Text('${dayTime(o.createdAt)} · ${o.status == 'placed' ? 'Placed, awaiting dispatch' : o.status}'),
                  trailing: const Icon(Icons.chevron_right),
                ),
              ),
            ),
        ]),
      );
    });
  }
}
