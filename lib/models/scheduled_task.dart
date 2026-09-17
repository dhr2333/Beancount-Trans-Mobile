/// `ScheduledTask` 列表/详情项（`/reconciliation/tasks/`）。
class ScheduledTask {
  const ScheduledTask({
    required this.id,
    this.taskType = '',
    this.taskTypeDisplay = '',
    this.scheduledDate,
    this.completedDate,
    this.status = '',
    this.statusDisplay = '',
    this.accountName,
    this.accountType,
    this.fileName,
    this.fileId,
    this.reviewExpiresAt,
    this.entryCount,
    this.created = '',
    this.modified = '',
  });

  final int id;
  final String taskType; // reconciliation | parse_review | entry_review
  final String taskTypeDisplay;
  final String? scheduledDate;
  final String? completedDate;
  final String status; // inactive | pending | completed | cancelled
  final String statusDisplay;
  final String? accountName;
  final String? accountType;
  final String? fileName;
  final int? fileId;

  /// Unix 秒
  final int? reviewExpiresAt;
  final int? entryCount;
  final String created;
  final String modified;

  bool get isPending => status == 'pending';
  bool get isCompleted => status == 'completed';

  /// 是否逾期（`scheduled_date` 早于今天）。
  bool get isOverdue {
    final date = scheduledDate;
    if (date == null || date.isEmpty || !isPending) return false;
    final parsed = DateTime.tryParse(date.length >= 10 ? date.substring(0, 10) : date);
    if (parsed == null) return false;
    final today = DateTime.now();
    final todayDate = DateTime(today.year, today.month, today.day);
    return parsed.isBefore(todayDate);
  }

  factory ScheduledTask.fromJson(Map<String, Object?> json) {
    final id = json['id'];
    final rawEntryCount = json['entry_count'];
    final rawExpires = json['review_expires_at'];
    final rawFileId = json['file_id'];
    final accountName = json['account_name'];
    final accountType = json['account_type'];
    final fileName = json['file_name'];
    final scheduledDate = json['scheduled_date'];
    final completedDate = json['completed_date'];

    return ScheduledTask(
      id: id is int ? id : int.tryParse('${id ?? ''}') ?? 0,
      taskType: '${json['task_type'] ?? ''}',
      taskTypeDisplay: '${json['task_type_display'] ?? ''}',
      scheduledDate: scheduledDate is String ? scheduledDate : null,
      completedDate: completedDate is String ? completedDate : null,
      status: '${json['status'] ?? ''}',
      statusDisplay: '${json['status_display'] ?? ''}',
      accountName: accountName is String && accountName.isNotEmpty ? accountName : null,
      accountType: accountType is String && accountType.isNotEmpty ? accountType : null,
      fileName: fileName is String && fileName.isNotEmpty ? fileName : null,
      fileId: rawFileId is int ? rawFileId : int.tryParse('${rawFileId ?? ''}'),
      reviewExpiresAt: rawExpires is int
          ? rawExpires
          : (rawExpires is num ? rawExpires.toInt() : null),
      entryCount: rawEntryCount is int
          ? rawEntryCount
          : (rawEntryCount is num ? rawEntryCount.toInt() : null),
      created: '${json['created'] ?? ''}',
      modified: '${json['modified'] ?? ''}',
    );
  }
}
