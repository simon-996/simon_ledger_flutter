import 'api_exception.dart';

class FriendlyError {
  const FriendlyError._();

  static String message(Object? error, {String fallback = '操作失败，请稍后重试'}) {
    if (error == null) {
      return fallback;
    }

    if (error is FormatException) {
      return error.message;
    }

    if (error is ApiException) {
      return _apiMessage(error, fallback: fallback);
    }

    return _sanitize(error.toString(), fallback: fallback);
  }

  static String syncMessage(String? errorText) {
    if (errorText == null || errorText.trim().isEmpty) {
      return '网络恢复后会自动重试。';
    }
    return _sanitize(errorText, fallback: '网络恢复后会自动重试。');
  }

  static String _apiMessage(ApiException error, {required String fallback}) {
    switch (error.code) {
      case 400001:
        return _sanitize(error.message, fallback: '提交内容不正确，请检查后重试');
      case 401001:
        return '登录状态已失效，请重新登录';
      case 403001:
        return '当前账号没有权限执行此操作';
      case 404001:
        return '相关数据不存在，刷新后再试';
      case 409001:
        return '该流水已在其他设备更新，请刷新后重新提交';
      case 500001:
        return '服务暂时不可用，请稍后重试';
      case -1:
        return '网络连接不稳定，请检查网络后重试';
      default:
        return _sanitize(error.message, fallback: fallback);
    }
  }

  static String _sanitize(String raw, {required String fallback}) {
    final value = raw.trim();
    if (value.isEmpty) {
      return fallback;
    }

    final normalized = value
        .replaceFirst(RegExp(r'^Exception:\s*'), '')
        .replaceFirst(RegExp(r'^FormatException:\s*'), '')
        .replaceFirst(RegExp(r'^ApiException:\s*'), '')
        .trim();

    if (normalized == '系统错误') {
      return '服务暂时不可用，请稍后重试';
    }
    if (normalized.contains('数据冲突')) {
      return '该流水已在其他设备更新，请刷新后重新提交';
    }

    final technicalPatterns = [
      'DioException',
      'SocketException',
      'TimeoutException',
      'HandshakeException',
      'XMLHttpRequest',
      'Connection refused',
      'Connection reset',
      'Failed host lookup',
      'null check operator',
      'Null check operator',
      'NoSuchMethodError',
      'TypeError',
      'type ',
      'stack trace',
      'field list',
      'SQL',
      'Exception:',
    ];

    if (technicalPatterns.any(normalized.contains)) {
      return fallback;
    }

    if (normalized.length > 80) {
      return fallback;
    }

    return normalized;
  }
}
