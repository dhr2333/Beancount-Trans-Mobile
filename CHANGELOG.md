# Changelog

## [1.2.1](https://github.com/dhr2333/Beancount-Trans-Mobile/compare/1.2.0...1.2.1) (2026-09-29)

### Bug Fixes

* **auth:** 移除登出时停止Fava实例的逻辑，更新相关提示与文档 ([dd738d5](https://github.com/dhr2333/Beancount-Trans-Mobile/commit/dd738d54d2e0f62a48f5c038fc5ed50dca9f2f5d))
* **profile_page:** 修复个人页面登出后的导航逻辑问题 ([df762c3](https://github.com/dhr2333/Beancount-Trans-Mobile/commit/df762c353f579b27b20743bd233be072d8d04656))
* **shared-ledger:** 添加共享账本别名编辑功能 ([3fd8182](https://github.com/dhr2333/Beancount-Trans-Mobile/commit/3fd8182da03b5fbb6634ecaf260e08d93984193b))
* **theme:** 修复AppBar滚动变色问题并重构主题构建代码 ([100d467](https://github.com/dhr2333/Beancount-Trans-Mobile/commit/100d46734023b6eb0825a93ebf70ff79263eb1d1))
* 优化共享账本别名标签与页面展示逻辑 ([78f11ba](https://github.com/dhr2333/Beancount-Trans-Mobile/commit/78f11bafdd4fe62449f6772e3d65e8e42e32120f))
* 实现完整的应用内更新功能 ([5c59e2f](https://github.com/dhr2333/Beancount-Trans-Mobile/commit/5c59e2f6f72e6243f64bf57a2da07bf7f0009282))
* 页面优化 ([36ba06f](https://github.com/dhr2333/Beancount-Trans-Mobile/commit/36ba06ffa351b282853dc9682821dd5f5d9b782e))

## [1.2.0](https://github.com/dhr2333/Beancount-Trans-Mobile/compare/1.1.0...1.2.0) (2026-09-27)

### Features

* **shared-ledger:** 实现完整的共享账本功能支持 ([d03562a](https://github.com/dhr2333/Beancount-Trans-Mobile/commit/d03562a18f9aef9f6a74cf283c4bbc9826638bd1))

## [1.1.0](https://github.com/dhr2333/Beancount-Trans-Mobile/compare/1.0.0...1.1.0) (2026-09-26)

### Features

* **app-badge:** 添加应用图标角标展示待办数量 ([fe99961](https://github.com/dhr2333/Beancount-Trans-Mobile/commit/fe99961e2603b1c1bae74221284f5d60780226cc))
* **assistant chat:** 为聊天页面添加可折叠的BQL查询区块 ([b9a7a0a](https://github.com/dhr2333/Beancount-Trans-Mobile/commit/b9a7a0a92161deb14c65e2de1f500f44030deec9))
* **assistant chat:** 优化助手页示例问句规范与分页展示 ([1fc25fb](https://github.com/dhr2333/Beancount-Trans-Mobile/commit/1fc25fb9188cdf9d8525ba7bf8726a1557baee0a))
* **assistant chat:** 添加账单上传解析至审核待办功能 ([36e4ad0](https://github.com/dhr2333/Beancount-Trans-Mobile/commit/36e4ad0ee9ec5301562721b3fcd04101dc3cb8e8))
* **assistant:** 为助手聊天页面添加 Markdown 渲染支持 ([60b0f30](https://github.com/dhr2333/Beancount-Trans-Mobile/commit/60b0f30d67240d4d69c08e6d51f25011b5a3546d))
* **fava_page:** 添加报表页面关闭退出按钮 ([df651d4](https://github.com/dhr2333/Beancount-Trans-Mobile/commit/df651d4e6d246ba94ce068661f747934c70d4356))
* **theme:** 新增主题切换功能与持久化外观偏好 ([b5e150c](https://github.com/dhr2333/Beancount-Trans-Mobile/commit/b5e150c6e795c59dbbafb9fbb06a8cc1bfafde5c))
* 支持Copilot记账条目展示与分组 ([cc6e6b7](https://github.com/dhr2333/Beancount-Trans-Mobile/commit/cc6e6b7d8bf1fcc93f862966c57ace13220eb6e9))

### Bug Fixes

* **assistant chat page:** 为助手聊天页面添加思考内容自动折叠功能 ([d87b7f8](https://github.com/dhr2333/Beancount-Trans-Mobile/commit/d87b7f81700bd400f1b1a9bddebdcb11bcaf5dfd))
* **assistant chat page:** 调整聊天气泡背景色减少突兀感 ([1a1e2fb](https://github.com/dhr2333/Beancount-Trans-Mobile/commit/1a1e2fb531b04fe82b49bc8be1f46eb23e2e24b2))
* **auth:** 实现JWT本地过期校验并完善会话管理流程 ([cedc7f9](https://github.com/dhr2333/Beancount-Trans-Mobile/commit/cedc7f930881e01e68a37c4b2793b330db24e1a6))
* **fava_page:** 修复移动端WebView明文连接拦截问题 ([5324bbc](https://github.com/dhr2333/Beancount-Trans-Mobile/commit/5324bbcdc59cef6d19311ef9aac39a6e0b1867ba))

## 1.0.0 (2026-09-18)

### Features

* **assistant, home:** 重构主架构，上线抽屉式Copilot首页与聚合待办 ([495bcad](https://github.com/dhr2333/Beancount-Trans-Mobile/commit/495bcad97a8c5d0d5ffba0b9804b5576661204ee))
* 初始化 Beancount-Trans Flutter 移动端项目 ([40f5fdb](https://github.com/dhr2333/Beancount-Trans-Mobile/commit/40f5fdb11e39224fe5f140246874d2521c5fa924))

### Bug Fixes

* **jenkinsfile:** 替换bash专用的source为POSIX标准的.以修复兼容性问题 ([c6c8f41](https://github.com/dhr2333/Beancount-Trans-Mobile/commit/c6c8f417716e1e256bcf95bdc46743895a8101fa))
