import '../core/api_client.dart';
import '../models/parse_review.dart';
import '../models/scheduled_task.dart';

/// 解析审核待办服务 —— **严格只读**。
///
/// 只暴露两个 GET 方法，不实现也不调用任何写接口
/// （edit / tags / reparse / preview-sync / confirm / reparse-all）。
class EntryReviewService {
  EntryReviewService._();

  static final EntryReviewService instance = EntryReviewService._();

  final ApiClient _client = ApiClient.instance;

  /// `GET /translate/entry-review/results`（跨账单扁平条目列表）。
  Future<EntryReviewResults> results() async {
    final response =
        await _client.get<Object?>('/translate/entry-review/results');
    final data = response.data;
    return data is Map
        ? EntryReviewResults.fromJson(data.cast<String, Object?>())
        : const EntryReviewResults();
  }

  /// 条目审核待办（用于底栏徽标与到期时间）。
  Future<List<ScheduledTask>> pendingTasks() async {
    final response = await _client.get<Object?>(
      '/reconciliation/tasks/',
      query: const {'task_type': 'entry_review', 'status': 'pending'},
    );
    final data = response.data;
    if (data is! List) return const [];
    return data
        .whereType<Map>()
        .map((e) => ScheduledTask.fromJson(e.cast<String, Object?>()))
        .toList();
  }

  /// 待审核条目总数（汇总所有 entry_review 待办的 `entry_count`）。
  Future<int> pendingCount() async {
    final tasks = await pendingTasks();
    var total = 0;
    for (final task in tasks) {
      total += task.entryCount ?? 0;
    }
    return total;
  }
}
