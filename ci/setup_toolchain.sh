#!/usr/bin/env bash
# =============================================================================
# 移动端 CI 工具链准备脚本
#
# 幂等准备 Flutter SDK + Android SDK（含许可接受）到仓库外的共享目录，并生成 env.sh
# 供 Jenkinsfile 各阶段 source。重复执行只做存在性校验，不重复下载。
#
# 所有入参均可通过环境变量覆盖：
#   TOOLCHAIN_ROOT       共享工具链根目录（默认 /jenkins-share/mobile-toolchain）
#   FLUTTER_VERSION      Flutter 固定版本（默认 3.47.4）
#   FLUTTER_MIRROR       Flutter 下载镜像（默认 https://storage.flutter-io.cn）
#   PUB_HOSTED_URL       pub 镜像（默认 https://pub.flutter-io.cn）
#   MOBILE_JAVA_HOME     可选，显式指定 JDK 路径（需 ≥17）
#   CMDLINE_TOOLS_ZIP    可选，本地已有的 commandlinetools zip（跳过下载）
#   ANDROID_PLATFORM     Android 编译 SDK（默认 android-36）
#   ANDROID_BUILD_TOOLS  Android build-tools（默认 36.0.0）
# =============================================================================
set -euo pipefail

TOOLCHAIN_ROOT="${TOOLCHAIN_ROOT:-/jenkins-share/mobile-toolchain}"
FLUTTER_VERSION="${FLUTTER_VERSION:-3.47.4}"
FLUTTER_MIRROR="${FLUTTER_MIRROR:-https://storage.flutter-io.cn}"
PUB_HOSTED_URL="${PUB_HOSTED_URL:-https://pub.flutter-io.cn}"
MOBILE_JAVA_HOME="${MOBILE_JAVA_HOME:-}"
CMDLINE_TOOLS_ZIP="${CMDLINE_TOOLS_ZIP:-}"
ANDROID_PLATFORM="${ANDROID_PLATFORM:-android-36}"
ANDROID_BUILD_TOOLS="${ANDROID_BUILD_TOOLS:-36.0.0}"

# 共享目录布局（全部位于 TOOLCHAIN_ROOT 下，仓库内不落任何工具链文件）
FLUTTER_ROOT="$TOOLCHAIN_ROOT/flutter"
ANDROID_HOME="$TOOLCHAIN_ROOT/android-sdk"
CMDLINE_TOOLS_DIR="$ANDROID_HOME/cmdline-tools/latest"
SDKMANAGER="$CMDLINE_TOOLS_DIR/bin/sdkmanager"
PUB_CACHE_DIR="$TOOLCHAIN_ROOT/pub-cache"
GRADLE_HOME_DIR="$TOOLCHAIN_ROOT/gradle-home"

log() { echo "[setup] $*"; }
die() { echo "!! $*" >&2; exit 1; }

log "工具链根目录：$TOOLCHAIN_ROOT"
log "Flutter $FLUTTER_VERSION（镜像 $FLUTTER_MIRROR）/ Android $ANDROID_PLATFORM + build-tools $ANDROID_BUILD_TOOLS"

mkdir -p "$TOOLCHAIN_ROOT" "$PUB_CACHE_DIR" "$GRADLE_HOME_DIR"

# -----------------------------------------------------------------------------
# 1. 解析 JDK（≥17 即可；优先复用环境里已有的 JDK，缺失则快速失败）
# -----------------------------------------------------------------------------
log "[1/5] 解析 JDK（最低 17）..."
MIN_JDK_MAJOR=17

# 输出 javac 主版本号（如 17、21、25），识别失败输出空串
javac_major_version() {
  "$1" -version 2>&1 | awk '
    /^javac 1\./ { split($2, a, "."); print a[2]; exit }
    /^javac [0-9]+\./ { split($2, a, "."); print a[1]; exit }
  '
}

