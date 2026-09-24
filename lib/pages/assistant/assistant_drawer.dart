import 'package:flutter/material.dart';

import '../../models/assistant.dart';
import '../../state/auth_store.dart';

/// Copilot 对话页左侧抽屉：会话列表 + 待办 / 我的入口。
///
/// 无内部状态，数据与回调全部由 [AssistantChatPage] 通过构造参数注入。
class AssistantDrawer extends StatelessWidget {
  const AssistantDrawer({
    super.key,
    required this.searchController,
    required this.sessions,
    required this.loading,
    required this.error,
    required this.currentSessionId,
    required this.todoBadge,
    required this.onSearchSubmitted,
    required this.onSelectSession,
    required this.onDeleteSession,
    required this.onOpenTodo,
    required this.onOpenProfile,
    required this.onRefresh,
  });

  /// 会话搜索输入框控制器（由父级持有）。
  final TextEditingController searchController;
  final List<ChatSessionSummary> sessions;
  final bool loading;
  final String? error;
  final String currentSessionId;
  final int todoBadge;
  final VoidCallback onSearchSubmitted;
  final ValueChanged<String> onSelectSession;

  /// 滑动删除会话：父级弹出确认框后自行移除。
  final ValueChanged<ChatSessionSummary> onDeleteSession;
  final VoidCallback onOpenTodo;
  final VoidCallback onOpenProfile;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(context),
            _buildSearchField(context),
            Expanded(child: _buildSessionList(context)),
            const Divider(height: 1),
            _buildTodoTile(context),
            _buildProfileTile(context),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
      child: Row(
        children: [
          Text('Copilot', style: theme.textTheme.titleMedium),
          const Spacer(),
          IconButton(
            tooltip: '刷新',
            onPressed: loading ? null : onRefresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchField(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Container(
        padding: const EdgeInsets.only(left: 12, right: 4),
        decoration: BoxDecoration(
          // 与底部胶囊输入框同一底色，避免抽屉里并存两种输入风格
          color: theme.colorScheme.surfaceContainer,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          children: [
            Icon(
              Icons.search,
              size: 18,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: searchController,
                style: theme.textTheme.bodyMedium,
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => onSearchSubmitted(),
                decoration: InputDecoration(
                  hintText: '搜索会话',
                  // 默认 hintStyle 为 bodyLarge（16），显式降到与正文一致
                  hintStyle: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  isDense: true,
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                ),
              ),
            ),
            // 无内部状态：用 ValueListenableBuilder 监听控制器决定清空按钮显隐
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: searchController,
              builder: (context, value, _) {
                if (value.text.isEmpty) return const SizedBox(width: 4);
                return IconButton(
                  tooltip: '清空',
                  iconSize: 18,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints.tightFor(
                    width: 32,
                    height: 32,
                  ),
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    searchController.clear();
                    onSearchSubmitted();
                  },
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSessionList(BuildContext context) {
    final theme = Theme.of(context);

    if (loading && sessions.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (error != null && sessions.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                error!,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
              const SizedBox(height: 8),
              TextButton(onPressed: onRefresh, child: const Text('重试')),
            ],
          ),
        ),
      );
    }

    if (sessions.isEmpty) {
      return Center(
        child: Text(
          '暂无历史会话',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.outline,
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      itemCount: sessions.length,
      itemBuilder: (context, index) {
        final session = sessions[index];
        final selected = session.id == currentSessionId;
        return Dismissible(
          key: ValueKey(session.id),
          direction: DismissDirection.endToStart,
          // 返回 false：由父级确认后自行移除，避免 Dismissible 提前销毁条目
          confirmDismiss: (_) async {
            onDeleteSession(session);
            return false;
          },
          background: Container(
            margin: const EdgeInsets.only(bottom: 2),
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 16),
            decoration: BoxDecoration(
              color: theme.colorScheme.errorContainer,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              Icons.delete_outline,
              color: theme.colorScheme.onErrorContainer,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => onSelectSession(session.id),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: selected ? theme.colorScheme.primaryContainer : null,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  // 标题为空时与 Web 侧栏一致回退为「新对话」
                  session.title.trim().isEmpty ? '新对话' : session.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    height: 1.3,
                    color: selected
                        ? theme.colorScheme.onPrimaryContainer
                        : theme.colorScheme.onSurface,
                    fontWeight: selected ? FontWeight.w500 : null,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildTodoTile(BuildContext context) {
    return ListTile(
      titleTextStyle: Theme.of(context).textTheme.bodyMedium,
      leading: Badge(
        isLabelVisible: todoBadge > 0,
        label: Text('$todoBadge'),
        child: const Icon(Icons.checklist_outlined),
      ),
      title: const Text('待办'),
      trailing: const Icon(Icons.chevron_right, size: 18),
      onTap: onOpenTodo,
    );
  }

  Widget _buildProfileTile(BuildContext context) {
    return ListenableBuilder(
      listenable: AuthStore.instance,
      builder: (context, _) {
        final displayName = AuthStore.instance.user?.displayName ?? '';
        return ListTile(
          titleTextStyle: Theme.of(context).textTheme.bodyMedium,
          leading: CircleAvatar(
            child: Text(
              displayName.isEmpty
                  ? '?'
                  : displayName.substring(0, 1).toUpperCase(),
            ),
          ),
          title: Text(displayName.isEmpty ? '我的' : displayName),
          trailing: const Icon(Icons.chevron_right, size: 18),
          onTap: onOpenProfile,
        );
      },
    );
  }
}
