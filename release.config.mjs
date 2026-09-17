// Beancount-Trans-Mobile 语义化发布配置（plain ESM，不依赖 ts-node）。
// prepare 阶段会用发布版本号构建已签名 APK，publish 阶段把 APK 作为 Release 附件上传。
// 版本号由 conventional commits 推导，tag 直接使用裸版本号（如 1.2.3）。

/** @type {import('semantic-release').GlobalConfig} */
export default {
  branches: ['main'],
  repositoryUrl: 'https://github.com/dhr2333/Beancount-Trans-Mobile',
  tagFormat: '${version}',
  plugins: [
    ['@semantic-release/commit-analyzer', { preset: 'conventionalcommits' }],
    ['@semantic-release/release-notes-generator', { preset: 'conventionalcommits' }],
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
