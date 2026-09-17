import 'package:flutter/material.dart';

import 'core/route_observer.dart';
import 'pages/assistant/assistant_chat_page.dart';
import 'pages/login_page.dart';
import 'pages/splash_page.dart';
import 'state/auth_store.dart';

/// 应用根组件。
class BeancountTransApp extends StatelessWidget {
  const BeancountTransApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Beancount-Trans',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF2F6FED),
      ),
      home: const AuthGate(),
      navigatorObservers: [routeObserver],
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