resolve_java_home() {
  local candidates=() candidate globbed derived java_bin major
  [ -n "$MOBILE_JAVA_HOME" ] && candidates+=("$MOBILE_JAVA_HOME")
  # 优先固定的 JDK 17 路径，保证「有 17 就用 17」
  candidates+=("/usr/lib/jvm/java-17-openjdk" "/usr/lib/jvm/java-17-openjdk-amd64")
  # 由 PATH 中的 java 真实路径反推 JAVA_HOME（.../bin/java -> ...）：复用环境自带 JDK
  if java_bin="$(command -v java 2>/dev/null)"; then
    derived="$(readlink -f "$java_bin" 2>/dev/null || true)"
    if [ -n "$derived" ]; then
      candidates+=("$(dirname "$(dirname "$derived")")")
    fi
  fi
  # 常见发行版 / 镜像布局（含 eclipse-temurin 的 /opt/java/openjdk、Jenkins 官方镜像等）
  for globbed in /opt/java/*/bin/javac /usr/lib/jvm/*/bin/javac /opt/*jdk*/bin/javac \
    /usr/local/openjdk*/bin/javac /usr/java/*/bin/javac "$HOME"/.sdkman/candidates/java/*/bin/javac; do
    [ -x "$globbed" ] || continue
    candidates+=("$(dirname "$(dirname "$globbed")")")
  done
  for candidate in "${candidates[@]}"; do
    [ -n "$candidate" ] || continue
    [ -x "$candidate/bin/javac" ] || continue
    major="$(javac_major_version "$candidate/bin/javac")"
    [ -n "$major" ] || continue
    if [ "$major" -ge "$MIN_JDK_MAJOR" ]; then
      echo "$candidate"
      return 0
    fi
  done
  return 1
}

if ! JAVA_HOME="$(resolve_java_home)"; then
  die "未找到 JDK $MIN_JDK_MAJOR+。请安装 JDK（如 /usr/lib/jvm/java-17-openjdk），或用 MOBILE_JAVA_HOME=/path/to/jdk 显式指定。"
fi
export JAVA_HOME
export PATH="$JAVA_HOME/bin:$PATH"
log "      JAVA_HOME = $JAVA_HOME（$("$JAVA_HOME/bin/javac" -version 2>&1)）"

# -----------------------------------------------------------------------------
# 2. Flutter SDK：版本匹配则跳过，否则重装（保证版本可复现）
# -----------------------------------------------------------------------------
log "[2/5] 检查 Flutter SDK ..."
FLUTTER_BIN="$FLUTTER_ROOT/bin/flutter"
FLUTTER_VERSION_JSON="$FLUTTER_ROOT/bin/cache/flutter.version.json"

# 从 flutter.version.json 中读取 flutterVersion 字段
installed_flutter_version() {
  [ -f "$FLUTTER_VERSION_JSON" ] || return 0
  sed -n 's/.*"flutterVersion"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$FLUTTER_VERSION_JSON" | head -n 1
}

need_flutter_install=1
if [ -x "$FLUTTER_BIN" ]; then
  installed_version="$(installed_flutter_version)"
  if [ "$installed_version" = "$FLUTTER_VERSION" ]; then
    need_flutter_install=0
    log "      已存在 $FLUTTER_ROOT 且版本匹配（$installed_version），跳过下载"
  else
    log "      版本漂移：已有 '${installed_version:-未知}' != 期望 '$FLUTTER_VERSION'，删除后重新安装"
  fi
fi

if [ "$need_flutter_install" = "1" ]; then
  FLUTTER_ARCHIVE_URL="$FLUTTER_MIRROR/flutter_infra_release/releases/stable/linux/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz"
  FLUTTER_ARCHIVE_FILE="$TOOLCHAIN_ROOT/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz"
  rm -rf "$FLUTTER_ROOT"
  log "      下载 $FLUTTER_ARCHIVE_URL"
  if ! curl -fL --retry 3 --retry-delay 5 -C - -o "$FLUTTER_ARCHIVE_FILE" "$FLUTTER_ARCHIVE_URL"; then
    die "Flutter SDK 下载失败：$FLUTTER_ARCHIVE_URL（请检查网络或 FLUTTER_MIRROR）"
  fi
  log "      解压到 $TOOLCHAIN_ROOT（归档内含 flutter/ 顶层目录）"
  if ! tar -xf "$FLUTTER_ARCHIVE_FILE" -C "$TOOLCHAIN_ROOT"; then
    die "Flutter SDK 解压失败：$FLUTTER_ARCHIVE_FILE（Flutter 仅提供 .tar.xz，需要 xz 支持；若本机缺少 xz，可先在能解压的机器上把归档解到 $FLUTTER_ROOT 后重跑本脚本）"
  fi
  rm -f "$FLUTTER_ARCHIVE_FILE"
  [ -x "$FLUTTER_BIN" ] || die "Flutter SDK 安装异常，未找到可执行文件：$FLUTTER_BIN"
  log "      安装完成：$(installed_flutter_version)"
