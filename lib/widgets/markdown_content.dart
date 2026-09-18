import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

/// Markdown 渲染组件，对齐 Web 端 `components/assistant/MarkdownContent.vue`。
///
/// 支持标题、列表、表格、行内代码/代码块、引用、分割线、链接（GFM）。
/// 换行行为与 Web 端 markdown-it 的 `breaks: true` 一致（单个换行即换行）。
class MarkdownContent extends StatelessWidget {
  const MarkdownContent({super.key, required this.content, this.baseStyle});

  final String content;

  /// 正文基准样式；标题、代码等在此基础上按比例推导。
  final TextStyle? baseStyle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final base = (baseStyle ?? theme.textTheme.bodyMedium ?? const TextStyle())
        .copyWith(height: 1.5);
    final fontSize = base.fontSize ?? 14;

    TextStyle heading(double scale) => base.copyWith(
          fontSize: fontSize * scale,
          fontWeight: FontWeight.w600,
          height: 1.4,
        );

    const headingPadding = EdgeInsets.only(top: 10, bottom: 4);

    return MarkdownBody(
      data: content,
      // 保持与 Web 端一致：回复内容可选中复制
      selectable: true,
      softLineBreak: true,
      styleSheet: MarkdownStyleSheet(
        p: base,
        pPadding: EdgeInsets.zero,
        a: base.copyWith(color: scheme.primary),
        em: base.copyWith(fontStyle: FontStyle.italic),
        strong: base.copyWith(fontWeight: FontWeight.w600),
        h1: heading(1.3),
        h2: heading(1.18),
        h3: heading(1.06),
        h4: base.copyWith(fontWeight: FontWeight.w600),
        h5: base.copyWith(fontWeight: FontWeight.w600),
        h6: base.copyWith(fontWeight: FontWeight.w600),
        h1Padding: headingPadding,
        h2Padding: headingPadding,
        h3Padding: headingPadding,
        h4Padding: headingPadding,
        h5Padding: headingPadding,
        h6Padding: headingPadding,
        code: base.copyWith(
          fontFamily: 'monospace',
          fontSize: fontSize * 0.9,
          color: scheme.primary,
          backgroundColor: scheme.surfaceContainerHighest,
        ),
        codeblockPadding: const EdgeInsets.all(10),
        codeblockDecoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(6),
        ),
        blockquote: base.copyWith(color: scheme.onSurfaceVariant),
        blockquotePadding: const EdgeInsets.fromLTRB(12, 4, 8, 4),
        blockquoteDecoration: BoxDecoration(
          border: Border(
            left: BorderSide(color: scheme.outlineVariant, width: 3),
          ),
        ),
        listBullet: base,
        listIndent: 20,
        listBulletPadding: const EdgeInsets.only(right: 6),
        tableHead: base.copyWith(fontWeight: FontWeight.w600),
        tableBody: base,
        tableHeadAlign: TextAlign.left,
        tableBorder: TableBorder.all(color: scheme.outlineVariant),
        tableCellsPadding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
        tableHeadCellsDecoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
        ),
        tablePadding: EdgeInsets.zero,
        horizontalRuleDecoration: BoxDecoration(
          border: Border(top: BorderSide(color: scheme.outlineVariant)),
        ),
        blockSpacing: 8,
      ),
      onTapLink: (text, href, title) => _onLinkTap(context, href),
    );
  }

  /// 链接点击不打开系统浏览器（与 FavaPage 的外链策略一致），只提示并支持复制。
  void _onLinkTap(BuildContext context, String? href) {
    final url = href?.trim() ?? '';
    if (url.isEmpty) return;
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('已拦截外部链接：$url'),
          action: SnackBarAction(
            label: '复制链接',
            onPressed: () => Clipboard.setData(ClipboardData(text: url)),
          ),
        ),
      );
  }
}
