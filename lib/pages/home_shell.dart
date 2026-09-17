import 'package:flutter/material.dart';

import '../services/entry_review_service.dart';
import 'assistant/assistant_list_page.dart';
import 'profile_page.dart';
import 'reconciliation/reconciliation_list_page.dart';
import 'review/review_list_page.dart';

/// 应用主壳：底部导航四项（审核 / 对账 / Copilot / 我的），`IndexedStack` 保活。
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;
  int _reviewCount = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadReviewBadge());
  }

  Future<void> _loadReviewBadge() async {
    try {
      final count = await EntryReviewService.instance.pendingCount();
      if (mounted) setState(() => _reviewCount = count);
    } catch (_) {
      // 徽标失败不影响主壳展示
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: const [
          ReviewListPage(),
          ReconciliationListPage(),
          AssistantListPage(),
          ProfilePage(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (index) {
          setState(() => _index = index);
          if (index == 0) _loadReviewBadge();
        },
        destinations: [
          NavigationDestination(
            icon: _reviewIcon(const Icon(Icons.rule_outlined)),
            selectedIcon: _reviewIcon(const Icon(Icons.rule)),
            label: '审核',
          ),
          const NavigationDestination(
            icon: Icon(Icons.balance_outlined),
            selectedIcon: Icon(Icons.balance),
            label: '对账',
          ),
          const NavigationDestination(
            icon: Icon(Icons.auto_awesome_outlined),
            selectedIcon: Icon(Icons.auto_awesome),
            label: 'Copilot',
          ),
          const NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: '我的',
          ),
        ],
      ),
    );
  }

  Widget _reviewIcon(Widget icon) {
    return Badge(
      isLabelVisible: _reviewCount > 0,
      label: Text('$_reviewCount'),
      child: icon,
    );
  }
}
