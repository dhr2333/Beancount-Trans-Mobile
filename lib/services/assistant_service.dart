import 'package:dio/dio.dart';

import '../core/api_client.dart';
import '../core/sse_client.dart';
import '../models/assistant.dart';

/// Copilot（AI 助手）服务，对应后端 `/api/assistant/`。
class AssistantService {
  AssistantService._();

  static final AssistantService instance = AssistantService._();

  final ApiClient _client = ApiClient.instance;

  Future<AssistantStatus> status() async {
    final response = await _client.get<Object?>('/assistant/status/');
    final data = response.data;
    return data is Map
        ? AssistantStatus.fromJson(data.cast<String, Object?>())
        : const AssistantStatus();
  }

  Future<List<ChatSessionSummary>> listSessions({String search = ''}) async {
    final response = await _client.get<Object?>(
      '/assistant/sessions/',
      query: search.trim().isEmpty ? null : {'search': search.trim()},
    );
    final data = response.data;
    if (data is! List) return const [];
    return data
        .whereType<Map>()
        .map((e) => ChatSessionSummary.fromJson(e.cast<String, Object?>()))
        .toList();
  }

  Future<ChatSessionDetail> getSession(String id) async {
    final response = await _client.get<Object?>('/assistant/sessions/$id/');
    final data = response.data;
    return ChatSessionDetail.fromJson(
      data is Map ? data.cast<String, Object?>() : const {},
    );
  }

  Future<void> renameSession(String id, String title) async {
    await _client.patch<Object?>(
      '/assistant/sessions/$id/',
      data: {'title': title},
    );
  }

  Future<void> deleteSession(String id) async {
    await _client.delete<Object?>('/assistant/sessions/$id/');
  }

  /// 新建消息并发起 SSE 流式对话。
  Future<void> sendStream({
    required String content,
    String? sessionId,
    String? editMessageId,
    bool deepThink = false,
    CancelToken? cancelToken,
    required void Function(SseEvent event) onEvent,
  }) {
    return SseClient.instance.post(
      '/assistant/chat/stream/',
      data: {
        if (sessionId != null && sessionId.isNotEmpty) 'session_id': sessionId,
        'content': content,
        'show_bql': false,
        'deep_think': deepThink,
        if (editMessageId != null && editMessageId.isNotEmpty)
          'edit_message_id': editMessageId,
      },
      cancelToken: cancelToken,
      onEvent: onEvent,
    );
  }

  /// 重连正在生成的回复（进入历史会话时使用）。
  Future<void> reconnectStream(
    String assistantMessageId, {
    CancelToken? cancelToken,
    required void Function(SseEvent event) onEvent,
  }) {
    return SseClient.instance.get(
      '/assistant/chat/stream/$assistantMessageId/',
      cancelToken: cancelToken,
      onEvent: onEvent,
    );
  }

  /// 停止生成。
  Future<void> stopMessage(String messageId) async {
    await _client.post<Object?>('/assistant/messages/$messageId/stop/');
  }

  /// 提交 / 取消点赞点踩，返回服务端保存的 rating。
  Future<String?> submitFeedback({
    required String messageId,
    required String? rating,
    required String userMessage,
    required String assistantReply,
    List<QueryRecord> queries = const [],
    String comment = '',
  }) async {
    final response = await _client.post<Object?>(
      '/assistant/feedback/',
      data: {
        'message_id': messageId,
        'rating': rating,
        'user_message': userMessage,
        'assistant_reply': assistantReply,
        'queries': queries.map((e) => e.toJson()).toList(),
        'comment': comment,
      },
    );
    final data = response.data;
    if (data is Map) {
      final value = data['rating'];
      return value is String && value.isNotEmpty ? value : null;
    }
    return null;
  }
}
