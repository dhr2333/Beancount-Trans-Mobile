/// 对账模块数据模型。
library;

/// 单币种预期余额（金额保持字符串）。
class CurrencyBalance {
  const CurrencyBalance({this.currency = '', this.expectedBalance = ''});

  final String currency;
  final String expectedBalance;

  factory CurrencyBalance.fromJson(Map<String, Object?> json) => CurrencyBalance(
        currency: '${json['currency'] ?? ''}',
        expectedBalance:
            json['expected_balance'] == null ? '' : '${json['expected_balance']}',
      );
}

/// `POST /reconciliation/tasks/{id}/start/` 的响应。
class ReconciliationStart {
  const ReconciliationStart({
    this.balances = const [],
    this.accountName = '',
    this.asOfDate = '',
    this.defaultCurrency,
    this.isFirstReconciliation = false,
    this.defaultAllocationAccount = '',
    this.lastReconciliationDate,
    this.lastCompletedTaskId,
    this.lastTransactionItems = const [],
  });

  final List<CurrencyBalance> balances;
  final String accountName;
  final String asOfDate;
  final String? defaultCurrency;
  final bool isFirstReconciliation;
  final String defaultAllocationAccount;
  final String? lastReconciliationDate;
  final int? lastCompletedTaskId;
  final List<TransactionItemDraft> lastTransactionItems;

  /// 把预填条目转成待提交草稿（日期为空的按截止日期补齐）。
  List<TransactionItemDraft> prefillItems() =>
      lastTransactionItems.map((e) => e.copyWith(date: e.date ?? asOfDate)).toList();

  factory ReconciliationStart.fromJson(Map<String, Object?> json) {
    final rawBalances = json['balances'];
    final rawDefaultCurrency = json['default_currency'];
    final rawLastDate = json['last_reconciliation_date'];
    final rawLastTaskId = json['last_completed_task_id'];
    final rawItems = json['last_reconciliation_transaction_items'];

    return ReconciliationStart(
      balances: rawBalances is List
          ? rawBalances
              .whereType<Map>()
              .map((e) => CurrencyBalance.fromJson(e.cast<String, Object?>()))
              .toList()
          : const [],
      accountName: '${json['account_name'] ?? ''}',
      asOfDate: '${json['as_of_date'] ?? ''}',
      defaultCurrency:
          rawDefaultCurrency is String && rawDefaultCurrency.isNotEmpty
              ? rawDefaultCurrency
              : null,
      isFirstReconciliation: json['is_first_reconciliation'] == true,
      defaultAllocationAccount: '${json['default_allocation_account'] ?? ''}',
      lastReconciliationDate: rawLastDate is String && rawLastDate.isNotEmpty
          ? rawLastDate
          : null,
      lastCompletedTaskId: rawLastTaskId is int
          ? rawLastTaskId
          : int.tryParse('${rawLastTaskId ?? ''}'),
      lastTransactionItems: rawItems is List
          ? rawItems
              .whereType<Map>()
              .map((e) => TransactionItemDraft.fromJson(e.cast<String, Object?>()))
              .toList()
          : const [],
    );
  }
}

/// 差额分配条目草稿 / 提交体（金额用字符串，原样透传）。
class TransactionItemDraft {
  const TransactionItemDraft({
    this.account = '',
    this.amount,
    this.isAuto = false,
    this.date,
  });

  final String account;
  final String? amount;
  final bool isAuto;
  final String? date;

  TransactionItemDraft copyWith({
    String? account,
    String? amount,
    bool? isAuto,
    String? date,
  }) =>
      TransactionItemDraft(
        account: account ?? this.account,
        amount: amount ?? this.amount,
        isAuto: isAuto ?? this.isAuto,
        date: date ?? this.date,
      );

  Map<String, Object?> toJson() => {
        'account': account,
        if (amount != null && amount!.isNotEmpty) 'amount': amount,
        'is_auto': isAuto,
        if (!isAuto && date != null && date!.isNotEmpty) 'date': date,
      };

  factory TransactionItemDraft.fromJson(Map<String, Object?> json) {
    final rawDate = json['date'];
    return TransactionItemDraft(
      account: '${json['account'] ?? ''}',
      amount: json['amount'] == null ? null : '${json['amount']}',
      isAuto: json['is_auto'] == true,
      date: rawDate is String && rawDate.isNotEmpty ? rawDate : null,
    );
  }
}

/// `POST /reconciliation/tasks/{id}/execute/` 的响应。
class ReconciliationExecuteResult {
  const ReconciliationExecuteResult({
    this.status = '',
    this.directives = const [],
    this.nextTaskId,
  });

  final String status;
  final List<String> directives;
  final int? nextTaskId;

  factory ReconciliationExecuteResult.fromJson(Map<String, Object?> json) {
    final rawDirectives = json['directives'];
    final rawNext = json['next_task_id'];
    return ReconciliationExecuteResult(
      status: '${json['status'] ?? ''}',
      directives:
          rawDirectives is List ? rawDirectives.whereType<String>().toList() : const [],
      nextTaskId: rawNext is int ? rawNext : int.tryParse('${rawNext ?? ''}'),
    );
  }
}

/// 账户树节点（用于差额分配账户选择）。
class AccountNode {
  const AccountNode({
    required this.id,
    this.account = '',
    this.accountType = '',
    this.enable = true,
    this.children = const [],
  });

  final int id;
  final String account;
  final String accountType;
  final bool enable;
  final List<AccountNode> children;

  factory AccountNode.fromJson(Map<String, Object?> json) {
    final id = json['id'];
    final rawChildren = json['children'];
    return AccountNode(
      id: id is int ? id : int.tryParse('${id ?? ''}') ?? 0,
      account: '${json['account'] ?? ''}',
      accountType: '${json['account_type'] ?? ''}',
      enable: json['enable'] != false,
      children: rawChildren is List
          ? rawChildren
              .whereType<Map>()
              .map((e) => AccountNode.fromJson(e.cast<String, Object?>()))
              .toList()
          : const [],
    );
  }

  /// 展平为「路径 + 缩进层级」，便于在底部弹层里平铺选择。
  void flatten(List<AccountNode> out, {int depth = 0}) {
    out.add(this);
    for (final child in children) {
      child.flatten(out, depth: depth + 1);
    }
  }

  static List<AccountNode> flatTree(List<AccountNode> roots) {
    final out = <AccountNode>[];
    for (final root in roots) {
      root.flatten(out);
    }
    return out;
  }
}
