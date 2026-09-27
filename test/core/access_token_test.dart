import 'package:beancount_trans/core/access_token.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const token = 'bct_0123456789abcdef0123456789abcdef';

  group('extractAccessToken', () {
    test('纯令牌原样返回', () {
      expect(extractAccessToken(token), token);
    });

    test('前后空白与换行被忽略', () {
      expect(extractAccessToken('  \n$token\n  '), token);
    });

    test('夹带说明文字时取其中的令牌', () {
      expect(
        extractAccessToken('这是分享给你的令牌：$token，请妥善保管'),
        token,
      );
    });

    test('非令牌文本返回 null', () {
      expect(extractAccessToken('hello world'), isNull);
    });

    test('空串与 null 返回 null', () {
      expect(extractAccessToken(''), isNull);
      expect(extractAccessToken('   '), isNull);
      expect(extractAccessToken(null), isNull);
    });

    test('bct_ 后字符过短返回 null', () {
      expect(extractAccessToken('bct_0123456789'), isNull);
    });

    test('多个令牌时取第一个', () {
      const second = 'bct_ffffffffffffffffffffffffffffffff';
      expect(extractAccessToken('$token 和 $second'), token);
    });

    test('令牌可包含 - 与 _', () {
      const withSymbols = 'bct_ab-cd_ef-gh_ij-kl_mn-op';
      expect(extractAccessToken(withSymbols), withSymbols);
    });
  });

  group('accessTokenFingerprint', () {
    test('返回前 12 个字符', () {
      expect(accessTokenFingerprint(token), 'bct_01234567');
      expect(accessTokenFingerprint(token).length, 12);
    });

    test('前缀常量与令牌前缀一致', () {
      expect(kAccessTokenPrefix, 'bct_');
      expect(token.startsWith(kAccessTokenPrefix), isTrue);
    });
  });
}
