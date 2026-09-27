/// 共享账本访问令牌（`bct_…`）的提取与非机密指纹工具。
library;

/// 访问令牌前缀（与后端个人访问令牌一致）。
const String kAccessTokenPrefix = 'bct_';

/// 令牌形态：`bct_` 后跟至少 20 个 `[A-Za-z0-9_-]` 字符。
final RegExp _accessTokenPattern = RegExp(
  '$kAccessTokenPrefix[A-Za-z0-9_\\-]{20,}',
);

/// 从文本中提取访问令牌。
///
/// 兼容「纯令牌」与「令牌夹带说明文字」两种粘贴方式，取第一个匹配；
/// `trim` 后为空或无匹配返回 `null`。
String? extractAccessToken(String? text) {
  final value = text?.trim() ?? '';
  if (value.isEmpty) return null;
  return _accessTokenPattern.firstMatch(value)?.group(0);
}

/// 令牌指纹：前 12 个字符（`bct_` + 8 位前缀），**非机密**，可用于本地去重。
///
/// 本地只持久化指纹，绝不落明文令牌。
String accessTokenFingerprint(String token) =>
    token.length <= 12 ? token : token.substring(0, 12);