fi

# -----------------------------------------------------------------------------
# 3. Android SDK：cmdline-tools + platform-tools + platforms + build-tools
# -----------------------------------------------------------------------------
log "[3/5] 检查 Android SDK ..."
export ANDROID_HOME
export ANDROID_SDK_ROOT="$ANDROID_HOME"

if [ ! -x "$SDKMANAGER" ]; then
  # 3.1 取得 commandlinetools zip（优先使用本地已有文件）
  if [ -n "$CMDLINE_TOOLS_ZIP" ]; then
    CMDLINE_TOOLS_ARCHIVE="$CMDLINE_TOOLS_ZIP"
    CMDLINE_TOOLS_DOWNLOADED=0
    [ -f "$CMDLINE_TOOLS_ARCHIVE" ] || die "CMDLINE_TOOLS_ZIP 指向的文件不存在：$CMDLINE_TOOLS_ARCHIVE"
    log "      使用本地 commandlinetools：$CMDLINE_TOOLS_ARCHIVE"
  else
    log "      解析 commandlinetools 包名 ..."
    CMDLINE_TOOLS_ZIP_NAME="$(curl -fsSL --retry 3 --retry-delay 5 https://dl.google.com/android/repository/repository2-3.xml \
      | grep -oE 'commandlinetools-linux-[0-9]+_latest\.zip' | head -n 1)"
    [ -n "$CMDLINE_TOOLS_ZIP_NAME" ] || die "无法从 repository2-3.xml 解析出 commandlinetools 包名"
    log "      zip = $CMDLINE_TOOLS_ZIP_NAME"
    CMDLINE_TOOLS_ARCHIVE="$TOOLCHAIN_ROOT/$CMDLINE_TOOLS_ZIP_NAME"
    CMDLINE_TOOLS_DOWNLOADED=1
    if ! curl -fL --retry 3 --retry-delay 5 -C - -o "$CMDLINE_TOOLS_ARCHIVE" \
      "https://dl.google.com/android/repository/$CMDLINE_TOOLS_ZIP_NAME"; then
      die "commandlinetools 下载失败：$CMDLINE_TOOLS_ZIP_NAME"
    fi
  fi

  # 3.2 解压为 cmdline-tools/latest 结构（zip 内顶层目录名为 cmdline-tools）
  log "      解压出 cmdline-tools/latest ..."
  rm -rf "$CMDLINE_TOOLS_DIR" "$ANDROID_HOME/cmdline-tools/.tmp"
  mkdir -p "$ANDROID_HOME/cmdline-tools/.tmp"
  if ! unzip -q -o "$CMDLINE_TOOLS_ARCHIVE" -d "$ANDROID_HOME/cmdline-tools/.tmp"; then
    die "commandlinetools 解压失败：$CMDLINE_TOOLS_ARCHIVE"
  fi
  [ -d "$ANDROID_HOME/cmdline-tools/.tmp/cmdline-tools" ] \
    || die "commandlinetools 归档结构异常，未找到 cmdline-tools 目录：$CMDLINE_TOOLS_ARCHIVE"
  mv "$ANDROID_HOME/cmdline-tools/.tmp/cmdline-tools" "$CMDLINE_TOOLS_DIR"
  rm -rf "$ANDROID_HOME/cmdline-tools/.tmp"
  # 只清理由本脚本下载的压缩包（本地传入的不动）
  if [ "$CMDLINE_TOOLS_DOWNLOADED" = "1" ]; then
    rm -f "$CMDLINE_TOOLS_ARCHIVE"
  fi
  [ -x "$SDKMANAGER" ] || die "cmdline-tools 安装异常，未找到 $SDKMANAGER"
else
  log "      已存在 $SDKMANAGER，跳过下载与解压"
fi

# 3.3 接受许可（不同环境可能无交互输入，失败不中断）
log "      接受 Android SDK 许可 ..."
yes | "$SDKMANAGER" --sdk_root="$ANDROID_HOME" --licenses >/dev/null || true

# 3.4 安装所需组件：已全部安装时跳过，避免每次构建都联网校验
if [ -x "$ANDROID_HOME/platform-tools/adb" ] \
  && [ -f "$ANDROID_HOME/platforms/$ANDROID_PLATFORM/sdk.properties" ] \
  && [ -f "$ANDROID_HOME/build-tools/$ANDROID_BUILD_TOOLS/source.properties" ]; then
  log "      platform-tools / platforms;$ANDROID_PLATFORM / build-tools;$ANDROID_BUILD_TOOLS 已安装，跳过"
