import 'package:beancount_trans/core/format.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';

/// 把 `DateTime` 换算为 Unix 秒。
///
/// 统一用「四舍五入」而不是截断，避免毫秒丢失导致倒计时档位偏移
/// （例如 `now + 5 分钟` 因截断变成 4 分 59 秒）。
int _unixSeconds(DateTime dt) => (dt.millisecondsSinceEpoch / 1000).round();

void main() {
  group('FormatUtil.amount', () {
    test('null 返回占位符', () {
      expect(FormatUtil.amount(null), FormatUtil.placeholder);
    });

    test('空串与纯空白返回占位符', () {
      expect(FormatUtil.amount(''), FormatUtil.placeholder);
      expect(FormatUtil.amount('   '), FormatUtil.placeholder);
    });

    test('字符串原样返回并去掉首尾空白', () {
      expect(FormatUtil.amount('123.45'), '123.45');
      expect(FormatUtil.amount('  123.45  '), '123.45');
    });

    test('数字转换为字符串', () {
      expect(FormatUtil.amount(100), '100');
    });
  });

  group('FormatUtil.signedAmount', () {
    test('正整数部分加千分位且保留小数', () {
      expect(FormatUtil.signedAmount('1234567.89'), '1,234,567.89');
    });

    test('负数保留负号并加千分位', () {
      expect(FormatUtil.signedAmount('-1234'), '-1,234');
    });

    test('非数字内容原样返回', () {
      expect(FormatUtil.signedAmount('abc'), 'abc');
    });

    test('null 返回占位符', () {
      expect(FormatUtil.signedAmount(null), FormatUtil.placeholder);
    });
  });

  group('FormatUtil.date', () {
    test('标准日期原样返回', () {
      expect(FormatUtil.date('2026-09-17'), '2026-09-17');
    });

    test('ISO 时间串截断为日期', () {
      expect(FormatUtil.date('2026-09-17T12:30:00Z'), '2026-09-17');
    });

    test('null 返回占位符', () {
      expect(FormatUtil.date(null), FormatUtil.placeholder);
    });

    test('无法解析的内容原样返回', () {
      expect(FormatUtil.date('not-a-date'), 'not-a-date');
    });
  });

  group('FormatUtil.dateTime', () {
    test('null 返回占位符', () {
      expect(FormatUtil.dateTime(null), FormatUtil.placeholder);
    });

    test('无法解析的内容原样返回', () {
      expect(FormatUtil.dateTime('not-a-date'), 'not-a-date');
    });

    test('本地时间串格式化为 16 字符且年份正确', () {
      final result = FormatUtil.dateTime('2026-09-17T12:30:00');
      expect(result.length, 16);
      expect(result.startsWith('2026-'), isTrue);
    });
  });

  group('FormatUtil.unixDateTime', () {
    test('null 返回占位符', () {
      expect(FormatUtil.unixDateTime(null), FormatUtil.placeholder);
    });

    test('时间戳按本地时区格式化为 yyyy-MM-dd HH:mm', () {
      final ts = _unixSeconds(DateTime.now());
      final expected = DateFormat('yyyy-MM-dd HH:mm').format(
        DateTime.fromMillisecondsSinceEpoch(ts * 1000).toLocal(),
      );
      expect(FormatUtil.unixDateTime(ts), expected);
      expect(
        FormatUtil.unixDateTime(ts),
        matches(RegExp(r'^\d{4}-\d{2}-\d{2} \d{2}:\d{2}$')),
      );
    });
  });

  group('FormatUtil.unixDate', () {
    test('null 返回占位符', () {
      expect(FormatUtil.unixDate(null), FormatUtil.placeholder);
    });

    test('时间戳按本地时区格式化为 yyyy-MM-dd', () {
      final ts = _unixSeconds(DateTime.now());
      final expected = DateFormat('yyyy-MM-dd').format(
        DateTime.fromMillisecondsSinceEpoch(ts * 1000).toLocal(),
      );
      expect(FormatUtil.unixDate(ts), expected);
      expect(
        FormatUtil.unixDate(ts),
        matches(RegExp(r'^\d{4}-\d{2}-\d{2}$')),
      );
    });
  });

  group('FormatUtil.countdown', () {
    test('null 返回无到期时间', () {
      expect(FormatUtil.countdown(null), '无到期时间');
    });

    test('过去时间戳返回审核已过期', () {
      final past = _unixSeconds(DateTime.now().subtract(const Duration(hours: 1)));
      expect(FormatUtil.countdown(past), '审核已过期');
    });

    test('剩余 3 天 5 小时时以「剩余 3 天」开头', () {
      final ts = _unixSeconds(
        DateTime.now().add(const Duration(days: 3, hours: 5)),
      );
      expect(FormatUtil.countdown(ts), startsWith('剩余 3 天'));
    });

    test('剩余 2 小时 40 分钟时以「剩余 2 小时」开头', () {
      final ts = _unixSeconds(
        DateTime.now().add(const Duration(hours: 2, minutes: 40)),
      );
      expect(FormatUtil.countdown(ts), startsWith('剩余 2 小时'));
    });

    test('剩余 5 分钟（容许 1 分钟漂移）', () {
      final ts = _unixSeconds(DateTime.now().add(const Duration(minutes: 5)));
      final result = FormatUtil.countdown(ts);
      expect(
        result.startsWith('剩余 5 分钟') || result.startsWith('剩余 4 分钟'),
        isTrue,
        reason: '实际输出：$result',
      );
    });
  });

  group('FormatUtil.remainingUntil', () {
    test('null 返回 null', () {
      expect(FormatUtil.remainingUntil(null), isNull);
    });

    test('过去时间返回 null', () {
      final past = _unixSeconds(DateTime.now().subtract(const Duration(hours: 1)));
      expect(FormatUtil.remainingUntil(past), isNull);
    });

    test('未来时间返回非空时长', () {
      final future = _unixSeconds(DateTime.now().add(const Duration(hours: 1)));
      expect(FormatUtil.remainingUntil(future), isNotNull);
    });
  });

  group('FormatUtil.isExpired', () {
    test('null 返回 false', () {
      expect(FormatUtil.isExpired(null), isFalse);
    });

    test('过去时间返回 true', () {
      final past = _unixSeconds(DateTime.now().subtract(const Duration(hours: 1)));
      expect(FormatUtil.isExpired(past), isTrue);
    });

    test('未来时间返回 false', () {
      final future = _unixSeconds(DateTime.now().add(const Duration(hours: 1)));
      expect(FormatUtil.isExpired(future), isFalse);
    });
  });
}
