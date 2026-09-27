/// Copilot（AI 助手）数据模型，对齐前端 `types/assistant.ts`。
library;

/// 生成被中断时的兜底文案。
const String kInterruptedReply = '生成已中断，请重试';

/// `GET /assistant/status/`。
class AssistantStatus {
  const AssistantStatus({
    this.apiKeyConfigured = false,
    this.assistantModel = '',
    this.deepThinkSupported = false,
    this.ledgerExists = false,
    this.hasUsableSharedLedger = false,
    this.ledgerPath = '',
    this.referenceDate = '',
  });

  final bool apiKeyConfigured;
  final String assistantModel;
  final bool deepThinkSupported;

  /// 本人账本是否存在（仅反映本人账本，不含共享账本）。
  final bool ledgerExists;

  /// 是否存在可用的共享账本（他人共享给当前用户）。
  final bool hasUsableSharedLedger;
  final String ledgerPath;
  final String referenceDate;

  bool get canChat =>
      apiKeyConfigured && (ledgerExists || hasUsableSharedLedger);

  factory AssistantStatus.fromJson(Map<String, Object?> json) =>
      AssistantStatus(
        apiKeyConfigured: json['api_key_configured'] == true,
        assistantModel: '${json['assistant_model'] ?? ''}',
        deepThinkSupported: json['deep_think_supported'] == true,
        ledgerExists: json['ledger_exists'] == true,
        hasUsableSharedLedger: json['has_usable_shared_ledger'] == true,
        ledgerPath: '${json['ledger_path'] ?? ''}',
        referenceDate: '${json['reference_date'] ?? ''}',
      );
}

/// `GET /assistant/shared-ledgers/` 中的一个共享账本绑定。
class SharedLedgerBinding {
  const SharedLedgerBinding({
    this.id = 0,
    this.ownerUsername = '',
    this.aliases = const [],
    this.usable = false,
    this.expiresAt = '',
    this.lastUsedAt = '',
    this.created = '',
  });

  final int id;
  final String ownerUsername;
  final List<String> aliases;
  final bool usable;
  final String expiresAt;
  final String lastUsedAt;
  final String created;

  /// Copilot 匹配到该账本时用于展示的名称：优先取第一个别名，否则用来源用户名。
  String get displayName => aliases.isNotEmpty ? aliases.first : ownerUsername;

  /// 别名列表展示文案（无别名时为占位符）。
  String get aliasesLabel => aliases.isEmpty ? '—' : aliases.join('、');

  factory SharedLedgerBinding.fromJson(Map<String, Object?> json) {
    final rawId = json['id'];
    final rawAliases = json['aliases'];
    return SharedLedgerBinding(
      id: rawId is int ? rawId : int.tryParse('${rawId ?? ''}') ?? 0,
      ownerUsername: '${json['owner_username'] ?? ''}',
      aliases: rawAliases is List
          ? rawAliases.whereType<String>().toList()
          : const [],
      usable: json['usable'] == true,
      expiresAt: '${json['expires_at'] ?? ''}',
      lastUsedAt: '${json['last_used_at'] ?? ''}',
      created: '${json['created'] ?? ''}',
    );
  }
}

/// BQL 查询卡片关联的报表链接。
class QueryReportLink {
  const QueryReportLink({this.name = '', this.label = '', this.path = ''});

  final String name;
  final String label;
  final String path;

  factory QueryReportLink.fromJson(Map<String, Object?> json) =>
      QueryReportLink(
        name: '${json['name'] ?? ''}',
        label: '${json['label'] ?? ''}',
        path: '${json['path'] ?? ''}',
      );
}

/// 一次 BQL 查询记录。
class QueryRecord {
  const QueryRecord({
    this.bql = '',
    this.resultPreview = '',
    this.ledger = '',
    this.favaPath,
    this.report,
  });

  final String bql;
  final String resultPreview;

  /// 该查询命中的账本标识：共享账本的别名或来源用户名；
  /// `'self'` 或空串表示本人账本。
  final String ledger;
  final String? favaPath;
  final QueryReportLink? report;

  factory QueryRecord.fromJson(Map<String, Object?> json) {
    final rawReport = json['report'];
    final rawPath = json['fava_path'];
    return QueryRecord(
      bql: '${json['bql'] ?? ''}',
      resultPreview: '${json['result_preview'] ?? ''}',
      ledger: '${json['ledger'] ?? ''}',
      favaPath: rawPath is String && rawPath.isNotEmpty ? rawPath : null,
      report: rawReport is Map
          ? QueryReportLink.fromJson(rawReport.cast<String, Object?>())
          : null,
    );
  }

  Map<String, Object?> toJson() => {
    'bql': bql,
    'result_preview': resultPreview,
    if (ledger.isNotEmpty) 'ledger': ledger,
    if (favaPath != null) 'fava_path': favaPath,
    if (report != null)
      'report': {
        'name': report!.name,
        'label': report!.label,
        'path': report!.path,
      },
  };
}

/// 会话列表项。
class ChatSessionSummary {
  const ChatSessionSummary({
    this.id = '',
    this.title = '',
    this.created = '',
    this.modified = '',
  });

  final String id;
  final String title;
  final String created;
  final String modified;

  factory ChatSessionSummary.fromJson(Map<String, Object?> json) =>
      ChatSessionSummary(
        id: '${json['id'] ?? ''}',
        title: '${json['title'] ?? ''}',
        created: '${json['created'] ?? ''}',
        modified: '${json['modified'] ?? ''}',
      );
}

