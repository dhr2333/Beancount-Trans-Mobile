/// 条目审核（统一待办）数据模型，逐字段对齐前端 `types/parse-review.ts`。
library;

/// 原始账单行。
class OriginalRow {
  const OriginalRow({
    this.transactionTime = '',
    this.transactionCategory = '',
    this.counterparty = '',
    this.commodity = '',
    this.transactionType = '',
    this.amount = '',
    this.paymentMethod = '',
    this.transactionStatus = '',
    this.billIdentifier = '',
  });

  final String transactionTime;
  final String transactionCategory;
  final String counterparty;
  final String commodity;
  final String transactionType;
  final String amount;
  final String paymentMethod;
  final String transactionStatus;
  final String billIdentifier;

  factory OriginalRow.fromJson(Map<String, Object?> json) => OriginalRow(
        transactionTime: '${json['transaction_time'] ?? ''}',
        transactionCategory: '${json['transaction_category'] ?? ''}',
        counterparty: '${json['counterparty'] ?? ''}',
        commodity: '${json['commodity'] ?? ''}',
        transactionType: '${json['transaction_type'] ?? ''}',
        // 金额一律保留字符串形态，不做 double 解析
        amount: json['amount'] == null ? '' : '${json['amount']}',
        paymentMethod: '${json['payment_method'] ?? ''}',
        transactionStatus: '${json['transaction_status'] ?? ''}',
        billIdentifier: '${json['bill_identifier'] ?? ''}',
      );
}

/// 标签来源。
class TagSource {
  const TagSource({this.type = '', this.key = '', this.mappingType = ''});

  final String type; // mapping | source | manual
  final String key;
  final String mappingType; // expense | income | asset

  factory TagSource.fromJson(Map<String, Object?> json) => TagSource(
        type: '${json['type'] ?? ''}',
        key: '${json['key'] ?? ''}',
        mappingType: '${json['mapping_type'] ?? ''}',
      );
}

/// 单个标签及其来源。
class TagDetail {
  const TagDetail({this.path = '', this.sources = const []});

  final String path;
  final List<TagSource> sources;

  factory TagDetail.fromJson(Map<String, Object?> json) {
    final rawSources = json['sources'];
    return TagDetail(
      path: '${json['path'] ?? ''}',
      sources: rawSources is List
          ? rawSources
              .whereType<Map>()
              .map((e) => TagSource.fromJson(e.cast<String, Object?>()))
              .toList()
          : const [],
    );
  }
}

/// 人工增删的标签覆盖。
class TagOverrides {
  const TagOverrides({this.removedPaths = const [], this.addedPaths = const []});

  final List<String> removedPaths;
  final List<String> addedPaths;

  bool get isEmpty => removedPaths.isEmpty && addedPaths.isEmpty;

  factory TagOverrides.fromJson(Map<String, Object?> json) => TagOverrides(
        removedPaths: _stringList(json['removed_paths']),
        addedPaths: _stringList(json['added_paths']),
      );

  static List<String> _stringList(Object? value) {
    if (value is! List) return const [];
    return value.whereType<String>().toList();
  }
}

/// 映射候选（含匹配分）。
class ExpenseCandidate {
  const ExpenseCandidate({this.key = '', this.score = 0});

  final String key;
  final int score;

  factory ExpenseCandidate.fromJson(Map<String, Object?> json) {
    final score = json['score'];
    return ExpenseCandidate(
      key: '${json['key'] ?? ''}',
      score: score is int ? score : (score is num ? score.toInt() : 0),
    );
  }
}

/// 一条待审核条目。
class FormattedEntry {
  const FormattedEntry({
    this.uuid = '',
    this.formatted = '',
    this.editedFormatted = '',
    this.selectedExpenseKey = '',
    this.expenseCandidates = const [],
    this.originalRow,
    this.tagDetails = const [],
    this.tagOverrides,
    this.installmentRole,
    this.installmentPeriod,
    this.fileId,
    this.fileName = '',
  });

