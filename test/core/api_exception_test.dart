import 'package:beancount_trans/core/api_exception.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ApiException.fromResponse 错误体归一', () {
    test('{"error": ...} 取 error 作为 message', () {
      final exception = ApiException.fromResponse(
        400,
        <String, Object?>{'error': '账号或密码错误'},
      );
      expect(exception.statusCode, 400);
      expect(exception.message, '账号或密码错误');
    });

    test('{"detail": ...} 取 detail 作为 message', () {
      final exception = ApiException.fromResponse(
        403,
        <String, Object?>{'detail': '未认证'},
      );
      expect(exception.message, '未认证');
    });

    test('字段校验错误归入 fieldErrors 并回退为 message', () {
      final exception = ApiException.fromResponse(
        400,
        <String, Object?>{
          'username': <String>['该字段是必填项。'],
        },
      );
      expect(exception.fieldErrors['username'], '该字段是必填项。');
      expect(exception.message, '该字段是必填项。');
    });

    test('复合错误体：code / requires_totp / pending_files / payload', () {
      final body = <String, Object?>{
        'error': '需要二次验证',
        'code': 'require_totp',
        'requires_totp': true,
        'pending_files': <String>['a'],
      };
      final exception = ApiException.fromResponse(400, body);

      expect(exception.message, '需要二次验证');
      expect(exception.code, 'require_totp');
      expect(exception.requiresTotp, isTrue);
      expect(exception.fieldErrors['pending_files'], 'a');
      expect(exception.payload, equals(body));
    });

    test('error 优先于 detail', () {
      final exception = ApiException.fromResponse(
        400,
        <String, Object?>{'error': '来自 error', 'detail': '来自 detail'},
      );
      expect(exception.message, '来自 error');
    });

    test('error 为非空数组时取第一个元素', () {
      final exception = ApiException.fromResponse(
        400,
        <String, Object?>{
          'error': <String>['第一个错误', '第二个错误'],
        },
      );
      expect(exception.message, '第一个错误');
    });

    test('非空字符串响应体直接作为 message', () {
      final exception = ApiException.fromResponse(500, '服务暂时不可用');
      expect(exception.message, '服务暂时不可用');
    });

    test('非 Map 响应体使用 fallback', () {
      final exception = ApiException.fromResponse(500, null);
      expect(exception.message, '请求失败');
    });
  });

  group('ApiException.isUnauthorized', () {
    test('401 为 true', () {
      final exception = ApiException.fromResponse(
        401,
        <String, Object?>{'detail': '未认证'},
      );
      expect(exception.isUnauthorized, isTrue);
    });

    test('400 为 false', () {
      final exception = ApiException.fromResponse(
        400,
        <String, Object?>{'error': '账号或密码错误'},
      );
      expect(exception.isUnauthorized, isFalse);
    });
  });

  group('ApiException 预置异常', () {
    test('network 提供网络错误文案', () {
      expect(ApiException.network().message, '网络连接失败，请检查网络后重试');
    });

    test('timeout 提供超时文案', () {
      expect(ApiException.timeout().message, '请求超时，请稍后重试');
    });
  });
}
