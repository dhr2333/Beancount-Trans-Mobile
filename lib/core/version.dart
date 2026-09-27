/// 语义化版本号（只覆盖版本比较所需的语义）。
///
/// 支持 `1.2.3`、`v1.2.3`、`1.2.3+build`、`1.2.3-rc.1` 等写法：
/// 忽略前导 `v` 与构建号（`+` 之后），保留预发布标识参与比较。
/// 缺失的段位按 0 处理，因此 `1.2` 与 `1.2.0` 等价。
class AppVersion implements Comparable<AppVersion> {
  const AppVersion(this.major, this.minor, this.patch, [this.preRelease = '']);

  final int major;
  final int minor;
  final int patch;

  /// 预发布标识（不含前导 `-`）；为空表示正式版。
  final String preRelease;

  /// 解析版本号；无法解析时返回 null。
  static AppVersion? tryParse(String raw) {
    final input = raw.trim();
    if (input.isEmpty) return null;
    // 依次去掉前导 v/V 与构建号，只保留 x.y.z[-pre]
    final normalized = input
        .replaceFirst(RegExp(r'^[vV]'), '')
        .split('+')
        .first;
    final match = RegExp(
      r'^(\d+)(?:\.(\d+))?(?:\.(\d+))?(?:-(.+))?$',
    ).firstMatch(normalized);
    if (match == null) return null;
    return AppVersion(
      int.parse(match.group(1)!),
      int.parse(match.group(2) ?? '0'),
      int.parse(match.group(3) ?? '0'),
      match.group(4) ?? '',
    );
  }

  bool get isPreRelease => preRelease.isNotEmpty;

  /// 是否比 [other] 更新。
  bool isNewerThan(AppVersion other) => compareTo(other) > 0;

  @override
  int compareTo(AppVersion other) {
    if (major != other.major) return major.compareTo(other.major);
    if (minor != other.minor) return minor.compareTo(other.minor);
    if (patch != other.patch) return patch.compareTo(other.patch);
    // 正式版优先级高于任何预发布版
    if (!isPreRelease && other.isPreRelease) return 1;
    if (isPreRelease && !other.isPreRelease) return -1;
    return _comparePreRelease(preRelease, other.preRelease);
  }

  /// 按 semver 规则逐段比较预发布标识。
  static int _comparePreRelease(String left, String right) {
    final a = left.split('.');
    final b = right.split('.');
    for (var i = 0; i < a.length && i < b.length; i++) {
      if (a[i] == b[i]) continue;
      final an = int.tryParse(a[i]);
      final bn = int.tryParse(b[i]);
      if (an != null && bn != null) return an.compareTo(bn);
      // 数字标识优先级低于字母标识
      if (an != null) return -1;
      if (bn != null) return 1;
      return a[i].compareTo(b[i]);
    }
    return a.length.compareTo(b.length);
  }

  @override
  String toString() =>
      '$major.$minor.$patch${isPreRelease ? '-$preRelease' : ''}';

  @override
  bool operator ==(Object other) =>
      other is AppVersion &&
      major == other.major &&
      minor == other.minor &&
      patch == other.patch &&
      preRelease == other.preRelease;

  @override
  int get hashCode => Object.hash(major, minor, patch, preRelease);
}
