#!/usr/bin/env bash
#
# 输出本次构建使用的 versionCode —— 一个只增不减的构建序号。
#
# 契约：
#   1. 取当前提交在历史中的序号（git rev-list --count HEAD），随每次提交 +1；
#      与语义化版本号（versionName）解耦，前缀仍由 semantic-release 管理。
#   2. VERSION_CODE_BASE 默认为 0：新包的 versionCode（如 51）会小于旧公式发布过的值（10201），
#      因此从旧版本升级需要先卸载重装一次；改为 100000 即可让旧版本原地覆盖升级（代价是多一个基数）。
#   3. 需要完整提交历史（Jenkins 为完整克隆，勿改成 shallow clone），且不要 rewrite/force-push main，
#      否则计数可能回退，导致 Android 判为降级安装。
#   4. 同一提交上多次调用结果相同，因此同一次构建里的「滚动 APK」与
#      「semantic-release 正式 APK」必然拿到同一个 versionCode。
set -euo pipefail

readonly VERSION_CODE_BASE=0

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

COUNT="$(git rev-list --count HEAD)"
if [[ ! "$COUNT" =~ ^[0-9]+$ ]]; then
  echo "错误：无法获取提交数（git rev-list --count HEAD = '$COUNT'）。" >&2
  exit 1
fi

echo $((VERSION_CODE_BASE + COUNT))
