// Green Logistics fulfillment state machine on the offline engine (mirrors backend/tests/test_fulfillment.py).
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

  Map<String, dynamic> codOrder({String key = 'ful-1'}) {
    final id = e.createCart(a, kurta)['id'] as String;
    e.checkoutStarted(a, id, city: 'Karachi', whatsappOptIn: false, paymentMethod: 'cod');
    return e.placeOrder(cartId: id, paymentMethod: 'cod', codConfirmed: true, idempotencyKey: key, shopperId: a);
  }

  Matcher throwsCode(String code) => throwsA(isA<ApiException>().having((x) => x.code, 'code', code));

  test('new COD order needs confirmation before dispatch', () {
    final o = codOrder();
    expect(o['fulfillment_status'], 'pending_confirmation');
    expect(o['cod_predispatch_confirmed'], false);
    expect(() => e.dispatchOrder(o['id']), throwsCode('illegal_transition'));
  });

  test('confirm then dispatch then deliver', () {
    final o = codOrder();
    final c = e.confirmCod(o['id'], true);
    expect(c['fulfillment_status'], 'ready_to_dispatch');
    expect(c['cod_predispatch_confirmed'], true);
    expect(e.dispatchOrder(o['id'])['fulfillment_status'], 'dispatched');
    final d = e.markDelivered(o['id']);
    expect(d['fulfillment_status'], 'delivered');
    expect(d['ever_delivered'], true);
  });

  test('rejecting confirmation holds, not cancels, by default', () {
    final o = codOrder();
    final r = e.confirmCod(o['id'], false);
    expect(r['fulfillment_status'], 'hold');
    expect(r['cod_predispatch_confirmed'], false);
  });

  test('address correction then release', () {
    final o = codOrder();
    e.confirmCod(o['id'], false);
    final corrected = e.correctAddress(o['id'], 'House 12, Block 3', 'Karachi');
    expect(corrected['delivery_zone'], 'Karachi');
    expect(corrected['fulfillment_status'], 'hold'); // correction does not auto-release
    final released = e.releaseOrder(o['id']);
    expect(released['fulfillment_status'], 'ready_to_dispatch');
  });

  test('duplicate confirmation does not double count', () {
    final o = codOrder();
    e.confirmCod(o['id'], true);
    final before = e.metrics()['green']['counts']['cod_confirmed'];
    expect(() => e.confirmCod(o['id'], true), throwsCode('illegal_transition'));
    final after = e.metrics()['green']['counts']['cod_confirmed'];
    expect(before, 1);
    expect(after, 1);
  });

  test('returns and failed attempts are distinct', () {
    final o1 = codOrder(key: 'ful-fail');
    e.confirmCod(o1['id'], true);
    e.dispatchOrder(o1['id']);
    e.markFailedAttempt(o1['id'], 'no answer');

    final o2 = codOrder(key: 'ful-return');
    e.confirmCod(o2['id'], true);
    e.dispatchOrder(o2['id']);
    e.markDelivered(o2['id']);
    e.markReturned(o2['id'], 'wrong size');

    final g = e.metrics()['green'];
    expect(g['counts']['failed_attempt'], 1);
    expect(g['counts']['returned'], 1);
  });

  test('online_demo orders skip COD confirmation', () {
    final id = e.createCart(a, kurta)['id'] as String;
    e.checkoutStarted(a, id, city: 'Karachi', whatsappOptIn: false, paymentMethod: 'online_demo');
    final o = e.placeOrder(cartId: id, paymentMethod: 'online_demo', codConfirmed: false, idempotencyKey: 'ful-online', shopperId: a);
    expect(o['fulfillment_status'], 'ready_to_dispatch');
  });

  test('illustrative estimate requires an explicit assumption and never moves observed counts', () {
    final o = codOrder();
    e.confirmCod(o['id'], false); // -> hold
    var g = e.metrics()['green'];
    expect(g['counts']['held_or_cancelled'], 1);
    expect(g['estimates']['estimated_avoided_attempts'], isNull);

    e.patchAssumptions({'assumed_failure_probability_without_intervention': 0.4});
    g = e.metrics()['green'];
    expect(g['estimates']['estimated_avoided_attempts'], closeTo(0.4, 1e-9));
    expect(g['counts']['held_or_cancelled'], 1);
  });

  test('size question is tracked on the order', () {
    final id = e.createCart(a, kurta)['id'] as String;
    e.postMessage(a, id, 'What size should I get?');
    e.checkoutStarted(a, id, city: 'Karachi', whatsappOptIn: false, paymentMethod: 'cod');
    final o = e.placeOrder(cartId: id, paymentMethod: 'cod', codConfirmed: true, idempotencyKey: 'ful-size', shopperId: a);
    expect(o['size_question_resolved'], true);
  });
}
