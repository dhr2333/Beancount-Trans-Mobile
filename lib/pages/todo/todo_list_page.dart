import 'package:flutter/material.dart';

import '../../core/api_exception.dart';
import '../../core/format.dart';
import '../../core/route_observer.dart';
import '../../services/todo_service.dart';
import '../../widgets/async_view.dart';
import '../../widgets/status_chip.dart';
import '../reconciliation/reconciliation_form_page.dart';
import '../review/review_list_page.dart';

/// 待办列表（解析审核 + 到期对账）。
class TodoListPage extends StatefulWidget {
  const TodoListPage({super.key});

  @override
  State<TodoListPage> createState() => _TodoListPageState();
}

class _TodoListPageState extends State<TodoListPage> with RouteAware {
  TodoSummary? _summary;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    routeObserver.subscribe(this, ModalRoute.of(context)!);
  }

  @override
  void dispose() {
    routeObserver.unsubscribe(this);
    super.dispose();
  }

  /// 上层页面弹出、本页重新回到栈顶时刷新，避免展示已完成待办。
  @override
  void didPopNext() {
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await TodoService.instance.summary();
      if (!mounted) return;
      setState(() => _summary = result);
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// 打开待办详情；返回后刷新列表。
  Future<void> _openItem(TodoItem item) async {
    switch (item.kind) {
      case TodoKind.entryReview:
        await Navigator.of(
          context,
        ).push(MaterialPageRoute<void>(builder: (_) => const ReviewListPage()));
      case TodoKind.reconciliation:
        await Navigator.of(context).push(
          MaterialPageRoute<bool>(
            builder: (_) => ReconciliationFormPage(taskId: item.taskId!),
          ),
        );
    }
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final items = _summary?.items ?? const <TodoItem>[];

    return Scaffold(
      appBar: AppBar(
        title: const Text('待办'),
        actions: [
          IconButton(
            tooltip: '刷新',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: AsyncView(
          loading: _loading,
          error: _error,
          isEmpty: (_summary?.items.isEmpty ?? true),
          onRetry: _load,
          emptyText: '暂无到期待办',
          emptyIcon: Icons.task_alt,
          padding: const EdgeInsets.symmetric(vertical: 8),
          builder: (context) => ListView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.only(bottom: 24),
            itemCount: items.length,
            itemBuilder: (context, index) {
              final item = items[index];
              return _TodoCard(item: item, onTap: () => _openItem(item));
            },
          ),
        ),
      ),
    );
  }
}

/// 单条待办卡片。
class _TodoCard extends StatelessWidget {
  const _TodoCard({required this.item, required this.onTap});

  final TodoItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isReview = item.kind == TodoKind.entryReview;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    isReview
                        ? Icons.rule_folder_outlined
                        : Icons.balance_outlined,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      item.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall,
                    ),
                  ),
                  const Icon(Icons.chevron_right, size: 18),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  if (isReview) ...[
                    StatusChip(
                      label: '${item.entryCount} 条待审',
                      tone: ChipTone.info,
                      icon: Icons.rule_folder_outlined,
                    ),
                    if (item.reviewExpiresAt != null)
                      if (FormatUtil.isExpired(item.reviewExpiresAt))
                        const StatusChip(
                          label: '审核已过期',
                          tone: ChipTone.danger,
                          icon: Icons.timer_outlined,
                        )
                      else
                        StatusChip(
                          label: FormatUtil.countdown(item.reviewExpiresAt),
                          tone: ChipTone.info,
                          icon: Icons.timer_outlined,
                        ),
                  ] else ...[
                    StatusChip(
                      label: '计划 ${FormatUtil.date(item.scheduledDate)}',
                      icon: Icons.event_outlined,
                    ),
                    if (item.isOverdue)
                      const StatusChip(label: '已逾期', tone: ChipTone.danger),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
