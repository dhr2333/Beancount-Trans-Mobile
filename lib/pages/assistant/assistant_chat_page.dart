import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../core/api_exception.dart';
import '../../core/format.dart';
import '../../core/sse_client.dart';
import '../../models/assistant.dart';
import '../../services/assistant_service.dart';
import '../../services/todo_service.dart';
import '../../widgets/status_chip.dart';
import '../fava_page.dart';
import '../profile_page.dart';
import '../reconciliation/reconciliation_form_page.dart';
import '../review/review_list_page.dart';
import '../todo/todo_list_page.dart';
import 'assistant_drawer.dart';

/// 空白会话页展示的示例问题。
const List<String> kExampleQuestions = [
  '提供一份消费洞察',
  '有什么令人意外的消费发现？',
  '帮我写一份月度总结',
  '最近有哪些大额消费？',
];

/// Copilot 对话页：消息流 + SSE 流式生成。
///
/// 事件处理状态机照搬 Web 端
/// `useAssistantChat.ts` 的 `handleStreamEvent`。
class AssistantChatPage extends StatefulWidget {
  const AssistantChatPage({super.key, this.sessionId});

  /// 为空表示新建会话。
  final String? sessionId;

  @override
  State<AssistantChatPage> createState() => _AssistantChatPageState();
}

