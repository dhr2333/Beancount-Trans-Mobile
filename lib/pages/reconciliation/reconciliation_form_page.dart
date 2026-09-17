import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/api_exception.dart';
import '../../core/format.dart';
import '../../models/reconciliation.dart';
import '../../services/reconciliation_service.dart';
import '../../widgets/status_chip.dart';

/// 对账表单（单页三步）：start → 实际余额 + 差额分配 → execute。
class ReconciliationFormPage extends StatefulWidget {
  const ReconciliationFormPage({super.key, required this.taskId});

  final int taskId;

  @override
  State<ReconciliationFormPage> createState() => _ReconciliationFormPageState();
}

class _ReconciliationFormPageState extends State<ReconciliationFormPage> {
  final TextEditingController _actualController = TextEditingController();

  ReconciliationStart? _start;
  List<_ItemEntry> _items = const [];
  List<AccountNode> _accounts = const [];
  String _currency = '';
  String? _error;
  bool _loading = true;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _actualController.addListener(_onInputChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _actualController.dispose();
    for (final item in _items) {
      item.amountController.removeListener(_onInputChanged);
      item.dispose();
    }
    super.dispose();
  }

  void _onInputChanged() => setState(() {});

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await ReconciliationService.instance.start(widget.taskId);
      if (!mounted) return;
      setState(() {
        _start = data;
        _currency = data.defaultCurrency ??
            (data.balances.isNotEmpty ? data.balances.first.currency : '');
        _items = [];
      });
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ---------------------------------------------------------------- 计算

  /// 当前币种的预期余额。
  String get _expectedBalance {
    final start = _start;
    if (start == null) return '';
    for (final balance in start.balances) {
      if (balance.currency == _currency) return balance.expectedBalance;
    }
    return '';
  }

  /// 基础差额 = 实际余额 − 预期余额。
  _Dec? get _baseDifference {
    final actual = _Dec.tryParse(_actualController.text);
    final expected = _Dec.tryParse(_expectedBalance);
    if (actual == null || expected == null) return null;
    return actual - expected;
  }

  /// 已分配金额合计。
  _Dec get _totalAllocated {
    var total = _Dec.zero;
    for (final item in _items) {
      final amount = _Dec.tryParse(item.amountController.text);
      if (amount != null) total = total + amount;
    }
    return total;
  }

  /// 剩余待分配差额 = −基础差额 − 已分配。
  _Dec? get _remaining {
    final base = _baseDifference;
    if (base == null) return null;
    return -base - _totalAllocated;
  }

  List<String> get _errors {
    final start = _start;
    final base = _baseDifference;
    if (start == null || base == null) return const [];

    final errors = <String>[];
    final items = _items.where((e) => e.account.isNotEmpty).toList();

    for (final item in items) {
      final text = item.amountController.text.trim();
      if (text.isNotEmpty && _Dec.tryParse(text) == null) {
        return ['条目金额格式不正确：$text'];
      }
    }

    if (base.isZero) {
      final withAmount = items.where(
        (e) => e.amountController.text.trim().isNotEmpty,
      );
      if (withAmount.isNotEmpty) {
        errors.add('预期余额和实际余额相等时，差额分配中的金额需留空');
      }
      return errors;
    }

    if (items.isEmpty) return errors;

    for (final item in items) {
      if (item.account == start.accountName) {
        errors.add('差额分配账户不能与对账账户相同（${start.accountName}）');
        break;
      }
    }

    final lastDate = start.lastReconciliationDate;
    if (lastDate != null) {
      for (final item in items) {
        final date = item.date;
        if (date == null || date.isEmpty) continue;
        if (item.amountController.text.trim().isEmpty) continue;
        if (date.compareTo(lastDate) <= 0) {
          errors.add('条目日期 $date 必须晚于上一次对账日期 $lastDate');
        }
      }
    }

    final emptyAmountCount = items
        .where((e) => e.amountController.text.trim().isEmpty)
        .length;
    if (emptyAmountCount > 1) {
      errors.add('只能有一个账户的金额留空（由系统自动分配剩余差额）');
      return errors;
    }

    if (emptyAmountCount == 0) {
      final target = -base;
      if (!_totalAllocated.equals(target)) {
        errors.add(
          '已分配金额与差额不匹配（应分配 ${target.toFixed(2)}，'
          '已分配 ${_totalAllocated.toFixed(2)}）',
        );
      }
    }

    return errors;
  }

  // ---------------------------------------------------------------- 交互

  void _addItem() {
    final start = _start;
    final entry = _ItemEntry(account: start?.defaultAllocationAccount ?? '');
    entry.amountController.addListener(_onInputChanged);
    setState(() => _items = [..._items, entry]);
  }

