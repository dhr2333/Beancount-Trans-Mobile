import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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
  });

  final String content;

  /// 正文基准样式；标题、代码等在此基础上按比例推导。
  final TextStyle? baseStyle;

  /// 是否允许选中复制；离屏渲染成分享图时传 `false`（无需交互且更省开销）。
  final bool selectable;

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
      // 默认与 Web 端一致：回复内容可选中复制
      selectable: selectable,
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
        // 短列（金额、日期等）按内容宽度固定，长文本列吃掉剩余宽度并换行，
        // 避免默认的等宽列把长列挤窄（默认值 FlexColumnWidth 即所有列等宽）
        tableColumnWidth: const _AdaptiveTableColumnWidth(),
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

/// 自适应表格列宽：内容窄的列按内容宽度固定，内容宽的列吃掉剩余宽度并自动换行。
///
/// 对齐 Web 端表格观感（短列不挤压长列、长列在可用宽度内换行，无需横向滚动）。
/// 取值依据 [RenderTable] 的 `_computeColumnWidths`：
/// 短列 min=max=内容宽度且不参与弹性分配 → 既不被压缩也不抢宽度；
/// 长列 flex=1、下限为最小内容宽度 → 吸收剩余宽度、放不下时换行。
class _AdaptiveTableColumnWidth extends TableColumnWidth {
  const _AdaptiveTableColumnWidth();

  /// 自然宽度不超过该值的列视为「短列」（如金额、日期、状态）。
  static const double _shortColumnMaxWidth = 120;

  static double _naturalWidth(Iterable<RenderBox> cells) {
    var width = 0.0;
    for (final cell in cells) {
      width = math.max(width, cell.getMaxIntrinsicWidth(double.infinity));
    }
    return width;
  }

  static double _minContentWidth(Iterable<RenderBox> cells) {
    var width = 0.0;
    for (final cell in cells) {
      width = math.max(width, cell.getMinIntrinsicWidth(double.infinity));
    }
    return width;
  }

  static bool _isShortColumn(Iterable<RenderBox> cells) =>
      _naturalWidth(cells) <= _shortColumnMaxWidth;

  @override
  double maxIntrinsicWidth(Iterable<RenderBox> cells, double containerWidth) =>
      _naturalWidth(cells);

  @override
  double minIntrinsicWidth(Iterable<RenderBox> cells, double containerWidth) =>
      _isShortColumn(cells) ? _naturalWidth(cells) : _minContentWidth(cells);

  @override
  double? flex(Iterable<RenderBox> cells) => _isShortColumn(cells) ? null : 1;
}
