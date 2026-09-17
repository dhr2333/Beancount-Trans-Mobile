/// 统一 API 异常：把后端四种错误体归一为 `{statusCode, code, message, fieldErrors}`。
///
/// 后端错误体形态：
/// 1. `{"error": "..."}`            —— authentication 自定义视图
/// 2. `{"detail": "..."}`           —— DRF / assistant
/// 3. `{"字段": ["..."]}`            —— DRF 字段校验
/// 4. `{"error": ..., "code": ..., "pending_files": [...]}` —— 复合体
class ApiException implements Exception {
  ApiException({
    this.statusCode,
    this.code,
    required this.message,
    this.fieldErrors = const {},
    Map<String, Object?>? payload,
  }) : payload = payload ?? const {};

  final int? statusCode;
  final String? code;
  final String message;
  final Map<String, String> fieldErrors;

  /// 原始响应体（仅在需要读取 `requires_totp` 之类的布尔标记时使用）。
  final Map<String, Object?> payload;

  bool get isUnauthorized => statusCode == 401;

  /// 账密登录首次返回 400 且 `requires_totp=true`。
  bool get requiresTotp => payload['requires_totp'] == true;

  static const _reservedKeys = {'error', 'detail', 'code', 'message'};

  factory ApiException.fromResponse(
    int? statusCode,
    Object? data, {
    String fallback = '请求失败',
  }) {
    if (data is String && data.trim().isNotEmpty) {
      return ApiException(statusCode: statusCode, message: data.trim());
    }
    if (data is! Map) {
      return ApiException(statusCode: statusCode, message: fallback);
    }

    final map = data.cast<String, Object?>();
    String? message;
    String? code;
    final fieldErrors = <String, String>{};

    final detail = map['detail'];
    if (detail is String && detail.trim().isNotEmpty) {
      message = detail.trim();
    }

    // `error` 优先于 `detail`
    final error = map['error'];
    if (error is String && error.trim().isNotEmpty) {
      message = error.trim();
    } else if (error is List && error.isNotEmpty) {
      final first = error.first;
      if (first is String && first.trim().isNotEmpty) {
        message = first.trim();
      }
    }

    final codeValue = map['code'];
    if (codeValue is String && codeValue.isNotEmpty) {
      code = codeValue;
    }

    if (message == null) {
      final msg = map['message'];
      if (msg is String && msg.trim().isNotEmpty) {
        message = msg.trim();
      }
    }

    map.forEach((key, value) {
      if (_reservedKeys.contains(key)) return;
      if (value is List && value.isNotEmpty) {
        final first = value.first;
        if (first is String && first.trim().isNotEmpty) {
          fieldErrors[key] = first.trim();
        }
      } else if (value is String && value.trim().isNotEmpty) {
        fieldErrors[key] = value.trim();
      }
    });

    if (message == null || message.isEmpty) {
      message = fieldErrors.isNotEmpty ? fieldErrors.values.first : fallback;
    }

    return ApiException(
      statusCode: statusCode,
      code: code,
      message: message,
      fieldErrors: fieldErrors,
      payload: map,
    );
  }

  factory ApiException.network([Object? cause]) {
    return ApiException(message: '网络连接失败，请检查网络后重试');
  }

  factory ApiException.timeout() {
    return ApiException(message: '请求超时，请稍后重试');
  }

  @override
  String toString() => message;
}
