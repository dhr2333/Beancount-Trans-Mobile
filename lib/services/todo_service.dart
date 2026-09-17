import '../core/format.dart';
import '../models/scheduled_task.dart';
import 'entry_review_service.dart';
import 'reconciliation_service.dart';

/// 待办条目的类别。
enum TodoKind {
  /// 解析审核（跨账单扁平条目）。
  entryReview,

  /// 到期对账。
  reconciliation,
}

/// 首页待办列表项（解析审核或对账）。
class TodoItem {
  const TodoItem({
    required this.kind,
    required this.title,
    required this.subtitle,
    this.taskId,
    this.entryCount = 0,
    this.scheduledDate,
    this.reviewExpiresAt,
    this.isOverdue = false,
  });

  final TodoKind kind;
  final String title;
  final String subtitle;

  /// 对账任务 ID；解析审核汇总项为 null。
  final int? taskId;

  /// 待审核条目数（对账项固定为 0）。
  final int entryCount;

  /// 计划日期（对账项；解析审核汇总项为 null）。
  final String? scheduledDate;

  /// 审核到期时间（Unix 秒；对账项为 null）。
  final int? reviewExpiresAt;

  final bool isOverdue;
}

/// 首页待办汇总结果。
class TodoSummary {
  const TodoSummary({this.items = const []});

  final List<TodoItem> items;

  /// 是否存在解析审核待办（汇总项位于 [items] 首位）。
  bool get hasEntryReview =>
      items.isNotEmpty && items.first.kind == TodoKind.entryReview;

  /// 到期对账条目数。
  int get reconciliationCount =>
      items.where((e) => e.kind == TodoKind.reconciliation).length;

  /// 底栏徽标数：对账条目数 + 是否存在解析审核（0 或 1）。
  int get badgeCount => reconciliationCount + (hasEntryReview ? 1 : 0);

  bool get isEmpty => items.isEmpty;
}

/// 首页待办聚合服务 —— **严格只读**。
///
/// 汇总解析审核与到期对账两类待办，供首页列表与底栏徽标使用。
/// 底层复用 [EntryReviewService] 与 [ReconciliationService]，不新增写接口。
class TodoService {
  TodoService._();

  static final TodoService instance = TodoService._();

  /// 到期的对账待办（`scheduled_date <= today`）。
  Future<List<ScheduledTask>> dueReconciliations() {
    return ReconciliationService.instance
        .listTasks(taskType: 'reconciliation', due: true);
  }

  /// 待审核的条目审核待办。
  Future<List<ScheduledTask>> pendingReviewTasks() {
    return EntryReviewService.instance.pendingTasks();
  }

  /// 聚合待办汇总。
  ///
  /// 并发拉取两类底层数据后：
  /// - 当解析审核待办 `entry_count` 之和大于 0 时，生成一个汇总条目并置于首位；
  /// - 其后为每个到期对账任务生成一个条目，按 [TodoItem.scheduledDate] 升序排列（空值靠后）。
  Future<TodoSummary> summary() async {
    final results = await Future.wait([
      pendingReviewTasks(),
      dueReconciliations(),
    ]);
    final reviews = results[0];
    final reconciliations = results[1];

    final items = <TodoItem>[];

    var entryCount = 0;
    int? minExpires;
    for (final task in reviews) {
      entryCount += task.entryCount ?? 0;
      final expires = task.reviewExpiresAt;
      if (expires != null && (minExpires == null || expires < minExpires)) {
        minExpires = expires;
      }
    }
    if (entryCount > 0) {
      items.add(
        TodoItem(
          kind: TodoKind.entryReview,
          title: '解析审核',
          subtitle: '$entryCount 条待审',
          entryCount: entryCount,
          reviewExpiresAt: minExpires,
        ),
      );
    }

    final reconciliationItems = reconciliations.map((task) {
      return TodoItem(
        kind: TodoKind.reconciliation,
        taskId: task.id,
        title: _reconciliationTitle(task),
        subtitle: '计划 ${FormatUtil.date(task.scheduledDate)}',
        scheduledDate: task.scheduledDate,
        isOverdue: task.isOverdue,
      );
    }).toList()
      ..sort(_byScheduledDate);
    items.addAll(reconciliationItems);

    return TodoSummary(items: items);
  }

  /// 底栏徽标数。
  Future<int> badgeCount() async => (await summary()).badgeCount;

  static String _reconciliationTitle(ScheduledTask task) {
    for (final candidate in [
      task.accountName,
      task.fileName,
      task.taskTypeDisplay,
    ]) {
      if (candidate != null && candidate.isNotEmpty) return candidate;
    }
    return '对账';
  }

  /// 按计划日期升序排列，空值排在最后。
  static int _byScheduledDate(TodoItem a, TodoItem b) {
    final left = a.scheduledDate;
    final right = b.scheduledDate;
    if (left == null && right == null) return 0;
    if (left == null) return 1;
    if (right == null) return -1;
    return left.compareTo(right);
  }
}
