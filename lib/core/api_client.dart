import 'package:dio/dio.dart';

import 'api_exception.dart';
import 'config.dart';
import 'jwt.dart';
import 'token_store.dart';

/// access token 续期结果。
enum RefreshResult {
  /// 续期成功；新的 access（以及后端返回的新 refresh）已保存。
  success,

  /// refresh 缺失或被后端明确拒绝（400/401/403）：登录态确实失效，需要重新登录。
  invalid,

  /// 网络 / 超时 / 5xx / 响应异常：登录态仍然有效，稍后可重试。
  transient,
}

/// Dio 单例：统一注入 Bearer、统一把错误转成 [ApiException]、
/// access 临近过期时主动续期，401 时自动刷新并重放原请求。
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

  Future<RefreshResult>? _refreshing;

  /// 续期 access token；并发调用共享同一次刷新。
  Future<RefreshResult> refreshAccessToken() {
    return _refreshing ??= _doRefresh().whenComplete(() {
      _refreshing = null;
    });
  }

  Future<RefreshResult> _doRefresh() async {
    final store = TokenStore.instance;
    final refresh = await store.readRefresh();
    if (refresh == null || refresh.isEmpty) return RefreshResult.invalid;
    try {
      final response = await _refreshDio.post<Object?>(
        '/auth/token/refresh/',
        data: {'refresh': refresh},
      );
      final data = response.data;
      if (data is! Map) return RefreshResult.transient;
      final access = data['access'];
      if (access is! String || access.isEmpty) return RefreshResult.transient;
      // 后端开启了滑动续期：必须保存返回的新 refresh，否则窗口无法顺延
      final rotated = data['refresh'];
      await store.saveTokens(
        access: access,
        refresh: rotated is String && rotated.isNotEmpty ? rotated : refresh,
      );
      return RefreshResult.success;
    } on DioException catch (error) {
      final status = error.response?.statusCode;
      if (status == 400 || status == 401 || status == 403) {
        return RefreshResult.invalid;
      }
      // 5xx、超时、连接失败等：不要清空登录态
      return RefreshResult.transient;
    } catch (_) {
      return RefreshResult.transient;
    }
  }

  Future<Response<T>> get<T>(
    String path, {
    Map<String, Object?>? query,
    Options? options,
  }) => _run(() => dio.get<T>(path, queryParameters: query, options: options));

  Future<Response<T>> post<T>(
    String path, {
    Object? data,
    Map<String, Object?>? query,
    Options? options,
  }) => _run(
    () =>
        dio.post<T>(path, data: data, queryParameters: query, options: options),
  );

  Future<Response<T>> patch<T>(String path, {Object? data, Options? options}) =>
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
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    final store = TokenStore.instance;
    final token = store.accessToken;
    final skipRefresh = options.extra[_skipRefreshFlag] == true;

    // access 临近过期时提前续期，避免依赖 401 往返；
    // SSE 自带刷新重试逻辑、匿名态无 refresh，均不在此续期。
    if (!skipRefresh &&
        token != null &&
        token.isNotEmpty &&
        store.refreshToken != null &&
        isJwtExpiringSoon(token)) {
      await _client.refreshAccessToken();
    }

    final current = store.accessToken;
    if (current != null && current.isNotEmpty) {
      options.headers['Authorization'] = 'Bearer $current';
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
      switch (await _client.refreshAccessToken()) {
        case RefreshResult.success:
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
        case RefreshResult.invalid:
          // refresh 确实失效：清空本地登录态并退回登录页
          _client.onSessionExpired?.call();
          return handler.next(err);
        case RefreshResult.transient:
          // 网络 / 服务端临时故障：保留登录态，只提示可重试
          return handler.reject(
            DioException(
              requestOptions: options,
              error: ApiException(message: '网络异常，请稍后重试'),
              type: DioExceptionType.unknown,
            ),
          );
      }
    }

    handler.next(err);
  }
}
