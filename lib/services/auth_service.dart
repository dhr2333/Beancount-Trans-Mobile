import '../core/api_client.dart';
import '../core/api_exception.dart';
import '../models/user.dart';

/// 认证相关接口封装（对应后端 `/api/auth/`）。
class AuthService {
  AuthService._();

  static final AuthService instance = AuthService._();

  final ApiClient _client = ApiClient.instance;

  /// 11 位纯数字手机号补 `+86` 前缀（照搬 Web 端 `normalizePhone`）。
  static String normalizePhone(String input) {
    final trimmed = input.trim();
    if (trimmed.startsWith('+')) return trimmed;
    if (trimmed.startsWith('86')) return '+$trimmed';
    return '+86$trimmed';
  }

  static bool isValidPhone(String input) =>
      RegExp(r'^1[3-9]\d{9}$').hasMatch(input.trim());

  static bool isValidCode(String input) => RegExp(r'^\d{6}$').hasMatch(input.trim());

  Future<AuthPublicConfig> publicConfig() async {
    final response = await _client.get<Object?>('/auth/public-config/');
    final data = response.data;
    return data is Map
        ? AuthPublicConfig.fromJson(data.cast<String, Object?>())
        : const AuthPublicConfig();
  }

  /// 发送手机验证码（需后端开启短信服务）。
  Future<String> sendPhoneCode(String phoneNumber) async {
    final response = await _client.post<Object?>(
      '/auth/phone/send-code/',
      data: {'phone_number': normalizePhone(phoneNumber)},
    );
    final data = response.data;
    if (data is Map && data['message'] is String) {
      return data['message'] as String;
    }
    return '验证码已发送';
  }

  /// 手机验证码登录（用户不存在时后端自动注册）。
  Future<LoginResult> loginByPhoneCode({
    required String phoneNumber,
    required String code,
  }) async {
    final response = await _client.post<Object?>(
      '/auth/phone/login-by-code/',
      data: {
        'phone_number': normalizePhone(phoneNumber),
        'code': code.trim(),
      },
    );
    return _toLoginResult(response.data);
  }

  /// 用户名 / 邮箱 + 密码登录（可选 TOTP 二次验证）。
  Future<LoginResult> loginByPassword({
    required String username,
    required String password,
    String? totpCode,
  }) async {
    final response = await _client.post<Object?>(
      '/auth/username/login-by-password/',
      data: {
        'username': username.trim(),
        'password': password,
        if (totpCode != null && totpCode.isNotEmpty) 'totp_code': totpCode.trim(),
      },
    );
    return _toLoginResult(response.data);
  }

  /// 账号绑定信息（用户名 / 邮箱 / 手机号 / 是否已验证）。
  Future<UserBindings> bindings() async {
    final response = await _client.get<Object?>('/auth/bindings/');
    final data = response.data;
    return data is Map
        ? UserBindings.fromJson(data.cast<String, Object?>())
        : const UserBindings();
  }

  /// 绑定手机号。
  Future<String> bindPhone({
    required String phoneNumber,
    required String code,
  }) async {
    final response = await _client.post<Object?>(
      '/auth/bindings/bind-phone/',
      data: {
        'phone_number': normalizePhone(phoneNumber),
        'code': code.trim(),
      },
    );
    final data = response.data;
    if (data is Map && data['message'] is String) {
      return data['message'] as String;
    }
    return '绑定成功';
  }

  LoginResult _toLoginResult(Object? data) {
    if (data is! Map) {
      throw ApiException(message: '登录响应格式异常');
    }
    final result = LoginResult.fromJson(data.cast<String, Object?>());
    if (!result.isValid) {
      throw ApiException(message: '登录响应缺少令牌');
    }
    return result;
  }
}
