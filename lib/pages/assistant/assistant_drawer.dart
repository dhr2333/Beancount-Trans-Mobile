import 'package:flutter/material.dart';

import '../../core/format.dart';
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
    required this.onNewChat,
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
  final VoidCallback onNewChat;
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
            _buildTodoTile(),
            _buildProfileTile(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
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
          const SizedBox(height: 4),
          FilledButton.tonalIcon(
            onPressed: onNewChat,
            icon: const Icon(Icons.add_comment_outlined, size: 18),
            label: const Text('新对话'),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchField(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: TextField(
        controller: searchController,
        textInputAction: TextInputAction.search,
        onSubmitted: (_) => onSearchSubmitted(),
        decoration: InputDecoration(
          hintText: '搜索会话',
          isDense: true,
          prefixIcon: const Icon(Icons.search, size: 20),
          border: const OutlineInputBorder(),
          // 无内部状态：用 ValueListenableBuilder 监听控制器决定清空按钮显隐
          suffixIcon: ValueListenableBuilder<TextEditingValue>(
            valueListenable: searchController,
            builder: (context, value, _) {
              if (value.text.isEmpty) return const SizedBox.shrink();
              return IconButton(
                tooltip: '清空',
                iconSize: 18,
                icon: const Icon(Icons.clear),
                onPressed: () {
                  searchController.clear();
                  onSearchSubmitted();
                },
              );
            },
          ),
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
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.error),
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
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.outline),
        ),
      );
    }

    return ListView.builder(
      padding: EdgeInsets.zero,
      itemCount: sessions.length,
      itemBuilder: (context, index) {
        final session = sessions[index];
        return Dismissible(
          key: ValueKey(session.id),
          direction: DismissDirection.endToStart,
          // 返回 false：由父级确认后自行移除，避免 Dismissible 提前销毁条目
          confirmDismiss: (_) async {
            onDeleteSession(session);
            return false;
          },
          background: Container(
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 20),
            color: theme.colorScheme.errorContainer,
            child: Icon(
              Icons.delete_outline,
              color: theme.colorScheme.onErrorContainer,
            ),
          ),
          child: ListTile(
            leading: const Icon(Icons.chat_bubble_outline),
            title: Text(
              session.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(FormatUtil.dateTime(session.modified)),
            selected: session.id == currentSessionId,
            trailing: const Icon(Icons.chevron_right, size: 18),
            onTap: () => onSelectSession(session.id),
          ),
        );
      },
    );
  }

  Widget _buildTodoTile() {
    return ListTile(
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

  Widget _buildProfileTile() {
    return ListenableBuilder(
      listenable: AuthStore.instance,
      builder: (context, _) {
        final displayName = AuthStore.instance.user?.displayName ?? '';
        return ListTile(
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
