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
    return ApiResult<T>(
      code: (json['code'] as num?)?.toInt() ?? -1,
      message: json['message']?.toString() ?? '',
      data: fromJsonT == null ? json['data'] as T? : fromJsonT(json['data']),
    );
  }
}
