#!/usr/bin/env bash
#
# 用发布版本号回写 pubspec.yaml 并构建已签名的 release APK。
#
# 用法：bash ci/release_android.sh 1.2.3
#
# 契约（Jenkinsfile 与 semantic-release 的 prepare 阶段都依赖）：
#   1. 自动 source 工具链 env.sh，拿到 flutter / JAVA_HOME / PUB_CACHE / GRADLE_USER_HOME；
#   2. 把 semver 解析为 versionCode = major*10000 + minor*100 + patch；
#   3. 回写 pubspec.yaml 顶层 version 行为 "<semver>+<versionCode>"（幂等）；
#   4. 用 --build-name / --build-number 构建 release APK（签名由 android/key.properties 决定）。
set -euo pipefail

usage() {
  echo "用法：bash ci/release_android.sh <semver>" >&2
  echo "示例：bash ci/release_android.sh 1.2.3" >&2
}

# 参数校验：必须且只能有一个形如 x.y.z 的版本号
if [[ $# -ne 1 ]]; then
  usage
  exit 1
fi
SEMVER="$1"
if [[ ! "$SEMVER" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
  echo "错误：版本号 '$SEMVER' 格式非法，应为 x.y.z（例如 1.2.3）。" >&2
  usage
  exit 1
fi
MAJOR="${BASH_REMATCH[1]}"
MINOR="${BASH_REMATCH[2]}"
PATCH="${BASH_REMATCH[3]}"

# 准备工具链环境（flutter、JDK、pub/gradle 缓存都放在仓库外的共享目录）
TOOLCHAIN_ROOT="${TOOLCHAIN_ROOT:-/jenkins-share/mobile-toolchain}"
TOOLCHAIN_ENV="$TOOLCHAIN_ROOT/env.sh"
if [[ -f "$TOOLCHAIN_ENV" ]]; then
  # shellcheck disable=SC1090
  source "$TOOLCHAIN_ENV"
else
  echo "错误：未找到工具链环境文件 $TOOLCHAIN_ENV" >&2
  echo "请先运行 ci/setup_toolchain.sh 准备 Flutter 与 Android SDK 工具链。" >&2
  exit 1
fi

# 始终在仓库根目录工作（semantic-release 的 cwd 是仓库根，这里再显式保证一次）
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

# versionCode：major*10000 + minor*100 + patch，例如 1.2.3 -> 10203、1.0.0 -> 10000
VERSION_CODE=$((MAJOR * 10000 + MINOR * 100 + PATCH))

# 回写 pubspec.yaml：只匹配顶层行首的 version 行（注释里的 "like 1.2.43" 不受影响）
if ! grep -qE '^version:[[:space:]]*[0-9]+\.[0-9]+\.[0-9]+' pubspec.yaml; then
  echo "错误：pubspec.yaml 中未找到顶层 version: x.y.z 行。" >&2
  exit 1
fi
sed -i -E "s/^version:.*/version: ${SEMVER}+${VERSION_CODE}/" pubspec.yaml
echo "已更新 pubspec.yaml: version: ${SEMVER}+${VERSION_CODE}"

# 构建 release APK：签名由 android/key.properties 决定，缺失时 Gradle 回退 debug 签名
flutter build apk --release --build-name="$SEMVER" --build-number="$VERSION_CODE"

echo "APK 产物：build/app/outputs/flutter-apk/app-release.apk"
