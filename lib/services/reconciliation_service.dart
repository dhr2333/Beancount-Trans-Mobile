import '../core/api_client.dart';
import '../models/reconciliation.dart';
import '../models/scheduled_task.dart';

/// 对账模块服务（对应后端 `/api/reconciliation/` 与 `/api/account/`）。
class ReconciliationService {
  ReconciliationService._();

  static final ReconciliationService instance = ReconciliationService._();

  final ApiClient _client = ApiClient.instance;

  /// 待办列表。
  ///
  /// [status] 可选 `pending` / `completed` / `cancelled`；[due] 为 true 时
  /// 只返回 `scheduled_date <= today` 的待办。
  Future<List<ScheduledTask>> listTasks({
    String taskType = 'reconciliation',
    String? status,
    bool due = false,
  }) async {
    final response = await _client.get<Object?>(
      '/reconciliation/tasks/',
      query: {
        'task_type': taskType,
        if (status != null && status.isNotEmpty) 'status': status,
        if (due) 'due': 'true',
      },
    );
    final data = response.data;
    if (data is! List) return const [];
    return data
        .whereType<Map>()
        .map((e) => ScheduledTask.fromJson(e.cast<String, Object?>()))
        .toList();
  }

  /// 待办详情。
  Future<ScheduledTask> getTask(int id) async {
    final response = await _client.get<Object?>('/reconciliation/tasks/$id/');
    final data = response.data;
    return ScheduledTask.fromJson(
      data is Map ? data.cast<String, Object?>() : const {},
    );
  }

  /// 仅允许修改 `scheduled_date`。
  Future<ScheduledTask> updateScheduledDate(int id, String scheduledDate) async {
    final response = await _client.patch<Object?>(
      '/reconciliation/tasks/$id/',
      data: {'scheduled_date': scheduledDate},
    );
    final data = response.data;
    return ScheduledTask.fromJson(
      data is Map ? data.cast<String, Object?>() : const {},
    );
  }

  /// 开始对账：拿到预期余额与默认分配账户。
  Future<ReconciliationStart> start(int id) async {
    final response =
        await _client.post<Object?>('/reconciliation/tasks/$id/start/');
    final data = response.data;
    return ReconciliationStart.fromJson(
      data is Map ? data.cast<String, Object?>() : const {},
    );
  }

  /// 执行对账。
  Future<ReconciliationExecuteResult> execute({
    required int id,
    required String actualBalance,
    required String currency,
    required String asOfDate,
    List<TransactionItemDraft> transactionItems = const [],
  }) async {
    final response = await _client.post<Object?>(
      '/reconciliation/tasks/$id/execute/',
      data: {
        'actual_balance': actualBalance,
        'currency': currency,
        'as_of_date': asOfDate,
        'transaction_items': transactionItems.map((e) => e.toJson()).toList(),
      },
    );
    final data = response.data;
    return ReconciliationExecuteResult.fromJson(
      data is Map ? data.cast<String, Object?>() : const {},
    );
  }

  /// 撤销对账（仅 `completed` 状态可用）。
  Future<void> revoke(int id) async {
    await _client.post<Object?>(
      '/reconciliation/tasks/$id/revoke_reconciliation/',
    );
  }

  /// 账户树（差额分配账户候选）。
  Future<List<AccountNode>> accountTree() async {
    final response = await _client.get<Object?>('/account/tree/');
    final data = response.data;
    if (data is! List) return const [];
    return data
        .whereType<Map>()
        .map((e) => AccountNode.fromJson(e.cast<String, Object?>()))
        .toList();
  }
}
