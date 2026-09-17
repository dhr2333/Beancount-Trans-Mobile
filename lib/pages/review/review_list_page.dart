import 'package:flutter/material.dart';

import '../../core/api_exception.dart';
import '../../core/format.dart';
import '../../models/parse_review.dart';
import '../../services/entry_review_service.dart';
import '../../widgets/status_chip.dart';
import 'review_detail_page.dart';

/// 解析审核待办列表（**严格只读**）。
class ReviewListPage extends StatefulWidget {
  const ReviewListPage({super.key});

  @override
  State<ReviewListPage> createState() => _ReviewListPageState();
}

class _ReviewListPageState extends State<ReviewListPage> {
  EntryReviewResults? _data;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await EntryReviewService.instance.results();
      if (!mounted) return;
      setState(() => _data = result);
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _openDetail(FormattedEntry entry) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => ReviewDetailPage(entry: entry)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    final isEmpty = (data?.entries.isEmpty ?? true);

    return Scaffold(
      appBar: AppBar(
        title: const Text('解析审核待办'),
        actions: [
          IconButton(
            tooltip: '刷新',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _buildBody(data, isEmpty),
      ),
    );
  }

  Widget _buildBody(EntryReviewResults? data, bool isEmpty) {
    if (_loading && data == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && data == null) {
      return _ErrorView(message: _error!, onRetry: _load);
    }
    if (isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          if (data != null) _SummaryCard(data: data),
          const SizedBox(height: 80),
          Center(
            child: Column(
              children: [
                Icon(
                  Icons.task_alt,
                  size: 44,
                  color: Theme.of(context).colorScheme.outline,
                ),
                const SizedBox(height: 12),
                Text('暂无待审核条目', style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
          ),
        ],
      );
    }

    final grouped = data!.groupedByFile;
    final files = grouped.keys.toList();

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        _SummaryCard(data: data),
        for (final file in files) ...[
          _GroupHeader(fileName: file, count: grouped[file]!.length),
          for (final entry in grouped[file]!)
            _EntryCard(entry: entry, onTap: () => _openDetail(entry)),
        ],
      ],
    );
  }
}

/// 顶部汇总：待审条数 + 审核到期倒计时。
class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.data});

  final EntryReviewResults data;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final expiresAt = data.reviewExpiresAt;
    final expired = FormatUtil.isExpired(expiresAt);

    return Card(
      margin: const EdgeInsets.fromLTRB(12, 10, 12, 6),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.rule_folder_outlined, color: theme.colorScheme.primary),
                const SizedBox(width: 10),
                Text('待审核条目', style: theme.textTheme.titleSmall),
                const Spacer(),
                Text(
                  '${data.entryCount}',
                  style: theme.textTheme.headlineSmall
                      ?.copyWith(color: theme.colorScheme.primary),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                StatusChip(
                  label: expired
                      ? '审核已过期'
                      : FormatUtil.countdown(expiresAt),
                  tone: expired ? ChipTone.danger : ChipTone.info,
                  icon: Icons.timer_outlined,
                ),
                if (expiresAt != null)
                  StatusChip(
                    label: '截止 ${FormatUtil.unixDateTime(expiresAt)}',
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _GroupHeader extends StatelessWidget {
  const _GroupHeader({required this.fileName, required this.count});

  final String fileName;
  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 2),
      child: Row(
        children: [
          Icon(Icons.description_outlined, size: 16, color: theme.colorScheme.outline),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              fileName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelLarge
                  ?.copyWith(color: theme.colorScheme.outline),
            ),
          ),
          Text(
            '$count 条',
            style: theme.textTheme.labelMedium
                ?.copyWith(color: theme.colorScheme.outline),
          ),
        ],
      ),
    );
  }
}

class _EntryCard extends StatelessWidget {
  const _EntryCard({required this.entry, required this.onTap});

  final FormattedEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final row = entry.originalRow;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          row == null || row.counterparty.trim().isEmpty
                              ? '未填写交易对手方'
                              : row.counterparty,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${FormatUtil.date(row?.transactionTime)} · '
                          '${row == null || row.transactionType.trim().isEmpty ? FormatUtil.placeholder : row.transactionType}',
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: theme.colorScheme.outline),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    FormatUtil.signedAmount(row?.amount),
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.chevron_right, size: 18),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  if (row != null && row.commodity.trim().isNotEmpty)
                    StatusChip(label: row.commodity),
                  if (entry.isInstallmentRepayment)
                    const StatusChip(
                      label: '分期还款',
                      tone: ChipTone.warning,
                      icon: Icons.credit_score_outlined,
                    ),
                  if (entry.isInstallmentPurchase)
                    const StatusChip(
                      label: '分期消费',
                      tone: ChipTone.info,
                      icon: Icons.shopping_bag_outlined,
                    ),
                  if (entry.selectedExpenseKey.trim().isNotEmpty)
                    StatusChip(
                      label: entry.selectedExpenseKey,
                      icon: Icons.local_offer_outlined,
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        const SizedBox(height: 100),
        Icon(Icons.error_outline, size: 44, color: theme.colorScheme.outline),
        const SizedBox(height: 12),
        Center(child: Text('加载失败', style: theme.textTheme.titleMedium)),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Text(
            message,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.outline),
          ),
        ),
        const SizedBox(height: 16),
        Center(
          child: FilledButton.tonal(onPressed: onRetry, child: const Text('重试')),
        ),
      ],
    );
  }
}
