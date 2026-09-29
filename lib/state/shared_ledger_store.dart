import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../core/access_token.dart';
import '../core/api_exception.dart';
import '../models/assistant.dart';
import '../services/shared_ledger_service.dart';

/// 共享账本状态：绑定列表、添加，以及剪贴板令牌识别。
///
/// 与 [ThemeStore] 一致：单例 + [ChangeNotifier]，页面用 [ListenableBuilder] 监听。
class SharedLedgerStore extends ChangeNotifier {
  SharedLedgerStore._();

  static final SharedLedgerStore instance = SharedLedgerStore._();

  /// 已提示过的令牌指纹（非明文）持久化键。
  static const String _kPromptedTokens = 'shared_ledger_prompted_tokens';

  /// 指纹最多保留最近 50 条。
  static const int _kPromptedLimit = 50;

  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  List<SharedLedgerBinding> _bindings = const [];
  bool _loading = false;
  String? _error;

  // 按插入顺序保存（默认 Set 为 LinkedHashSet），便于保留最近若干条。
  Set<String> _promptedFingerprints = <String>{};
  bool _promptedLoaded = false;

  List<SharedLedgerBinding> get bindings => _bindings;

  bool get loading => _loading;

  String? get error => _error;

  /// 可用的共享账本。
  List<SharedLedgerBinding> get usableBindings =>
      _bindings.where((e) => e.usable).toList();

  /// 拉取共享账本列表；错误记录在 store 内，不抛给调用方。
  Future<void> refresh() async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      _bindings = await SharedLedgerService.instance.list();
    } on ApiException catch (error) {
      _error = error.message;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// 添加共享账本；[ApiException] 向上抛出，由表单展示 `error.message`。
  Future<void> bind({
    required String token,
    required List<String> aliases,
  }) async {
    await SharedLedgerService.instance.bind(token: token, aliases: aliases);
    await refresh();
    await _rememberFingerprint(accessTokenFingerprint(token));
  }

  /// 更新某条共享账本的别名；[ApiException] 向上抛出，由表单展示 `error.message`。
  Future<void> updateAliases({
    required int id,
    required List<String> aliases,
  }) async {
    await SharedLedgerService.instance.updateAliases(id: id, aliases: aliases);
    await refresh();
  }

  /// 读取剪贴板中的访问令牌；未命中或已提示过则返回 `null`。
  ///
  /// 命中后**先记录指纹再返回**（同一条令牌只提醒一次，用户忽略后不再打扰）。
  Future<String?> takeClipboardToken() async {
    await _ensurePromptedLoaded();
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final token = extractAccessToken(data?.text);
    if (token == null) return null;
    final fingerprint = accessTokenFingerprint(token);
    if (_promptedFingerprints.contains(fingerprint)) return null;
    await _rememberFingerprint(fingerprint);
    return token;
  }

  /// 记录指纹并持久化（仅存指纹，绝不存明文令牌）。
  Future<void> _rememberFingerprint(String fingerprint) async {
    await _ensurePromptedLoaded();
    if (fingerprint.isEmpty || !_promptedFingerprints.add(fingerprint)) return;

    final ordered = _promptedFingerprints.toList();
    final kept = ordered.length > _kPromptedLimit
        ? ordered.sublist(ordered.length - _kPromptedLimit)
        : ordered;
    _promptedFingerprints = kept.toSet();
    try {
      await _storage.write(key: _kPromptedTokens, value: jsonEncode(kept));
    } catch (_) {
      // 写入失败仅影响下次启动的去重，本次已生效
    }
  }

  /// 惰性加载本地指纹集合；读取/解码失败静默回退为空集。
  Future<void> _ensurePromptedLoaded() async {
    if (_promptedLoaded) return;
    _promptedLoaded = true;
    try {
      final raw = await _storage.read(key: _kPromptedTokens);
      if (raw == null || raw.isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        _promptedFingerprints = decoded.whereType<String>().toSet();
      }
    } catch (_) {
      // 忽略脏数据，视为空集
    }
  }
}