else
  log "      安装 platform-tools、platforms;$ANDROID_PLATFORM、build-tools;$ANDROID_BUILD_TOOLS ..."
  # 新版 sdkmanager 会转发给 Android CLI，并以交互方式要求确认服务条款/条款；
  # 用进程替换持续喂 'y'（不参与管道状态，避免 pipefail 误判），保证非交互环境下不挂起
  if ! "$SDKMANAGER" --sdk_root="$ANDROID_HOME" \
    "platform-tools" "platforms;$ANDROID_PLATFORM" "build-tools;$ANDROID_BUILD_TOOLS" < <(yes); then
    die "Android SDK 组件安装失败（platform-tools / platforms;$ANDROID_PLATFORM / build-tools;$ANDROID_BUILD_TOOLS）"
  fi
fi
export PATH="$FLUTTER_ROOT/bin:$CMDLINE_TOOLS_DIR/bin:$ANDROID_HOME/platform-tools:$JAVA_HOME/bin:$PATH"

# -----------------------------------------------------------------------------
# 4. 预热：关闭埋点统计（flag 随版本可能变化，失败忽略）与 Android 产物预下载
# -----------------------------------------------------------------------------
log "[4/5] 预热 Flutter（precache --android）..."
export PUB_CACHE="$PUB_CACHE_DIR"
export PUB_HOSTED_URL
export FLUTTER_STORAGE_BASE_URL="$FLUTTER_MIRROR"
"$FLUTTER_BIN" config --no-analytics >/dev/null 2>&1 || true
"$FLUTTER_BIN" precache --android || die "flutter precache --android 失败"

# -----------------------------------------------------------------------------
# 5. 生成 env.sh（可被 source，保留调用方原有 PATH，不修改 HOME）
# -----------------------------------------------------------------------------
log "[5/5] 生成 $TOOLCHAIN_ROOT/env.sh ..."
cat > "$TOOLCHAIN_ROOT/env.sh" <<EOF
# 移动端 CI 工具链环境（由 ci/setup_toolchain.sh 生成，请勿手工修改）
# 用法：source "$TOOLCHAIN_ROOT/env.sh"
export TOOLCHAIN_ROOT="$TOOLCHAIN_ROOT"
export FLUTTER_ROOT="\$TOOLCHAIN_ROOT/flutter"
export ANDROID_HOME="\$TOOLCHAIN_ROOT/android-sdk"
export ANDROID_SDK_ROOT="\$ANDROID_HOME"
export JAVA_HOME="$JAVA_HOME"
export PUB_CACHE="\$TOOLCHAIN_ROOT/pub-cache"
export GRADLE_USER_HOME="\$TOOLCHAIN_ROOT/gradle-home"
export PUB_HOSTED_URL="$PUB_HOSTED_URL"
export FLUTTER_STORAGE_BASE_URL="$FLUTTER_MIRROR"
export PATH="\$FLUTTER_ROOT/bin:\$ANDROID_HOME/cmdline-tools/latest/bin:\$ANDROID_HOME/platform-tools:\$JAVA_HOME/bin:\$PATH"
EOF

# -----------------------------------------------------------------------------
# 完成摘要
# -----------------------------------------------------------------------------
echo "==================== 工具链就绪 ===================="
echo "TOOLCHAIN_ROOT : $TOOLCHAIN_ROOT"
echo "Flutter        : $(installed_flutter_version)（期望 $FLUTTER_VERSION）"
echo "Dart           : $(sed -n 's/.*"dartSdkVersion"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$FLUTTER_VERSION_JSON" | head -n 1)"
echo "JDK            : $JAVA_HOME（$("$JAVA_HOME/bin/javac" -version 2>&1)）"
echo "Android SDK    : $ANDROID_HOME"
echo "                 已安装 platform-tools、platforms;$ANDROID_PLATFORM、build-tools;$ANDROID_BUILD_TOOLS"
echo "缓存           : PUB_CACHE=$PUB_CACHE_DIR  GRADLE_USER_HOME=$GRADLE_HOME_DIR"
echo "环境文件       : $TOOLCHAIN_ROOT/env.sh（source 后即可使用 flutter / sdkmanager）"
echo "SETUP_TOOLCHAIN_DONE"
