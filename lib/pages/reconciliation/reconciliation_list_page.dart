import 'package:flutter/material.dart';

import '../../core/api_exception.dart';
import '../../models/scheduled_task.dart';
import '../../services/reconciliation_service.dart';
import '../../widgets/async_view.dart';
import '../../widgets/task_card.dart';
import 'reconciliation_form_page.dart';

/// 对账列表筛选条件。
enum ReconciliationFilter {
  pending('待处理'),
  due('已到期'),
  completed('已完成');

  const ReconciliationFilter(this.label);

  final String label;
}

/// 对账待办列表。
class ReconciliationListPage extends StatefulWidget {
  const ReconciliationListPage({super.key});

  @override
  State<ReconciliationListPage> createState() => _ReconciliationListPageState();
}

class _ReconciliationListPageState extends State<ReconciliationListPage> {
  ReconciliationFilter _filter = ReconciliationFilter.pending;
  List<ScheduledTask> _tasks = const [];
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final status = switch (_filter) {
        ReconciliationFilter.pending => 'pending',
        ReconciliationFilter.completed => 'completed',
        ReconciliationFilter.due => null,
      };
      final tasks = await ReconciliationService.instance.listTasks(
        status: status,
        due: _filter == ReconciliationFilter.due,
      );
      if (!mounted) return;
      setState(() => _tasks = tasks);
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _changeFilter(ReconciliationFilter filter) {
    if (filter == _filter) return;
    setState(() {
      _filter = filter;
      _tasks = const [];
    });
    _load();
  }

  Future<void> _openForm(ScheduledTask task) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => ReconciliationFormPage(taskId: task.id),
      ),
    );
    if (changed == true) _load();
  }

  Future<void> _confirmRevoke(ScheduledTask task) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('撤销对账'),
        content: Text(
          '确认撤销「${task.accountName ?? task.taskTypeDisplay}」'
          '${task.completedDate == null ? '' : '（${task.completedDate}）'}的对账记录？',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('撤销'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await ReconciliationService.instance.revoke(task.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('已撤销对账')));
      _load();
    } on ApiException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('对账待办'),
        actions: [
          IconButton(
            tooltip: '刷新',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
            child: SegmentedButton<ReconciliationFilter>(
              segments: [
                for (final filter in ReconciliationFilter.values)
                  ButtonSegment(value: filter, label: Text(filter.label)),
              ],
              selected: {_filter},
              showSelectedIcon: false,
              onSelectionChanged: (selection) => _changeFilter(selection.first),
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _load,
              child: AsyncView(
                loading: _loading,
                error: _error,
                isEmpty: _tasks.isEmpty,
                onRetry: _load,
                emptyText: '暂无对账待办',
                emptyIcon: Icons.balance_outlined,
                padding: const EdgeInsets.symmetric(vertical: 8),
                builder: (context) => ListView.builder(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.only(bottom: 16),
                  itemCount: _tasks.length,
                  itemBuilder: (context, index) {
                    final task = _tasks[index];
                    return TaskCard(
                      task: task,
                      onTap: task.isCompleted ? null : () => _openForm(task),
                      trailing: task.isCompleted
                          ? TextButton(
                              onPressed: () => _confirmRevoke(task),
                              child: const Text('撤销对账'),
                            )
                          : null,
                    );
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