  final String uuid;
  final String formatted;
  final String editedFormatted;
  final String selectedExpenseKey;
  final List<ExpenseCandidate> expenseCandidates;
  final OriginalRow? originalRow;
  final List<TagDetail> tagDetails;
  final TagOverrides? tagOverrides;
  final String? installmentRole; // purchase | installment | null
  final int? installmentPeriod;
  final int? fileId;
  final String fileName;

  /// 展示用 Beancount 文本：优先编辑后内容，为空回退原始内容。
  String get displayFormatted =>
      editedFormatted.trim().isNotEmpty ? editedFormatted : formatted;

  /// 映射候选按分值降序。
  List<ExpenseCandidate> get sortedCandidates {
    final list = [...expenseCandidates];
    list.sort((a, b) => b.score.compareTo(a.score));
    return list;
  }

  factory FormattedEntry.fromJson(Map<String, Object?> json) {
    final rawRow = json['original_row'];
    final rawTags = json['tag_details'];
    final rawOverrides = json['tag_overrides'];
    final rawCandidates = json['expense_candidates_with_score'];
    final rawPeriod = json['installment_period'];
    final rawFileId = json['file_id'];
    final rawRole = json['installment_role'];

    return FormattedEntry(
      uuid: '${json['uuid'] ?? ''}',
      formatted: '${json['formatted'] ?? ''}',
      editedFormatted: '${json['edited_formatted'] ?? ''}',
      selectedExpenseKey: '${json['selected_expense_key'] ?? ''}',
      expenseCandidates: rawCandidates is List
          ? rawCandidates
              .whereType<Map>()
              .map((e) => ExpenseCandidate.fromJson(e.cast<String, Object?>()))
              .toList()
          : const [],
      originalRow: rawRow is Map
          ? OriginalRow.fromJson(rawRow.cast<String, Object?>())
          : null,
      tagDetails: rawTags is List
          ? rawTags
              .whereType<Map>()
              .map((e) => TagDetail.fromJson(e.cast<String, Object?>()))
              .toList()
          : const [],
      tagOverrides: rawOverrides is Map
          ? TagOverrides.fromJson(rawOverrides.cast<String, Object?>())
          : null,
      installmentRole:
          rawRole is String && rawRole.isNotEmpty ? rawRole : null,
      installmentPeriod: rawPeriod is int
          ? rawPeriod
          : (rawPeriod is num ? rawPeriod.toInt() : null),
      fileId:
          rawFileId is int ? rawFileId : int.tryParse('${rawFileId ?? ''}'),
      fileName: '${json['file_name'] ?? ''}',
    );
  }

  bool get isInstallmentRepayment => installmentRole == 'installment';
  bool get isInstallmentPurchase => installmentRole == 'purchase';
}

/// `GET /translate/entry-review/results` 的响应。
class EntryReviewResults {
  const EntryReviewResults({
    this.entries = const [],
    this.entryCount = 0,
    this.reviewExpiresAt,
  });

  final List<FormattedEntry> entries;
  final int entryCount;

  /// 审核截止时间（**Unix 秒**），无有效条目时为 null。
  final int? reviewExpiresAt;

  factory EntryReviewResults.fromJson(Map<String, Object?> json) {
    final rawEntries = json['entries'];
    final rawCount = json['entry_count'];
    final rawExpires = json['review_expires_at'];

    final entries = rawEntries is List
        ? rawEntries
            .whereType<Map>()
            .map((e) => FormattedEntry.fromJson(e.cast<String, Object?>()))
            .toList()
        : <FormattedEntry>[];

    return EntryReviewResults(
      entries: entries,
      entryCount:
          rawCount is int ? rawCount : (rawCount is num ? rawCount.toInt() : entries.length),
      reviewExpiresAt: rawExpires is int
          ? rawExpires
          : (rawExpires is num ? rawExpires.toInt() : null),
    );
  }

  /// 按来源账单文件名分组（未命名归入「未知账单」）。
  Map<String, List<FormattedEntry>> get groupedByFile {
    final grouped = <String, List<FormattedEntry>>{};
    for (final entry in entries) {
      final key = entry.fileName.trim().isEmpty ? '未知账单' : entry.fileName;
      grouped.putIfAbsent(key, () => []).add(entry);
    }
    return grouped;
  }
}
