/*
 * Beancount-Trans-Mobile 多分支流水线（Jenkins Multibranch Pipeline）
 *
 * 流水线目标：
 *   依次完成「共享工具链准备 → 依赖安装 → 静态分析 → 单元测试 → 正式签名注入 →
 *   release APK 构建与归档」，并在 main 分支额外执行语义化发布
 *   （semantic-release 依据 conventional commits 计算版本号、打 tag、创建 GitHub Release，
 *    并把以发布版本号重新构建的已签名 APK 作为 Release 附件上传）。
 *
 * 分支策略：
 *   非 main 分支只做校验与构建（不发布、不打 tag）；
 *   main 分支在前述校验与构建之外额外执行语义化发布。
 *
 * 关于 main 分支会构建两次 APK（有意为之，非重复劳动）：
 *   1) 第 7 阶段「构建 release APK」以 Jenkins 构建号作为 versionCode，产物归档到 Jenkins，
 *      用于每次提交的冒烟校验与人工下载，且保证任意分支都有统一的构建产物可用；
 *   2) 第 8 阶段 semantic-release 的 prepare 阶段会调用 ci/release_android.sh，
 *      按 semantic-release 计算出的发布版本号（versionCode = major*10000 + minor*100 + patch）
 *      重新构建一次已签名 APK，并由 publish 阶段作为 GitHub Release 附件上传。
 *   两次构建的版本号语义不同（构建号 vs 发布版本号），故刻意保留两次构建，不做产物复用。
 *
 * 注意：本仓库不涉及 Docker 镜像构建与服务器 SSH 部署，所有 flutter/gradle 命令
 *       都先 source 共享工具链目录（TOOLCHAIN_ROOT）下的 env.sh，复用仓库外的缓存与 SDK。
 */

