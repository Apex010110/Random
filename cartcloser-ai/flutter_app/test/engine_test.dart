// Offline engine: MRD scenarios A-H plus pricing/consent/metrics rules (mirrors backend tests).
import 'dart:convert';
import 'dart:io';

import 'package:cartcloser_ai/core/engine/demo_engine.dart';
import 'package:cartcloser_ai/core/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final seed = jsonDecode(File('assets/seed/demo_seed.json').readAsStringSync()) as Map<String, dynamic>;
  final copy = jsonDecode(File('assets/seed/assistant_copy.json').readAsStringSync()) as Map<String, dynamic>;
  late DateTime now;
  late DemoEngine e;
  const a = 'shp_ayesha';
  const kurta = [
    {'product_id': 'p_linen_kurta', 'size': 'M', 'quantity': 1}
  ];

  setUp(() {
    now = DateTime.utc(2026, 11, 4, 7); // Wed 12:00 PKT
    e = DemoEngine(seed, copy, clock: () => now);
  });

  String cartWith({bool optIn = true, String shopper = a, String city = 'Karachi', List<Map<String, dynamic>> items = kurta}) {
    final id = e.createCart(shopper, items)['id'] as String;
    e.checkoutStarted(shopper, id, city: city, whatsappOptIn: optIn);
    return id;
  }

  Map<String, dynamic> m() => e.metrics();
  Matcher throwsCode(String code) => throwsA(isA<ApiException>().having((x) => x.code, 'code', code));

  test('A: opted-in recovery counts only when the order is placed', () {
    final id = cartWith();
    expect(e.abandon(a, id)['status'], 'scheduled');
    expect(e.triggerDemo(id)['status'], 'sent');
    final conv = e.conversation(a, id);
    expect(conv['channel'], 'whatsapp_sim');
    expect((conv['messages'] as List).first['text'], contains('Reply STOP'));
    final r1 = e.postMessage(a, id, 'Will it arrive in Karachi by Friday?').last;
    expect(r1['text'], contains("can't guarantee Friday"));
    final r2 = e.postMessage(a, id, 'Can I pay COD?').last;
    expect(r2['meta']['cod_result'], 'cod_yes');
    expect(m()['counts']['recovered'], 0);
    e.openRecoveryLink(id, r2['meta']['token']);
    expect(m()['counts']['recovered'], 0);
    final o = e.placeOrder(cartId: id, paymentMethod: 'cod', codConfirmed: true, idempotencyKey: 'o1', recoveryToken: r2['meta']['token']);
    expect(o['attributed'], true);
    expect(o['total_pkr'], 4690);
    final mm = m();
    expect(mm['counts']['recovered'], 1);
    expect(mm['counts']['replied'], 1);
    expect(mm['money']['attributed_recovered_sales_pkr'], 4690);
    expect(mm['rates']['observed_recovery_rate'], {'numerator': 1, 'denominator': 1, 'value': 1.0});
    expect(mm['incremental_lift']['measured'], false);
  });

  test('B: no opt-in -> no outbound; on-site chat still answers', () {
    final id = cartWith(optIn: false);
    final c = e.abandon(a, id);
    expect(c['status'], 'not_eligible');
    expect(c['status_reason'], 'no_consent');
    expect(() => e.triggerDemo(id), throwsCode('not_eligible'));
    expect(e.conversation(a, id)['messages'], isEmpty);
    expect(e.postMessage(a, id, 'Is COD available?').last['intent'], 'cod');
    expect(e.conversation(a, id)['channel'], 'onsite_chat');
    expect(m()['blocked_reasons']['no_consent'], 1);
  });

  test('C: STOP revokes consent and blocks later carts', () {
    final id = cartWith();
    e.abandon(a, id);
    e.triggerDemo(id);
    expect(e.postMessage(a, id, 'STOP').last['intent'], 'opt_out');
    expect(e.consentMe(a)['opted_in'], false);
    final id2 = cartWith(optIn: false, items: [
      {'product_id': 'p_waistcoat', 'size': 'M', 'quantity': 1}
    ]);
    expect(e.abandon(a, id2)['status_reason'], 'opted_out');
    expect(m()['counts']['opt_outs'], 1);
  });

  test('D: out of stock is never fabricated', () {
    final id = cartWith();
    final r = e.postMessage(a, id, 'Is the dupatta in stock?').last;
    expect(r['text'], contains("can't promise a restock"));
    expect(r['meta']['alternative_product_id'], isNotNull);
    expect(e.postMessage(a, id, 'Is L available?').last['text'], contains('L is out of stock'));
    expect(
        () => e.createCart(a, [
              {'product_id': 'p_dupatta', 'size': 'One size', 'quantity': 1}
            ]),
        throwsCode('insufficient_stock'));
  });

  test('E: under-18 safeguard blocks outbound even with opt-in', () {
    final id = cartWith(shopper: 'shp_zara', city: 'Islamabad');
    final c = e.abandon('shp_zara', id);
    expect(c['status_reason'], 'under_18_safeguard');
    expect(() => e.triggerDemo(id), throwsCode('not_eligible'));
  });

  test('F: purchase before the scheduled send cancels it', () {
    final id = cartWith();
    expect(e.abandon(a, id)['status'], 'scheduled');
    final o = e.placeOrder(cartId: id, paymentMethod: 'cod', codConfirmed: true, idempotencyKey: 'o-f', shopperId: a);
    expect(o['attributed'], false);
    final c = e.getCart(a, id);
    expect(c['status'], 'ordered');
    expect(c['recovery_attempts'][0]['reason'], 'already_purchased');
    now = now.add(const Duration(minutes: 30));
    expect(e.tick(), 0);
  });

  test('G: unsupported question escalates; human takeover silences AI', () {
    final id = cartWith();
    e.abandon(a, id);
    e.triggerDemo(id);
    final r = e.postMessage(a, id, 'Can you embroider my name on the sleeve?').last;
    expect(r['intent'], 'unknown');
    expect(r['confidence'], lessThan(.5));
    expect(e.merchantConversations().first['escalated'], true);
    e.humanReply(id, 'Let me check with our tailor.');
    expect(e.postMessage(a, id, 'ok thanks').length, 1);
  });

  test('H: duplicate events do not duplicate sends or orders', () {
    final id = cartWith();
    for (var i = 0; i < 3; i++) {
      e.abandon(a, id, idempotencyKey: 'evt-1');
    }
    expect((e.getCart(a, id)['recovery_attempts'] as List).length, 1);
    expect(e.triggerDemo(id)['status'], 'sent');
    expect(() => e.triggerDemo(id), throwsCode('not_eligible'));
    e.postMessage(a, id, 'COD?', idempotencyKey: 'k');
    e.postMessage(a, id, 'COD?', idempotencyKey: 'k');
    expect((e.conversation(a, id)['messages'] as List).where((x) => x['role'] == 'shopper').length, 1);
    final o1 = e.placeOrder(cartId: id, paymentMethod: 'online_demo', codConfirmed: false, idempotencyKey: 'same', shopperId: a);
    final o2 = e.placeOrder(cartId: id, paymentMethod: 'online_demo', codConfirmed: false, idempotencyKey: 'same', shopperId: a);
    expect(o1['id'], o2['id']);
    expect(() => e.placeOrder(cartId: id, paymentMethod: 'online_demo', codConfirmed: false, idempotencyKey: 'other', shopperId: a),
        throwsCode('already_ordered'));
  });

  test('scheduler sends after the configured delay; quiet hours defer', () {
    final id = cartWith();
    e.abandon(a, id);
    expect(e.tick(), 0);
    now = now.add(const Duration(minutes: 21));
    expect(e.tick(), 1);
    now = DateTime.utc(2026, 11, 4, 18); // 23:00 PKT
    final id2 = cartWith(shopper: 'shp_bilal', city: 'Lahore');
    e.abandon('shp_bilal', id2);
    expect(e.triggerDemo(id2)['status'], 'scheduled');
  });

  test('pricing, promo, COD and discount ceiling', () {
    final id = e.createCart(a, [
      {'product_id': 'p_linen_kurta', 'size': 'M', 'quantity': 2}
    ])['id'];
    expect(e.getCart(a, id)['totals']['shipping_pkr'], 0); // free over 6000
    final c = e.patchCart(a, id, items: kurta, promoCode: 'WELCOME5');
    expect(c['totals']['discount_pkr'], (4490 * .05).round());
    expect(() => e.patchCart(a, id, promoCode: 'FREE100'), throwsCode('invalid_discount'));
    e.checkoutStarted(a, id, city: 'Karachi', whatsappOptIn: true);
    e.patchCart(a, id, promoCode: '');
    final r = e.postMessage(a, id, 'Can I get 20% off?').last;
    expect(r['meta']['discount_pct'], 5);
    expect(r['text'], contains("can't offer 20%"));
    final jid = cartWith(shopper: 'shp_bilal', city: 'Lahore', items: [
      {'product_id': 'p_jhumka', 'size': 'One size', 'quantity': 1}
    ]);
    expect(() => e.placeOrder(cartId: jid, paymentMethod: 'cod', codConfirmed: true, idempotencyKey: 'j', shopperId: 'shp_bilal'), throwsCode('cod_no_product'));
  });

  test('consent record carries version, source, channel, purpose and time', () {
    cartWith();
    final rec = e.consentMe(a)['record'];
    expect(rec['consent_version'], 'v1');
    expect(rec['source'], 'checkout_form');
    expect(rec['channel'], 'whatsapp_sim');
    expect(rec['purpose'], 'checkout_reminders');
    expect(rec['created_at'], isNotNull);
  });

  test('recovery token must match', () {
    final id = cartWith();
    expect(() => e.openRecoveryLink(id, 'forged'), throwsCode('invalid_link'));
    expect(() => e.placeOrder(cartId: id, paymentMethod: 'online_demo', codConfirmed: false, idempotencyKey: 'x', recoveryToken: 'forged'),
        throwsCode('invalid_link'));
  });

  test('metrics match events; audit log redacts phone numbers', () {
    final id = cartWith();
    e.abandon(a, id);
    e.triggerDemo(id);
    e.postMessage(a, id, 'my number is +92 300 1234567 COD?');
    final mm = m();
    expect(mm['counts']['contacted'], 1);
    expect(jsonEncode(mm['recent_events']), isNot(contains('1234567')));
    expect((mm['funnel'] as List).map((f) => f['count']).toList(), [1, 1, 1, 1, 1, 0]);
  });

  test('settings validation and reset', () {
    expect(() => e.patchSettings({'discount_ceiling_pct': 90}), throwsCode('validation_error'));
    expect(() => e.patchSettings({'nope': 1}), throwsCode('validation_error'));
    cartWith();
    e.reset();
    expect(e.merchantCarts(), isEmpty);
  });
}
