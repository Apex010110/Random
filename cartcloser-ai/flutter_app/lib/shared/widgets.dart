import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../app/theme.dart';
import '../core/models.dart';
import '../core/providers.dart';

final _money = NumberFormat('#,##0');
String pkr(num v) => 'PKR ${_money.format(v)}';

/// Pakistan time (UTC+5, no DST) for display.
DateTime pkt(DateTime utc) => utc.toUtc().add(const Duration(hours: 5));
String hhmm(DateTime utc) => DateFormat('h:mm a').format(pkt(utc));
String dayTime(DateTime utc) => DateFormat('EEE d MMM, h:mm a').format(pkt(utc));

String ago(DateTime utc, DateTime now) {
  final d = now.difference(utc);
  if (d.inSeconds < 60) return '${math.max(0, d.inSeconds)}s ago';
  if (d.inMinutes < 60) return '${d.inMinutes}m ago';
  if (d.inHours < 24) return '${d.inHours}h ago';
  return '${d.inDays}d ago';
}

/// Motion helper: respects OS "reduce motion" and the in-app toggle.
Duration motion(BuildContext context, WidgetRef ref, int ms) {
  final reduced = MediaQuery.maybeDisableAnimationsOf(context) == true || ref.watch(reducedMotionProvider);
  return reduced ? Duration.zero : Duration(milliseconds: ms);
}

void toast(BuildContext context, String msg, {bool error = false}) {
  final m = ScaffoldMessenger.maybeOf(context);
  m?.hideCurrentSnackBar();
  m?.showSnackBar(SnackBar(
    content: Row(children: [
      Icon(error ? Icons.error_outline : Icons.check_circle_outline, color: error ? CC.coral : CC.green, size: 20),
      const SizedBox(width: 10),
      Expanded(child: Text(msg)),
    ]),
    duration: const Duration(seconds: 3),
  ));
}

/// Run an async action and surface domain errors as a toast (no silent failures).
Future<T?> guarded<T>(BuildContext context, Future<T> Function() f, {String? success}) async {
  try {
    final r = await f();
    if (success != null && context.mounted) toast(context, success);
    return r;
  } on ApiException catch (e) {
    if (context.mounted) toast(context, e.message, error: true);
  } catch (e) {
    if (context.mounted) toast(context, 'Something went wrong: $e', error: true);
  }
  return null;
}

// ---------------------------------------------------------------- brand
class LogoMark extends StatelessWidget {
  final double size;
  const LogoMark({super.key, this.size = 40});
  @override
  Widget build(BuildContext context) => SizedBox(
        width: size,
        height: size,
        child: CustomPaint(painter: _LogoPainter()),
      );
}

class _LogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size s) {
    final w = s.width, h = s.height;
    final bubble = Path()
      ..addRRect(RRect.fromRectAndRadius(Rect.fromLTWH(w * .05, h * .07, w * .9, h * .72), Radius.circular(w * .16)))
      ..moveTo(w * .25, h * .76)
      ..lineTo(w * .2, h * .95)
      ..lineTo(w * .44, h * .78)
      ..close();
    canvas.drawPath(
        bubble,
        Paint()
          ..shader = const LinearGradient(colors: [CC.cyan, CC.green], begin: Alignment.topLeft, end: Alignment.bottomRight)
              .createShader(Offset.zero & s));
    final cart = Paint()
      ..color = CC.ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * .055
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(
        Path()
          ..moveTo(w * .22, h * .24)
          ..lineTo(w * .3, h * .24)
          ..lineTo(w * .38, h * .56)
          ..lineTo(w * .71, h * .56)
          ..lineTo(w * .78, h * .33)
          ..lineTo(w * .33, h * .33),
        cart);
    canvas.drawCircle(Offset(w * .42, h * .67), w * .04, Paint()..color = CC.ink);
    canvas.drawCircle(Offset(w * .67, h * .67), w * .04, Paint()..color = CC.ink);
    canvas.drawPath(
        Path()
          ..moveTo(w * .46, h * .43)
          ..lineTo(w * .53, h * .49)
          ..lineTo(w * .66, h * .37),
        Paint()
          ..color = CC.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = w * .05
          ..strokeCap = StrokeCap.round);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class DemoBadge extends StatelessWidget {
  final String text;
  final Color color;
  const DemoBadge({super.key, this.text = 'DEMO DATA', this.color = CC.amber});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: color.withValues(alpha: .14), borderRadius: BorderRadius.circular(99), border: Border.all(color: color.withValues(alpha: .5))),
        child: Text(text, style: TextStyle(color: color, fontSize: 10.5, fontWeight: FontWeight.w700, letterSpacing: .8)),
      );
}