pipeline {
    agent any

    tools {
        nodejs 'NodeJS 25.1.0'
    }

    options {
        timeout(time: 60, unit: 'MINUTES')
        buildDiscarder(logRotator(numToKeepStr: '5'))
    }

    environment {
        // 共享工具链目录（仓库外，由 ci/setup_toolchain.sh 幂等准备）
        TOOLCHAIN_ROOT = '/jenkins-share/mobile-toolchain'
        FLUTTER_VERSION = '3.47.4'

        // GitHub 配置
        GITHUB_REPO = 'dhr2333/Beancount-Trans-Mobile'
        GITHUB_API_URL = 'https://api.github.com'
        // 沿用现有 GitHub Token 凭据
        GITHUB_CREDENTIALS_ID = '1b709f07-d907-4000-8a8a-2adafa6fc658'

        // Android 签名凭据（Secret file：jks 文件与 key.properties）
        KEYSTORE_CREDENTIALS_ID = 'mobile-android-keystore'
        KEYPROPERTIES_CREDENTIALS_ID = 'mobile-android-keyproperties'

        // release APK 产物路径
        APK_PATH = 'build/app/outputs/flutter-apk/app-release.apk'
    }

    stages {
        stage('初始化') {
            steps {
                script {
                    echo "🚀 开始构建 Beancount-Trans-Mobile 项目"
                    echo "分支: ${env.BRANCH_NAME}"

                    env.GIT_COMMIT_SHORT = sh(
                        script: 'git rev-parse --short HEAD',
                        returnStdout: true
                    ).trim()

                    echo "Git Commit短哈希: ${env.GIT_COMMIT_SHORT}"
                    echo "工作目录: ${env.WORKSPACE}"

                    updateGitHubStatus('pending', '开始构建...')
                }
            }
        }

        stage('准备工具链') {
            steps {
                sh "TOOLCHAIN_ROOT=${env.TOOLCHAIN_ROOT} FLUTTER_VERSION=${env.FLUTTER_VERSION} bash ci/setup_toolchain.sh"
            }
        }

        stage('安装依赖') {
            steps {
                // 用 POSIX 的 '.' 而不是 bash 专有的 'source'：Jenkins 的 sh 步骤在
                // Debian/Ubuntu 系下是 /bin/sh（dash），不认识 source
                sh ". ${env.TOOLCHAIN_ROOT}/env.sh && flutter pub get"
            }
        }

        stage('静态分析') {
            steps {
                script {
                    echo "🔍 运行 flutter analyze（warning / info 不阻断，仅 error 阻断）..."
                    sh ". ${env.TOOLCHAIN_ROOT}/env.sh && flutter analyze --no-fatal-infos --no-fatal-warnings"
                }
            }
        }

        stage('单元测试') {
            steps {
                script {
                    echo "🧪 运行单元测试（门禁：存在失败用例即中断流水线）..."
                    sh ". ${env.TOOLCHAIN_ROOT}/env.sh && flutter test"

                    // 以下为 best effort 的 JUnit 报告生成与发布：
                    // 门禁已在上一步完成，这里任何环节失败都只打印警告，不影响构建结论
                    try {
                        echo "📊 生成并发布 JUnit 测试报告..."
                        sh ". ${env.TOOLCHAIN_ROOT}/env.sh && dart pub global activate junitreport"
                        sh 'mkdir -p reports'
                        sh ". ${env.TOOLCHAIN_ROOT}/env.sh && flutter test --machine > reports/test-report.json"
                        // env.sh 未把 pub 全局 bin（$PUB_CACHE/bin，tojunit 安装于此）加入 PATH，这里显式补上
                        sh ". ${env.TOOLCHAIN_ROOT}/env.sh && export PATH=\"\$PUB_CACHE/bin:\$PATH\" && tojunit --output reports/junit.xml < reports/test-report.json"
                        junit allowEmptyResults: true, testResults: 'reports/junit.xml'
                    } catch (Exception e) {
                        echo "⚠️ JUnit 测试报告生成/发布失败，已忽略（不影响构建结论）: ${e.message}"
                    }
                }
            }
        }

        stage('配置签名') {
            steps {
                withCredentials([
                    file(credentialsId: env.KEYSTORE_CREDENTIALS_ID, variable: 'ANDROID_KEYSTORE'),
                    file(credentialsId: env.KEYPROPERTIES_CREDENTIALS_ID, variable: 'ANDROID_KEYPROPERTIES')
                ]) {
                    // 两个目标路径均已被 .gitignore 忽略（*.jks 与 android/key.properties）
                    sh '''
                        cp "$ANDROID_KEYSTORE" android/app/release.jks
                        cp "$ANDROID_KEYPROPERTIES" android/key.properties
                        chmod 600 android/app/release.jks android/key.properties
                        echo "已注入 release 签名文件: android/app/release.jks, android/key.properties"
                    '''
                }
            }
        }

        stage('构建 release APK') {
            steps {
                script {
                    echo "📦 构建 release APK（versionCode = Jenkins 构建号 ${env.BUILD_NUMBER}）..."
                    sh ". ${env.TOOLCHAIN_ROOT}/env.sh && flutter build apk --release --build-number=${env.BUILD_NUMBER}"
                    archiveArtifacts artifacts: 'build/app/outputs/flutter-apk/app-release.apk', fingerprint: true
                    sh "ls -lh ${env.APK_PATH}"
                }
            }
        }

        stage('语义化发布') {
            when {
                branch 'main'
            }
            steps {
                script {
                    echo "📝 运行 semantic-release，生成版本号、tag 与 GitHub Release..."

                    // 记录发布前 pubspec.yaml 中的版本，用于判断本次是否真的产生了新发布
                    def versionBefore = sh(
                        script: "sed -n 's/^version: *//p' pubspec.yaml | head -1",
                        returnStdout: true
                    ).trim()

                    withCredentials([string(credentialsId: env.GITHUB_CREDENTIALS_ID, variable: 'GITHUB_TOKEN')]) {
                        // @semantic-release/git 需要提交身份
                        sh '''
                            git config user.name "Beancount-Trans CI"
                            git config user.email "ci@beancount-trans.local"
                        '''
                        sh ". ${env.TOOLCHAIN_ROOT}/env.sh && npm ci --no-audit --no-fund"
                        sh ". ${env.TOOLCHAIN_ROOT}/env.sh && npm run semantic-release"
                    }

                    // npm run semantic-release 即 semantic-release --config release.config.mjs：
                    // prepare 阶段调用 ci/release_android.sh 按发布版本号回写 pubspec.yaml 并重新构建已签名 APK
                    def versionAfter = sh(
                        script: "sed -n 's/^version: *//p' pubspec.yaml | head -1",
                        returnStdout: true
                    ).trim()

                    if (versionAfter && versionAfter != versionBefore) {
                        env.RELEASE_VERSION = versionAfter.split('\\+')[0]
                        echo "🎉 本次已发布版本: ${env.RELEASE_VERSION}"
                    } else {
                        echo "ℹ️ 本次没有可发布提交，未产生新版本"
                    }
                }
            }
        }
    }

    post {
        success {
            script {
                echo '✅ 构建成功'
                def isMainBranch = env.BRANCH_NAME == 'main'
                def branchInfo = isMainBranch ? 'main 分支' : "分支 ${env.BRANCH_NAME}"
                def releaseInfo = env.RELEASE_VERSION ? "已发布 v${env.RELEASE_VERSION}" : '未发布'
                updateGitHubStatus('success', "构建成功 ✓ | ${branchInfo} | ${releaseInfo}")

                if (env.RELEASE_VERSION) {
                    echo "🎉 已发布版本: v${env.RELEASE_VERSION}"
                }
                echo "📦 APK 归档路径: ${env.APK_PATH}"
            }
        }

        failure {
            script {
                echo '❌ 构建失败'
                updateGitHubStatus('failure', '构建或测试失败')
            }
        }

        always {
            cleanWs()
        }
    }
}

// 更新GitHub提交状态的函数
def updateGitHubStatus(String state, String description) {
    // 获取当前commit SHA，优先使用环境变量，缺失时回退到 git 命令
    def commitSha = env.GIT_COMMIT

    if (!commitSha) {
        try {
            commitSha = sh(script: 'git rev-parse HEAD', returnStdout: true).trim()
        } catch (Exception e) {
            echo "无法获取Git commit SHA: ${e.message}"
            return
        }
    }

    // 构建Jenkins构建URL
    def targetUrl = "${env.BUILD_URL}"

    // GitHub状态API payload
    def payload = """
    {
        "state": "${state}",
        "target_url": "${targetUrl}",
        "description": "${description}",
        "context": "continuous-integration/jenkins/mobile/${env.BRANCH_NAME}"
    }
    """

    // 使用GitHub Token更新状态，失败只告警不影响构建结论
    try {
        withCredentials([string(credentialsId: env.GITHUB_CREDENTIALS_ID, variable: 'GITHUB_TOKEN')]) {
            sh """
                curl -X POST \
                    -H "Authorization: token \${GITHUB_TOKEN}" \
                    -H "Accept: application/vnd.github.v3+json" \
                    ${env.GITHUB_API_URL}/repos/${env.GITHUB_REPO}/statuses/${commitSha} \
                    -d '${payload}'
            """
        }
        echo "GitHub状态已更新: ${state} - ${description}"
    } catch (Exception e) {
        echo "更新GitHub状态失败: ${e.message}"
    }
}
