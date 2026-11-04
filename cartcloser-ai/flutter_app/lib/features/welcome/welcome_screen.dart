import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../../core/providers.dart';
import '../../shared/widgets.dart';

class WelcomeScreen extends ConsumerWidget {
  const WelcomeScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(repositoryProvider);
    final w = MediaQuery.sizeOf(context).width;
    final cards = [
      _RoleCard(
        key: const ValueKey('role-shopper'),
        icon: Icons.shopping_bag_outlined,
        color: CC.cyan,
        title: 'Shopper demo',
        body: 'Browse UrbanThread PK, add the linen kurta, opt in (or not) and leave checkout.',
        onTap: () => context.go('/shop'),
      ),
      _RoleCard(
        key: const ValueKey('role-merchant'),
        icon: Icons.dashboard_outlined,
        color: CC.green,
        title: 'Merchant dashboard',
        body: 'Eligible carts, live funnel, conversations, catalog, consent-safe campaign settings.',
        onTap: () => context.go('/merchant'),
      ),
      _RoleCard(
        key: const ValueKey('role-judge'),
        icon: Icons.slideshow_outlined,
        color: CC.amber,
        title: 'Guided judge demo',
        body: 'Shopper phone and merchant dashboard side by side, with step-by-step scenarios A to H.',
        onTap: () => context.go('/judge'),
      ),
    ];
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(center: Alignment(.8, -.6), radius: 1.3, colors: [Color(0xFF0E2A3A), CC.ink]),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1100),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const LogoMark(size: 64),
                  const SizedBox(height: 18),
                  RichText(
                    text: const TextSpan(style: TextStyle(fontFamily: CC.fonts, fontSize: 42, fontWeight: FontWeight.w800, color: CC.white), children: [
                      TextSpan(text: 'CartCloser '),
                      TextSpan(text: 'AI', style: TextStyle(color: CC.cyan)),
                    ]),
                  ),
                  const SizedBox(height: 6),
                  const Text('Turning abandoned carts into helpful conversations, and conversations into completed orders.',
                      style: TextStyle(fontSize: 17, color: CC.muted)),
                  const SizedBox(height: 10),
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    DemoBadge(text: repo.isOffline ? 'OFFLINE DEMO MODE' : 'BACKEND MODE', color: repo.isOffline ? CC.amber : CC.cyan),
                    const DemoBadge(text: 'SIMULATED WHATSAPP', color: CC.green),
                    const DemoBadge(text: 'FICTIONAL STORE & SHOPPERS', color: CC.muted),
                  ]),
                  const SizedBox(height: 28),
                  if (w >= 820)
                    IntrinsicHeight(child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [for (final c in cards) Expanded(child: Padding(padding: const EdgeInsets.only(right: 14), child: c))]))
                  else
                    Column(children: [for (final c in cards) Padding(padding: const EdgeInsets.only(bottom: 12), child: c)]),
                  const SizedBox(height: 24),
                  Row(children: [
                    TextButton.icon(onPressed: () => confirmReset(context, ref), icon: const Icon(Icons.restart_alt), label: const Text('Reset demo')),
                    const Spacer(),
                    const Flexible(
                      child: Text('IGNITE XIII prototype. No real WhatsApp messages are sent; Shopify, WooCommerce and WhatsApp are not connected.',
                          textAlign: TextAlign.right, style: TextStyle(color: CC.dim, fontSize: 11.5)),
                    ),
                  ]),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RoleCard extends StatefulWidget {
  final IconData icon;
  final Color color;
  final String title, body;
  final VoidCallback onTap;
  const _RoleCard({super.key, required this.icon, required this.color, required this.title, required this.body, required this.onTap});
  @override
  State<_RoleCard> createState() => _RoleCardState();
}

class _RoleCardState extends State<_RoleCard> {
  bool _hover = false;
  @override
  Widget build(BuildContext context) => MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          transform: Matrix4.translationValues(0, _hover ? -4 : 0, 0),
          child: Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide(color: _hover ? widget.color : CC.line)),
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: widget.onTap,
              child: Padding(
                padding: const EdgeInsets.all(22),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(color: widget.color.withValues(alpha: .15), borderRadius: BorderRadius.circular(14)),
                    child: Icon(widget.icon, color: widget.color),
                  ),
                  const SizedBox(height: 16),
                  Text(widget.title, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 6),
                  Text(widget.body, style: const TextStyle(color: CC.muted, height: 1.4)),
                  const SizedBox(height: 14),
                  Row(children: [Text('Open', style: TextStyle(color: widget.color, fontWeight: FontWeight.w700)), Icon(Icons.arrow_forward, size: 18, color: widget.color)]),
                ]),
              ),
            ),
          ),
        ),
      );
}
