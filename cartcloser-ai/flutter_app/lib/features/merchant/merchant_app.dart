import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/providers.dart';
import '../../shared/widgets.dart';
import 'green_logistics.dart';
import 'merchant_admin.dart';
import 'merchant_screens.dart';

const _tabs = [
  (MerchantTab.overview, Icons.dashboard_outlined, Icons.dashboard, 'Overview'),
  (MerchantTab.analytics, Icons.insights_outlined, Icons.insights, 'Analytics'),
  (MerchantTab.carts, Icons.shopping_cart_outlined, Icons.shopping_cart, 'Carts'),
  (MerchantTab.inbox, Icons.forum_outlined, Icons.forum, 'Inbox'),
  (MerchantTab.orders, Icons.local_shipping_outlined, Icons.local_shipping, 'Orders'),
  (MerchantTab.green, Icons.eco_outlined, Icons.eco, 'Green Logistics'),
  (MerchantTab.catalog, Icons.inventory_2_outlined, Icons.inventory_2, 'Catalog'),
  (MerchantTab.campaign, Icons.campaign_outlined, Icons.campaign, 'Campaign'),
  (MerchantTab.integrations, Icons.hub_outlined, Icons.hub, 'Integrations'),
  (MerchantTab.settings, Icons.settings_outlined, Icons.settings, 'Settings'),
];

/// Adaptive merchant dashboard: navigation rail on tablet/desktop, drawer on phones.
class MerchantApp extends ConsumerWidget {
  final bool embedded;
  const MerchantApp({super.key, this.embedded = false});

  Widget _body(MerchantTab t) => switch (t) {
        MerchantTab.overview => const OverviewScreen(),
        MerchantTab.analytics => const AnalyticsScreen(),
        MerchantTab.carts => const CartsScreen(),
        MerchantTab.inbox => const MerchantInboxScreen(),
        MerchantTab.orders => const GreenOrdersScreen(),
        MerchantTab.green => const GreenDashboardScreen(),
        MerchantTab.catalog => const CatalogScreen(),
        MerchantTab.campaign => const CampaignScreen(),
        MerchantTab.integrations => const IntegrationsScreen(),
        MerchantTab.settings => const SettingsScreen(),
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nav = ref.watch(merchantNavProvider);
    final wide = MediaQuery.sizeOf(context).width >= 900 || embedded;
    final idx = _tabs.indexWhere((t) => t.$1 == nav.tab);
    final repo = ref.watch(repositoryProvider);
    final escalated = ref.watch(snapshotProvider).value?.conversations.values.where((c) => c.escalated).length ?? 0;

    final header = AppBar(
      automaticallyImplyLeading: !wide,
      title: Row(children: [
        const LogoMark(size: 28),
        const SizedBox(width: 10),
        const Text('CartCloser AI', style: TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(width: 10),
        Flexible(child: Text('· ${_tabs[idx].$4}', overflow: TextOverflow.ellipsis, style: const TextStyle(color: CC.muted, fontWeight: FontWeight.w500))),
      ]),
      actions: [
        Padding(padding: const EdgeInsets.only(right: 8), child: DemoBadge(text: repo.isOffline ? 'DEMO · OFFLINE' : 'DEMO · BACKEND', color: repo.isOffline ? CC.amber : CC.cyan)),
        IconButton(tooltip: 'Reset demo', icon: const Icon(Icons.restart_alt), onPressed: () => confirmReset(context, ref)),
      ],
    );

    final body = AnimatedSwitcher(
      duration: motion(context, ref, 220),
      child: KeyedSubtree(key: ValueKey(nav.tab), child: _body(nav.tab)),
    );

    if (!wide) {
      return Scaffold(
        appBar: header,
        drawer: Drawer(
          backgroundColor: CC.ink,
          child: SafeArea(
            child: ListView(children: [
              const Padding(padding: EdgeInsets.all(16), child: Text('UrbanThread PK · demo tenant', style: TextStyle(color: CC.muted))),
              for (final t in _tabs)
                ListTile(
                  selected: t.$1 == nav.tab,
                  selectedColor: CC.cyan,
                  leading: Icon(t.$1 == nav.tab ? t.$3 : t.$2),
                  title: Text(t.$4),
                  trailing: t.$1 == MerchantTab.inbox && escalated > 0 ? Badge(label: Text('$escalated'), backgroundColor: CC.amber) : null,
                  onTap: () {
                    ref.read(merchantNavProvider.notifier).tab(t.$1);
                    Navigator.pop(context);
                  },
                ),
            ]),
          ),
        ),
        body: body,
      );
    }
    return Scaffold(
      appBar: header,
      body: Row(children: [
        NavigationRail(
          selectedIndex: idx,
          labelType: NavigationRailLabelType.all,
          minWidth: 76,
          onDestinationSelected: (i) => ref.read(merchantNavProvider.notifier).tab(_tabs[i].$1),
          destinations: [
            for (final t in _tabs)
              NavigationRailDestination(
                icon: t.$1 == MerchantTab.inbox && escalated > 0 ? Badge(label: Text('$escalated'), backgroundColor: CC.amber, child: Icon(t.$2)) : Icon(t.$2),
                selectedIcon: Icon(t.$3),
                label: Text(t.$4),
              ),
          ],
        ),
        const VerticalDivider(width: 1),
        Expanded(child: body),
      ]),
    );
  }
}
