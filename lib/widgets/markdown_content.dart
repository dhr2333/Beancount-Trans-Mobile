import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

/// Markdown 渲染组件，对齐 Web 端 `components/assistant/MarkdownContent.vue`。
///
/// 支持标题、列表、表格、行内代码/代码块、引用、分割线、链接（GFM）。
/// 换行行为与 Web 端 markdown-it 的 `breaks: true` 一致（单个换行即换行）。
class MarkdownContent extends StatelessWidget {
  const MarkdownContent({
    super.key,
    required this.content,
    this.baseStyle,
    this.selectable = true,
    this.fitTableWidth = false,
  });

  final String content;

  /// 正文基准样式；标题、代码等在此基础上按比例推导。
  final TextStyle? baseStyle;

  /// 是否允许选中复制；离屏渲染成分享图时传 `false`（无需交互且更省开销）。
  final bool selectable;

  /// 表格收缩到容器宽度并自动换行。
  ///
  /// 分享图等不可滚动场景传 `true`，保证超宽表格不会被裁掉；聊天正文传
  /// `false` 时超宽表格保持横向滚动。
  final bool fitTableWidth;

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

    return ScrollbarTheme(
      // 库内会给表格/代码块显式包 Scrollbar，thumbVisibility 为 false 时
      // 滚动期间仍会短暂显示；统一置为透明且零粗细，滚动全程都不出现滚动条。
      data: ScrollbarTheme.of(context).copyWith(
        thickness: const WidgetStatePropertyAll(0),
        thumbColor: const WidgetStatePropertyAll(Colors.transparent),
        trackColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
      child: ScrollConfiguration(
        behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
        child: _wrapSelectable(
          MarkdownBody(
            data: content,
            // 不使用库内置的 SelectableText：单元格里的文字选择手势会抢走横向拖动，
            // 导致宽表格无法左右滑动；改由外层 SelectionArea 统一提供选中复制。
            selectable: false,
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
              // IntrinsicColumnWidth 才会触发库内横向滚动；自定义上限避免长文本撑成单行。
              tableColumnWidth: fitTableWidth
                  ? const _FitTableColumnWidth()
                  : const _ScrollableTableColumnWidth(),
              tableScrollbarThumbVisibility: false,
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
          ),
        ),
      ),
    );
  }

  /// 可选中复制时包一层 [SelectionArea]。
  ///
  /// [SelectionArea] 位于表格横向滚动视图的上层，横向拖动会优先交给滚动视图，
  /// 不像 [SelectableText] 那样抢占单元格内的横向手势。
  Widget _wrapSelectable(Widget child) =>
      selectable ? SelectionArea(child: child) : child;

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

/// 可横向滑动的表格列宽：短列跟内容走，长列封顶后换行，总宽超出时由外层滚动。
///
/// 必须继承 [IntrinsicColumnWidth]：`flutter_markdown_plus` 只对 Fixed/Intrinsic
/// 包裹横向 [SingleChildScrollView]。单列上限避免长文本变成无限宽的一行。
class _ScrollableTableColumnWidth extends IntrinsicColumnWidth {
  const _ScrollableTableColumnWidth();

  /// 单列内容区加内边距后的最大宽度，超出则在单元格内换行。
  static const double _maxColumnWidth = 240;

  @override
  double maxIntrinsicWidth(Iterable<RenderBox> cells, double containerWidth) =>
      math.min(super.maxIntrinsicWidth(cells, containerWidth), _maxColumnWidth);

  @override
  double minIntrinsicWidth(Iterable<RenderBox> cells, double containerWidth) =>
      math.min(super.minIntrinsicWidth(cells, containerWidth), _maxColumnWidth);
}

/// 分享图等不可滚动场景的表格列宽：列可被压缩到 0 并让长文本换行。
///
/// 不继承 [IntrinsicColumnWidth]，因此库内不会包横向滚动容器；表格宽度受
/// 容器约束，列宽不足时文字自动换行，保证整张表完整出现在图片里。
class _FitTableColumnWidth implements TableColumnWidth {
  const _FitTableColumnWidth();

  @override
  double minIntrinsicWidth(Iterable<RenderBox> cells, double containerWidth) =>
      0;

  @override
  double maxIntrinsicWidth(Iterable<RenderBox> cells, double containerWidth) {
    var result = 0.0;
    for (final cell in cells) {
      result = math.max(result, cell.getMaxIntrinsicWidth(double.infinity));
    }
    return math.min(result, _ScrollableTableColumnWidth._maxColumnWidth);
  }

  @override
  double? flex(Iterable<RenderBox> cells) => null;
}
