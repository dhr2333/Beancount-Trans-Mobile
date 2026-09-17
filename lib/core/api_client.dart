import 'package:dio/dio.dart';

import 'api_exception.dart';
import 'config.dart';
import 'token_store.dart';

/// Dio 单例：统一注入 Bearer、统一把错误转成 [ApiException]、
/// 401 时自动刷新 access 并重放原请求。
class ApiClient {
  ApiClient._() {
    dio = Dio(
      BaseOptions(
        baseUrl: ApiConfig.apiBase,
        connectTimeout: ApiConfig.requestTimeout,
        sendTimeout: ApiConfig.requestTimeout,
        receiveTimeout: ApiConfig.requestTimeout,
        contentType: Headers.jsonContentType,
        responseType: ResponseType.json,
      ),
    );
    dio.interceptors.add(_AuthInterceptor(this));

    // 刷新 token 专用实例：不挂拦截器，避免递归
    _refreshDio = Dio(
      BaseOptions(
        baseUrl: ApiConfig.apiBase,
        connectTimeout: ApiConfig.requestTimeout,
        receiveTimeout: ApiConfig.requestTimeout,
        contentType: Headers.jsonContentType,
      ),
    );
  }

  static final ApiClient instance = ApiClient._();

  /// 主 Dio 实例（SSE 等特殊请求可直接使用）。
  late final Dio dio;

  late final Dio _refreshDio;

  /// 刷新失败（refresh 过期/被清空）时回调，供 AuthStore 退回登录页。
  void Function()? onSessionExpired;

  Future<bool>? _refreshing;

  /// 刷新 access token；并发调用共享同一次刷新。
  Future<bool> refreshAccessToken() {
    return _refreshing ??= _doRefresh().whenComplete(() {
      _refreshing = null;
    });
  }

  Future<bool> _doRefresh() async {
    final refresh = await TokenStore.instance.readRefresh();
    if (refresh == null || refresh.isEmpty) return false;
    try {
      final response = await _refreshDio.post<Object?>(
        '/auth/token/refresh/',
        data: {'refresh': refresh},
      );
      final data = response.data;
      if (data is! Map) return false;
      final access = data['access'];
      if (access is! String || access.isEmpty) return false;
      await TokenStore.instance.saveAccess(access);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<Response<T>> get<T>(
    String path, {
    Map<String, Object?>? query,
    Options? options,
  }) =>
      _run(() => dio.get<T>(path, queryParameters: query, options: options));

  Future<Response<T>> post<T>(
    String path, {
    Object? data,
    Map<String, Object?>? query,
    Options? options,
  }) =>
      _run(() => dio.post<T>(path, data: data, queryParameters: query, options: options));

  Future<Response<T>> patch<T>(
    String path, {
    Object? data,
    Options? options,
  }) =>
      _run(() => dio.patch<T>(path, data: data, options: options));

  Future<Response<T>> delete<T>(String path, {Options? options}) =>
      _run(() => dio.delete<T>(path, options: options));

  Future<Response<T>> _run<T>(Future<Response<T>> Function() action) async {
    try {
      return await action();
    } on DioException catch (error) {
      throw toApiException(error);
    }
  }

  /// 把 Dio 异常转成统一的 [ApiException]。
  ApiException toApiException(DioException error) {
    final inner = error.error;
    if (inner is ApiException) return inner;

    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.transformTimeout:
        return ApiException.timeout();
      case DioExceptionType.badCertificate:
      case DioExceptionType.connectionError:
        return ApiException.network(error);
      case DioExceptionType.cancel:
        return ApiException(message: '请求已取消');
      case DioExceptionType.badResponse:
        return ApiException.fromResponse(
          error.response?.statusCode,
          error.response?.data,
        );
      case DioExceptionType.unknown:
        return ApiException.network(error);
    }
  }
}

class _AuthInterceptor extends Interceptor {
  _AuthInterceptor(this._client);

  final ApiClient _client;

  static const String _retriedFlag = 'auth_retried';
  static const String _skipRefreshFlag = 'skip_auth_refresh';

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final token = TokenStore.instance.accessToken;
    if (token != null && token.isNotEmpty) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final options = err.requestOptions;
    final isRefreshRequest = options.path.contains('/auth/token/refresh/');
    final skipRefresh = options.extra[_skipRefreshFlag] == true;
    final alreadyRetried = options.extra[_retriedFlag] == true;

    if (err.response?.statusCode == 401 &&
        !isRefreshRequest &&
        !skipRefresh &&
        !alreadyRetried) {
      final refreshed = await _client.refreshAccessToken();
      if (refreshed) {
        final retryOptions = options
          ..extra[_retriedFlag] = true
          ..headers['Authorization'] =
              'Bearer ${TokenStore.instance.accessToken ?? ''}';
        try {
          final response = await _client.dio.fetch(retryOptions);
          return handler.resolve(response);
        } on DioException catch (retryError) {
          return handler.next(retryError);
        }
      }
      _client.onSessionExpired?.call();
    }

    handler.next(err);
  }
}
