# 财见（Caijian）

> 看清自己的钱，再做决定。

财见是 [Beancount-Trans](https://github.com/dhr2333/Beancount-Trans) 旗下的个人财务分析移动端。它基于你的财务账本，帮助你在行动之前看清现金流、支出结构与财务趋势。

## 与 Beancount-Trans 的关系

财见是 Beancount-Trans 的**官方移动客户端**，本身不包含独立的账本与记账引擎：登录、账本、账单解析、审核等能力均由 Beancount-Trans 后端提供。使用前需要有一个可访问的 Beancount-Trans 服务地址。

本项目以 [Apache-2.0](LICENSE) 许可开源，欢迎 fork 与改动；但「由 Beancount-Trans 提供」的品牌背书仅适用于本仓库的官方构建，衍生版本请自行更换名称与标识。

## 命名与身份约定

同一个发布物在不同层面使用不同标识，此处集中记录以免混淆：

| 层面 | 取值 |
| --- | --- |
| 应用展示名 | 财见 |
| 英文辅助名 | Caijian |
| 品牌背书 | by Beancount-Trans |
| 宣传语 | 看清自己的钱，再做决定。 |
| 仓库名 | `Beancount-Trans-Mobile` |
| Dart 包名 | `beancount_trans` |
| Android `applicationId` / iOS Bundle ID | `cn.dhr2333.caijian` |

仓库名与应用 ID 一经发布不宜再动：前者被 CI 与发布资产名引用，后者决定应用在商店与设备上的身份。

## 功能

- Copilot 对话：以自然语言查询账本，支持 Markdown 渲染与分享卡片
- 账单上传解析与审核待办
- 共享账本与别名管理
- 待办系统与图标角标
- 报表页（内嵌 Fava）
- 亮/暗主题与应用内更新

## 开发与构建

```bash
# 准备隔离工具链（Flutter / Android SDK / JDK）
bash ci/setup_toolchain.sh

# 每次执行 flutter / gradle 前先加载环境
source .toolchain/env.sh
flutter pub get
flutter run
```

发布由 Jenkins + semantic-release 驱动：`ci/release_android.sh <versionName>` 回写版本号并构建已签名 APK，`ci/publish_latest_release.mjs` 把 APK 发布到固定 tag 的滚动 Release。

## 应用内更新契约

应用内更新通过 GitHub 公开 API 读取**滚动 Release**（tag = `latest`，prerelease = true），并依赖资产名格式：

```
beancount-trans-<versionName>-<versionCode>.apk
```

该格式由 [ci/publish_latest_release.mjs](ci/publish_latest_release.mjs) 与 [lib/services/update_service.dart](lib/services/update_service.dart) 两侧共同约定，**改一侧必须同步另一侧**。

## 升级注意事项

应用 ID 曾由 `cn.dhr2333.beancount_trans` 改为 `cn.dhr2333.caijian`。在系统看来两者是不同的应用，**新版本无法覆盖升级**：旧版本用户需卸载后重新安装，登录态与本地缓存不会迁移（账本数据在后端，不受影响）。

## 许可

[Apache License 2.0](LICENSE)。再分发时请按 §4 保留版权、许可与 NOTICE 署名。
