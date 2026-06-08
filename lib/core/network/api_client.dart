import 'package:dio/dio.dart';

import 'api_config.dart';
import 'api_exception.dart';
import 'api_result.dart';
import 'token_store.dart';

class ApiClient {
  ApiClient({
    required TokenStore tokenStore,
    ApiConfig config = const ApiConfig(baseUrl: ApiConfig.defaultBaseUrl),
    Dio? dio,
  }) : _tokenStore = tokenStore,
       _dio =
           dio ??
           Dio(
             BaseOptions(
               baseUrl: config.baseUrl,
               connectTimeout: const Duration(seconds: 10),
               receiveTimeout: const Duration(seconds: 20),
               sendTimeout: const Duration(seconds: 20),
               contentType: Headers.jsonContentType,
               responseType: ResponseType.json,
             ),
           ) {
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final token = await _tokenStore.read();
          if (token != null && token.isValid) {
            options.headers[token.name] = token.value;
          }
          handler.next(options);
        },
      ),
    );
  }

  final Dio _dio;
  final TokenStore _tokenStore;

  Future<T> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    T Function(Object? json)? fromJson,
  }) {
    return _request(
      () => _dio.get<Object?>(path, queryParameters: queryParameters),
      fromJson: fromJson,
    );
  }

  Future<T> post<T>(
    String path, {
    Object? data,
    String? idempotencyKey,
    T Function(Object? json)? fromJson,
  }) {
    return _request(
      () => _dio.post<Object?>(
        path,
        data: data,
        options: _options(idempotencyKey),
      ),
      fromJson: fromJson,
    );
  }

  Future<void> postVoid(String path, {Object? data, String? idempotencyKey}) {
    return _requestVoid(
      () => _dio.post<Object?>(
        path,
        data: data,
        options: _options(idempotencyKey),
      ),
    );
  }

  Future<T> put<T>(
    String path, {
    Object? data,
    String? idempotencyKey,
    T Function(Object? json)? fromJson,
  }) {
    return _request(
      () => _dio.put<Object?>(
        path,
        data: data,
        options: _options(idempotencyKey),
      ),
      fromJson: fromJson,
    );
  }

  Future<T> delete<T>(
    String path, {
    Object? data,
    String? idempotencyKey,
    T Function(Object? json)? fromJson,
  }) {
    return _request(
      () => _dio.delete<Object?>(
        path,
        data: data,
        options: _options(idempotencyKey),
      ),
      fromJson: fromJson,
    );
  }

  Future<void> deleteVoid(String path, {Object? data, String? idempotencyKey}) {
    return _requestVoid(
      () => _dio.delete<Object?>(
        path,
        data: data,
        options: _options(idempotencyKey),
      ),
    );
  }

  Future<T> _request<T>(
    Future<Response<Object?>> Function() request, {
    T Function(Object? json)? fromJson,
  }) async {
    try {
      final response = await request();
      return _parseResponse(response, fromJson);
    } on DioException catch (e) {
      final response = e.response;
      if (response?.data is Map<String, dynamic>) {
        final result = ApiResult<Object?>.fromJson(
          response!.data! as Map<String, dynamic>,
          null,
        );
        throw ApiException(
          code: result.code,
          message: result.message,
          statusCode: response.statusCode,
        );
      }
      throw ApiException(
        code: -1,
        message: e.message ?? '网络请求失败',
        statusCode: response?.statusCode,
      );
    }
  }

  Future<void> _requestVoid(
    Future<Response<Object?>> Function() request,
  ) async {
    try {
      final response = await request();
      _parseVoidResponse(response);
    } on DioException catch (e) {
      final response = e.response;
      if (response?.data is Map<String, dynamic>) {
        final result = ApiResult<Object?>.fromJson(
          response!.data! as Map<String, dynamic>,
          null,
        );
        throw ApiException(
          code: result.code,
          message: result.message,
          statusCode: response.statusCode,
        );
      }
      throw ApiException(
        code: -1,
        message: e.message ?? '网络请求失败',
        statusCode: response?.statusCode,
      );
    }
  }

  T _parseResponse<T>(
    Response<Object?> response,
    T Function(Object? json)? fromJson,
  ) {
    final body = response.data;
    if (body is! Map<String, dynamic>) {
      throw ApiException(
        code: -1,
        message: '响应格式不正确',
        statusCode: response.statusCode,
      );
    }

    final result = ApiResult<T>.fromJson(body, fromJson);
    if (!result.isSuccess) {
      throw ApiException(
        code: result.code,
        message: result.message,
        statusCode: response.statusCode,
      );
    }

    return result.data as T;
  }

  void _parseVoidResponse(Response<Object?> response) {
    final body = response.data;
    if (body is! Map<String, dynamic>) {
      throw ApiException(
        code: -1,
        message: '响应格式不正确',
        statusCode: response.statusCode,
      );
    }

    final result = ApiResult<Object?>.fromJson(body, null);
    if (!result.isSuccess) {
      throw ApiException(
        code: result.code,
        message: result.message,
        statusCode: response.statusCode,
      );
    }
  }

  Options? _options(String? idempotencyKey) {
    if (idempotencyKey == null || idempotencyKey.isEmpty) {
      return null;
    }
    return Options(headers: {'Idempotency-Key': idempotencyKey});
  }
}
