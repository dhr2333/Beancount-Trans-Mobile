/// 当前登录用户与账号绑定信息。
class AppUser {
  const AppUser({
    this.id,
    this.username = '',
    this.email = '',
    this.phoneNumber = '',
  });

  final int? id;
  final String username;
  final String email;
  final String phoneNumber;

  factory AppUser.fromJson(Map<String, Object?> json) {
    final id = json['id'];
    return AppUser(
      id: id is int ? id : int.tryParse('${id ?? ''}'),
      username: '${json['username'] ?? ''}',
      email: '${json['email'] ?? ''}',
      phoneNumber: '${json['phone_number'] ?? ''}',
    );
  }

  Map<String, Object?> toJson() => {
        'id': id,
        'username': username,
        'email': email,
        'phone_number': phoneNumber,
      };

  String get displayName => username.isNotEmpty ? username : (email.isNotEmpty ? email : '未登录');
}

/// `GET /auth/bindings/` 的响应。
class UserBindings {
  const UserBindings({
    this.username = '',
    this.email = '',
    this.phoneNumber = '',
    this.phoneVerified = false,
    this.hasPassword = false,
  });

  final String username;
  final String email;
  final String phoneNumber;
  final bool phoneVerified;
  final bool hasPassword;

  factory UserBindings.fromJson(Map<String, Object?> json) => UserBindings(
        username: '${json['username'] ?? ''}',
        email: '${json['email'] ?? ''}',
        phoneNumber: '${json['phone_number'] ?? ''}',
        phoneVerified: json['phone_verified'] == true,
        hasPassword: json['has_password'] == true,
      );

  Map<String, Object?> toJson() => {
        'username': username,
        'email': email,
        'phone_number': phoneNumber,
        'phone_verified': phoneVerified,
        'has_password': hasPassword,
      };
}

/// `GET /auth/public-config/` 的响应。
class AuthPublicConfig {
  const AuthPublicConfig({
    this.phoneBindingRequired = false,
    this.smsEnabled = false,
    this.favaDeployMode = '',
  });

  final bool phoneBindingRequired;
  final bool smsEnabled;
  final String favaDeployMode;

  factory AuthPublicConfig.fromJson(Map<String, Object?> json) =>
      AuthPublicConfig(
        phoneBindingRequired: json['phone_binding_required'] == true,
        smsEnabled: json['sms_enabled'] == true,
        favaDeployMode: '${json['fava_deploy_mode'] ?? ''}',
      );
}

/// 登录接口返回的凭证。
class LoginResult {
  const LoginResult({
    required this.access,
    required this.refresh,
    required this.user,
  });

  final String access;
  final String refresh;
  final AppUser user;

  factory LoginResult.fromJson(Map<String, Object?> json) {
    final rawUser = json['user'];
    return LoginResult(
      access: '${json['access'] ?? ''}',
      refresh: '${json['refresh'] ?? ''}',
      user: rawUser is Map
          ? AppUser.fromJson(rawUser.cast<String, Object?>())
          : const AppUser(),
    );
  }

  bool get isValid => access.isNotEmpty && refresh.isNotEmpty;
}
