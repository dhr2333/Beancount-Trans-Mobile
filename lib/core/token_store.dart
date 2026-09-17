import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// JWT 与用户信息的本地安全存储（Android: Keystore 加密 / iOS: Keychain）。
///
/// 同时维护一份 access 的内存缓存，供请求拦截器同步读取。
class TokenStore {
  TokenStore._();

  static final TokenStore instance = TokenStore._();

  static const String _kAccess = 'access';
  static const String _kRefresh = 'refresh';
  static const String _kUser = 'user';
  static const String _kBindings = 'bindings';

  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  String? _accessCache;

  /// 内存中的 access token（可能为 null）。
  String? get accessToken => _accessCache;

  /// 启动时把 access 读入内存缓存。
  Future<void> init() async {
    _accessCache = await _storage.read(key: _kAccess);
  }

  Future<String?> readAccess() async {
    _accessCache ??= await _storage.read(key: _kAccess);
    return _accessCache;
  }

  Future<String?> readRefresh() => _storage.read(key: _kRefresh);

  Future<void> saveAccess(String access) async {
    _accessCache = access;
    await _storage.write(key: _kAccess, value: access);
  }

  Future<void> saveTokens({
    required String access,
    required String refresh,
  }) async {
    _accessCache = access;
    await _storage.write(key: _kAccess, value: access);
    await _storage.write(key: _kRefresh, value: refresh);
  }

  Future<void> saveUser(Map<String, Object?> user) =>
      _storage.write(key: _kUser, value: jsonEncode(user));

  Future<Map<String, Object?>?> readUser() async {
    final raw = await _storage.read(key: _kUser);
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) return decoded.cast<String, Object?>();
    } catch (_) {
      // 忽略脏数据
    }
    return null;
  }

  Future<void> saveBindings(Map<String, Object?> bindings) =>
      _storage.write(key: _kBindings, value: jsonEncode(bindings));

  Future<Map<String, Object?>?> readBindings() async {
    final raw = await _storage.read(key: _kBindings);
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) return decoded.cast<String, Object?>();
    } catch (_) {
      // 忽略脏数据
    }
    return null;
  }

  Future<void> clear() async {
    _accessCache = null;
    await _storage.delete(key: _kAccess);
    await _storage.delete(key: _kRefresh);
    await _storage.delete(key: _kUser);
    await _storage.delete(key: _kBindings);
  }
}
