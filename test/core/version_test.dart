import 'package:beancount_trans/core/version.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppVersion.tryParse', () {
    test('解析标准三段版本', () {
      final version = AppVersion.tryParse('1.2.3');
      expect(version.toString(), '1.2.3');
    });

    test('忽略前导 v 与构建号', () {
      expect(AppVersion.tryParse('v1.2.3')!.toString(), '1.2.3');
      expect(AppVersion.tryParse('1.2.3+10100')!.toString(), '1.2.3');
      expect(AppVersion.tryParse('v1.2.3+10100')!.toString(), '1.2.3');
    });

    test('缺失段位按 0 补齐', () {
      expect(AppVersion.tryParse('1')!.toString(), '1.0.0');
      expect(AppVersion.tryParse('1.2')!.toString(), '1.2.0');
    });

    test('保留预发布标识', () {
      expect(AppVersion.tryParse('1.2.3-rc.1')!.toString(), '1.2.3-rc.1');
    });

    test('非法输入返回 null', () {
      expect(AppVersion.tryParse(''), isNull);
      expect(AppVersion.tryParse('latest'), isNull);
      expect(AppVersion.tryParse('1.2.x'), isNull);
    });
  });

  group('AppVersion.compareTo', () {
    AppVersion parse(String raw) => AppVersion.tryParse(raw)!;

    test('按 major/minor/patch 依次比较', () {
      expect(parse('1.2.3').isNewerThan(parse('1.2.2')), isTrue);
      expect(parse('1.3.0').isNewerThan(parse('1.2.9')), isTrue);
      expect(parse('2.0.0').isNewerThan(parse('1.99.99')), isTrue);
      expect(parse('1.2.3').isNewerThan(parse('1.2.3')), isFalse);
    });

    test('正式版高于同号预发布版', () {
      expect(parse('1.2.3').isNewerThan(parse('1.2.3-rc.1')), isTrue);
      expect(parse('1.2.3-rc.1').isNewerThan(parse('1.2.3')), isFalse);
    });

    test('预发布标识按 semver 规则比较', () {
      expect(parse('1.2.3-rc.2').isNewerThan(parse('1.2.3-rc.1')), isTrue);
      expect(parse('1.2.3-beta').isNewerThan(parse('1.2.3-alpha')), isTrue);
      // 数字标识优先级低于字母标识
      expect(parse('1.2.3-1').isNewerThan(parse('1.2.3-alpha')), isFalse);
      // 段数更少且前缀相同时更小
      expect(parse('1.2.3-rc.1').isNewerThan(parse('1.2.3-rc')), isTrue);
    });

    test('缺少段位的写法与补零等价', () {
      expect(parse('1.2').isNewerThan(parse('1.2.0')), isFalse);
      expect(parse('1.2.0').isNewerThan(parse('1.2')), isFalse);
    });
  });
}
