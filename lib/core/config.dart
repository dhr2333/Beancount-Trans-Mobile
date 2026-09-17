/// 全局配置：API 地址与超时常量。
///
/// API 基址在编译期确定，可用 `--dart-define=API_BASE=...` 覆盖（调试逃生口）。
class ApiConfig {
  const ApiConfig._();

  static const String apiBase = String.fromEnvironment(
    'API_BASE',
    defaultValue: 'https://trans.dhr2333.cn/api',
  );

  /// API 基址的 origin（去掉 `/api` 后缀），用于拼装 Fava 绝对 URL。
  static String get apiOrigin {
    final uri = Uri.parse(apiBase);
    return '${uri.scheme}://${uri.authority}';
  }

  /// 普通请求超时。
  static const Duration requestTimeout = Duration(seconds: 30);

  /// SSE 空闲超时：超过该时长未收到任何帧则中止请求。
  static const Duration sseIdleTimeout = Duration(seconds: 90);
}
