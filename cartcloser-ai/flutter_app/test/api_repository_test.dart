// Backend mode: drives the real FastAPI server through ApiRepository.
// Skipped unless CARTCLOSER_BACKEND is set, e.g.
//   CARTCLOSER_BACKEND=http://localhost:8000 flutter test test/api_repository_test.dart
import 'dart:io';

import 'package:cartcloser_ai/core/api_repository.dart';
import 'package:cartcloser_ai/core/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final url = Platform.environment['CARTCLOSER_BACKEND'];
  const personas = [
    Persona('shp_ayesha', 'Ayesha', '', 'Karachi', 'adult', ''),
    Persona('shp_bilal', 'Bilal', '', 'Lahore', 'adult', ''),
    Persona('shp_zara', 'Zara', '', 'Islamabad', 'under_18', ''),
  ];

  test('acceptance path against the live backend', () async {
    final repo = ApiRepository(baseUrl: url!, merchantToken: 'demo-merchant-token', personas: personas);
    await repo.reset();
    await repo.patchSettings({'quiet_hours_enabled': false});
    final c0 = await repo.createCart('shp_ayesha', [
      {'product_id': 'p_linen_kurta', 'size': 'M', 'quantity': 1}
    ]);
    await repo.checkoutStarted('shp_ayesha', c0.id, city: 'Karachi', paymentMethod: 'cod', optIn: true);
    final c1 = await repo.abandon('shp_ayesha', c0.id, idempotencyKey: 'evt-1');
    expect(c1.status, 'scheduled');
    expect(await repo.triggerRecovery(c0.id), 'sent');
    final r1 = await repo.sendMessage('shp_ayesha', c0.id, 'Will it arrive in Karachi by Friday?');
    expect(r1.last.text, contains("can't guarantee Friday"));
    final r2 = await repo.sendMessage('shp_ayesha', c0.id, 'COD hai?');
    expect(r2.last.language, 'roman');
    final token = r2.last.meta['token'] as String;
    await repo.openRecoveryLink(c0.id, token);
    final o = await repo.placeOrder(cartId: c0.id, paymentMethod: 'cod', codConfirmed: true, idempotencyKey: 'live-order-1', recoveryToken: token);
    expect(o.attributed, isTrue);
    // snapshot (live refresh) reflects the recovery
    await repo.refresh();
    expect(repo.lastError, isNull);
    final s = repo.current!;
    expect(s.metrics.c('recovered'), 1);
    expect(s.metrics.money['attributed_recovered_sales_pkr'], 4690);
    expect(s.conversations[c0.id]!.messages.length, greaterThanOrEqualTo(5));
    // no opt-in -> blocked
    final b = await repo.createCart('shp_bilal', [
      {'product_id': 'p_linen_kurta', 'size': 'M', 'quantity': 1}
    ]);
    await repo.checkoutStarted('shp_bilal', b.id, city: 'Lahore', paymentMethod: 'cod', optIn: false);
    expect((await repo.abandon('shp_bilal', b.id)).statusReason, 'no_consent');
    await expectLater(repo.triggerRecovery(b.id), throwsA(isA<ApiException>().having((e) => e.code, 'code', 'not_eligible')));
    await repo.reset();
    await repo.dispose();
  }, skip: url == null ? 'set CARTCLOSER_BACKEND to run against a live backend' : false);
}
