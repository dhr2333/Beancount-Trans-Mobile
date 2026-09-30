#!/usr/bin/env node
//
// 把一次 main 构建的 APK 发布到固定 tag 的「滚动 Release」，供应用内更新即时感知。
//
// 契约（与 lib/services/update_service.dart 一一对应，改这里必须同步改那边）：
//   1. Release tag 固定为 latest，且 prerelease = true —— 不污染 GitHub
//      /releases/latest（正式版本）语义，正式 Release 仍由 semantic-release 产出；
//   2. 资产名固定为 beancount-trans-<versionName>-<versionCode>.apk，
//      App 用正则 ^beancount-trans-(.+)-(\d+)\.apk$ 同时取出 versionName 与构建号；
//   3. Release 的 name / body 只供人阅读，App 不解析，可以随时调整文案。
//
// 用法：
//   GITHUB_TOKEN=xxx node ci/publish_latest_release.mjs \
//     --apk build/app/outputs/flutter-apk/app-release.apk \
//     --version-name 1.2.1 --version-code 51
//
//   # 本地核对（不触网、不需要 token）
//   node ci/publish_latest_release.mjs --apk /tmp/fake.apk \
//     --version-name 1.2.1 --version-code 51 --dry-run
//
// 环境变量：GITHUB_TOKEN（非 dry-run 必填）、GITHUB_REPO、LATEST_TAG。
// 依赖：Node >= 18 的全局 fetch。刻意不引入 npm 依赖，也不依赖 jq / python3。
import { execFileSync } from 'node:child_process';
import { existsSync, readFileSync, statSync } from 'node:fs';

const API = 'https://api.github.com';
const UPLOADS = 'https://uploads.github.com';
const DEFAULT_REPO = 'dhr2333/Beancount-Trans-Mobile';
const DEFAULT_TAG = 'latest';
const APK_CONTENT_TYPE = 'application/vnd.android.package-archive';

/** 与 App 端约定的资产名格式。 */
const ASSET_PATTERN = /^beancount-trans-(.+)-(\d+)\.apk$/;

function fail(message) {
  console.error(`错误：${message}`);
  process.exit(1);
}

function parseArgs(argv) {
  const options = { apk: '', versionName: '', versionCode: '', dryRun: false };
  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    switch (arg) {
      case '--apk':
        options.apk = argv[++i] ?? '';
        break;
      case '--version-name':
        options.versionName = argv[++i] ?? '';
        break;
      case '--version-code':
        options.versionCode = argv[++i] ?? '';
        break;
      case '--dry-run':
        options.dryRun = true;
        break;
      case '--help':
      case '-h':
        console.log(
          '用法：node ci/publish_latest_release.mjs --apk <path> ' +
            '--version-name <x.y.z> --version-code <int> [--dry-run]',
        );
        process.exit(0);
        break;
      default:
        fail(`无法识别的参数 ${arg}`);
    }
  }
  return options;
}

function git(args) {
  try {
    return execFileSync('git', args, { encoding: 'utf8' }).trim();
  } catch {
    return '';
  }
}

/** 发一个 GitHub API 请求；不抛异常，由调用方按状态码判断。 */
async function request(url, { token, method = 'GET', body }) {
  const headers = {
    Authorization: `Bearer ${token}`,
    Accept: 'application/vnd.github+json',
    'X-GitHub-Api-Version': '2022-11-28',
    'User-Agent': 'beancount-trans-ci',
  };
  let payload;
  if (body !== undefined) {
    headers['Content-Type'] = 'application/json';
    payload = JSON.stringify(body);
  }
  let response;
  try {
    response = await fetch(url, { method, headers, body: payload });
  } catch (error) {
    fail(`请求 ${method} ${url} 失败：${error.message}`);
  }
  const text = await response.text();
  let data = null;
  if (text) {
    try {
      data = JSON.parse(text);
    } catch {
      data = null;
    }
  }
  return { response, data, text };
}

/** 状态码非 2xx 时直接终止（让流水线失败，避免静默漏发）。 */
function ensureOk(result, what) {
  if (!result.response.ok) {
    fail(`${what}（HTTP ${result.response.status}）：${result.text.slice(0, 500)}`);
  }
}

