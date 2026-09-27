import 'package:beancount_trans/services/update_service.dart';
import 'package:beancount_trans/widgets/update_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // 测试宿主机不是 Android，canInstallInApp 恒为 false，走「复制下载链接」分支
  final info = UpdateInfo(
    currentVersion: '1.0.0',
    latestVersion: '1.1.0',
    notes:
        '## 新特性\n\n- 支持应用内更新\n\n```\nflutter build apk\n```\n\n'
        '${'很长的更新说明段落。' * 60}',
    apkUrl: null,
    releaseUrl: 'https://example.com/release',
  );

  Future<void> openDialog(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => showUpdateDialog(context, info),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('展示版本对比与更新说明，长内容不溢出', (tester) async {
    await openDialog(tester);

    expect(find.text('发现新版本'), findsOneWidget);
    expect(find.text('当前 1.0.0'), findsOneWidget);
    expect(find.text('最新 1.1.0'), findsOneWidget);
    expect(find.text('复制下载链接'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('复制下载链接后关闭弹窗并提示', (tester) async {
    // 测试环境没有真实剪贴板，拦截平台调用让复制走通
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async => null,
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    await openDialog(tester);

    await tester.tap(find.text('复制下载链接'));
    await tester.pumpAndSettle();

    expect(find.text('发现新版本'), findsNothing);
    expect(find.text('下载链接已复制'), findsOneWidget);
  });
}
