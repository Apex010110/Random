import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/models.dart';
import '../../core/providers.dart';
import '../../shared/widgets.dart';
import 'actions.dart';
import 'shopper_app.dart';

const simulatorNote = 'Simulated WhatsApp-style messages for the demo. This is not the WhatsApp app and no real messages are sent.';

class InboxScreen extends ConsumerWidget {
  const InboxScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final persona = ref.watch(currentPersonaProvider);
    return SnapshotGate(builder: (s) {
      final convs = s.conversationsFor(persona.id);
      return Scaffold(
        appBar: const ShopperHeader('Messages'),
        body: Column(children: [
          Container(
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: CC.navy2, borderRadius: BorderRadius.circular(12)),
            child: const Row(children: [
              Icon(Icons.science_outlined, color: CC.amber, size: 18),
              SizedBox(width: 8),
              Expanded(child: Text(simulatorNote, style: TextStyle(color: CC.muted, fontSize: 12))),
            ]),
          ),
          Expanded(
            child: convs.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('No messages yet.\nStores can only message you here if you opt in at checkout.',
                          textAlign: TextAlign.center, style: TextStyle(color: CC.muted)),
                    ),
                  )
                : ListView.separated(
                    itemCount: convs.length,
                    separatorBuilder: (_, _) => const Divider(indent: 76),
                    itemBuilder: (_, i) {
                      final c = convs[i];
                      final last = c.last!;
                      return ListTile(
                        onTap: () => ref.read(shopperNavProvider.notifier).push(ChatPage(c.cartId)),
                        leading: const CircleAvatar(radius: 24, backgroundColor: CC.navy2, child: LogoMark(size: 30)),
                        title: Text(s.store.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Text(last.text, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: CC.muted)),
                        trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                          Text(hhmm(last.createdAt), style: const TextStyle(color: CC.dim, fontSize: 11.5)),
                          const SizedBox(height: 4),
                          Pill(c.isWhatsAppSim ? 'WhatsApp sim' : 'On-site chat', color: c.isWhatsAppSim ? CC.green : CC.cyan),
                        ]),
                      );
                    },
                  ),
          ),
        ]),
      );
    });
  }
}

class ChatScreen extends ConsumerStatefulWidget {
  final String cartId;
  const ChatScreen({super.key, required this.cartId});
  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  int _revealedSeq = -1; // messages above this are held back while "typing"
  bool _typing = false;
  Timer? _typingTimer;
  bool _sending = false;

  static const quickReplies = [
    'Will it arrive in Karachi by Friday?',
    'Can I pay COD?',
    'COD hai?',
    'What size should I get?',
    'Any discount?',
    'کیا کراچی میں جمعہ تک پہنچ جائے گا؟',
    'Can I exchange it?',
    'Talk to a human',
    'STOP',
  ];