async function main() {
  const { apk, versionName, versionCode, dryRun } = parseArgs(process.argv.slice(2));
  if (!apk) fail('缺少 --apk');
  if (!/^\d+\.\d+\.\d+$/.test(versionName)) {
    fail(`--version-name 非法：${versionName}（应为 x.y.z）`);
  }
  const build = Number(versionCode);
  if (!Number.isInteger(build) || build <= 0) {
    fail(`--version-code 非法：${versionCode}（应为正整数）`);
  }
  if (!existsSync(apk)) fail(`APK 不存在：${apk}`);

  const assetName = `beancount-trans-${versionName}-${build}.apk`;
  // 守住与 App 端的资产名契约：改名即等于 App 认不出更新
  if (!ASSET_PATTERN.test(assetName)) fail(`资产名 ${assetName} 不符合与 App 的约定`);

  const repo = (process.env.GITHUB_REPO ?? '').trim() || DEFAULT_REPO;
  const tag = (process.env.LATEST_TAG ?? '').trim() || DEFAULT_TAG;
  const sha = git(['rev-parse', 'HEAD']);
  const shortSha = git(['rev-parse', '--short', 'HEAD']) || 'unknown';
  const subject = git(['log', '-1', '--pretty=%s']);
  const size = statSync(apk).size;
  const name = `滚动构建 ${versionName} (${build})`;
  const body = [
    `滚动构建：${versionName}（构建 ${build}）`,
    '',
    `提交 ${shortSha} ${subject}`,
    new Date().toISOString(),
    '',
    '本通道随 main 每次提交更新，用于应用内自动更新；正式版本见带版本号的 Release。',
  ].join('\n');

  if (dryRun) {
    console.log('[dry-run] 仓库：%s', repo);
    console.log('[dry-run] tag：%s（prerelease = true）', tag);
    console.log('[dry-run] APK：%s（%d 字节）', apk, size);
    console.log('[dry-run] 资产名：%s', assetName);
    console.log('[dry-run] Release name：%s', name);
    console.log('[dry-run] Release body：\n%s', body);
    return;
  }

  const token = (process.env.GITHUB_TOKEN ?? '').trim();
  if (!token) fail('缺少 GITHUB_TOKEN 环境变量');

  // 1) 取或建固定 tag 的 Release（幂等：已存在则更新文案）
  const found = await request(`${API}/repos/${repo}/releases/tags/${tag}`, { token });
  let release;
  if (found.response.status === 404) {
    const created = await request(`${API}/repos/${repo}/releases`, {
      token,
      method: 'POST',
      body: {
        tag_name: tag,
        // 仓库不在 git 工作区时回退到默认分支，保证创建动作仍能成功
        target_commitish: sha || undefined,
        name,
        body,
        prerelease: true,
      },
    });
    ensureOk(created, '创建滚动 Release 失败');
    release = created.data;
    console.log('已创建滚动 Release：%s', release.html_url);
  } else {
    ensureOk(found, '读取滚动 Release 失败');
    const updated = await request(`${API}/repos/${repo}/releases/${found.data.id}`, {
      token,
      method: 'PATCH',
      body: { name, body, prerelease: true },
    });
    ensureOk(updated, '更新滚动 Release 失败');
    release = updated.data;
    console.log('已更新滚动 Release：%s', release.html_url);
  }

  // 2) 先删掉旧的 apk 资产：GitHub 没有资产覆盖接口，同名上传会返回 422
  const assets = await request(
    `${API}/repos/${repo}/releases/${release.id}/assets?per_page=100`,
    { token },
  );
  ensureOk(assets, '读取滚动 Release 资产失败');
  for (const asset of assets.data ?? []) {
    if (!String(asset.name ?? '').toLowerCase().endsWith('.apk')) continue;
    const removed = await request(`${API}/repos/${repo}/releases/assets/${asset.id}`, {
      token,
      method: 'DELETE',
    });
    if (!removed.response.ok) {
      fail(`删除旧资产 ${asset.name} 失败（HTTP ${removed.response.status}）`);
    }
    console.log('已删除旧资产：%s', asset.name);
  }

  // 3) 上传本次 APK
  let uploaded;
  try {
    uploaded = await fetch(
      `${UPLOADS}/repos/${repo}/releases/${release.id}/assets?name=${encodeURIComponent(assetName)}`,
      {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${token}`,
          Accept: 'application/vnd.github+json',
          'X-GitHub-Api-Version': '2022-11-28',
          'User-Agent': 'beancount-trans-ci',
          'Content-Type': APK_CONTENT_TYPE,
        },
        body: readFileSync(apk),
      },
    );
  } catch (error) {
    fail(`上传 APK 失败：${error.message}`);
  }
  if (!uploaded.ok) {
    fail(`上传 APK 失败（HTTP ${uploaded.status}）：${(await uploaded.text()).slice(0, 500)}`);
  }
  const asset = await uploaded.json();
  console.log('已上传资产：%s（%d 字节）', asset.name, asset.size ?? size);
  console.log('下载地址：%s', asset.browser_download_url);
  console.log('应用内更新将看到：最新 %s（构建 %d）', versionName, build);
}

main().catch((error) => fail(error.stack ?? String(error)));
