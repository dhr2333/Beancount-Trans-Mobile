// Beancount-Trans-Mobile 语义化发布配置（plain ESM，不依赖 ts-node）。
//
// 只负责「正式发布」：按 conventional commits 计算语义化版本（feat → minor、fix → patch、
// BREAKING CHANGE → major，其它提交不发布），打 tag、写 CHANGELOG、建 GitHub Release，
// 并把 prepare 阶段用该版本重新构建的已签名 APK 作为 Release 附件上传。
//
// 「每次提交都能更新」由独立的滚动构建通道承担（见 ci/publish_latest_release.mjs）：
// 每次 main 构建都会把 APK 发到固定 tag 的 Release，应用内更新读它。

/** @type {import('semantic-release').GlobalConfig} */
export default {
  branches: ['main'],
  repositoryUrl: 'https://github.com/dhr2333/Beancount-Trans-Mobile',
  tagFormat: '${version}',
  plugins: [
    // @semantic-release/commit-analyzer 是 semantic-release 自带的依赖，无需在 package.json 声明
    ['@semantic-release/commit-analyzer', { preset: 'conventionalcommits' }],
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
