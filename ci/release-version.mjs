// Beancount-Trans-Mobile 专用 semantic-release 本地插件。
//
// 把发布版本号接管为 `<semver>-<main 提交数>`（例如 1.2.1-51）：
//   - 前缀 X.Y.Z 只在 feat / fix / BREAKING CHANGE 时抬高，其它提交保持不变；
//   - 后缀取 `git rev-list --count HEAD`，因此每次 main 提交都会 +1。
//
// semantic-release 本身无法产出这种 tag（版本号由 analyzeCommits 的 release type 经 semver.inc
// 推导，且默认对 chore / style 提交不发布），所以这里：
//   - analyzeCommits 只决定「本次是否发版」（有非发布提交就发）；
//   - verifyRelease 覆盖 nextRelease.version / gitTag / name（nextRelease 是共享对象，
//     覆盖结果会生效到后续 generateNotes → prepare → git tag → publish）。
import { execFileSync } from 'node:child_process';
import { readFileSync } from 'node:fs';

/** 形如 1.2.1-51 的构建 tag */
const BUILD_TAG = /^(\d+)\.(\d+)\.(\d+)-(\d+)$/;
/** 形如 1.2.1 的正式 tag */
const CLEAN_TAG = /^\d+\.\d+\.\d+$/;
/** semantic-release 生成的发布提交主题 */
const RELEASE_SUBJECT = /^chore\(release\)/;

const git = (...args) => execFileSync('git', args, { encoding: 'utf8' }).trim();

/** 可达的 X.Y.Z-N 构建 tag（即上次发版），按版本倒序取第一个 */
function lastBuildTag() {
  return (
    git('tag', '--merged', 'HEAD', '--list', '*.*.*-*', '--sort=-v:refname')
      .split('\n')
      .map((tag) => tag.trim())
      .find((tag) => BUILD_TAG.test(tag)) ?? null
  );
}

/** 还没有构建 tag 时的起点：最近的正式 tag（如 1.2.1） */
function lastCleanTag() {
  return (
    git('tag', '--merged', 'HEAD', '--list', '*.*.*', '--sort=-v:refname')
      .split('\n')
      .map((tag) => tag.trim())
      .find((tag) => CLEAN_TAG.test(tag)) ?? null
  );
}

/** 本次版本对应的提交起点 */
const rangeStart = () => lastBuildTag() ?? lastCleanTag();

/**
 * 起点之后的提交，形如 semantic-release 的 commit 对象（旧 → 新）。
 * 说明：semantic-release 的 lastRelease 会退回正式 tag（1.2.1 在 semver 上大于 1.2.1-50），
 * 这里自行按构建 tag 取范围，保证 release notes / CHANGELOG 只覆盖本次提交。
 */
function commitsSince(start) {
  const raw = git(
    'log',
    start ? `${start}..HEAD` : 'HEAD',
    '--reverse',
    '--format=%H%x1f%cI%x1f%B%x1e',
  );
  return raw
    .split('\x1e')
    .map((chunk) => chunk.trim())
    .filter(Boolean)
    .map((chunk) => {
      const first = chunk.indexOf('\x1f');
      const second = chunk.indexOf('\x1f', first + 1);
      return {
        hash: chunk.slice(0, first),
        committerDate: new Date(chunk.slice(first + 1, second)),
        message: chunk.slice(second + 1).trim(),
        // 与 semantic-release 自身的 commit 结构保持一致
        gitTags: '',
      };
    });
}

const isReleaseCommit = ({ message }) =>
  RELEASE_SUBJECT.test(message.split('\n')[0]);

/** conventional commits → 前缀抬高级别 */
function bumpLevel(commits) {
  let level = 'none';
  for (const { message } of commits) {
    if (/^BREAKING CHANGE:/m.test(message) || /^\w+(?:\([^)]*\))?!:/.test(message)) {
      return 'major';
    }
    if (/^feat(?:\([^)]*\))?:/.test(message)) {
      level = 'minor';
    } else if (/^fix(?:\([^)]*\))?:/.test(message) && level === 'none') {
      level = 'patch';
    }
  }
  return level;
}

/** 按级别抬高前缀 */
function bump(prefix, level) {
  const [major, minor, patch] = prefix.split('.').map(Number);
  if (level === 'major') return `${major + 1}.0.0`;
  if (level === 'minor') return `${major}.${minor + 1}.0`;
  if (level === 'patch') return `${major}.${minor}.${patch + 1}`;
  return prefix;
}

/** 前缀来源：上次构建 tag 的前缀，缺失时回退 pubspec（首次即 1.2.1） */
function currentPrefix() {
  const previous = lastBuildTag();
  if (previous) return previous.replace(BUILD_TAG, '$1.$2.$3');
  const matched = /^version:\s*(\d+\.\d+\.\d+)/m.exec(
    readFileSync('pubspec.yaml', 'utf8'),
  );
  return matched ? matched[1] : '1.0.0';
}

/** 本次发布版本号，如 1.2.1-51 */
function buildVersion() {
  const commits = commitsSince(rangeStart());
  const prefix = bump(currentPrefix(), bumpLevel(commits));
  return `${prefix}-${Number(git('rev-list', '--count', 'HEAD'))}`;
}

/** 更新说明只覆盖本次提交，因此要剔除 semantic-release 自己产生的发布提交 */
const releasableCommits = () =>
  commitsSince(rangeStart()).filter((commit) => !isReleaseCommit(commit));

export async function analyzeCommits() {
  // 守卫：自上次发版以来没有“非发布提交”就不发版，避免发布提交自己触发新一轮发布
  // 'patch' 只是占位（analyzeCommits 必须返回 release type 才会发版），真实版本在 verifyRelease 覆盖
  return releasableCommits().length > 0 ? 'patch' : false;
}

export async function verifyRelease(_pluginConfig, context) {
  const previous = lastBuildTag();
  const version = buildVersion();

  // 三个字段都覆盖，保证 tag 名 / Release 名 / 附件名 / CHANGELOG 一致
  context.nextRelease.version = version;
  context.nextRelease.gitTag = version;
  context.nextRelease.name = version;

  if (previous) {
    // semantic-release 的 lastRelease 会退回正式 tag（1.2.1 在 semver 上大于 1.2.1-50），
    // 这里改回上一个构建 tag，让 release notes / CHANGELOG 只覆盖本次提交
    context.lastRelease = {
      ...context.lastRelease,
      version: previous.replace(BUILD_TAG, '$1.$2.$3'),
      gitTag: previous,
      gitHead: git('rev-list', '-1', previous),
    };
  }
  context.commits = releasableCommits();
}

export default { analyzeCommits, verifyRelease };