class Pill extends StatelessWidget {
  final String text;
  final Color color;
  final IconData? icon;
  const Pill(this.text, {super.key, this.color = CC.cyan, this.icon});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(color: color.withValues(alpha: .13), borderRadius: BorderRadius.circular(99)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[Icon(icon, size: 13, color: color), const SizedBox(width: 4)],
          Text(text, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
        ]),
      );
}

const statusLabels = {
  'active_cart': 'Browsing',
  'checkout_started': 'At checkout',
  'abandoned': 'Abandoned',
  'not_eligible': 'Not eligible',
  'eligible': 'Eligible',
  'scheduled': 'Scheduled',
  'message_sent': 'Message sent',
  'replied': 'Replied',
  'human_handoff': 'Human handoff',
  'recovered': 'Recovered',
  'ordered': 'Ordered',
  'expired': 'Expired',
  'opted_out': 'Opted out',
};

const reasonLabels = {
  'no_consent': 'No opt-in',
  'opted_out': 'Opted out (STOP)',
  'under_18_safeguard': 'Under-18 safeguard',
  'already_purchased': 'Already purchased',
  'campaign_paused': 'Campaign paused',
  'cart_paused': 'Paused for this cart',
  'contact_cap': 'Contact cap reached',
  'quiet_hours': 'Quiet hours',
  'empty_cart': 'Empty cart',
  'holdout_control': 'Holdout (no message)',
};

Color statusColor(String s) => switch (s) {
      'recovered' => CC.green,
      'ordered' => CC.green,
      'replied' || 'message_sent' || 'scheduled' || 'eligible' => CC.cyan,
      'human_handoff' => CC.amber,
      'not_eligible' || 'opted_out' || 'abandoned' => CC.coral,
      _ => CC.muted,
    };

class StatusChip extends StatelessWidget {
  final String status;
  final String? reason;
  const StatusChip(this.status, {super.key, this.reason});
  @override
  Widget build(BuildContext context) {
    final label = statusLabels[status] ?? status;
    final r = reason == null ? '' : ' · ${reasonLabels[reason] ?? reason}';
    return Pill('$label$r', color: statusColor(status));
  }
}

/// Animated number (live dashboard count-up).
class CountUp extends ConsumerWidget {
  final num value;
  final String Function(num v) format;
  final TextStyle? style;
  const CountUp(this.value, {super.key, required this.format, this.style});
  @override
  Widget build(BuildContext context, WidgetRef ref) => TweenAnimationBuilder<double>(
        tween: Tween(end: value.toDouble()),
        duration: motion(context, ref, 700),
        curve: Curves.easeOutCubic,
        builder: (_, v, _) => Text(format(v), style: style),
      );
}

/// Placeholder product art (no stock photography; clearly a placeholder).
class ProductArt extends StatelessWidget {
  final Product product;
  final double radius;
  final double iconSize;
  const ProductArt(this.product, {super.key, this.radius = 16, this.iconSize = 52});

  static IconData iconFor(String key) => switch (key) {
        'kurta' || 'shirt' => Icons.checkroom,
        'suit' => Icons.dry_cleaning,
        'waistcoat' => Icons.checkroom_outlined,
        'dupatta' => Icons.texture,
        'chappal' => Icons.hiking,
        'bag' => Icons.shopping_bag_outlined,
        'jewelry' => Icons.diamond_outlined,
        'sherwani' => Icons.auto_awesome,
        _ => Icons.local_mall_outlined,
      };

  @override
  Widget build(BuildContext context) {
    final c = Color(int.parse('FF${product.colorHex.substring(1)}', radix: 16));
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Stack(fit: StackFit.expand, children: [
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [c.withValues(alpha: .55), CC.navy2], begin: Alignment.topLeft, end: Alignment.bottomRight),
          ),
        ),
        Center(child: Icon(iconFor(product.imageKey), size: iconSize, color: CC.white.withValues(alpha: .9))),
        if (!product.inStock)
          Positioned(
            left: 8,
            top: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: CC.ink.withValues(alpha: .8), borderRadius: BorderRadius.circular(99)),
              child: const Text('Out of stock', style: TextStyle(color: CC.coral, fontSize: 11, fontWeight: FontWeight.w600)),
            ),
          ),
      ]),
    );
  }
}

