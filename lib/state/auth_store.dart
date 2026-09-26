import 'package:flutter/foundation.dart';

import '../core/api_client.dart';
import '../core/jwt.dart';
import '../core/token_store.dart';
import '../models/user.dart';
import '../services/auth_service.dart';
import '../services/badge_service.dart';
import '../services/fava_service.dart';

enum AuthStatus { unknown, loggedOut, loggedIn }

/// 认证状态：登录态、用户信息、公共配置。
class AuthStore extends ChangeNotifier {
  AuthStore._() {
    // refresh 确认失效时退回登录页
    ApiClient.instance.onSessionExpired = _handleSessionExpired;
  }

  static final AuthStore instance = AuthStore._();

  AuthStatus _status = AuthStatus.unknown;
  AppUser? _user;
  AuthPublicConfig _publicConfig = const AuthPublicConfig();
  UserBindings? _bindings;
  bool _busy = false;
  bool _configLoaded = false;
  bool _sessionExpired = false;

  AuthStatus get status => _status;
  AppUser? get user => _user;
  AuthPublicConfig get publicConfig => _publicConfig;
  UserBindings? get bindings => _bindings;
  bool get isBusy => _busy;

  /// 是否因登录态失效而退回登录页（用于登录页提示）。
  bool get sessionExpired => _sessionExpired;

  /// 公共配置是否已成功拉取过。
  bool get configLoaded => _configLoaded;
  bool get isLoggedIn => _status == AuthStatus.loggedIn;

  /// 启动时恢复登录态。
  ///
  /// access 缺失或临近过期时先静默续期：续期只因网络等临时原因失败时**保留**本地登录态，
  /// 只有 refresh 被后端明确拒绝才清空并退回登录页。
  Future<void> restore() async {
    final store = TokenStore.instance;
    await store.init();

    if (!store.hasSession) {
      _status = AuthStatus.loggedOut;
      notifyListeners();
      return;
    }

    final access = store.accessToken;
    if (access == null || access.isEmpty || isJwtExpiringSoon(access)) {
      final result = await ApiClient.instance.refreshAccessToken();
      if (result == RefreshResult.invalid) {
        await store.clear();
        _user = null;
        _bindings = null;
        _sessionExpired = true;
        _status = AuthStatus.loggedOut;
        notifyListeners();
        return;
      }
      // success / transient：都保持已登录（transient 时后续请求会再次尝试）
    }

    final rawUser = await store.readUser();
    _user = rawUser == null ? null : AppUser.fromJson(rawUser);
    _bindings = _readCachedBindings(await store.readBindings());
    _status = AuthStatus.loggedIn;
    notifyListeners();
  }

  /// 拉取公共配置（是否开启短信、Fava 部署模式）。
  Future<void> loadPublicConfig() async {
    try {
      _publicConfig = await AuthService.instance.publicConfig();
      _configLoaded = true;
      notifyListeners();
    } catch (_) {
      // 公共配置失败不阻塞启动
    }
  }

  /// 手机验证码登录。
  Future<void> loginByCode({
    required String phoneNumber,
    required String code,
  }) async {
    _setBusy(true);
    try {
      final result = await AuthService.instance.loginByPhoneCode(
        phoneNumber: phoneNumber,
        code: code,
      );
      await _persist(result);
    } finally {
      _setBusy(false);
    }
  }

  /// 用户名 / 邮箱密码登录。
  Future<void> loginByPassword({
    required String username,
    required String password,
    String? totpCode,
  }) async {
    _setBusy(true);
    try {
      final result = await AuthService.instance.loginByPassword(
        username: username,
        password: password,
        totpCode: totpCode,
      );
      await _persist(result);
    } finally {
      _setBusy(false);
    }
  }

  /// 刷新账号绑定信息。
  Future<void> refreshBindings() async {
    final value = await AuthService.instance.bindings();
    _bindings = value;
    await TokenStore.instance.saveBindings(value.toJson());
    notifyListeners();
  }

  /// 绑定手机号后刷新绑定信息。
  Future<void> bindPhone({
    required String phoneNumber,
    required String code,
  }) async {
    await AuthService.instance.bindPhone(phoneNumber: phoneNumber, code: code);
    await refreshBindings();
  }

  /// 退出登录：先停止 Fava 实例与待办角标，再清空本地令牌。
  Future<void> logout() async {
    try {
      await FavaService.instance.stopFava();
    } catch (_) {
      // 停止实例失败不影响退出登录
    }
    await BadgeService.instance.clear();
    await TokenStore.instance.clear();
    _user = null;
    _bindings = null;
    _sessionExpired = false;
    _status = AuthStatus.loggedOut;
    notifyListeners();
  }

  Future<void> _persist(LoginResult result) async {
    await TokenStore.instance.saveTokens(
      access: result.access,
      refresh: result.refresh,
    );
    await TokenStore.instance.saveUser(result.user.toJson());
    _user = result.user;
    _sessionExpired = false;
    _status = AuthStatus.loggedIn;
    notifyListeners();
  }

  void _handleSessionExpired() {
    if (_status == AuthStatus.loggedOut) return;
    TokenStore.instance.clear();
    // 登录态失效同样要清掉系统角标（无需等待结果）
    BadgeService.instance.clear();
    _user = null;
    _bindings = null;
    _sessionExpired = true;
    _status = AuthStatus.loggedOut;
    notifyListeners();
  }

  void _setBusy(bool value) {
    _busy = value;
    notifyListeners();
  }

  UserBindings? _readCachedBindings(Map<String, Object?>? json) =>
      json == null ? null : UserBindings.fromJson(json);
}
