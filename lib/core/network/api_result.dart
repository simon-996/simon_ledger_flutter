class ApiResult<T> {
  const ApiResult({
    required this.code,
    required this.message,
    required this.data,
  });

  final int code;
  final String message;
  final T? data;

  bool get isSuccess => code == 0;

  factory ApiResult.fromJson(
    Map<String, dynamic> json,
    T Function(Object? json)? fromJsonT,
  ) {
    final code = (json['code'] as num?)?.toInt() ?? -1;
    final data = json['data'];
    return ApiResult<T>(
      code: code,
      message: json['message']?.toString() ?? '',
      data: code == 0
          ? (fromJsonT == null ? data as T? : fromJsonT(data))
          : null,
    );
  }
}