/// Three bouncing dots (typing state).
class TypingDots extends StatefulWidget {
  const TypingDots({super.key});
  @override
  State<TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<TypingDots> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat();
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _c,
        builder: (_, _) => Row(mainAxisSize: MainAxisSize.min, children: [
          for (var i = 0; i < 3; i++)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2.5),
              child: Transform.translate(
                offset: Offset(0, -3 * math.sin(((_c.value + i * .2) % 1) * math.pi).clamp(0, 1)),
                child: Container(width: 7, height: 7, decoration: const BoxDecoration(color: CC.muted, shape: BoxShape.circle)),
              ),
            ),
        ]),
      );
}

/// Animated "drawn" check mark used on the recovered-order receipt.
class AnimatedCheck extends ConsumerWidget {
  final double size;
  const AnimatedCheck({super.key, this.size = 96});
  @override
  Widget build(BuildContext context, WidgetRef ref) => TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: motion(context, ref, 700),
        curve: Curves.easeOutBack,
        builder: (_, t, _) => Transform.scale(
          scale: .6 + .4 * t.clamp(0, 1.2),
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(color: CC.green, shape: BoxShape.circle, boxShadow: [
              BoxShadow(color: CC.green.withValues(alpha: .35 * t.clamp(0, 1)), blurRadius: 30, spreadRadius: 4),
            ]),
            child: CustomPaint(painter: _CheckPainter(t.clamp(0, 1).toDouble())),
          ),
        ),
      );
}

class _CheckPainter extends CustomPainter {
  final double t;
  _CheckPainter(this.t);
  @override
  void paint(Canvas canvas, Size s) {
    final p = Path()
      ..moveTo(s.width * .28, s.height * .52)
      ..lineTo(s.width * .44, s.height * .67)
      ..lineTo(s.width * .74, s.height * .36);
    final metric = p.computeMetrics().first;
    canvas.drawPath(
        metric.extractPath(0, metric.length * t),
        Paint()
          ..color = CC.ink
          ..style = PaintingStyle.stroke
          ..strokeWidth = s.width * .09
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round);
  }

  @override
  bool shouldRepaint(covariant _CheckPainter old) => old.t != t;
}

/// Pulsing skeleton block for loading states.
class Skeleton extends StatefulWidget {
  final double height;
  final double? width;
  const Skeleton({super.key, this.height = 16, this.width});
  @override
  State<Skeleton> createState() => _SkeletonState();
}

class _SkeletonState extends State<Skeleton> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))..repeat(reverse: true);
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
        opacity: Tween(begin: .35, end: .8).animate(_c),
        child: Container(height: widget.height, width: widget.width, decoration: BoxDecoration(color: CC.navy2, borderRadius: BorderRadius.circular(10))),
      );
}

class SnapshotGate extends ConsumerWidget {
  final Widget Function(Snapshot s) builder;
  const SnapshotGate({super.key, required this.builder});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snap = ref.watch(snapshotProvider);
    return snap.when(
      data: builder,
      loading: () => const Padding(
        padding: EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Skeleton(height: 28, width: 200),
          SizedBox(height: 16),
          Skeleton(height: 120),
          SizedBox(height: 12),
          Skeleton(height: 120),
        ]),
      ),
      error: (e, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.cloud_off, color: CC.coral, size: 40),
            const SizedBox(height: 12),
            Text('Could not load demo data: $e', textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () => ref.read(appModeProvider.notifier).set(const AppMode(offline: true)),
              child: const Text('Switch to offline demo'),
            ),
          ]),
        ),
      ),
    );
  }
}

class SectionTitle extends StatelessWidget {
  final String text;
  final Widget? trailing;
  const SectionTitle(this.text, {super.key, this.trailing});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10, top: 6),
        child: Row(children: [
          Expanded(child: Text(text, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: CC.muted, letterSpacing: 1.1))),
          ?trailing,
        ]),
      );
}

/// Confirm-before-reset dialog shared by shopper, merchant and judge screens.
Future<void> confirmReset(BuildContext context, WidgetRef ref) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      backgroundColor: CC.navy,
      title: const Text('Reset demo?'),
      content: const Text('Clears all carts, chats, orders and consent records and reloads the fictional UrbanThread PK seed data.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Reset')),
      ],
    ),
  );
  if (ok == true && context.mounted) {
    await guarded(context, () => ref.read(repositoryProvider).reset(), success: 'Demo reset');
    ref.read(shopperNavProvider.notifier).root(const StorePage());
    ref.read(merchantNavProvider.notifier).closeCart();
  }
}
