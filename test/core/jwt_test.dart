import 'dart:convert';

import 'package:beancount_trans/core/jwt.dart';
import 'package:flutter_test/flutter_test.dart';

/// 构造仅用于本地解析的 JWT（无签名，payload 可为任意 JSON）。
String fakeJwt(Map<String, Object?> payload) {
  String segment(Object value) =>
      base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');

  return '${segment(<String, Object?>{'alg': 'none'})}.'
      '${segment(payload)}.signature';
}

void main() {
  group('jwtExpiresAt', () {
    test('解析合法 token 的 exp', () {
      final exp = DateTime.now().add(const Duration(hours: 1));
      final token = fakeJwt({'exp': exp.millisecondsSinceEpoch ~/ 1000});

      expect(
        jwtExpiresAt(token)!.difference(exp).inSeconds.abs() <= 1,
        isTrue,
      );
    });

    test('非三段式 token 返回 null', () {
      expect(jwtExpiresAt('not-a-token'), isNull);
    });

    test('payload 缺少 exp 返回 null', () {
      expect(jwtExpiresAt(fakeJwt({'sub': '1'})), isNull);
    });

    test('payload 非法 JSON 返回 null', () {
      expect(jwtExpiresAt('header.not-base64-json.signature'), isNull);
    });
  });

  group('isJwtExpiringSoon', () {
    test('缺失或空 token 视为需要续期', () {
      expect(isJwtExpiringSoon(null), isTrue);
      expect(isJwtExpiringSoon(''), isTrue);
    });

    test('剩余有效期大于 leeway 时返回 false', () {
      final token = fakeJwt({
        'exp': DateTime.now().add(const Duration(minutes: 30)).millisecondsSinceEpoch ~/ 1000,
      });

      expect(isJwtExpiringSoon(token), isFalse);
    });

    test('已过期或落在 leeway 内时返回 true', () {
      final expired = fakeJwt({
        'exp': DateTime.now().subtract(const Duration(minutes: 1)).millisecondsSinceEpoch ~/ 1000,
      });
      final almostExpired = fakeJwt({
        'exp': DateTime.now().add(const Duration(minutes: 2)).millisecondsSinceEpoch ~/ 1000,
      });

      expect(isJwtExpiringSoon(expired), isTrue);
      expect(isJwtExpiringSoon(almostExpired), isTrue);
    });

    test('无法解析时返回 false（交由 401 兜底）', () {
      expect(isJwtExpiringSoon('not-a-token'), isFalse);
    });
  });
}
