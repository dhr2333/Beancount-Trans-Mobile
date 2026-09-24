import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// 外观偏好：跟随系统 / 浅色 / 深色，本地持久化。
///
/// 复用已有的 [FlutterSecureStorage]（不引入额外依赖）；读写失败时保持「跟随系统」，
/// 不影响启动与本次切换。
class ThemeStore extends ChangeNotifier {
  ThemeStore._();

  static final ThemeStore instance = ThemeStore._();

  static const String _kThemeMode = 'theme_mode';

  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  ThemeMode _mode = ThemeMode.system;

  /// 当前主题模式，默认跟随系统。
  ThemeMode get mode => _mode;

  /// 启动时读取本地偏好。
  Future<void> load() async {
    try {
      _mode = _decode(await _storage.read(key: _kThemeMode));
    } catch (_) {
      // 本地存储不可用时保持跟随系统
    }
    notifyListeners();
  }

  /// 切换主题模式并写入本地。
  Future<void> setMode(ThemeMode mode) async {
    if (_mode == mode) return;
    _mode = mode;
    notifyListeners();
    try {
      await _storage.write(key: _kThemeMode, value: _encode(mode));
    } catch (_) {
      // 写入失败仅影响下次启动的记忆，本次切换已生效
    }
  }

  static ThemeMode _decode(String? raw) => switch (raw) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };

  static String _encode(ThemeMode mode) => switch (mode) {
        ThemeMode.light => 'light',
        ThemeMode.dark => 'dark',
        ThemeMode.system => 'system',
      };
}
