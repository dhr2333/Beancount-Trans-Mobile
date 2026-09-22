import 'dart:convert';

/// JWT 本地解析工具。
///
/// 仅用于判断 access 是否临近过期（不做签名校验），避免无谓的 401 往返。
DateTime? jwtExpiresAt(String token) {
  final parts = token.split('.');
  if (parts.length != 3) return null;
  try {
    final payload = utf8.decode(base64Url.decode(base64Url.normalize(parts[1])));
    final decoded = jsonDecode(payload);
    if (decoded is! Map) return null;
    final exp = decoded['exp'];
    if (exp is! num) return null;
    return DateTime.fromMillisecondsSinceEpoch(exp.toInt() * 1000);
  } catch (_) {
    return null;
  }
}

/// token 是否缺失、已过期或将在 [leeway] 内过期。
///
/// 解析失败时返回 `false`：交由 401 兜底刷新，避免因脏 token 反复续期。
bool isJwtExpiringSoon(
  String? token, {
  Duration leeway = const Duration(minutes: 5),
}) {
  if (token == null || token.isEmpty) return true;
  final expiresAt = jwtExpiresAt(token);
  if (expiresAt == null) return false;
  return expiresAt.isBefore(DateTime.now().add(leeway));
}
