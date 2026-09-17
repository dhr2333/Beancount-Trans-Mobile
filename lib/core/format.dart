import 'package:intl/intl.dart';

/// 展示层格式化工具。
///
/// 金额一律以字符串输入、字符串输出，**不做 double 解析**，避免浮点误差。
class FormatUtil {
  FormatUtil._();

  static final DateFormat _date = DateFormat('yyyy-MM-dd');
  static final DateFormat _dateTime = DateFormat('yyyy-MM-dd HH:mm');

  /// 空值占位符。
  static const String placeholder = '—';

  /// 今天的日期（`yyyy-MM-dd`）。
  static String today() => _date.format(DateTime.now());

  /// 金额原样展示；`null` / 空串返回占位符。
  static String amount(Object? value) {
    if (value == null) return placeholder;
    final text = value is String ? value : '$value';
    final trimmed = text.trim();
    if (trimmed.isEmpty) return placeholder;
    return trimmed;
  }

  /// 带正负号与千分位的金额展示（仍基于字符串，不参与计算）。
  static String signedAmount(Object? value) {
    final text = amount(value);
    if (text == placeholder) return text;
    if (!RegExp(r'^-?\d+(\.\d+)?$').hasMatch(text)) return text;

    var body = text;
    var sign = '';
    if (body.startsWith('-')) {
      sign = '-';
      body = body.substring(1);
    }
    final parts = body.split('.');
    final grouped = _group(parts.first);
    final decimals = parts.length > 1 ? '.${parts[1]}' : '';
    return '$sign$grouped$decimals';
  }

  static String _group(String digits) {
    final buffer = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
      buffer.write(digits[i]);
    }
    return buffer.toString();
  }

  /// `yyyy-MM-dd`（自动截断 ISO 时间串）。
  static String date(Object? value) {
    if (value == null) return placeholder;
    final text = value is String ? value : '$value';
    final trimmed = text.trim();
    if (trimmed.isEmpty) return placeholder;
    if (trimmed.length >= 10 && trimmed[4] == '-' && trimmed[7] == '-') {
      return trimmed.substring(0, 10);
    }
    final parsed = DateTime.tryParse(trimmed);
    return parsed == null ? trimmed : _date.format(parsed.toLocal());
  }

  /// `yyyy-MM-dd HH:mm`（自动转本地时区）。
  static String dateTime(Object? value) {
    if (value == null) return placeholder;
    final text = value is String ? value : '$value';
    final trimmed = text.trim();
    if (trimmed.isEmpty) return placeholder;
    final parsed = DateTime.tryParse(trimmed);
    return parsed == null ? trimmed : _dateTime.format(parsed.toLocal());
  }

  /// Unix 秒时间戳 → `yyyy-MM-dd HH:mm`。
  static String unixDateTime(int? seconds) {
    if (seconds == null) return placeholder;
    final dt = DateTime.fromMillisecondsSinceEpoch(seconds * 1000);
    return _dateTime.format(dt.toLocal());
  }

  /// Unix 秒时间戳 → `yyyy-MM-dd`。
  static String unixDate(int? seconds) {
    if (seconds == null) return placeholder;
    final dt = DateTime.fromMillisecondsSinceEpoch(seconds * 1000);
    return _date.format(dt.toLocal());
  }

  /// Unix 秒时间戳的剩余时长；已过期或为空返回 null。
  static Duration? remainingUntil(int? expiresAtSeconds) {
    if (expiresAtSeconds == null) return null;
    final expiresAt =
        DateTime.fromMillisecondsSinceEpoch(expiresAtSeconds * 1000);
    final diff = expiresAt.difference(DateTime.now());
    return diff.isNegative ? null : diff;
  }

  /// 审核到期倒计时文案。
  static String countdown(int? expiresAtSeconds) {
    final duration = remainingUntil(expiresAtSeconds);
    if (expiresAtSeconds == null) return '无到期时间';
    if (duration == null) return '审核已过期';
    final days = duration.inDays;
    final hours = duration.inHours % 24;
    final minutes = duration.inMinutes % 60;
    if (days > 0) return '剩余 $days 天 $hours 小时';
    if (hours > 0) return '剩余 $hours 小时 $minutes 分钟';
    if (minutes > 0) return '剩余 $minutes 分钟';
    return '即将过期';
  }

  /// 已过期判断。
  static bool isExpired(int? expiresAtSeconds) {
    if (expiresAtSeconds == null) return false;
    return remainingUntil(expiresAtSeconds) == null;
  }
}