/// 服务端存储的消息（`GET /assistant/sessions/{id}/` 内）。
class StoredChatMessage {
  const StoredChatMessage({
    this.id = '',
    this.role = 'assistant',
    this.content = '',
    this.thinking = '',
    this.reasoning = '',
    this.queries = const [],
    this.position = 0,
    this.generationStatus = '',
    this.feedback,
    this.created = '',
  });

  final String id;
  final String role; // user | assistant
  final String content;
  final String thinking;
  final String reasoning;
  final List<QueryRecord> queries;
  final int position;
  final String generationStatus; // generating | complete | cancelled | failed
  final String? feedback; // like | dislike | null
  final String created;

  bool get isGenerating => generationStatus == 'generating';

  factory StoredChatMessage.fromJson(Map<String, Object?> json) {
    final rawQueries = json['queries'];
    final rawPosition = json['position'];
    final rawFeedback = json['feedback'];
    return StoredChatMessage(
      id: '${json['id'] ?? ''}',
      role: '${json['role'] ?? 'assistant'}',
      content: '${json['content'] ?? ''}',
      thinking: '${json['thinking'] ?? ''}',
      reasoning: '${json['reasoning'] ?? ''}',
      queries: rawQueries is List
          ? rawQueries
                .whereType<Map>()
                .map((e) => QueryRecord.fromJson(e.cast<String, Object?>()))
                .toList()
          : const [],
      position: rawPosition is int
          ? rawPosition
          : int.tryParse('${rawPosition ?? ''}') ?? 0,
      generationStatus: '${json['generation_status'] ?? ''}',
      feedback: rawFeedback is String && rawFeedback.isNotEmpty
          ? rawFeedback
          : null,
      created: '${json['created'] ?? ''}',
    );
  }
}

/// 会话详情。
class ChatSessionDetail {
  const ChatSessionDetail({
    this.id = '',
    this.title = '',
    this.titleLocked = false,
    this.messages = const [],
    this.created = '',
    this.modified = '',
  });

  final String id;
  final String title;
  final bool titleLocked;
  final List<StoredChatMessage> messages;
  final String created;
  final String modified;

  factory ChatSessionDetail.fromJson(Map<String, Object?> json) {
    final rawMessages = json['messages'];
    return ChatSessionDetail(
      id: '${json['id'] ?? ''}',
      title: '${json['title'] ?? ''}',
      titleLocked: json['title_locked'] == true,
      messages: rawMessages is List
          ? rawMessages
                .whereType<Map>()
                .map(
                  (e) => StoredChatMessage.fromJson(e.cast<String, Object?>()),
                )
                .toList()
          : const [],
      created: '${json['created'] ?? ''}',
      modified: '${json['modified'] ?? ''}',
    );
  }
}

/// UI 层可变消息（流式增量就地更新）。
class ChatMessage {
  ChatMessage({
    required this.id,
    required this.role,
    this.content = '',
    this.thinking = '',
    this.reasoning = '',
    this.thinkingExpanded = false,
    List<QueryRecord>? queries,
    this.queriesExpanded = false,
    this.streaming = false,
    this.status,
    this.feedback,
    this.feedbackSubmitting = false,
    this.localNotice = false,
  }) : queries = queries ?? [];

  String id;
  final String role; // user | assistant
  String content;
  String thinking;
  String reasoning;
  bool thinkingExpanded;
  List<QueryRecord> queries;

  /// BQL 查询区块的展开态，仅用于 UI，不落服务端。
  bool queriesExpanded;
  bool streaming;

  /// thinking | querying | writing
  String? status;
  String? feedback;
  bool feedbackSubmitting;

  /// 纯客户端提示（如上传解析结果）：不落服务端，也不参与点赞点踩。
  final bool localNotice;

  bool get isUser => role == 'user';

  factory ChatMessage.fromStored(StoredChatMessage message) => ChatMessage(
    id: message.id,
    role: message.role,
    content: message.content,
    thinking: message.thinking,
    reasoning: message.reasoning,
    // 正在生成的历史消息默认展开思考过程
    thinkingExpanded: message.isGenerating,
    queries: [...message.queries],
    streaming: message.isGenerating,
    status: message.isGenerating ? 'thinking' : null,
    feedback: message.feedback,
  );

  /// 是否为「被中断」的空回复。
  bool get isInterrupted {
    if (isUser || streaming) return false;
    final text = content.trim();
    return text.isEmpty || text == kInterruptedReply;
  }

  /// 阶段文案。
  String? get statusText {
    switch (status) {
      case 'thinking':
        return '正在思考…';
      case 'querying':
        return '正在查询账本…';
      case 'writing':
        return '正在整理回复…';
      default:
        return null;
    }
  }
}

/// `tool_end` 事件携带的查询卡片数据。
class ToolEndPayload {
  const ToolEndPayload({
    this.name = '',
    this.bql,
    this.resultPreview,
    this.favaPath,
    this.report,
  });

  final String name;
  final String? bql;
  final String? resultPreview;
  final String? favaPath;
  final QueryReportLink? report;

  bool get hasQuery =>
      (bql ?? '').isNotEmpty && (resultPreview ?? '').isNotEmpty;

  QueryRecord toQueryRecord() => QueryRecord(
    bql: bql ?? '',
    resultPreview: resultPreview ?? '',
    favaPath: favaPath,
    report: report,
  );
}
