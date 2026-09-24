import 'package:flutter/material.dart';

import 'core/route_observer.dart';
import 'pages/assistant/assistant_chat_page.dart';
import 'pages/login_page.dart';
import 'pages/splash_page.dart';
import 'state/auth_store.dart';
import 'state/theme_store.dart';

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
        home: const AuthGate(),
        navigatorObservers: [routeObserver],
      ),
    );
  }

  static ThemeData _buildTheme(Brightness brightness) => ThemeData(
        useMaterial3: true,
        colorSchemeSeed: _brandSeed,
        brightness: brightness,
      );
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
