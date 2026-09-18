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
          .widgetList<EditableText>(find.byType(EditableText))
          .map((e) => e.controller.text)
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
      await _pump(tester, List.generate(200, (i) => '- 第 $i 行 **加粗**').join('\n'));
      expect(tester.takeException(), isNull);
    });
  });
}