class _AssistantChatPageState extends State<AssistantChatPage> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final TextEditingController _input = TextEditingController();
  final TextEditingController _sessionSearch = TextEditingController();
  final ScrollController _scroll = ScrollController();

  final List<ChatMessage> _messages = [];
  String _sessionId = '';
  String _title = '';
  AssistantStatus? _status;
  String? _error;

  bool _loading = true;
  bool _sending = false;
  bool _deepThink = false;

  // ------------------------------------------------------------ 抽屉数据
  List<ChatSessionSummary> _sessions = const [];
  bool _drawerLoading = false;
  String? _drawerError;
  int _todoBadge = 0;

  CancelToken? _cancelToken;
  int _activeRequestId = 0;
  int _idSeed = 0;

  @override
  void initState() {
    super.initState();
    _sessionId = widget.sessionId ?? '';
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  @override
  void dispose() {
    _cancelToken?.cancel();
    _input.dispose();
    _sessionSearch.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    await _loadStatus();
    // 抽屉数据（会话列表 + 待办徽标）不阻塞主流程
    _refreshDrawerData();
    if (_sessionId.isNotEmpty) {
      await _loadSession(_sessionId);
    } else {
      setState(() => _loading = false);
    }
  }

  /// 拉取抽屉所需的会话列表与待办徽标数。
  Future<void> _refreshDrawerData() async {
    if (!mounted) return;
    setState(() {
      _drawerLoading = true;
      _drawerError = null;
    });
    try {
      final results = await Future.wait<Object>([
        AssistantService.instance.listSessions(search: _sessionSearch.text),
        TodoService.instance.badgeCount(),
      ]);
      if (!mounted) return;
      setState(() {
        _sessions = results[0] as List<ChatSessionSummary>;
        _todoBadge = results[1] as int;
      });
    } on ApiException catch (error) {
      if (mounted) setState(() => _drawerError = error.message);
    } finally {
      if (mounted) setState(() => _drawerLoading = false);
    }
  }

  Future<void> _loadStatus() async {
    try {
      final status = await AssistantService.instance.status();
      if (mounted) setState(() => _status = status);
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    }
  }

  Future<void> _loadSession(String id) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final detail = await AssistantService.instance.getSession(id);
      if (!mounted) return;
      final messages = detail.messages.map(ChatMessage.fromStored).toList();
      setState(() {
        // 记录当前会话，后续提问才会写入该会话。
        _sessionId = id;
        _title = detail.title;
        _messages
          ..clear()
          ..addAll(messages);
      });

      final last = messages.isEmpty ? null : messages.last;
      if (last != null && last.streaming && last.id.isNotEmpty) {
        await _reconnect(last.id);
      }
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ---------------------------------------------------------------- 流式

  /// SSE 事件状态机（与 Web 端 `handleStreamEvent` 一致）。
  void _handleEvent(SseEvent event) {
    if (!mounted) return;
    setState(() => _applyEvent(event));
  }

  void _applyEvent(SseEvent event) {
    final data = event.data;
    switch (event.event) {
      case 'session':
        final userMessageId = data['user_message_id'];
        final user = _lastUserMessage();
        if (user != null &&
            userMessageId is String &&
            userMessageId.isNotEmpty) {
          user.id = userMessageId;
        }
        final assistantMessageId = data['assistant_message_id'];
        final assistant = _lastAssistantMessage();
        if (assistant != null &&
            assistantMessageId is String &&
            assistantMessageId.isNotEmpty) {
          assistant.id = assistantMessageId;
        }
        final newId = '${data['id'] ?? ''}';
        if (_sessionId.isEmpty && newId.isNotEmpty) _sessionId = newId;
        break;

      case 'status':
        _lastAssistantMessage()?.status = '${data['phase'] ?? ''}';
        break;

      case 'reasoning_delta':
        final assistant = _lastAssistantMessage();
        if (assistant == null) break;
        final content = '${data['content'] ?? ''}';
        assistant.reasoning = assistant.reasoning + content;
        assistant.thinking = assistant.thinking + content;
        assistant.thinkingExpanded = true;
        break;

      case 'thinking_set':
        final assistant = _lastAssistantMessage();
        if (assistant == null) break;
        assistant.thinking = '${data['content'] ?? ''}';
        assistant.reasoning = '${data['reasoning'] ?? ''}';
        break;

      case 'tool_end':
        final bql = data['bql'];
        final preview = data['result_preview'];
        if (bql is String &&
            bql.isNotEmpty &&
            preview is String &&
            preview.isNotEmpty) {
          _appendQuery(
            QueryRecord(
              bql: bql,
              resultPreview: preview,
              favaPath: data['fava_path'] is String
                  ? data['fava_path'] as String
                  : null,
              report: data['report'] is Map
                  ? QueryReportLink.fromJson(
                      (data['report'] as Map).cast<String, Object?>(),
                    )
                  : null,
            ),
          );
        }
        break;

      case 'delta':
        final assistant = _lastAssistantMessage();
        if (assistant == null) break;
        assistant.content += '${data['content'] ?? ''}';
        assistant.status = 'writing';
        assistant.thinkingExpanded = false;
        break;

      case 'done':
        final assistant = _lastAssistantMessage();
        if (assistant == null) break;
        assistant.content = '${data['reply'] ?? ''}';
        final rawQueries = data['queries'];
        assistant.queries = rawQueries is List
            ? rawQueries
                  .whereType<Map>()
                  .map((e) => QueryRecord.fromJson(e.cast<String, Object?>()))
                  .toList()
            : [];
        final thinking = '${data['thinking'] ?? ''}';
        final reasoning = '${data['reasoning'] ?? ''}';
        assistant.thinking = thinking.isNotEmpty
            ? thinking
            : assistant.thinking;
        assistant.reasoning = reasoning.isNotEmpty
            ? reasoning
            : assistant.reasoning;
        assistant.streaming = false;
        assistant.status = null;
        assistant.thinkingExpanded = false;
        final assistantMessageId = data['assistant_message_id'];
        if (assistantMessageId is String && assistantMessageId.isNotEmpty) {
          assistant.id = assistantMessageId;
        }
        final userMessageId = data['user_message_id'];
        if (userMessageId is String && userMessageId.isNotEmpty) {
          final user = _lastUserMessage();
          if (user != null) user.id = userMessageId;
        }
        break;

      case 'error':
        final assistant = _lastAssistantMessage();
        final detail = '${data['detail'] ?? '生成失败'}';
        if (assistant != null) {
          if (assistant.content.trim().isEmpty) assistant.content = detail;
          assistant.streaming = false;
          assistant.status = null;
        }
        _error = detail;
        break;

      default:
        break;
    }
  }

  void _appendQuery(QueryRecord record) {
    final assistant = _lastAssistantMessage();
    if (assistant == null) return;
    final index = assistant.queries.indexWhere((e) => e.bql == record.bql);
    if (index >= 0) {
      assistant.queries[index] = record;
    } else {
      assistant.queries.add(record);
    }
  }

  Future<void> _send({String? retryText, bool appendUser = true}) async {
    final text = (retryText ?? _input.text).trim();
    if (text.isEmpty || _sending) return;

    final requestId = ++_activeRequestId;

    setState(() {
      if (appendUser) {
        _messages.add(ChatMessage(id: _newId(), role: 'user', content: text));
      }
      _messages.add(
        ChatMessage(
          id: _newId(),
          role: 'assistant',
          thinkingExpanded: true,
          streaming: true,
          status: 'thinking',
        ),
      );
      _sending = true;
      _error = null;
      _input.clear();
    });

    _cancelToken?.cancel();
    _cancelToken = CancelToken();

    try {
      await AssistantService.instance.sendStream(
        content: text,
        sessionId: _sessionId.isEmpty ? null : _sessionId,
        deepThink: _deepThink,
        cancelToken: _cancelToken,
        onEvent: _handleEvent,
      );
      if (requestId != _activeRequestId || !mounted) return;

      setState(() {
        final assistant = _lastAssistantMessage();
        if (assistant != null && assistant.streaming) {
          assistant.streaming = false;
          assistant.status = null;
          if (assistant.content.trim().isEmpty) {
            assistant.content = '未收到完整回复，请重试';
            _error = assistant.content;
          }
        }
      });
    } on ApiException catch (error) {
      if (requestId != _activeRequestId || !mounted) return;
      setState(() {
        final assistant = _lastAssistantMessage();
        if (assistant != null && assistant.streaming) {
          assistant.streaming = false;
          assistant.status = null;
          if (assistant.content.trim().isEmpty) {
            assistant.content = error.code == SseClient.codeCancelled
                ? kInterruptedReply
                : error.message;
          }
        }
        _error = error.message;
      });
    } finally {
      if (requestId == _activeRequestId && mounted) {
        setState(() => _sending = false);
      }
    }
  }

  /// 重试被中断的回复：移除空回复后重发上一条提问。
  Future<void> _retry(ChatMessage message) async {
    final index = _messages.indexOf(message);
    final text = index < 0 ? '' : _userMessageBefore(index).trim();
    if (text.isEmpty) {
      _notify('未找到可重试的提问');
      return;
    }
    setState(() => _messages.removeAt(index));
    await _send(retryText: text, appendUser: false);
  }

  Future<void> _reconnect(String assistantMessageId) async {
    final requestId = ++_activeRequestId;
    _cancelToken = CancelToken();
    setState(() => _sending = true);

    try {
      await AssistantService.instance.reconnectStream(
        assistantMessageId,
        cancelToken: _cancelToken,
        onEvent: _handleEvent,
      );
    } on ApiException catch (error) {
      if (requestId != _activeRequestId || !mounted) return;
      setState(() {
        final assistant = _lastAssistantMessage();
        if (assistant != null) {
          assistant.streaming = false;
          assistant.status = null;
        }
        _error = error.message;
      });
    } finally {
      if (requestId == _activeRequestId && mounted) {
        setState(() => _sending = false);
      }
    }
  }

  Future<void> _stop() async {
    final assistant = _lastAssistantMessage();
    final messageId = assistant?.id;

    _activeRequestId += 1;
    _cancelToken?.cancel();
    _cancelToken = null;

    setState(() {
      if (assistant != null && assistant.streaming) {
        assistant.streaming = false;
        assistant.status = null;
        if (assistant.content.trim().isEmpty) {
          assistant.content = kInterruptedReply;
        }
      }
      _sending = false;
    });

    if (messageId != null && messageId.isNotEmpty) {
      try {
        await AssistantService.instance.stopMessage(messageId);
      } catch (_) {
        // 停止请求失败时仍保留本地已展示内容
      }
    }
  }

  Future<void> _submitFeedback(ChatMessage message, String? rating) async {
    if (message.id.isEmpty) {
      _notify('消息尚未保存，暂时无法反馈');
      return;
    }
    setState(() => message.feedbackSubmitting = true);
    try {
      final saved = await AssistantService.instance.submitFeedback(
        messageId: message.id,
        rating: message.feedback == rating ? null : rating,
        userMessage: _userMessageBefore(_messages.indexOf(message)),
        assistantReply: message.content,
        queries: message.queries,
      );
      if (!mounted) return;
      setState(() => message.feedback = saved);
    } on ApiException catch (error) {
      if (mounted) _notify(error.message);
    } finally {
      if (mounted) setState(() => message.feedbackSubmitting = false);
    }
  }

  void _openFava(String path) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => FavaPage(relativePath: path)),
    );
  }

  // ---------------------------------------------------------------- 抽屉

  /// 关闭抽屉（未打开时为空操作）。
  void _closeDrawer() => _scaffoldKey.currentState?.closeDrawer();

  /// 重置为空白新会话（不关闭抽屉）。
  void _resetChat() {
    _activeRequestId += 1;
    _cancelToken?.cancel();
    _cancelToken = null;
    setState(() {
      _messages.clear();
      _sessionId = '';
      _title = '';
      _error = null;
      _sending = false;
      _loading = false;
    });
  }

  void _onNewChat() {
    _closeDrawer();
    _resetChat();
  }

  Future<void> _onSelectSession(String id) async {
    _closeDrawer();
    if (id == _sessionId) return;
    await _loadSession(id);
    // 刷新列表高亮
    await _refreshDrawerData();
  }

  Future<void> _onDeleteSession(ChatSessionSummary session) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除会话'),
        content: Text('确认删除「${session.title}」？删除后不可恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      await AssistantService.instance.deleteSession(session.id);
    } on ApiException catch (error) {
      if (mounted) _notify(error.message);
      return;
    }
    if (!mounted) return;
    setState(() {
      _sessions = _sessions.where((e) => e.id != session.id).toList();
    });
    // 删除的是当前会话时回到空白新对话
    if (session.id == _sessionId) _resetChat();
  }

  void _onOpenProfile() {
    _closeDrawer();
    Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => const ProfilePage()));
  }

  Future<void> _onOpenTodo() async {
    _closeDrawer();
    try {
      final summary = await TodoService.instance.summary();
      if (!mounted) return;
      if (summary.items.isEmpty) {
        _notify('暂无到期待办');
        return;
      }

      final item = summary.items.first;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => summary.items.length == 1
              ? (item.kind == TodoKind.reconciliation
                    ? ReconciliationFormPage(taskId: item.taskId!)
                    : const ReviewListPage())
              : const TodoListPage(),
        ),
      );
      // 返回后刷新抽屉徽标
      await _refreshDrawerData();
    } on ApiException catch (error) {
      if (mounted) _notify(error.message);
    }
  }

  // ---------------------------------------------------------------- 工具

  String _newId() =>
      'local-${DateTime.now().microsecondsSinceEpoch}-${_idSeed++}';

  ChatMessage? _lastAssistantMessage() {
    if (_messages.isEmpty) return null;
    final last = _messages.last;
    return last.isUser ? null : last;
  }

  ChatMessage? _lastUserMessage() {
    for (var i = _messages.length - 1; i >= 0; i--) {
      if (_messages[i].isUser) return _messages[i];
    }
    return null;
  }

  String _userMessageBefore(int index) {
    for (var i = index - 1; i >= 0; i--) {
      if (_messages[i].isUser) return _messages[i].content;
    }
    return '';
  }

  void _notify(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  // ---------------------------------------------------------------- 视图

  @override
  Widget build(BuildContext context) {
    final canChat = _status?.canChat ?? false;

    return Scaffold(
      key: _scaffoldKey,
      drawer: AssistantDrawer(
        searchController: _sessionSearch,
        sessions: _sessions,
        loading: _drawerLoading,
        error: _drawerError,
        currentSessionId: _sessionId,
        todoBadge: _todoBadge,
        onSearchSubmitted: _refreshDrawerData,
        onNewChat: _onNewChat,
        onSelectSession: _onSelectSession,
        onDeleteSession: _onDeleteSession,
        onOpenTodo: _onOpenTodo,
        onOpenProfile: _onOpenProfile,
        onRefresh: _refreshDrawerData,
      ),
      // 打开抽屉时刷新会话列表与待办徽标
      onDrawerChanged: (isOpened) {
        if (isOpened) _refreshDrawerData();
      },
      appBar: AppBar(
        title: Text(
          _title.isNotEmpty
              ? _title
              : (_sessionId.isEmpty ? '新对话' : 'Copilot 对话'),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          if (_status != null && !canChat)
            const Padding(
              padding: EdgeInsets.only(right: 12),
              child: Center(
                child: StatusChip(label: '助手不可用', tone: ChipTone.danger),
              ),
            ),
        ],
      ),
      body: _loading && _messages.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                if (_error != null) _errorBanner(_error!),
                Expanded(child: _buildMessageList()),
                _buildInputBar(canChat),
              ],
            ),
    );
  }

  Widget _errorBanner(String message) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
      color: theme.colorScheme.errorContainer,
      child: Row(
        children: [
          Icon(
            Icons.error_outline,
            size: 16,
            color: theme.colorScheme.onErrorContainer,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onErrorContainer,
              ),
            ),
          ),
          IconButton(
            tooltip: '关闭',
            iconSize: 16,
            onPressed: () => setState(() => _error = null),
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageList() {
    if (_messages.isEmpty) {
      final theme = Theme.of(context);
      final canChat = _status?.canChat ?? false;
      return Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.auto_awesome,
                size: 44,
                color: theme.colorScheme.outline,
              ),
              const SizedBox(height: 12),
              Text(
                '你好，我可以帮你查询支出、收入、余额等账本信息。',
                style: theme.textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Copilot 只读查询账本，不会改账。',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.outline,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  for (final question in kExampleQuestions)
                    ActionChip(
                      label: Text(question),
                      // 助手不可用时禁用示例问题
                      onPressed: canChat
                          ? () => _send(retryText: question)
                          : null,
                    ),
                ],
              ),
              if (!canChat) ...[
                const SizedBox(height: 12),
                Text(
                  '向 Copilot 提问你的账本',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      controller: _scroll,
      reverse: true,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      itemCount: _messages.length,
      itemBuilder: (context, index) {
        final message = _messages[_messages.length - 1 - index];
        return message.isUser
            ? _buildUserBubble(message)
            : _buildAssistantBubble(message);
      },
    );
  }

  Widget _buildUserBubble(ChatMessage message) {
    final theme = Theme.of(context);
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.78,
        ),
        decoration: BoxDecoration(
          color: theme.colorScheme.primaryContainer,
          borderRadius: BorderRadius.circular(14),
        ),
        child: SelectableText(
          message.content,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onPrimaryContainer,
          ),
        ),
      ),
    );
  }

  Widget _buildAssistantBubble(ChatMessage message) {
    final theme = Theme.of(context);
    final statusText = message.statusText;
    final hasThinking = message.thinking.trim().isNotEmpty;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (hasThinking || message.streaming)
            InkWell(
              onTap: () => setState(
                () => message.thinkingExpanded = !message.thinkingExpanded,
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Icon(
                      message.thinkingExpanded
                          ? Icons.expand_more
                          : Icons.chevron_right,
                      size: 18,
                      color: theme.colorScheme.outline,
                    ),
                    Text(
                      hasThinking ? '思考过程' : '正在思考…',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.outline,
                      ),
                    ),
                    if (statusText != null) ...[
                      const SizedBox(width: 8),
                      StatusChip(label: statusText, tone: ChipTone.info),
                    ],
                  ],
                ),
              ),
            ),
          if (hasThinking && message.thinkingExpanded)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(10),
              ),
              child: SelectableText(
                message.thinking,
                style: theme.textTheme.bodySmall?.copyWith(height: 1.5),
              ),
            ),
          if (message.content.trim().isNotEmpty)
            SelectableText(
              message.content,
              style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
            )
          else if (message.streaming)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 6),
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          for (final query in message.queries) _buildQueryCard(query),
          if (message.isInterrupted && !message.streaming)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: TextButton.icon(
                onPressed: _sending ? null : () => _retry(message),
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('重试'),
              ),
            ),
          if (!message.streaming &&
              message.content.trim().isNotEmpty &&
              !message.isInterrupted)
            _buildFeedbackRow(message),
        ],
      ),
    );
  }

  Widget _buildQueryCard(QueryRecord query) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(top: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.search, size: 16, color: theme.colorScheme.primary),
                const SizedBox(width: 6),
                Text(
                  query.report?.label.isNotEmpty == true
                      ? query.report!.label
                      : 'BQL 查询',
                  style: theme.textTheme.labelLarge,
                ),
                const Spacer(),
                if (query.favaPath != null && query.favaPath!.isNotEmpty)
                  TextButton(
                    onPressed: () => _openFava(query.favaPath!),
                    child: const Text('查看报表'),
                  ),
              ],
            ),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: SelectableText(
                query.bql,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontFamily: 'monospace',
                  height: 1.4,
                ),
              ),
            ),
            const SizedBox(height: 8),
            SelectableText(
              query.resultPreview,
              style: theme.textTheme.bodySmall?.copyWith(height: 1.4),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFeedbackRow(ChatMessage message) {
    final theme = Theme.of(context);
    return Row(
      children: [
        IconButton(
          tooltip: '有帮助',
          visualDensity: VisualDensity.compact,
          onPressed: message.feedbackSubmitting
              ? null
              : () => _submitFeedback(message, 'like'),
          icon: Icon(
            message.feedback == 'like'
                ? Icons.thumb_up
                : Icons.thumb_up_outlined,
            size: 18,
            color: message.feedback == 'like'
                ? theme.colorScheme.primary
                : null,
          ),
        ),
        IconButton(
          tooltip: '没帮助',
          visualDensity: VisualDensity.compact,
          onPressed: message.feedbackSubmitting
              ? null
              : () => _submitFeedback(message, 'dislike'),
          icon: Icon(
            message.feedback == 'dislike'
                ? Icons.thumb_down
                : Icons.thumb_down_outlined,
            size: 18,
            color: message.feedback == 'dislike'
                ? theme.colorScheme.error
                : null,
          ),
        ),
      ],
    );
  }

  Widget _buildInputBar(bool canChat) {
    final theme = Theme.of(context);
    final deepThinkSupported = _status?.deepThinkSupported ?? false;

    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(color: theme.colorScheme.outlineVariant),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!canChat && _status != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  _status!.apiKeyConfigured
                      ? '账本文件不存在，助手暂时不可用'
                      : '尚未配置大模型 API Key，助手暂时不可用',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: TextField(
                    controller: _input,
                    minLines: 1,
                    maxLines: 4,
                    enabled: canChat,
                    textInputAction: TextInputAction.newline,
                    decoration: const InputDecoration(
                      hintText: '输入问题…',
                      isDense: true,
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 12,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                if (_sending)
                  IconButton.filledTonal(
                    tooltip: '停止生成',
                    onPressed: _stop,
                    icon: const Icon(Icons.stop),
                  )
                else
                  IconButton.filled(
                    tooltip: '发送',
                    onPressed: canChat ? () => _send() : null,
                    icon: const Icon(Icons.arrow_upward),
                  ),
              ],
            ),
            if (deepThinkSupported)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(
                  children: [
                    Switch(
                      value: _deepThink,
                      onChanged: _sending
                          ? null
                          : (value) => setState(() => _deepThink = value),
                    ),
                    const SizedBox(width: 4),
                    Text('深度思考', style: theme.textTheme.bodySmall),
                    if (_status?.assistantModel.isNotEmpty == true) ...[
                      const Spacer(),
                      Text(
                        _status!.assistantModel,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.outline,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            if (_status?.referenceDate.isNotEmpty == true)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  '账本参考日期：${FormatUtil.date(_status!.referenceDate)}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
