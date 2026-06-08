abstract final class InviteLinks {
  static const websiteOrigin = 'https://ledger.simon996.com';

  static final _codePattern = RegExp(r'^[A-Z0-9]{8}$');
  static final _linkPattern = RegExp(
    r'https?://ledger\.simon996\.com/invite/([a-z0-9]{8})',
    caseSensitive: false,
  );
  static final _textPattern = RegExp(
    r'邀请码\s*[：:]\s*([a-z0-9]{8})',
    caseSensitive: false,
  );

  static String urlForCode(String code) {
    return '$websiteOrigin/invite/${normalizeCode(code)}';
  }

  static String shareText({required String ledgerName, required String code}) {
    final normalizedCode = normalizeCode(code);
    return '邀请你加入 Simon Ledger 账本“$ledgerName”\n'
        '邀请码：$normalizedCode\n'
        '点击查看：${urlForCode(normalizedCode)}';
  }

  static String? codeFromUri(Uri uri) {
    if (uri.scheme != 'http' && uri.scheme != 'https') return null;
    if (uri.host.toLowerCase() != 'ledger.simon996.com') return null;
    if (uri.pathSegments.length != 2 || uri.pathSegments.first != 'invite') {
      return null;
    }
    return tryNormalizeCode(uri.pathSegments.last);
  }

  static String? codeFromRoute(String? route) {
    if (route == null) return null;
    final uri = Uri.tryParse(route);
    if (uri == null || uri.pathSegments.length != 2) return null;
    if (uri.pathSegments.first != 'invite') return null;
    return tryNormalizeCode(uri.pathSegments.last);
  }

  static String? codeFromText(String text) {
    final trimmed = text.trim();
    final rawCode = tryNormalizeCode(trimmed);
    if (rawCode != null) return rawCode;
    final linkMatch = _linkPattern.firstMatch(trimmed);
    if (linkMatch != null) return tryNormalizeCode(linkMatch.group(1));
    final textMatch = _textPattern.firstMatch(trimmed);
    return tryNormalizeCode(textMatch?.group(1));
  }

  static String normalizeCode(String value) {
    final code = tryNormalizeCode(value);
    if (code == null) {
      throw FormatException('邀请码格式不正确');
    }
    return code;
  }

  static String? tryNormalizeCode(String? value) {
    final code = value?.trim().toUpperCase();
    if (code == null || !_codePattern.hasMatch(code)) return null;
    return code;
  }
}

abstract final class InviteClipboardMemory {
  static String? _ignoredCode;

  static void ignore(String code) {
    _ignoredCode = InviteLinks.tryNormalizeCode(code);
  }

  static bool consumeIgnored(String code) {
    final normalized = InviteLinks.tryNormalizeCode(code);
    if (normalized == null || normalized != _ignoredCode) return false;
    _ignoredCode = null;
    return true;
  }
}
