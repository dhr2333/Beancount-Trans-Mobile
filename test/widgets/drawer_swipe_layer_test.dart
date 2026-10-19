import 'package:beancount_trans/widgets/drawer_swipe_layer.dart';
import 'package:beancount_trans/widgets/markdown_content.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const String _text = '这是一段普通回复文本，用来测试右滑打开抽屉。';

const String _table = '''
| 账户名称 | 交易日期 | 对手方 | 摘要说明 | 借方金额 | 贷方金额 | 余额 | 备注信息 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 餐饮 | 2026-10-01 | 某餐厅 | 聚餐 | 1200 | 0 | 800 | 团建 |
''';

Future<void> _pump(
  WidgetTester tester,
  GlobalKey<ScaffoldState> key,
  String content,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        key: key,
        drawer: const Drawer(child: Text('drawer')),
        drawerEnableOpenDragGesture: false,
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 360,
            height: double.infinity,
            child: DrawerSwipeLayer(
              onOpen: () => key.currentState?.openDrawer(),
              child: ListView(
                padding: const EdgeInsets.all(12),
                children: [MarkdownContent(content: content)],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

Finder _horizontalView() => find.descendant(
  of: find.byType(MarkdownContent),
  matching: find.byWidgetPredicate(
    (widget) =>
        widget is SingleChildScrollView &&
        widget.scrollDirection == Axis.horizontal,
  ),
);

void main() {
  group('DrawerSwipeLayer', () {
    testWidgets('普通文本右滑打开抽屉', (tester) async {
      final key = GlobalKey<ScaffoldState>();
      await _pump(tester, key, _text);

      final text = find.byWidgetPredicate(
        (widget) =>
            widget is RichText && widget.text.toPlainText().contains('普通回复'),
      );
      await tester.timedDrag(
        text.first,
        const Offset(300, 0),
        const Duration(milliseconds: 300),
      );
      await tester.pumpAndSettle();

      expect(key.currentState!.isDrawerOpen, isTrue);
    });

    testWidgets('普通文本左滑不打开抽屉', (tester) async {
      final key = GlobalKey<ScaffoldState>();
      await _pump(tester, key, _text);

      final text = find.byWidgetPredicate(
        (widget) =>
            widget is RichText && widget.text.toPlainText().contains('普通回复'),
      );
      await tester.timedDrag(
        text.first,
        const Offset(-300, 0),
        const Duration(milliseconds: 300),
      );
      await tester.pumpAndSettle();

      expect(key.currentState!.isDrawerOpen, isFalse);
    });

    testWidgets('表格内横向拖动只滚动表格，不打开抽屉', (tester) async {
      final key = GlobalKey<ScaffoldState>();
      await _pump(tester, key, _table);

      final controller = tester
          .widget<SingleChildScrollView>(_horizontalView())
          .controller!;
      final cell = find.byWidgetPredicate(
        (widget) => widget is Text && widget.textSpan?.toPlainText() == '餐饮',
      );

      // 左滑查看被裁掉的右侧列
      await tester.drag(cell, const Offset(-200, 0));
      await tester.pumpAndSettle();
      expect(controller.offset, greaterThan(0));
      expect(key.currentState!.isDrawerOpen, isFalse);

      // 右滑回到起始位置，同样不能误开抽屉
      final startOffset = controller.offset;
      await tester.drag(_horizontalView(), const Offset(200, 0));
      await tester.pumpAndSettle();
      expect(controller.offset, lessThan(startOffset));
      expect(key.currentState!.isDrawerOpen, isFalse);
    });

    testWidgets('表格内纵向拖动不打开抽屉', (tester) async {
      final key = GlobalKey<ScaffoldState>();
      await _pump(tester, key, _table);

      final cell = find.byWidgetPredicate(
        (widget) => widget is Text && widget.textSpan?.toPlainText() == '餐饮',
      );
      await tester.timedDrag(
        cell,
        const Offset(0, -200),
        const Duration(milliseconds: 300),
      );
      await tester.pumpAndSettle();

      expect(key.currentState!.isDrawerOpen, isFalse);
    });
  });
}
