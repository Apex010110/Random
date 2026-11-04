import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../../core/models.dart';
import '../../core/providers.dart';
import '../../shared/widgets.dart';
import '../merchant/merchant_app.dart';
import '../shopper/shopper_app.dart';
import 'scenarios.dart';

class GuideState {
  final int scenario, step;
  final String? note;
  final bool running;
  const GuideState({this.scenario = 0, this.step = 0, this.note, this.running = false});
  GuideState copyWith({int? scenario, int? step, String? note, bool clearNote = false, bool? running}) => GuideState(
        scenario: scenario ?? this.scenario,
        step: step ?? this.step,
        note: clearNote ? null : (note ?? this.note),
        running: running ?? this.running,
      );
}

class GuideNotifier extends Notifier<GuideState> {
  @override
  GuideState build() => const GuideState();
  void set(GuideState s) => state = s;
}

final guideProvider = NotifierProvider<GuideNotifier, GuideState>(GuideNotifier.new);

/// 16:9 judge mode: guided steps on top, shopper phone + live merchant dashboard side by side.
class JudgeScreen extends ConsumerStatefulWidget {
  const JudgeScreen({super.key});
  @override
  ConsumerState<JudgeScreen> createState() => _JudgeScreenState();
}

class _JudgeScreenState extends ConsumerState<JudgeScreen> with SingleTickerProviderStateMixin {
  late final _tabs = TabController(length: 2, vsync: this);

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _runStep() async {
    final g = ref.read(guideProvider);
    final sc = scenarios[g.scenario];
    final step = sc.steps[g.step];
    ref.read(guideProvider.notifier).set(g.copyWith(running: true, clearNote: true));
    _tabs.animateTo(step.focus == GuideFocus.shopper ? 0 : 1);
    String? note;
    try {
      note = await step.run?.call(GuideCtx(ref, sc.personaId));
    } on ApiException catch (e) {
      note = e.message;
    } catch (e) {
      note = 'Step failed: $e';
    }
    final next = (g.step + 1).clamp(0, sc.steps.length - 1);
    ref.read(guideProvider.notifier).set(GuideState(scenario: g.scenario, step: g.step == sc.steps.length - 1 ? g.step : next, note: note));
  }

  void _go(int step) {
    final g = ref.read(guideProvider);
    ref.read(guideProvider.notifier).set(g.copyWith(step: step.clamp(0, scenarios[g.scenario].steps.length - 1), clearNote: true));
  }

  void _pickScenario(int i) {
    ref.read(guideProvider.notifier).set(GuideState(scenario: i));
    ref.read(personaProvider.notifier).set(scenarios[i].personaId);
    ref.read(shopperNavProvider.notifier).root(const StorePage());
    ref.read(merchantNavProvider.notifier).closeCart();
  }

