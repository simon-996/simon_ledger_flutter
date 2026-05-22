class ApiException implements Exception {
  const ApiException({
    required this.code,
    required this.message,
    this.statusCode,
  });

  final int code;
  final String message;
  final int? statusCode;

  @override
  String toString() {
    return 'ApiException(code: $code, statusCode: $statusCode, message: $message)';
  }
}
