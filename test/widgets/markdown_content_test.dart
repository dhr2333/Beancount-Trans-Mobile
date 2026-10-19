import 'package:beancount_trans/widgets/markdown_content.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 覆盖 GFM 主要语法：标题、加粗、表格、列表、引用、行内代码、代码块、链接。
const String _sample = '''
## 本月概览

**总支出** 3,200.00 元，环比下降 12%。

| 分类 | 金额 |
| --- | --- |
| 餐饮 | 1,200.00 |
| 交通 | 800.00 |

- 餐饮环比下降 20%
- 交通持平

> 数据来自 `ledger.bean`

```bql
SELECT sum(position) WHERE account ~ "Expenses"
```

详见 [Fava 报表](https://trans.dhr2333.cn/fava/)。
''';

Future<void> _pump(WidgetTester tester, String content) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(child: MarkdownContent(content: content)),
      ),
    ),
  );
}

void main() {
  group('MarkdownContent', () {
    testWidgets('渲染 GFM 内容不抛异常', (tester) async {
      await _pump(tester, _sample);
      expect(tester.takeException(), isNull);
    });

    testWidgets('表格与代码块渲染为对应组件', (tester) async {
      await _pump(tester, _sample);

      // 表格：Table 组件存在，且表头、单元格文本已进入渲染树
      expect(find.byType(Table), findsOneWidget);

      final texts = tester
          .widgetList<Text>(find.byType(Text))
          .map((e) => e.textSpan?.toPlainText() ?? e.data ?? '')
          .join('\n');
      expect(texts, contains('本月概览'));
      expect(texts, contains('总支出'));
      expect(texts, contains('餐饮'));
      expect(texts, contains('SELECT sum(position)'));
      expect(texts, contains('ledger.bean'));
    });

    testWidgets('空内容不报错', (tester) async {
      await _pump(tester, '');
      expect(tester.takeException(), isNull);
    });

    testWidgets('超长内容不抛异常（避免流式文本解析崩溃）', (tester) async {
      await _pump(
        tester,
        List.generate(200, (i) => '- 第 $i 行 **加粗**').join('\n'),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('表格短列按内容收窄，长文本在列宽上限内换行', (tester) async {
      const note = '本月聚餐三次包含一次团建所以说明文本明显比其它单元格都要长';
      const table =
          '''
| 账户 | 金额 | 说明 |
| --- | --- | --- |
| 餐饮 | 1200 | $note |
''';

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 360,
                child: SingleChildScrollView(
                  child: MarkdownContent(content: table),
                ),
              ),
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);

      Size cellSize(String text) => tester.getSize(
        find.byWidgetPredicate(
          (widget) => widget is Text && widget.textSpan?.toPlainText() == text,
        ),
      );

      final amountSize = cellSize('1200');
      final noteSize = cellSize(note);

      expect(amountSize.width, lessThan(90));
      expect(noteSize.width, greaterThan(150));
      expect(amountSize.width, lessThan(noteSize.width));
      // 长文本封顶换行，而不是撑成单行横向拖到尽头
      expect(noteSize.height, greaterThan(amountSize.height + 8));
    });

    testWidgets('列过多时表格可横向滑动且不显示滚动条', (tester) async {
      const table = '''
| 账户名称 | 交易日期 | 对手方 | 摘要说明 | 借方金额 | 贷方金额 | 余额 | 备注信息 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 餐饮 | 2026-10-01 | 某餐厅 | 聚餐 | 1200 | 0 | 800 | 团建 |
''';

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 360,
                child: SingleChildScrollView(
                  child: MarkdownContent(content: table),
                ),
              ),
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);

      final tableSize = tester.getSize(find.byType(Table));
      expect(tableSize.width, greaterThan(360));

      final horizontalViews = tester
          .widgetList<SingleChildScrollView>(find.byType(SingleChildScrollView))
          .where((view) => view.scrollDirection == Axis.horizontal);
      expect(horizontalViews, isNotEmpty);
      expect(horizontalViews.first.controller, isNotNull);

      final viewport = tester.getSize(
        find
            .descendant(
              of: find.byType(MarkdownContent),
              matching: find.byWidgetPredicate(
                (widget) =>
                    widget is SingleChildScrollView &&
                    widget.scrollDirection == Axis.horizontal,
              ),
            )
            .first,
      );
      expect(viewport.width, lessThanOrEqualTo(360));

      final scrollbar = tester.widget<Scrollbar>(
        find.descendant(
          of: find.byType(MarkdownContent),
          matching: find.byType(Scrollbar),
        ),
      );
      expect(scrollbar.thumbVisibility, isFalse);
      // 滚动期间也不显示滚动条：表格内显式 Scrollbar 的粗细与颜色都被隐藏。
      final scrollbarTheme = tester.widget<ScrollbarTheme>(
        find
            .descendant(
              of: find.byType(MarkdownContent),
              matching: find.byType(ScrollbarTheme),
            )
            .first,
      );
      expect(scrollbarTheme.data.thickness?.resolve(<WidgetState>{}), 0);
      expect(
        scrollbarTheme.data.thumbColor?.resolve(<WidgetState>{}),
        Colors.transparent,
      );

      final horizontalFinder = find.descendant(
        of: find.byType(MarkdownContent),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is SingleChildScrollView &&
              widget.scrollDirection == Axis.horizontal,
        ),
      );
      final horizontalView = tester.widget<SingleChildScrollView>(
        horizontalFinder,
      );
      expect(horizontalView.controller!.offset, 0);

      // 从单元格内开始横向拖动也应滚动表格，而不是被文字选择手势拦截。
      final cellFinder = find.byWidgetPredicate(
        (widget) => widget is Text && widget.textSpan?.toPlainText() == '餐饮',
      );
      await tester.drag(cellFinder, const Offset(-200, 0));
      await tester.pumpAndSettle();
      expect(horizontalView.controller!.offset, greaterThan(0));
      expect(tester.takeException(), isNull);
    });
  });
}
