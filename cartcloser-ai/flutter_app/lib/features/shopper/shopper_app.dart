import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/models.dart';
import '../../core/providers.dart';
import '../../shared/widgets.dart';
import 'cart_checkout.dart';
import 'chat_screen.dart';
import 'profile_screen.dart';
import 'store_screen.dart';

/// The shopper experience. Navigation is a data stack in [shopperNavProvider] so the guided
/// demo can drive it; rendered with an animated switcher (works inside the judge split view).
class ShopperApp extends ConsumerStatefulWidget {
  final bool embedded;
  const ShopperApp({super.key, this.embedded = false});
  @override
  ConsumerState<ShopperApp> createState() => _ShopperAppState();
}

class _ShopperAppState extends ConsumerState<ShopperApp> {
  int _seenAiMessages = -1;

  Widget _page(ShopperPage p) => switch (p) {
        StorePage() => const StoreScreen(),
        ProductPage(:final productId) => ProductScreen(productId: productId),
        CartPageRoute() => const CartScreen(),
        CheckoutPage() => const CheckoutScreen(),
        InboxPage() => const InboxScreen(),
        ChatPage(:final cartId) => ChatScreen(cartId: cartId),
        RecoverPage(:final cartId, :final token) => RecoverScreen(cartId: cartId, token: token),
        ReceiptPage(:final orderId) => ReceiptScreen(orderId: orderId),
        ProfilePage() => const ProfileScreen(),
      };

  int _tabFor(ShopperPage p) => switch (p) {
        CartPageRoute() || CheckoutPage() || RecoverPage() || ReceiptPage() => 1,
        InboxPage() || ChatPage() => 2,
        ProfilePage() => 3,
        _ => 0,
      };

  void _watchIncoming(Snapshot s, String shopperId, ShopperPage top) {
    // In-app notification when a new store message arrives (simulated push).
    final convs = s.conversationsFor(shopperId);
    final ai = convs.fold<int>(0, (n, c) => n + c.messages.where((m) => m.role != 'shopper').length);
    if (_seenAiMessages >= 0 && ai > _seenAiMessages) {
      final newest = convs.first;
      final onChat = top is ChatPage && top.cartId == newest.cartId;
      final last = newest.last!;
      if (!onChat && last.intent == 'recovery_template') {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
            duration: const Duration(seconds: 4),
            persist: false,
            content: Row(children: [
              const LogoMark(size: 28),
              const SizedBox(width: 10),
              Expanded(child: Text('New message from ${s.store.name}\n${last.text}', maxLines: 2, overflow: TextOverflow.ellipsis)),
            ]),
            action: SnackBarAction(label: 'Open', textColor: CC.green, onPressed: () => ref.read(shopperNavProvider.notifier).push(ChatPage(newest.cartId))),
          ));
        });
      }
    }
    _seenAiMessages = ai;
  }

  @override
  Widget build(BuildContext context) {
    final stack = ref.watch(shopperNavProvider);
    final top = stack.last;
    final persona = ref.watch(currentPersonaProvider);
    final snap = ref.watch(snapshotProvider).value;
    ref.listen(personaProvider, (_, _) => _seenAiMessages = -1);
    if (snap != null) _watchIncoming(snap, persona.id, top);
    final cart = snap?.openCartFor(persona.id);
    final unread = snap == null ? 0 : snap.conversationsFor(persona.id).where((c) => c.last?.role == 'ai' || c.last?.role == 'human').length;
    final nav = ref.read(shopperNavProvider.notifier);

    final app = PopScope(
      canPop: stack.length == 1,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) nav.pop();
      },
      child: Scaffold(
        body: SafeArea(
          bottom: false,
          child: AnimatedSwitcher(
            duration: motion(context, ref, 260),
            switchInCurve: Curves.easeOutCubic,
            transitionBuilder: (child, a) => FadeTransition(
              opacity: a,
              child: SlideTransition(position: Tween(begin: const Offset(.04, 0), end: Offset.zero).animate(a), child: child),
            ),
            child: KeyedSubtree(key: ValueKey('${persona.id}/${top.key}'), child: _page(top)),
          ),
        ),
        bottomNavigationBar: NavigationBar(
          height: 64,
          selectedIndex: _tabFor(top),
          onDestinationSelected: (i) {
            HapticFeedback.selectionClick();
            nav.root(switch (i) { 1 => const CartPageRoute(), 2 => const InboxPage(), 3 => const ProfilePage(), _ => const StorePage() });
          },
          destinations: [
            const NavigationDestination(icon: Icon(Icons.storefront_outlined), selectedIcon: Icon(Icons.storefront), label: 'Shop'),
            NavigationDestination(
              icon: _CartBadge(count: cart?.itemCount ?? 0, child: const Icon(Icons.shopping_bag_outlined)),
              selectedIcon: _CartBadge(count: cart?.itemCount ?? 0, child: const Icon(Icons.shopping_bag)),
              label: 'Cart',
            ),
            NavigationDestination(
              icon: Badge(isLabelVisible: unread > 0, backgroundColor: CC.green, label: Text('$unread'), child: const Icon(Icons.chat_bubble_outline)),
              selectedIcon: const Icon(Icons.chat_bubble),
              label: 'Messages',
            ),
            const NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'Profile'),
          ],
        ),
      ),
    );
    // On wide screens (not inside the judge phone frame) keep the shopper app phone-sized.
    if (widget.embedded || MediaQuery.sizeOf(context).width <= 600) return app;
    return ColoredBox(
      color: const Color(0xFF04060F),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: DecoratedBox(
            decoration: const BoxDecoration(border: Border.symmetric(vertical: BorderSide(color: CC.line))),
            child: MediaQuery(data: MediaQuery.of(context).copyWith(size: Size(480, MediaQuery.sizeOf(context).height)), child: app),
          ),
        ),
      ),
    );
  }
}

/// Cart badge with a little pop when the count changes.
class _CartBadge extends ConsumerWidget {
  final int count;
  final Widget child;
  const _CartBadge({required this.count, required this.child});
  @override
  Widget build(BuildContext context, WidgetRef ref) => Badge(
        isLabelVisible: count > 0,
        backgroundColor: CC.cyan,
        textColor: CC.ink,
        label: AnimatedSwitcher(
          duration: motion(context, ref, 250),
          transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
          child: Text('$count', key: ValueKey(count)),
        ),
        child: child,
      );
}

/// Common shopper page header.
class ShopperHeader extends ConsumerWidget implements PreferredSizeWidget {
  final String title;
  final List<Widget> actions;
  const ShopperHeader(this.title, {super.key, this.actions = const []});
  @override
  Size get preferredSize => const Size.fromHeight(56);
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stack = ref.watch(shopperNavProvider);
    return AppBar(
      automaticallyImplyLeading: false,
      leading: stack.length > 1
          ? IconButton(tooltip: 'Back', icon: const Icon(Icons.arrow_back), onPressed: () => ref.read(shopperNavProvider.notifier).pop())
          : null,
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
      actions: actions,
    );
  }
}
