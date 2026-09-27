/// 共享账本别名输入解析与校验（纯函数，便于单测）。
library;

/// 别名分隔符：中英文逗号、顿号、中英文分号、空白（含换行）。
final RegExp _aliasSeparator = RegExp(r'[,，、;；\s]+');

/// 解析别名输入：按分隔符切分、逐项 trim、丢弃空串、大小写不敏感去重
/// （保留首次出现的原始大小写）。
List<String> parseAliases(String raw) {
  final result = <String>[];
  final seen = <String>{};
  for (final part in raw.split(_aliasSeparator)) {
    final alias = part.trim();
    if (alias.isEmpty) continue;
    if (seen.add(alias.toLowerCase())) result.add(alias);
  }
  return result;
}

/// 别名校验：返回错误文案，合法返回 `null`。
String? aliasValidationError(String alias) {
  if (alias.length > 64) return '别名最长为 64 个字符';
  if (alias.toLowerCase() == 'self') return '别名不能使用保留值 self';
  return null;
}
