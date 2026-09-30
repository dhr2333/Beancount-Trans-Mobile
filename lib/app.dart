import 'package:flutter/material.dart';

import 'core/route_observer.dart';
import 'pages/assistant/assistant_chat_page.dart';
import 'pages/login_page.dart';
import 'pages/splash_page.dart';
import 'services/update_service.dart';
import 'state/auth_store.dart';
import 'state/theme_store.dart';
import 'widgets/update_dialog.dart';

/// 品牌主色（亮/暗主题共用同一种子色）。
const Color _brandSeed = Color(0xFF2F6FED);

/// 应用根组件：亮/暗主题由 [ThemeStore] 的外观偏好决定。
class BeancountTransApp extends StatelessWidget {
  const BeancountTransApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ThemeStore.instance,
      builder: (context, _) => MaterialApp(
        title: 'Beancount-Trans',
        debugShowCheckedModeBanner: false,
        theme: _buildTheme(Brightness.light),
        darkTheme: _buildTheme(Brightness.dark),
        themeMode: ThemeStore.instance.mode,
        home: const UpdateGate(child: AuthGate()),
        navigatorObservers: [routeObserver],
      ),
    );
  }

  static ThemeData _buildTheme(Brightness brightness) {
    final ColorScheme scheme = ColorScheme.fromSeed(
      seedColor: _brandSeed,
      brightness: brightness,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      // 顶栏固定用页面底色：Material 3 在内容滚到 AppBar 下方时会直接把背景换成
      // surfaceContainer（与 elevation 无关，scrolledUnderElevation=0 拦不住），
      // 表现为「下拉变色」。显式指定 backgroundColor 后，静止与滚动两种状态都用
      // 同一个颜色，长截图拼接时顶部区域也就稳定了。
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
    );
  }
}

/// 认证门：启动中 → 启动页；未登录 → 登录页；已登录 → Copilot 对话页。
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AuthStore.instance,
      builder: (context, _) {
        switch (AuthStore.instance.status) {
          case AuthStatus.unknown:
            return const SplashPage();
          case AuthStatus.loggedOut:
            return const LoginPage();
          case AuthStatus.loggedIn:
            return const AssistantChatPage();
        }
      },
    );
  }
}

/// 启动后自动检查更新：等启动页结束（登录态不再是 unknown）再检查，
/// 避免更新弹窗盖在启动页上；整个进程只检查一次，失败静默忽略。
class UpdateGate extends StatefulWidget {
  const UpdateGate({super.key, required this.child});

  final Widget child;

  @override
  State<UpdateGate> createState() => _UpdateGateState();
}

class _UpdateGateState extends State<UpdateGate> {
  bool _checked = false;

  @override
  void initState() {
    super.initState();
    AuthStore.instance.addListener(_maybeCheck);
  }

  @override
  void dispose() {
    AuthStore.instance.removeListener(_maybeCheck);
    super.dispose();
  }

  void _maybeCheck() {
    if (_checked || AuthStore.instance.status == AuthStatus.unknown) return;
    _checked = true;
    AuthStore.instance.removeListener(_maybeCheck);
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
  }

  Future<void> _check() async {
    if (!mounted) return;
    try {
      final info = await UpdateService.instance.checkForUpdate();
      if (info == null || !mounted) return;
      // 用户点过「稍后」的版本不再自动提醒（手动检查不受此限制）
      if (await UpdateService.instance.isVersionSkipped(info.latestBuild)) {
        return;
      }
      if (!mounted) return;
      await showUpdateDialog(context, info);
    } catch (error) {
      debugPrint('检查更新失败：$error');
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
