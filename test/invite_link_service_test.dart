import 'package:flutter_test/flutter_test.dart';
import 'package:simon_ledger_flutter/core/services/invite_link_service.dart';

void main() {
  test('extracts invitation code from supported https link', () {
    final code = InviteLinks.codeFromUri(
      Uri.parse('https://ledger.simon996.com/invite/abcd1234'),
    );

    expect(code, 'ABCD1234');
  });

  test('rejects invitation links from another domain', () {
    final code = InviteLinks.codeFromUri(
      Uri.parse('https://example.com/invite/ABCD1234'),
    );

    expect(code, isNull);
  });

  test('extracts invitation code from copied share text', () {
    final text = InviteLinks.shareText(ledgerName: '旅行账本', code: 'abcd1234');

    expect(text, contains('邀请码：ABCD1234'));
    expect(text, contains('https://ledger.simon996.com/invite/ABCD1234'));
    expect(InviteLinks.codeFromText(text), 'ABCD1234');
  });

  test('extracts a raw invitation code from clipboard text', () {
    expect(InviteLinks.codeFromText('  abcd1234  '), 'ABCD1234');
  });
}