  @override
  void dispose() {
    _typingTimer?.cancel();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _sync(Conversation conv) {
    final maxSeq = conv.messages.isEmpty ? 0 : conv.messages.last.seq;
    if (_revealedSeq < 0) {
      _revealedSeq = maxSeq;
      return;
    }
    if (maxSeq > _revealedSeq && !_typing) {
      final pending = conv.messages.where((m) => m.seq > _revealedSeq).toList();
      final firstNonShopper = pending.indexWhere((m) => m.role != 'shopper');
      if (firstNonShopper < 0) {
        _revealedSeq = maxSeq;
      } else {
        // reveal shopper bubbles immediately, then "type" before showing the reply
        _revealedSeq = firstNonShopper == 0 ? _revealedSeq : pending[firstNonShopper - 1].seq;
        final delay = motion(context, ref, 750);
        if (delay == Duration.zero) {
          _revealedSeq = maxSeq;
        } else {
          _typing = true;
          _typingTimer = Timer(delay, () {
            if (!mounted) return;
            setState(() {
              _typing = false;
              _revealedSeq = maxSeq;
            });
            _toBottom();
          });
        }
      }
      _toBottom();
    }
  }

  void _toBottom() => WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) {
          _scroll.animateTo(_scroll.position.maxScrollExtent + 200, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
        }
      });

  Future<void> _send(String text) async {
    final t = text.trim();
    if (t.isEmpty || _sending) return;
    setState(() => _sending = true);
    _input.clear();
    await guarded(context, () => ShopperActions(ref).say(widget.cartId, t));
    if (mounted) setState(() => _sending = false);
  }

  @override
  Widget build(BuildContext context) {
    return SnapshotGate(builder: (s) {
      final conv = s.conversations[widget.cartId] ?? Conversation(widget.cartId, 'onsite_chat', false, false, const []);
      final cart = s.cart(widget.cartId);
      _sync(conv);
      final visible = conv.messages.where((m) => m.seq <= _revealedSeq).toList();
      final optedOut = cart?.status == 'opted_out';
      return Scaffold(
        backgroundColor: CC.chatBg,
        appBar: AppBar(
          backgroundColor: CC.chatHead,
          automaticallyImplyLeading: false,
          leading: IconButton(icon: const Icon(Icons.arrow_back), tooltip: 'Back', onPressed: () => ref.read(shopperNavProvider.notifier).pop()),
          titleSpacing: 0,
          title: Row(children: [
            const LogoMark(size: 34),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(s.store.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                Text(
                  _typing
                      ? 'typing…'
                      : conv.humanTakeover
                          ? 'Team member · human'
                          : (conv.isWhatsAppSim ? 'Store assistant · Demo AI (rule-based)' : 'On-site assistant · Demo AI (rule-based)'),
                  style: TextStyle(fontSize: 11.5, color: _typing ? CC.green : CC.muted),
                ),
              ]),
            ),
          ]),
          actions: [
            PopupMenuButton<String>(
              onSelected: (v) {
                if (v == 'stop') _send('STOP');
              },
              itemBuilder: (_) => [const PopupMenuItem(value: 'stop', child: Text('Stop messages (opt out)'))],
            ),
          ],
        ),
        body: Column(children: [
          Container(
            width: double.infinity,
            color: CC.chatHead.withValues(alpha: .6),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            child: Text(conv.isWhatsAppSim ? 'Simulated WhatsApp · demo only' : 'On-site chat · started by you (no opt-in needed)',
                textAlign: TextAlign.center, style: const TextStyle(color: CC.dim, fontSize: 11)),
          ),
          Expanded(
            child: ListView(controller: _scroll, padding: const EdgeInsets.fromLTRB(10, 10, 10, 10), children: [
              if (visible.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('Ask about size, delivery, cash on delivery or returns.', textAlign: TextAlign.center, style: TextStyle(color: CC.muted)),
                ),
              for (final m in visible) _Bubble(m: m, onLink: (token) => _openLink(token)),
              if (_typing)
                const Align(
                  alignment: Alignment.centerLeft,
                  child: _BubbleShell(out: false, child: Padding(padding: EdgeInsets.symmetric(vertical: 4), child: TypingDots())),
                ),
            ]),
          ),
          SizedBox(
            height: 44,
            child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 8), children: [
              for (final q in quickReplies)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 5),
                  child: ActionChip(label: Text(q, style: const TextStyle(fontSize: 12.5)), onPressed: optedOut && q == 'STOP' ? null : () => _send(q)),
                ),
            ]),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
              child: Row(children: [
                Expanded(
                  child: TextField(
                    key: const ValueKey('chat-input'),
                    controller: _input,
                    minLines: 1,
                    maxLines: 4,
                    maxLength: 500,
                    textInputAction: TextInputAction.send,
                    onSubmitted: _send,
                    decoration: const InputDecoration(hintText: 'Message (English, اردو or Roman Urdu)', counterText: '', isDense: true),
                  ),
                ),
                const SizedBox(width: 6),
                IconButton.filled(
                  key: const ValueKey('chat-send'),
                  style: IconButton.styleFrom(backgroundColor: CC.green, foregroundColor: CC.ink),
                  onPressed: () => _send(_input.text),
                  icon: _sending ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: CC.ink)) : const Icon(Icons.send),
                  tooltip: 'Send',
                ),
              ]),
            ),
          ),
        ]),
      );
    });
  }

  void _openLink(String token) => ref.read(shopperNavProvider.notifier).push(RecoverPage(widget.cartId, token));
}

