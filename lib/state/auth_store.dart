import 'package:flutter/foundation.dart';

import '../core/api_client.dart';
import '../core/token_store.dart';
import '../models/user.dart';
import '../services/auth_service.dart';
import '../services/fava_service.dart';

enum AuthStatus { unknown, loggedOut, loggedIn }

/// 认证状态：登录态、用户信息、公共配置。
class AuthStore extends ChangeNotifier {
  AuthStore._() {
    // access/refresh 均失效时退回登录页
    ApiClient.instance.onSessionExpired = _handleSessionExpired;
  }

  static final AuthStore instance = AuthStore._();

  AuthStatus _status = AuthStatus.unknown;
  AppUser? _user;
  AuthPublicConfig _publicConfig = const AuthPublicConfig();
  UserBindings? _bindings;
  bool _busy = false;
  bool _configLoaded = false;

  AuthStatus get status => _status;
  AppUser? get user => _user;
  AuthPublicConfig get publicConfig => _publicConfig;
  UserBindings? get bindings => _bindings;
  bool get isBusy => _busy;

  /// 公共配置是否已成功拉取过。
  bool get configLoaded => _configLoaded;
  bool get isLoggedIn => _status == AuthStatus.loggedIn;

  /// 启动时恢复登录态。
  Future<void> restore() async {
    await TokenStore.instance.init();
    final access = await TokenStore.instance.readAccess();
    final refresh = await TokenStore.instance.readRefresh();
    final hasToken = (access != null && access.isNotEmpty) ||
        (refresh != null && refresh.isNotEmpty);

    if (!hasToken) {
      _status = AuthStatus.loggedOut;
      notifyListeners();
      return;
    }

    final rawUser = await TokenStore.instance.readUser();
    _user = rawUser == null ? null : AppUser.fromJson(rawUser);
    _bindings = _readCachedBindings(await TokenStore.instance.readBindings());
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

  /// 退出登录：先停止 Fava 实例，再清空本地令牌。
  Future<void> logout() async {
    try {
      await FavaService.instance.stopFava();
    } catch (_) {
      // 停止实例失败不影响退出登录
    }
    await TokenStore.instance.clear();
    _user = null;
    _bindings = null;
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
    _status = AuthStatus.loggedIn;
    notifyListeners();
  }

  void _handleSessionExpired() {
    if (_status == AuthStatus.loggedOut) return;
    TokenStore.instance.clear();
    _user = null;
    _bindings = null;
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
