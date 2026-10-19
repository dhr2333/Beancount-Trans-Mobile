import 'package:beancount_trans/widgets/assistant_share_card.dart';
import 'package:beancount_trans/widgets/markdown_content.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pump(WidgetTester tester, List<AssistantShareTurn> turns) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          key: const Key('share-card-scroll'),
          child: AssistantShareCard(turns: turns),
        ),
      ),
    ),
  );
}

void main() {
  group('AssistantShareCard', () {
    testWidgets('单轮分享渲染页眉页脚，且不显示轮次编号', (tester) async {
      await _pump(tester, const [
        AssistantShareTurn(
          userMessage: '本月餐饮花了多少？',
          assistantContent: '**餐饮** 1,200.00 元。',
        ),
      ]);

      expect(tester.takeException(), isNull);
      expect(find.text('财见'), findsOneWidget);
      expect(find.text('你的问题'), findsOneWidget);
      expect(find.text('Copilot'), findsOneWidget);
      expect(find.text('本月餐饮花了多少？'), findsOneWidget);
      expect(find.text('对话 1'), findsNothing);
      expect(find.textContaining('隐私提示'), findsOneWidget);
      expect(find.textContaining('仅供参考'), findsOneWidget);
    });

    testWidgets('多轮分享按顺序编号并渲染各自提问', (tester) async {
      await _pump(tester, const [
        AssistantShareTurn(userMessage: '问题一', assistantContent: '回答一'),
        AssistantShareTurn(userMessage: '问题二', assistantContent: '回答二'),
      ]);

      expect(tester.takeException(), isNull);
      expect(find.text('对话 1'), findsOneWidget);
      expect(find.text('对话 2'), findsOneWidget);
      expect(find.text('问题一'), findsOneWidget);
      expect(find.text('问题二'), findsOneWidget);
    });

    testWidgets('宽表格在分享图内收缩换行，内容不被裁掉', (tester) async {
      const table = '''
| 一级类目 | 近 24 个月 | 近 12 个月 | 近 6 个月 |
| --- | --- | --- | --- |
| 餐饮（Expenses:Food） | 54,287.94 | 32,456.00 | 18,000.00 |
| 居家生活（Expenses:Home） | 216,562.66 | 13,238.00 | 8,000.00 |
''';

      await _pump(tester, const [
        AssistantShareTurn(userMessage: '各分类支出？', assistantContent: table),
      ]);

      expect(tester.takeException(), isNull);

      final tableSize = tester.getSize(find.byType(Table));
      // 卡片内容区宽度 = 卡片宽度 - 左右内边距
      expect(tableSize.width, lessThanOrEqualTo(kAssistantShareCardWidth - 48));

      // 分享图不可滚动，不应出现横向滚动容器
      final horizontalViews = tester
          .widgetList<SingleChildScrollView>(
            find.descendant(
              of: find.byType(MarkdownContent),
              matching: find.byType(SingleChildScrollView),
            ),
          )
          .where((view) => view.scrollDirection == Axis.horizontal);
      expect(horizontalViews, isEmpty);
    });

    testWidgets('卡片固定宽度且忽略系统字体缩放，保证分享图输出稳定', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: const Scaffold(
              body: SingleChildScrollView(
                child: AssistantShareCard(
                  turns: [
                    AssistantShareTurn(
                      userMessage: '问题',
                      assistantContent: '回答',
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(
        tester.getSize(find.byType(AssistantShareCard)).width,
        kAssistantShareCardWidth,
      );
      expect(
        MediaQuery.textScalerOf(tester.element(find.text('财见'))),
        TextScaler.noScaling,
      );
    });
  });
}
