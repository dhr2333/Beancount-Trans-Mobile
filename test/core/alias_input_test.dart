import 'package:beancount_trans/core/alias_input.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseAliases', () {
    test('按逗号/顿号/分号/空格/换行分割并去空', () {
      expect(
        parseAliases('老婆,老婆的账本、家庭；共同 账户\n备用'),
        ['老婆', '老婆的账本', '家庭', '共同', '账户', '备用'],
      );
    });

    test('逐项 trim', () {
      expect(parseAliases('  老婆账本 ,  老婆  '), ['老婆账本', '老婆']);
    });

    test('空串与纯分隔符返回空列表', () {
      expect(parseAliases(''), isEmpty);
      expect(parseAliases('  ,,, 、；; \n '), isEmpty);
    });

    test('大小写不敏感去重且保留首次出现的原始大小写', () {
      expect(parseAliases('Wife, wife, WIFE'), ['Wife']);
    });
  });

  group('aliasValidationError', () {
    test('超过 64 个字符报错', () {
      expect(aliasValidationError('a' * 65), '别名最长为 64 个字符');
    });

    test('64 个字符合法', () {
      expect(aliasValidationError('a' * 64), isNull);
    });

    test('保留值 self（大小写不敏感）报错', () {
      expect(aliasValidationError('self'), '别名不能使用保留值 self');
      expect(aliasValidationError('SELF'), '别名不能使用保留值 self');
      expect(aliasValidationError('Self'), '别名不能使用保留值 self');
    });

    test('正常别名返回 null', () {
      expect(aliasValidationError('老婆的账本'), isNull);
    });
  });
}