class _BubbleShell extends StatelessWidget {
  final bool out;
  final Widget child;
  const _BubbleShell({required this.out, required this.child});
  @override
  Widget build(BuildContext context) => Container(
        constraints: const BoxConstraints(maxWidth: 320),
        margin: const EdgeInsets.symmetric(vertical: 3),
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
        decoration: BoxDecoration(
          color: out ? CC.chatOut : CC.chatIn,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(14),
            topRight: const Radius.circular(14),
            bottomLeft: Radius.circular(out ? 14 : 4),
            bottomRight: Radius.circular(out ? 4 : 14),
          ),
        ),
        child: child,
      );
}

class _Bubble extends ConsumerWidget {
  final ChatMessage m;
  final void Function(String token) onLink;
  const _Bubble({required this.m, required this.onLink});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (m.role == 'system') {
      return Center(
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 6),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(color: const Color(0xFF182229), borderRadius: BorderRadius.circular(8)),
          child: Text(m.text, style: const TextStyle(color: Color(0xFF8696A0), fontSize: 11.5)),
        ),
      );
    }
    final out = m.role == 'shopper';
    final rtl = m.isUrdu || RegExp(r'[؀-ۿ]').hasMatch(m.text);
    final label = switch (m.source) { 'template' => 'Approved template', 'rules' => 'Demo AI · rule-based', 'llm' => 'Demo AI · grounded LLM', 'human' => 'Team member', _ => null };
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: motion(context, ref, 220),
      builder: (_, t, child) => Opacity(opacity: t, child: Transform.translate(offset: Offset(0, 8 * (1 - t)), child: child)),
      child: Align(
        alignment: out ? Alignment.centerRight : Alignment.centerLeft,
        child: _BubbleShell(
          out: out,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Directionality(
              textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
              child: Text(m.text, style: TextStyle(color: const Color(0xFFE9EDEF), fontSize: rtl ? 15.5 : 14.5, height: rtl ? 1.7 : 1.35)),
            ),
            if (m.hasCheckoutLink && m.meta['token'] != null) ...[
              const SizedBox(height: 8),
              InkWell(
                key: ValueKey('link-${m.seq}'),
                onTap: () => onLink(m.meta['token'] as String),
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(color: const Color(0xFF111B21), borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFF2A3942))),
                  child: Row(children: [
                    const Icon(Icons.link, size: 18, color: CC.green),
                    const SizedBox(width: 8),
                    Expanded(child: Text(m.meta['link_label'] as String? ?? 'Complete checkout', style: const TextStyle(color: CC.green, fontWeight: FontWeight.w700))),
                    const Icon(Icons.chevron_right, color: CC.green, size: 18),
                  ]),
                ),
              ),
            ],
            const SizedBox(height: 4),
            Row(mainAxisSize: MainAxisSize.min, children: [
              if (label != null && !out) ...[
                Flexible(child: Text(label, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xFF8696A0), fontSize: 10))),
                const SizedBox(width: 8),
              ],
              Text(hhmm(m.createdAt), style: const TextStyle(color: Color(0xFF8696A0), fontSize: 10.5)),
              if (out) ...[const SizedBox(width: 4), const Icon(Icons.done_all, size: 14, color: Color(0xFF53BDEB))],
            ]),
          ]),
        ),
      ),
    );
  }
}