  void _removeItem(int index) {
    final removed = _items[index];
    removed.amountController.removeListener(_onInputChanged);
    setState(() => _items = [..._items]..removeAt(index));
    removed.dispose();
  }

  Future<void> _pickAccount(int index) async {
    if (_accounts.isEmpty) {
      try {
        final tree = await ReconciliationService.instance.accountTree();
        if (!mounted) return;
        setState(() => _accounts = AccountNode.flatTree(tree));
      } on ApiException catch (error) {
        if (!mounted) return;
        _notify(error.message);
        return;
      }
    }
    if (!mounted) return;

    final options = _accounts.where((e) => e.enable && e.account.isNotEmpty).toList();
    final selected = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        builder: (_, scrollController) => Column(
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('选择差额分配账户'),
              ),
            ),
            Expanded(
              child: ListView.builder(
                controller: scrollController,
                itemCount: options.length,
                itemBuilder: (context, i) {
                  final node = options[i];
                  return ListTile(
                    title: Text(node.account),
                    subtitle: node.accountType.isEmpty
                        ? null
                        : Text(node.accountType),
                    onTap: () => Navigator.of(sheetContext).pop(node.account),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );

    if (selected == null || !mounted) return;
    setState(() => _items[index].account = selected);
  }

  Future<void> _pickDate(int index) async {
    final start = _start;
    if (start == null) return;

    final asOf = DateTime.tryParse(start.asOfDate);
    if (asOf == null) {
      _notify('对账截止日期异常，无法选择日期');
      return;
    }
    final lastDate = start.lastReconciliationDate == null
        ? null
        : DateTime.tryParse(start.lastReconciliationDate!);
    final minDate = lastDate == null
        ? asOf.subtract(const Duration(days: 365))
        : lastDate.add(const Duration(days: 1));

    if (minDate.isAfter(asOf)) {
      _notify('上一次对账日期已到 ${start.lastReconciliationDate}，无可选日期');
      return;
    }

    final current = _items[index].date;
    final initial = current == null ? asOf : DateTime.tryParse(current) ?? asOf;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial.isBefore(minDate) ? minDate : initial,
      firstDate: minDate,
      lastDate: asOf,
    );
    if (picked == null || !mounted) return;
    setState(() {
      _items[index].date = FormatUtil.date(
        '${picked.year.toString().padLeft(4, '0')}-'
        '${picked.month.toString().padLeft(2, '0')}-'
        '${picked.day.toString().padLeft(2, '0')}',
      );
    });
  }

  Future<void> _submit() async {
    final start = _start;
    if (start == null) return;

    if (_actualController.text.trim().isEmpty) {
      _notify('请输入实际余额');
      return;
    }
    if (_Dec.tryParse(_actualController.text) == null) {
      _notify('实际余额格式不正确');
      return;
    }
    if (_currency.isEmpty) {
      _notify('请选择币种');
      return;
    }
    final errors = _errors;
    if (errors.isNotEmpty) {
      _notify(errors.first);
      return;
    }

    final drafts = _items
        .where((e) => e.account.isNotEmpty)
        .map((e) {
      final amount = e.amountController.text.trim();
      return amount.isEmpty
          ? TransactionItemDraft(account: e.account, isAuto: true)
          : TransactionItemDraft(
              account: e.account,
              amount: amount,
              isAuto: false,
              date: e.date,
            );
    }).toList();

    setState(() => _submitting = true);
    try {
      final result = await ReconciliationService.instance.execute(
        id: widget.taskId,
        actualBalance: _actualController.text.trim(),
        currency: _currency,
        asOfDate: start.asOfDate,
        transactionItems: drafts,
      );
      if (!mounted) return;
      await _showResult(result);
    } on ApiException catch (error) {
      if (mounted) _notify(error.message);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _showResult(ReconciliationExecuteResult result) async {
    final nextTaskId = result.nextTaskId;
    final action = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('对账完成'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (result.directives.isEmpty)
                const Text('已生成对账记录')
              else
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Theme.of(dialogContext)
                        .colorScheme
                        .surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: SelectableText(
                    result.directives.join('\n'),
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      height: 1.4,
                    ),
                  ),
                ),
            ],
          ),
        ),
        actions: [
          if (nextTaskId != null)
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop('next'),
              child: const Text('继续下一个'),
            ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop('done'),
            child: const Text('返回列表'),
          ),
        ],
      ),
    );

    if (!mounted) return;
    if (action == 'next' && nextTaskId != null) {
      Navigator.of(context).pushReplacement<bool, bool>(
        MaterialPageRoute<bool>(
          builder: (_) => ReconciliationFormPage(taskId: nextTaskId),
        ),
        result: true,
      );
      return;
    }
    Navigator.of(context).pop(true);
  }

  void _notify(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  // ---------------------------------------------------------------- 视图

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final start = _start;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          start == null || start.accountName.isEmpty ? '对账' : start.accountName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: _loading && start == null
          ? const Center(child: CircularProgressIndicator())
          : _error != null && start == null
              ? _buildError(theme)
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                  children: [
                    _buildOverview(theme, start!),
                    const SizedBox(height: 12),
                    _buildBalances(theme, start),
                    const SizedBox(height: 12),
                    _buildActualInput(theme),
                    const SizedBox(height: 12),
                    if (_baseDifference?.isZero == false) ...[
                      _buildAllocation(theme, start),
                      const SizedBox(height: 12),
                    ],
                    if (_errors.isNotEmpty) ...[
                      _buildErrorList(theme),
                      const SizedBox(height: 12),
                    ],
                    FilledButton(
                      onPressed: _submitting ? null : _submit,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                      ),
                      child: _submitting
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('提交对账'),
                    ),
                  ],
                ),
    );
  }

  Widget _buildError(ThemeData theme) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 44, color: theme.colorScheme.outline),
              const SizedBox(height: 12),
              Text('无法开始对账', style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.outline),
              ),
              const SizedBox(height: 16),
              FilledButton.tonal(onPressed: _load, child: const Text('重试')),
            ],
          ),
        ),
      );

  Widget _buildOverview(ThemeData theme, ReconciliationStart start) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionTitle('账户信息'),
            InfoRow(label: '账户', value: start.accountName),
            InfoRow(label: '对账截止日', value: FormatUtil.date(start.asOfDate)),
            InfoRow(
              label: '上次对账',
              value: start.lastReconciliationDate == null
                  ? '无记录'
                  : FormatUtil.date(start.lastReconciliationDate),
            ),
            if (start.isFirstReconciliation) ...[
              const SizedBox(height: 8),
              const StatusChip(
                label: '首次对账',
                tone: ChipTone.info,
                icon: Icons.flag_outlined,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildBalances(ThemeData theme, ReconciliationStart start) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionTitle('预期余额'),
            if (start.balances.isEmpty)
              Text(
                '后端未返回预期余额',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.outline),
              )
            else
              for (final balance in start.balances)
                InfoRow(
                  label: balance.currency,
                  value: FormatUtil.amount(balance.expectedBalance),
                  monospace: true,
                ),
          ],
        ),
      ),
    );
  }

  Widget _buildActualInput(ThemeData theme) {
    final base = _baseDifference;
    final remaining = _remaining;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionTitle('实际余额'),
            TextField(
              controller: _actualController,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true, signed: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.\-]')),
              ],
              decoration: const InputDecoration(
                labelText: '实际余额',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final balance in _start?.balances ?? const <CurrencyBalance>[])
                  ChoiceChip(
                    label: Text(balance.currency),
                    selected: _currency == balance.currency,
                    onSelected: (_) => setState(() => _currency = balance.currency),
                  ),
              ],
            ),
            if (base != null) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '差额：${_signed(base)}',
                      style: theme.textTheme.titleSmall,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '已分配：${_signed(_totalAllocated)}'
                      '${remaining == null || remaining.isZero ? '（已完全分配）' : '（剩余：${_signed(remaining)}）'}',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.outline),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildAllocation(ThemeData theme, ReconciliationStart start) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SectionTitle(
              '差额分配',
              trailing: TextButton.icon(
                onPressed: _addItem,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('添加'),
              ),
            ),
            if (_items.isEmpty)
              Text(
                '账户余额与实际余额不一致，请添加差额分配条目。',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.outline),
              ),
            for (var i = 0; i < _items.length; i++) _buildItem(theme, i),
            if (start.lastReconciliationDate != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  '条目日期需晚于上次对账日期 ${FormatUtil.date(start.lastReconciliationDate)}，'
                  '且不晚于 ${FormatUtil.date(start.asOfDate)}',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.outline),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildItem(ThemeData theme, int index) {
    final item = _items[index];
    final isEmptyAmount = item.amountController.text.trim().isEmpty;

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 10),
        decoration: BoxDecoration(
          border: Border.all(color: theme.colorScheme.outlineVariant),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () => _pickAccount(index),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        children: [
                          Icon(Icons.account_balance_wallet_outlined,
                              size: 16, color: theme.colorScheme.outline),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              item.account.isEmpty ? '选择账户' : item.account,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: item.account.isEmpty
                                  ? theme.textTheme.bodyMedium
                                      ?.copyWith(color: theme.colorScheme.outline)
                                  : theme.textTheme.bodyMedium,
                            ),
                          ),
                          const Icon(Icons.expand_more, size: 18),
                        ],
                      ),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: '删除',
                  onPressed: () => _removeItem(index),
                  icon: const Icon(Icons.delete_outline, size: 20),
                ),
              ],
            ),
            const SizedBox(height: 6),
            TextField(
              controller: item.amountController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
                signed: true,
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.\-]')),
              ],
              decoration: const InputDecoration(
                labelText: '金额（留空表示自动分配）',
                isDense: true,
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                if (isEmptyAmount)
                  const StatusChip(
                    label: '自动分配剩余差额',
                    tone: ChipTone.info,
                    icon: Icons.auto_fix_high_outlined,
                  )
                else
                  ActionChip(
                    avatar: const Icon(Icons.event_outlined, size: 15),
                    label: Text(
                      item.date == null ? '选择日期（可选）' : item.date!,
                    ),
                    onPressed: () => _pickDate(index),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorList(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final error in _errors)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Text(
                '· $error',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onErrorContainer),
              ),
            ),
        ],
      ),
    );
  }

  static String _signed(_Dec value) =>
      value.isZero ? value.toFixed(2) : '${value.isNegative ? '' : '+'}${value.toFixed(2)}';
}

