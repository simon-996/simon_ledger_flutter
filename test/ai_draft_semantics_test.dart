import 'package:flutter_test/flutter_test.dart';
import 'package:simon_ledger_flutter/core/models/ai_draft.dart';

Map<String, dynamic> draftJson() => {
  'sourceText': '和陈欣吃饭，由陈欣付钱',
  'type': 0,
  'amount': 30,
  'currencyCode': 'CNY',
  'categorySuggestion': '餐饮',
  'personUuids': ['remote-person'],
  'payerPersonUuid': 'remote-person',
  'unresolvedNames': <String>[],
};

void main() {
  test('payment decisions and role-specific match provenance survive JSON', () {
    final json = draftJson()
      ..['paymentMode'] = 'person'
      ..['personMatches'] = [
        {
          'sourceName': '陈欣',
          'role': 'payer',
          'personUuid': 'remote-person',
          'matchedName': '陈鑫',
          'approximate': true,
          'candidatePersonUuids': ['remote-person'],
        },
      ];
    final restored = AiDraft.fromJson(json).toJson();
    expect(restored['paymentMode'], 'person');
    expect(restored['personMatches'], json['personMatches']);
  });

  test('legacy missing payer remains an unconfirmed payment decision', () {
    final json = draftJson()..remove('payerPersonUuid');
    expect(AiDraft.fromJson(json).toJson()['paymentMode'], 'unconfirmed');
  });

  test('legacy existing payer can restore personal payment', () {
    expect(AiDraft.fromJson(draftJson()).toJson()['paymentMode'], 'person');
  });
}
