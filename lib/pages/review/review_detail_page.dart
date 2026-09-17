import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../models/parse_review.dart';
import '../../widgets/status_chip.dart';

/// 审核条目详情（**纯只读展示**）。
///
/// 本页不包含任何输入控件与提交按钮：如需修改，请在 Web 端操作。
class ReviewDetailPage extends StatelessWidget {
  const ReviewDetailPage({super.key, required this.entry});

  final FormattedEntry entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          entry.fileName.trim().isEmpty ? '条目详情' : entry.fileName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          const _ReadOnlyBanner(),
          const SizedBox(height: 14),
          _section(
            theme,
            '原始行',
            _buildOriginalRow(theme),
          ),
          _section(
            theme,
            'Beancount 条目',
            _buildFormatted(theme),
          ),
          _section(
            theme,
            '映射',
            _buildMapping(theme),
          ),
          _section(
            theme,
            '标签',
            _buildTags(theme),
          ),
          if (entry.installmentRole != null)
            _section(theme, '分期', _buildInstallment(theme)),
          _section(theme, '其他', _buildMeta(theme)),
        ],
      ),
    );
  }

  Widget _section(ThemeData theme, String title, Widget child) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SectionTitle(title),
            child,
          ],
        ),
      ),
    );
  }

  Widget _buildOriginalRow(ThemeData theme) {
    final row = entry.originalRow;
    if (row == null) {
      return Text(
        '无原始行数据',
        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InfoRow(label: '交易时间', value: _orDash(row.transactionTime)),
        InfoRow(label: '交易分类', value: _orDash(row.transactionCategory)),
        InfoRow(label: '交易对手方', value: _orDash(row.counterparty)),
        InfoRow(label: '商品/币种', value: _orDash(row.commodity)),
        InfoRow(label: '收支类型', value: _orDash(row.transactionType)),
        InfoRow(label: '金额', value: FormatUtil.amount(row.amount)),
        InfoRow(label: '支付方式', value: _orDash(row.paymentMethod)),
        InfoRow(label: '交易状态', value: _orDash(row.transactionStatus)),
        InfoRow(label: '交易单号', value: _orDash(row.billIdentifier)),
      ],
    );
  }

  Widget _buildFormatted(ThemeData theme) {
    final text = entry.displayFormatted.trim();
    if (text.isEmpty) {
      return Text(
        '暂无生成的 Beancount 条目',
        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
      );
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: SelectableText(
        text,
        style: theme.textTheme.bodySmall?.copyWith(
          fontFamily: 'monospace',
          height: 1.5,
        ),
      ),
    );
  }

  Widget _buildMapping(ThemeData theme) {
    final candidates = entry.sortedCandidates;
    if (entry.selectedExpenseKey.trim().isEmpty && candidates.isEmpty) {
      return Text(
        '无映射候选',
        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InfoRow(
          label: '当前命中',
          value: _orDash(entry.selectedExpenseKey),
        ),
        if (candidates.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            '候选（按匹配分降序）',
            style: theme.textTheme.labelMedium
                ?.copyWith(color: theme.colorScheme.outline),
          ),
          const SizedBox(height: 6),
          for (final candidate in candidates)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  Icon(
                    candidate.key == entry.selectedExpenseKey
                        ? Icons.check_circle
                        : Icons.radio_button_unchecked,
                    size: 16,
                    color: candidate.key == entry.selectedExpenseKey
                        ? theme.colorScheme.primary
                        : theme.colorScheme.outlineVariant,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: SelectableText(
                      candidate.key,
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                  Text(
                    '${candidate.score}',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.outline),
                  ),
                ],
              ),
            ),
        ],
      ],
    );
  }

  Widget _buildTags(ThemeData theme) {
    final details = entry.tagDetails;
    final overrides = entry.tagOverrides;
    final hasOverrides = overrides != null && !overrides.isEmpty;

    if (details.isEmpty && !hasOverrides) {
      return Text(
        '无标签',
        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final detail in details)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.local_offer_outlined,
                    size: 15, color: theme.colorScheme.outline),
                const SizedBox(width: 8),
                Expanded(
                  child: SelectableText(
                    detail.path,
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
                const SizedBox(width: 8),
                Wrap(
                  spacing: 4,
                  children: [
                    for (final source in detail.sources)
                      StatusChip(
                        label: _sourceLabel(source.type),
                        tone: _sourceTone(source.type),
                      ),
                  ],
                ),
              ],
            ),
          ),
        if (hasOverrides) ...[
          const SizedBox(height: 10),
          if (overrides.addedPaths.isNotEmpty) ...[
            _overrideTitle(theme, '新增的标签', theme.colorScheme.primary),
            for (final path in overrides.addedPaths)
              _overrideItem(theme, '+ $path', theme.colorScheme.primary),
          ],
          if (overrides.removedPaths.isNotEmpty) ...[
            const SizedBox(height: 8),
            _overrideTitle(theme, '移除的标签', theme.colorScheme.error),
            for (final path in overrides.removedPaths)
              _overrideItem(theme, '- $path', theme.colorScheme.error),
          ],
        ],
      ],
    );
  }

  Widget _overrideTitle(ThemeData theme, String text, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(
        text,
        style: theme.textTheme.labelMedium?.copyWith(color: color),
      ),
    );
  }

  Widget _overrideItem(ThemeData theme, String text, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: SelectableText(
        text,
        style: theme.textTheme.bodySmall?.copyWith(color: color),
      ),
    );
  }

  Widget _buildInstallment(ThemeData theme) {
    final role = entry.installmentRole ?? '';
    final label = role == 'installment'
        ? '分期还款'
        : (role == 'purchase' ? '分期消费' : role);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InfoRow(label: '类型', value: label),
        InfoRow(
          label: '期数',
          value: entry.installmentPeriod == null
              ? FormatUtil.placeholder
              : '${entry.installmentPeriod}',
        ),
      ],
    );
  }

  Widget _buildMeta(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InfoRow(label: '条目 UUID', value: _orDash(entry.uuid), monospace: true),
        InfoRow(
          label: '来源账单',
          value: _orDash(entry.fileName),
        ),
        InfoRow(
          label: '文件 ID',
          value: entry.fileId == null
              ? FormatUtil.placeholder
              : '${entry.fileId}',
        ),
      ],
    );
  }

  static String _sourceLabel(String type) {
    switch (type) {
      case 'mapping':
        return '映射';
      case 'source':
        return '来源';
      case 'manual':
        return '手动';
      default:
        return type.isEmpty ? '来源' : type;
    }
  }

  static ChipTone _sourceTone(String type) {
    switch (type) {
      case 'mapping':
        return ChipTone.info;
      case 'manual':
        return ChipTone.warning;
      default:
        return ChipTone.neutral;
    }
  }

  static String _orDash(String value) =>
      value.trim().isEmpty ? FormatUtil.placeholder : value.trim();
}

/// 顶部只读提示。
class _ReadOnlyBanner extends StatelessWidget {
  const _ReadOnlyBanner();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.visibility_outlined,
              size: 18, color: theme.colorScheme.onSecondaryContainer),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '仅查看，如需修改，请在 Web 端操作',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSecondaryContainer),
            ),
          ),
        ],
      ),
    );
  }
}