/// 差额分配条目（金额输入 + 日期）。
class _ItemEntry {
  _ItemEntry({this.account = ''});

  String account;
  String? date;
  final TextEditingController amountController = TextEditingController();

  void dispose() => amountController.dispose();
}

/// 定点十进制（BigInt 尾数 + 小数位数），金额运算不经 `double`。
class _Dec implements Comparable<_Dec> {
  const _Dec._(this.scaled, this.scale);

  final BigInt scaled;
  final int scale;

  static final _Dec zero = _Dec._(BigInt.zero, 0);

  bool get isZero => scaled == BigInt.zero;
  bool get isNegative => scaled.isNegative;

  static _Dec? tryParse(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return null;
    if (!RegExp(r'^[+-]?\d*(\.\d*)?$').hasMatch(text)) return null;

    var sign = 1;
    var body = text;
    if (body.startsWith('-')) {
      sign = -1;
      body = body.substring(1);
    } else if (body.startsWith('+')) {
      body = body.substring(1);
    }
    if (body.isEmpty || body == '.') return null;

    final parts = body.split('.');
    final intPart = parts[0].isEmpty ? '0' : parts[0];
    final fracPart = parts.length > 1 ? parts[1] : '';
    final digits = BigInt.tryParse('$intPart$fracPart');
    if (digits == null) return null;
    return _Dec._(BigInt.from(sign) * digits, fracPart.length);
  }

