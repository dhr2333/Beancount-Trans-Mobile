import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../core/api_exception.dart';
import '../../core/sse_client.dart';
import '../../models/assistant.dart';
import '../../models/parse_review.dart';
import '../../services/assistant_service.dart';
import '../../services/todo_service.dart';
import '../../services/translate_service.dart';
import '../../widgets/markdown_content.dart';
import '../../widgets/status_chip.dart';
import '../fava_page.dart';
import '../profile_page.dart';
import '../reconciliation/reconciliation_form_page.dart';
import '../review/review_list_page.dart';
import '../todo/todo_list_page.dart';
import 'assistant_drawer.dart';

/// 首页（空白会话欢迎区）轮换展示的示例问句池。
///
/// 文案规范：
/// 1. 必须是疑问句并以「？」结尾，用提问代替功能自述，避免「我可以帮你……」式口吻。
/// 2. 正文字数 ≤ 19 字，保证移动端 chip 单行不折行。
/// 3. 每句只对应一项 Copilot 真实能力：账户与标签、收支、余额与资产负债、大额与渠道、
///    跨期对比与趋势、洞察与月度总结（洞察模式）、一句话生成待审核条目。
/// 4. 不复述「Copilot 只读查询账本，不会改账」的只读约束，也不承诺账本外能力。
/// 5. 时间用相对表述（上个月、今年、最近三个月），避免文案随日期过期。
/// 6. 条数保持为「一次展示 4 条」的整数倍，避免最后一组不满；换组只发生在
///    点击示例问句或开启新会话时，平时不自动变化。
const List<String> kExampleQuestions = [
  // 账户与标签
  '我有哪些账户和标签？',
  '哪个标签的花销最多？',
  '我常用哪些支付账户？',
  // 收支
  '上个月支出都花在哪了？',
  '今年以来收入有多少？',
  '今年和去年比花得多吗？',
  // 余额与资产负债
  '现在各账户余额是多少？',
  '我的资产和负债各多少？',
  '我的存款这半年在增加吗？',
  '我今年一共结余了多少？',
  // 大额与类目
  '最近有哪些大额消费？',
  '哪些类目花销涨得最快？',
  '上季度哪些类目花得最多？',
  '哪些支出每个月都在重复？',
  // 跨期与趋势
  '这个月比上个月花得多吗？',
  '最近三个月的支出趋势如何？',
  // 洞察与总结
  '有什么意外的消费发现？',
  '能给我一份消费洞察吗？',
  '能帮我写份月度总结吗？',
  // 一句话记账（只生成待审核条目）
  '能帮我把这笔花销记成账吗？',
];

