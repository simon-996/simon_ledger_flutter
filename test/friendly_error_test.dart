import 'package:flutter_test/flutter_test.dart';
import 'package:simon_ledger_flutter/core/network/api_exception.dart';
import 'package:simon_ledger_flutter/core/network/friendly_error.dart';

void main() {
  test('FriendlyError describes transaction API conflicts clearly', () {
    const error = ApiException(code: 409001, message: '数据冲突');

    expect(FriendlyError.message(error), '该流水已在其他设备更新，请刷新后重新提交');
  });

  test('FriendlyError describes stored transaction conflicts clearly', () {
    expect(FriendlyError.syncMessage('数据冲突'), '该流水已在其他设备更新，请刷新后重新提交');
  });
}