  _Dec operator +(_Dec other) {
    final target = scale > other.scale ? scale : other.scale;
    final a = scaled * _pow10(target - scale);
    final b = other.scaled * _pow10(target - other.scale);
    return _Dec._(a + b, target);
  }

  _Dec operator -(_Dec other) => this + (-other);

  _Dec operator -() => _Dec._(-scaled, scale);

  bool equals(_Dec other) => (this - other).isZero;

  @override
  int compareTo(_Dec other) => (this - other).scaled.sign;

  @override
  bool operator ==(Object other) =>
      other is _Dec && scaled == other.scaled && scale == other.scale;

  @override
  int get hashCode => Object.hash(scaled, scale);

  /// 固定小数位展示（截断多余位）。
  String toFixed(int digits) {
    var value = scaled;
    final negative = value.isNegative;
    if (negative) value = -value;

    var workScale = scale;
    while (workScale < digits) {
      value = value * BigInt.from(10);
      workScale += 1;
    }

    final text = value.toString().padLeft(workScale + 1, '0');
    final intPart = workScale == 0 ? text : text.substring(0, text.length - workScale);
    final fracPart = workScale == 0 ? '' : text.substring(text.length - workScale);
    final shown = fracPart.length > digits
        ? fracPart.substring(0, digits)
        : fracPart.padRight(digits, '0');

    return '${negative && value != BigInt.zero ? '-' : ''}$intPart'
        '${digits > 0 ? '.$shown' : ''}';
  }

  static BigInt _pow10(int exponent) {
    var result = BigInt.one;
    for (var i = 0; i < exponent; i++) {
      result = result * BigInt.from(10);
    }
    return result;
  }
}
