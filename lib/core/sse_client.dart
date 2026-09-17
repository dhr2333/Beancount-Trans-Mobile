import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';

import 'api_client.dart';
import 'api_exception.dart';
import 'config.dart';

/// 单个 SSE 事件。
class SseEvent {
  const SseEvent({required this.event, required this.data});

  final String event;
  final Map<String, Object?> data;
}

/// SSE 客户端。
///
/// 后端 `/assistant/chat/stream/` 是 **POST**，无法使用 `EventSource`，
/// 因此走 Dio 流式响应 + 手写 `\n\n` 分帧，与 Web 端行为保持一致，
/// 并实现 90s 空闲超时与 401 刷新重试。
class SseClient {
  SseClient._();

  static final SseClient instance = SseClient._();

  static const String _skipAuthRefreshExtra = 'skip_auth_refresh';

  /// 空闲超时错误码。
  static const String codeIdleTimeout = 'SSE_IDLE_TIMEOUT';

  /// 主动取消错误码。
  static const String codeCancelled = 'SSE_CANCELLED';

  /// POST 流式请求（新建消息）。
  Future<void> post(
    String path, {
    Object? data,
    CancelToken? cancelToken,
    required void Function(SseEvent event) onEvent,
  }) =>
      _stream(
        path,
        method: 'POST',
        data: data,
        cancelToken: cancelToken,
        onEvent: onEvent,
      );

  /// GET 流式请求（重连正在生成的回复）。
  Future<void> get(
    String path, {
    CancelToken? cancelToken,
    required void Function(SseEvent event) onEvent,
  }) =>
      _stream(
        path,
        method: 'GET',
        cancelToken: cancelToken,
        onEvent: onEvent,
      );

  Future<void> _stream(
    String path, {
    required String method,
    Object? data,
    CancelToken? cancelToken,
    required void Function(SseEvent event) onEvent,
  }) async {
    var attempt = 0;
    while (true) {
      attempt += 1;
      try {
        await _consume(
          path,
          method: method,
          data: data,
          cancelToken: cancelToken,
          onEvent: onEvent,
        );
        return;
      } on DioException catch (error) {
        final status = error.response?.statusCode;
        // 401：刷新一次 access 后重试；仅重试一次。
        if (status == 401 && attempt == 1) {
          final refreshed = await ApiClient.instance.refreshAccessToken();
          if (refreshed) continue;
          throw ApiException(
            statusCode: 401,
            message: '登录已过期，请重新登录',
          );
        }
        if (error.type == DioExceptionType.cancel) {
          throw ApiException(code: codeCancelled, message: '请求已取消');
        }
        throw ApiClient.instance.toApiException(error);
      }
    }
  }

  Future<void> _consume(
    String path, {
    required String method,
    Object? data,
    CancelToken? cancelToken,
    required void Function(SseEvent event) onEvent,
  }) async {
    final token = CancelToken();
    var idleTimedOut = false;
    Timer? idleTimer;

    void cancelByUser() => token.cancel('cancelled');
    cancelToken?.whenCancel.then((_) => cancelByUser());

    void resetIdleTimer() {
      idleTimer?.cancel();
      idleTimer = Timer(ApiConfig.sseIdleTimeout, () {
        idleTimedOut = true;
        token.cancel('idle-timeout');
      });
    }

    resetIdleTimer();

    try {
      final options = Options(
        method: method,
        responseType: ResponseType.stream,
        headers: const {'Accept': 'text/event-stream'},
        receiveTimeout: Duration.zero,
        sendTimeout: ApiConfig.requestTimeout,
        extra: const {_skipAuthRefreshExtra: true},
      );

      final response = await ApiClient.instance.dio.request<ResponseBody>(
        path,
        data: data,
        cancelToken: token,
        options: options,
      );

      final body = response.data;
      if (body == null) {
        throw ApiException(message: '流式响应不可用');
      }

      final lines = body.stream
          .cast<List<int>>()
          .transform(utf8.decoder)
          .transform(const LineSplitter());

      final dataLines = <String>[];
      var eventName = 'message';

      await for (final line in lines) {
        resetIdleTimer();
        if (line.isEmpty) {
          if (dataLines.isNotEmpty) {
            _emit(eventName, dataLines.join('\n'), onEvent);
          }
          dataLines.clear();
          eventName = 'message';
          continue;
        }
        if (line.startsWith('event:')) {
          eventName = line.substring(6).trim();
        } else if (line.startsWith('data: ')) {
          dataLines.add(line.substring(6));
        } else if (line.startsWith('data:')) {
          dataLines.add(line.substring(5));
        }
      }

      // 流结束时可能残留最后一帧（无结尾空行）
      if (dataLines.isNotEmpty) {
        _emit(eventName, dataLines.join('\n'), onEvent);
      }
    } on DioException catch (error) {
      if (error.type == DioExceptionType.cancel) {
        if (idleTimedOut) {
          throw ApiException(
            code: codeIdleTimeout,
            message: '响应超时，请重试',
          );
        }
        throw ApiException(code: codeCancelled, message: '请求已取消');
      }
      rethrow;
    } finally {
      idleTimer?.cancel();
    }
  }

  void _emit(
    String eventName,
    String rawData,
    void Function(SseEvent event) onEvent,
  ) {
    final trimmed = rawData.trim();
    if (trimmed.isEmpty) return;
    final decoded = jsonDecode(trimmed);
    if (decoded is! Map) return;
    onEvent(SseEvent(event: eventName, data: decoded.cast<String, Object?>()));
  }
}
