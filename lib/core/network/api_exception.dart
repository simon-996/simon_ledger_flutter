import '../models/conflict_record.dart';

class ApiException implements Exception {
  const ApiException({
    required this.code,
    required this.message,
    this.statusCode,
    this.data,
    this.conflict,
  });

  final int code;
  final String message;
  final int? statusCode;
  final Object? data;
  final ApiConflictPayload? conflict;

  bool get isConflict =>
      code == 409001 && statusCode == 409 && conflict != null;

  @override
  String toString() {
    return message;
  }
}
