import 'package:flutter/material.dart';

import '../core/format.dart';
import '../models/scheduled_task.dart';
import 'status_chip.dart';

/// 待办任务卡片（对账 / 条目审核共用）。
class TaskCard extends StatelessWidget {
  const TaskCard({
    super.key,
    required this.task,
    this.onTap,
    this.trailing,
    this.showStatus = true,
  });

  final ScheduledTask task;
  final VoidCallback? onTap;
  final Widget? trailing;
  final bool showStatus;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = task.accountName ?? task.fileName ?? task.taskTypeDisplay;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title.isEmpty ? '未命名待办' : title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall,
                    ),
                  ),
                  ?trailing,
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (showStatus)
                    StatusChip(
                      label: task.statusDisplay.isEmpty
                          ? task.status
                          : task.statusDisplay,
                      tone: _statusTone(task.status),
                    ),
                  StatusChip(
                    label: '计划 ${FormatUtil.date(task.scheduledDate)}',
                    icon: Icons.event_outlined,
                  ),
                  if (task.completedDate != null && task.completedDate!.isNotEmpty)
                    StatusChip(
                      label: '完成 ${FormatUtil.date(task.completedDate)}',
                      icon: Icons.check_circle_outline,
                    ),
                  if (task.isOverdue) const StatusChip(label: '已逾期', tone: ChipTone.danger),
                  if ((task.entryCount ?? 0) > 0)
                    StatusChip(
                      label: '${task.entryCount} 条待审',
                      tone: ChipTone.info,
                      icon: Icons.rule_folder_outlined,
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  ChipTone _statusTone(String status) {
    switch (status) {
      case 'pending':
        return ChipTone.warning;
      case 'completed':
        return ChipTone.success;
      case 'cancelled':
        return ChipTone.danger;
      default:
        return ChipTone.neutral;
    }
  }
}