  @override
  Widget build(BuildContext context) {
    final g = ref.watch(guideProvider);
    final sc = scenarios[g.scenario];
    final step = sc.steps[g.step];
    final wide = MediaQuery.sizeOf(context).width >= 1100;
    final repo = ref.watch(repositoryProvider);

    final panel = Container(
      color: CC.navy,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          IconButton(tooltip: 'Home', icon: const Icon(Icons.home_outlined), onPressed: () => GoRouter.of(context).go('/')),
          const LogoMark(size: 26),
          const SizedBox(width: 8),
          const Text('Guided judge demo', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          const SizedBox(width: 10),
          DemoBadge(text: repo.isOffline ? 'OFFLINE · SIMULATED MESSAGING' : 'BACKEND · SIMULATED MESSAGING', color: repo.isOffline ? CC.amber : CC.cyan),
          const Spacer(),
          SizedBox(
            width: wide ? 380 : 200,
            child: DropdownButtonFormField<int>(
              key: const ValueKey('scenario-picker'),
              initialValue: g.scenario,
              isExpanded: true,
              isDense: true,
              decoration: const InputDecoration(labelText: 'Scenario', isDense: true),
              items: [for (var i = 0; i < scenarios.length; i++) DropdownMenuItem(value: i, child: Text(scenarios[i].title, overflow: TextOverflow.ellipsis))],
              onChanged: (v) => _pickScenario(v ?? 0),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(tooltip: 'Reset demo', icon: const Icon(Icons.restart_alt), onPressed: () async {
            await confirmReset(context, ref);
            _pickScenario(g.scenario);
          }),
        ]),
        const SizedBox(height: 6),
        Text(sc.summary, style: const TextStyle(color: CC.muted, fontSize: 12.5)),
        const SizedBox(height: 10),
        Row(children: [
          Text('Step ${g.step + 1} of ${sc.steps.length}', style: const TextStyle(color: CC.cyan, fontWeight: FontWeight.w700, fontSize: 12.5)),
          const SizedBox(width: 12),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: TweenAnimationBuilder<double>(
                tween: Tween(end: (g.step + 1) / sc.steps.length),
                duration: motion(context, ref, 300),
                builder: (_, v, _) => LinearProgressIndicator(value: v, minHeight: 6, backgroundColor: CC.navy2, color: CC.cyan),
              ),
            ),
          ),
        ]),
        const SizedBox(height: 10),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(step.title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              if (step.body.isNotEmpty) ...[const SizedBox(height: 4), Text(step.body, style: const TextStyle(color: CC.muted, fontSize: 13, height: 1.35))],
              if (g.note != null) ...[
                const SizedBox(height: 6),
                Text(g.note!, style: const TextStyle(color: CC.amber, fontSize: 12.5, fontWeight: FontWeight.w600)),
              ],
            ]),
          ),
          const SizedBox(width: 12),
          OutlinedButton(onPressed: g.step == 0 ? null : () => _go(g.step - 1), child: const Text('Back')),
          const SizedBox(width: 8),
          FilledButton.icon(
            key: const ValueKey('guide-run'),
            icon: g.running ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: CC.ink)) : const Icon(Icons.play_arrow),
            label: const Text('Do this step'),
            onPressed: g.running ? null : _runStep,
          ),
          const SizedBox(width: 8),
          OutlinedButton(onPressed: g.step >= sc.steps.length - 1 ? null : () => _go(g.step + 1), child: const Text('Next')),
        ]),
      ]),
    );

    final phone = Center(
      child: LayoutBuilder(builder: (_, box) {
        final h = (box.maxHeight - 24).clamp(560.0, 860.0);
        final w = (h * 0.47).clamp(340.0, 400.0);
        return Container(
          width: w + 16,
          height: h,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: const Color(0xFF151D33),
            borderRadius: BorderRadius.circular(40),
            border: Border.all(color: const Color(0xFF3A4766), width: 1.5),
            boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 40, offset: Offset(0, 16))],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(32),
            child: MediaQuery(
              data: MediaQuery.of(context).copyWith(size: Size(w, h - 16), padding: const EdgeInsets.only(top: 8)),
              child: const ScaffoldMessenger(child: ShopperApp(embedded: true)),
            ),
          ),
        );
      }),
    );

    return Scaffold(
      body: SafeArea(
        child: Column(children: [
          panel,
          const Divider(),
          Expanded(
            child: wide
                ? Row(children: [
                    SizedBox(width: 460, child: Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: phone)),
                    const VerticalDivider(width: 1),
                    const Expanded(child: MerchantApp(embedded: true)),
                  ])
                : Column(children: [
                    TabBar(controller: _tabs, tabs: const [Tab(text: 'Shopper phone'), Tab(text: 'Merchant dashboard')]),
                    Expanded(
                      child: TabBarView(controller: _tabs, physics: const NeverScrollableScrollPhysics(), children: const [
                        ScaffoldMessenger(child: ShopperApp(embedded: true)),
                        MerchantApp(),
                      ]),
                    ),
                  ]),
          ),
        ]),
      ),
    );
  }
}
