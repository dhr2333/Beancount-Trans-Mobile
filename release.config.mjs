// Beancount-Trans-Mobile 语义化发布配置（plain ESM，不依赖 ts-node）。
// prepare 阶段会用发布版本号构建已签名 APK，publish 阶段把 APK 作为 Release 附件上传。
// 版本号形如 <semver>-<main 提交数>（如 1.2.1-51），由本地插件 ci/release-version.mjs 接管计算：
//   前缀只在 feat / fix / BREAKING CHANGE 时抬高，后缀每次 main 提交都 +1；
//   tag 直接使用该版本号（如 1.2.1-51）。
import releaseVersion from './ci/release-version.mjs';

/** @type {import('semantic-release').GlobalConfig} */
export default {
  branches: ['main'],
  repositoryUrl: 'https://github.com/dhr2333/Beancount-Trans-Mobile',
  tagFormat: '${version}',
  plugins: [
    // 本地插件接管版本计算，因此不再使用 @semantic-release/commit-analyzer
    // （否则它会把“只有发布提交”的情况也算作可发布，导致发布提交反复触发发版）
    releaseVersion,
    [
      '@semantic-release/release-notes-generator',
      {
        preset: 'conventionalcommits',
        // 每次 main 提交都会发版，若沿用默认类型表（只列 feat/fix/perf/revert），
        // style / chore 等提交单独成版时更新说明会是空的，这里把常用类型都显式列出来。
        // type 为空串用于兜住非 conventional 提交（如 merge commit、无前缀的中文标题）。
        presetConfig: {
          types: [
            { type: 'feat', section: 'Features' },
            { type: 'fix', section: 'Bug Fixes' },
            { type: 'perf', section: 'Performance Improvements' },
            { type: 'revert', section: 'Reverts' },
            { type: 'refactor', section: 'Code Refactoring' },
            { type: 'docs', section: 'Documentation' },
            { type: 'style', section: 'Styles' },
            { type: 'test', section: 'Tests' },
            { type: 'build', section: 'Build System' },
            { type: 'ci', section: 'Continuous Integration' },
            { type: 'chore', section: 'Miscellaneous Chores' },
            { type: '', section: 'Others' },
          ],
        },
      },
    ],
    [
      '@semantic-release/changelog',
      {
        changelogFile: 'CHANGELOG.md',
        changelogTitle: '# Changelog',
      },
    ],
    ['@semantic-release/npm', { npmPublish: false }],
    [
      '@semantic-release/exec',
      {
        prepareCmd: 'bash ci/release_android.sh ${nextRelease.version}',
      },
    ],
    [
      '@semantic-release/git',
      {
        assets: ['CHANGELOG.md', 'pubspec.yaml', 'package.json', 'package-lock.json'],
        message: 'chore(release): ${nextRelease.version}\n\n${nextRelease.notes}',
      },
    ],
    [
      '@semantic-release/github',
      {
        successComment: false,
        assets: [
          {
            path: 'build/app/outputs/flutter-apk/app-release.apk',
            label: 'beancount-trans-${nextRelease.version}.apk',
          },
        ],
      },
    ],
  ],
};
