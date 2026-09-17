import 'package:flutter/material.dart';

/// 列表类页面的统一「加载中 / 失败 / 空 / 内容」四态视图。
class AsyncView extends StatelessWidget {
  const AsyncView({
    super.key,
    required this.loading,
    required this.error,
    required this.onRetry,
    required this.isEmpty,
    required this.builder,
    this.emptyText = '暂无数据',
    this.emptyIcon = Icons.inbox_outlined,
    this.padding = const EdgeInsets.all(16),
  });

  final bool loading;
  final String? error;
  final VoidCallback onRetry;
  final bool isEmpty;
  final WidgetBuilder builder;
  final String emptyText;
  final IconData emptyIcon;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    if (loading && isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (error != null && isEmpty) {
      return _Message(
        icon: Icons.error_outline,
        title: '加载失败',
        detail: error,
        action: FilledButton.tonal(onPressed: onRetry, child: const Text('重试')),
      );
    }
    if (isEmpty) {
      return _Message(icon: emptyIcon, title: emptyText);
    }
    return builder(context);
  }
}

class _Message extends StatelessWidget {
  const _Message({
    required this.icon,
    required this.title,
    this.detail,
    this.action,
  });

  final IconData icon;
  final String title;
  final String? detail;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 44, color: theme.colorScheme.outline),
            const SizedBox(height: 12),
            Text(title, style: theme.textTheme.titleMedium),
            if (detail != null && detail!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                detail!,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.outline),
              ),
            ],
            if (action != null) ...[const SizedBox(height: 16), action!],
          ],
        ),
      ),
    );
  }
}