/// 首页示例问句一次展示的条数。
const int _kExampleWindow = 4;

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

  /// 账单上传解析中（上传/解析期间禁用附件按钮）。
  bool _uploading = false;

  /// 首页示例问句当前展示的分组下标（点击示例或开启新会话时前进一组）。
  int _examplePage = 0;

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
        final assistant = _lastAssistantMessage();
        if (assistant == null) break;
        final phase = '${data['phase'] ?? ''}';
        assistant.status = phase;
        // 思考阶段结束（查询/撰写）后自动折叠思考内容
        if (phase != 'thinking') assistant.thinkingExpanded = false;
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
        // 该事件在思考已定型时下发，自动折叠
        assistant.thinkingExpanded = false;
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
          assistant.thinkingExpanded = false;
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
          assistant.thinkingExpanded = false;
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
          assistant.thinkingExpanded = false;
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
          assistant.thinkingExpanded = false;
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
        assistant.thinkingExpanded = false;
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

  // ------------------------------------------------------------ 上传账单解析

  /// 选取账单文件上传解析：文件不入文件管理，解析结果并入解析审核待办。
  Future<void> _pickAndUploadBill() async {
    if (_uploading) return;

    final List<PlatformFile> picked;
    try {
      picked = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['csv', 'pdf', 'xls', 'xlsx', 'zip'],
      );
    } catch (_) {
      _notify('打开文件选择器失败');
      return;
    }
    if (picked.isEmpty || !mounted) return;

    final file = picked.first;
    setState(() => _uploading = true);
    try {
      final bytes = await file.readAsBytes();
      final result = await TranslateService.instance.uploadBillParse(
        filename: file.name,
        bytes: bytes,
      );
      if (!mounted) return;
      _appendNotice(_uploadResultText(result, file.name));
      // 上传解析会生成/刷新解析审核待办，同步刷新抽屉徽标
      await _refreshDrawerData();
    } on ApiException catch (error) {
      if (!mounted) return;
      _appendNotice('账单「${file.name}」解析失败：${error.message}');
      _notify(error.message);
    } catch (_) {
      if (!mounted) return;
      _appendNotice('账单「${file.name}」读取或上传失败，请重试');
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  /// 上传解析结果文案。
  String _uploadResultText(UploadParseResult result, String fileName) {
    final name = result.fileName.trim().isNotEmpty ? result.fileName : fileName;
    if (!result.hasEntries) {
      return '「$name」没有新增待审条目：${result.duplicateCount} 条已存在'
          '（当前待审 ${result.pendingTotal} 条）。';
    }
    final skipped = result.duplicateCount > 0
        ? '（跳过 ${result.duplicateCount} 条重复）'
        : '';
    return '已上传并解析「$name」：新增 ${result.entryCount} 条待审条目$skipped，'
        '可在「待办 → 解析审核」中查看。';
  }

  /// 追加一条本地提示消息（纯客户端，不落服务端）。
  void _appendNotice(String content) {
    setState(() {
      _messages.add(
        ChatMessage(
          id: _newId(),
          role: 'assistant',
          content: content,
          localNotice: true,
        ),
      );
    });
  }

  // ---------------------------------------------------------------- 抽屉

  /// 关闭抽屉（未打开时为空操作）。
  void _closeDrawer() => _scaffoldKey.currentState?.closeDrawer();

  /// 首页示例问句的分组数。
  int get _examplePageCount =>
      (kExampleQuestions.length + _kExampleWindow - 1) ~/ _kExampleWindow;

  /// 首页示例问句前进一组（重新进入欢迎区时才可见）。
  void _advanceExamplePage() {
    if (_examplePageCount <= 1) return;
    _examplePage = (_examplePage + 1) % _examplePageCount;
  }

  /// 点击示例问句：换一组并直接发送。
  void _onExampleSelected(String question) {
    setState(_advanceExamplePage);
    _send(retryText: question);
  }

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
      // 开启新会话时换一组示例问句
      _advanceExamplePage();
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
        onSelectSession: _onSelectSession,
        onDeleteSession: _onDeleteSession,
        onOpenTodo: _onOpenTodo,
        onOpenProfile: _onOpenProfile,
        onRefresh: _refreshDrawerData,
      ),
      // 整屏均可横向右滑拖出抽屉（默认只响应左侧 20dp 的边缘拖动）
      drawerEdgeDragWidth: MediaQuery.sizeOf(context).width,
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
            const Center(
              child: StatusChip(label: '助手不可用', tone: ChipTone.danger),
            ),
          // 新建对话：参考 DeepSeek 移动端放在标题栏右侧
          IconButton(
            tooltip: '新对话',
            onPressed: _onNewChat,
            icon: const Icon(Icons.add_comment_outlined),
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
                // '你好，我可以帮你查询支出、收入、余额等账本信息。',
                '欢迎回来',
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
              _ExampleChips(
                questions: kExampleQuestions,
                page: _examplePage,
                enabled: canChat,
                onSelect: _onExampleSelected,
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
              child: _buildThinkingText(message),
            ),
          if (message.queries.isNotEmpty) _buildQuerySection(message),
          if (message.content.trim().isNotEmpty)
            _buildReplyText(message)
          else if (message.streaming)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 6),
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
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
              !message.isInterrupted &&
              !message.localNotice)
            _buildFeedbackRow(message),
        ],
      ),
    );
  }

  /// 思考过程：流式期间按纯文本渲染，结束后按 Markdown 渲染（与 Web 端一致）。
  Widget _buildThinkingText(ChatMessage message) {
    final style = Theme.of(context).textTheme.bodySmall;
    if (message.streaming) {
      return SelectableText(
        message.thinking,
        style: style?.copyWith(height: 1.5),
      );
    }
    return MarkdownContent(content: message.thinking, baseStyle: style);
  }

  /// Copilot 回复正文：流式期间按纯文本渲染，避免未闭合的 Markdown 语法抖动。
  Widget _buildReplyText(ChatMessage message) {
    if (message.streaming) {
      return SelectableText(
        message.content,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.5),
      );
    }
    return MarkdownContent(content: message.content);
  }

  /// BQL 查询区块：整条消息的查询合并为一个折叠入口，默认折叠。
  Widget _buildQuerySection(ChatMessage message) {
    final theme = Theme.of(context);
    final queries = message.queries;
    final expanded = message.queriesExpanded;

    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => setState(
              () => message.queriesExpanded = !message.queriesExpanded,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Icon(
                    expanded ? Icons.expand_more : Icons.chevron_right,
                    size: 18,
                    color: theme.colorScheme.outline,
                  ),
                  Text(
                    queries.length > 1 ? 'BQL 查询（${queries.length}）' : 'BQL 查询',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.outline,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (expanded)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var i = 0; i < queries.length; i++) ...[
                    if (i > 0) const Divider(height: 24),
                    _buildQueryDetail(queries[i]),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// 单条 BQL 明细：报表名与入口（可选）+ BQL；结果仅通过报表跳转查看。
  Widget _buildQueryDetail(QueryRecord query) {
    final theme = Theme.of(context);
    final label = query.report?.label ?? '';
    final hasFava = query.favaPath != null && query.favaPath!.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label.isNotEmpty || hasFava)
          Row(
            children: [
              if (label.isNotEmpty)
                Expanded(
                  child: Text(
                    label,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.outline,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              if (hasFava)
                TextButton(
                  onPressed: () => _openFava(query.favaPath!),
                  child: const Text('查看报表'),
                ),
            ],
          ),
        SelectableText(
          query.bql,
          style: theme.textTheme.bodySmall?.copyWith(
            fontFamily: 'monospace',
            height: 1.4,
          ),
        ),
      ],
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
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
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
            // 胶囊输入框：第一行文本输入，第二行从左到右为深度思考 / 文件 / 发送
            Container(
              padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
              decoration: BoxDecoration(
                // 比 surfaceContainerHighest 更浅，贴近页面底色、避免大块灰突兀
                color: theme.colorScheme.surfaceContainer,
                borderRadius: BorderRadius.circular(24),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: _input,
                    minLines: 1,
                    maxLines: 4,
                    enabled: canChat,
                    textInputAction: TextInputAction.newline,
                    decoration: const InputDecoration(
                      hintText: '输入问题…',
                      isDense: true,
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(vertical: 6),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      if (deepThinkSupported)
                        FilterChip(
                          label: const Text('深度思考'),
                          selected: _deepThink,
                          // 发送中禁用：onSelected 为空即为禁用态
                          onSelected: _sending
                              ? null
                              : (value) => setState(() => _deepThink = value),
                          showCheckmark: false,
                          side: BorderSide.none,
                          backgroundColor:
                              theme.colorScheme.surfaceContainerHighest,
                          selectedColor: theme.colorScheme.primaryContainer,
                          labelStyle: theme.textTheme.labelMedium,
                          visualDensity: VisualDensity.compact,
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                        ),
                      const Spacer(),
                      if (_uploading)
                        const SizedBox(
                          width: 40,
                          height: 40,
                          child: Center(
                            child: SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ),
                        )
                      else
                        IconButton(
                          tooltip: '上传账单解析',
                          onPressed: _pickAndUploadBill,
                          icon: const Icon(Icons.attach_file),
                          iconSize: 20,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints.tightFor(
                            width: 40,
                            height: 40,
                          ),
                        ),
                      if (_sending)
                        IconButton.filledTonal(
                          tooltip: '停止生成',
                          onPressed: _stop,
                          icon: const Icon(Icons.stop),
                          iconSize: 20,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints.tightFor(
                            width: 40,
                            height: 40,
                          ),
                          style: IconButton.styleFrom(
                            shape: const CircleBorder(),
                          ),
                        )
                      else
                        IconButton.filled(
                          tooltip: '发送',
                          onPressed: canChat ? () => _send() : null,
                          icon: const Icon(Icons.arrow_upward),
                          iconSize: 20,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints.tightFor(
                            width: 40,
                            height: 40,
                          ),
                          style: IconButton.styleFrom(
                            shape: const CircleBorder(),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 首页示例问句：一次展示 [_kExampleWindow] 条，[page] 指定当前分组，点击直接发送。
///
/// 只在点击示例问句或开启新会话时换组（[page] 由页面 State 持有），
/// 平时不自动变化，避免手正要按下时 chips 被换走。
class _ExampleChips extends StatelessWidget {
  const _ExampleChips({
    required this.questions,
    required this.page,
    required this.enabled,
    required this.onSelect,
  });

  final List<String> questions;
  final int page;
  final bool enabled;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final start = page * _kExampleWindow;
    final current = questions.skip(start).take(_kExampleWindow).toList();
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      child: Wrap(
        // 分组下标作为 key，换组时触发淡入淡出
        key: ValueKey(page),
        spacing: 8,
        runSpacing: 8,
        alignment: WrapAlignment.center,
        children: [
          for (final question in current)
            ActionChip(
              label: Text(question),
              // 助手不可用时禁用示例问题
              onPressed: enabled ? () => onSelect(question) : null,
            ),
        ],
      ),
    );
  }
}
