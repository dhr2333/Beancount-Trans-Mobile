import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

import '../core/config.dart';

/// 检查更新过程中的可展示错误。
class UpdateException implements Exception {
  const UpdateException(this.message);

  /// 可直接展示给用户的文案。
  final String message;

  @override
  String toString() => message;
}

/// 一次可用的更新信息。
class UpdateInfo {
  const UpdateInfo({
    required this.currentVersion,
    required this.latestVersion,
    required this.latestBuild,
    required this.notes,
    required this.apkUrl,
    required this.releaseUrl,
  });

  /// 当前安装版本展示文案（含构建号），如 `1.2.1 (51)`。
  final String currentVersion;

  /// 最新版本展示文案（含构建号），如 `1.2.1 (52)`。
  final String latestVersion;

  /// 最新版本的 versionCode（= 提交数），用于判断是否需要更新。
  final int latestBuild;

  /// Release 说明（Markdown 原文）。
  final String notes;

  /// APK 附件下载地址；Release 未附 APK 时为 null。
  final String? apkUrl;

  /// Release 页面地址（无法应用内安装时的兜底入口）。
  final String releaseUrl;

  /// 是否具备应用内安装条件（Android 且存在 APK 附件）。
  bool get canInstallInApp =>
      Platform.isAndroid && (apkUrl?.isNotEmpty ?? false);
}

/// 应用内更新：检测 GitHub Release 新版本、下载 APK 并调起系统安装。
///
/// 检测走 GitHub 公开 API（无需鉴权），失败一律抛出 [UpdateException]，
/// 由调用方决定是静默忽略（启动检查）还是提示用户（手动检查）。
class UpdateService {
  UpdateService._();

  static final UpdateService instance = UpdateService._();

  /// 用户点过「稍后」的版本号，仅用于抑制启动时的自动弹窗。
  static const String _kSkippedVersion = 'update_skipped_version';

  /// GitHub API 与业务 API 不同源，这里单独配置一个 Dio。
  final Dio _dio = Dio(
    BaseOptions(
      baseUrl: 'https://api.github.com',
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
      headers: const {
        'Accept': 'application/vnd.github+json',
        // GitHub API 要求请求带 User-Agent
        'User-Agent': 'Beancount-Trans-Mobile',
      },
    ),
  );

  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  /// 当前版本展示文案（含构建号），如 `1.2.1 (51)`；读取失败返回空串。
  Future<String> currentVersionLabel() async {
    final info = await _packageInfo();
    if (info == null) return '';
    return _label(info.version, int.tryParse(info.buildNumber) ?? 0);
  }

  /// 检测是否有新版本；已是最新时返回 null，失败时抛出 [UpdateException]。
  ///
  /// 读滚动构建 Release（每次 main 提交都会更新），按 versionCode 判断新旧。
  Future<UpdateInfo?> checkForUpdate() async {
    final package = await _packageInfo();
    if (package == null) {
      throw const UpdateException('无法读取当前版本号');
    }
    final currentBuild = int.tryParse(package.buildNumber) ?? 0;

    final release = await _fetchLatestRelease();
    final latestBuild = release.buildNumber;
    if (latestBuild == null) {
      throw const UpdateException('最新版本号格式异常');
    }
    if (latestBuild <= currentBuild) return null;

    return UpdateInfo(
      currentVersion: _label(package.version, currentBuild),
      latestVersion: _label(release.versionName, latestBuild),
      latestBuild: latestBuild,
      notes: release.notes,
      apkUrl: release.apkUrl,
      releaseUrl: release.releaseUrl,
    );
  }

  /// 版本展示文案：有构建号时拼成 `1.2.1 (51)`。
  static String _label(String version, int build) =>
      build > 0 ? '$version ($build)' : version;

  /// 读取用户选择忽略的版本号。
  Future<String?> skippedVersion() async {
    try {
      return await _storage.read(key: _kSkippedVersion);
    } catch (_) {
      return null;
    }
  }

  /// 记录用户选择忽略的构建号。
  Future<void> skipVersion(int build) async {
    try {
      await _storage.write(key: _kSkippedVersion, value: '$build');
    } catch (_) {
      // 写入失败只影响下次启动是否再弹窗
    }
  }

  /// [build] 是否已被忽略（含比忽略版本更旧的构建）。
  Future<bool> isVersionSkipped(int build) async {
    final skipped = int.tryParse(await skippedVersion() ?? '');
    return skipped != null && build <= skipped;
  }

  /// 下载 APK 到临时目录并返回文件；[onProgress] 回调 0..1 的进度。
  Future<File> downloadApk(
    UpdateInfo info, {
    void Function(double progress)? onProgress,
    CancelToken? cancelToken,
  }) async {
    final url = info.apkUrl;
    if (url == null || url.isEmpty) {
      throw const UpdateException('该版本未提供 APK 安装包');
    }
    final directory = await getTemporaryDirectory();
    final file = File(
      '${directory.path}/beancount-trans-${info.latestBuild}.apk',
    );
    // 重试时清掉上次的残留，避免沿用不完整文件
    if (await file.exists()) await file.delete();

    try {
      await _dio.download(
        url,
        file.path,
        cancelToken: cancelToken,
        onReceiveProgress: (received, total) {
          if (total > 0) onProgress?.call(received / total);
        },
      );
    } on DioException catch (error) {
      if (error.type == DioExceptionType.cancel) {
        throw const UpdateException('已取消下载');
      }
      throw const UpdateException('下载安装包失败，请检查网络后重试');
    }
    return file;
  }

  /// 调起系统安装器安装已下载的 APK（仅 Android 支持应用内安装）。
  Future<void> installApk(File file) async {
    if (!Platform.isAndroid) {
      throw const UpdateException('当前平台不支持应用内安装');
    }
    final result = await OpenFilex.open(
      file.path,
      type: 'application/vnd.android.package-archive',
    );
    switch (result.type) {
      case ResultType.done:
        return;
      case ResultType.permissionDenied:
        throw const UpdateException('请允许本应用「安装未知应用」后重试');
      case ResultType.fileNotFound:
        throw const UpdateException('安装包不存在，请重新下载');
      case ResultType.noAppToOpen:
      case ResultType.error:
        throw UpdateException('无法调起安装器：${result.message}');
    }
  }

  Future<PackageInfo?> _packageInfo() async {
    try {
      return await PackageInfo.fromPlatform();
    } catch (error) {
      debugPrint('读取当前版本失败：$error');
      return null;
    }
  }

  /// 拉取滚动构建 Release（固定 tag）并提取版本、说明与 APK 附件地址。
  ///
  /// 该 Release 由 CI 在每次 main 提交后更新，因此它始终是最新的可安装版本。
  Future<_Release> _fetchLatestRelease() async {
    final Response<Object?> response;
    try {
      response = await _dio.get<Object?>(
        '/repos/${ApiConfig.releaseRepo}/releases/tags/${ApiConfig.latestReleaseTag}',
      );
    } on DioException catch (error) {
      if (error.response?.statusCode == 404) {
        throw const UpdateException('暂无发布记录');
      }
      throw const UpdateException('检查更新失败，请检查网络后重试');
    }

    final data = response.data;
    if (data is! Map) {
      throw const UpdateException('版本信息格式异常');
    }
    return _Release.fromJson(data.cast<String, Object?>());
  }
}

/// GitHub Release 中与本功能相关的字段。
class _Release {
  const _Release({
    required this.versionName,
    required this.buildNumber,
    required this.notes,
    required this.apkUrl,
    required this.releaseUrl,
  });

  /// 版本名，如 `1.2.1`。
  final String versionName;

  /// 版本对应的 versionCode；附件名不符合约定时为 null。
  final int? buildNumber;

  final String notes;
  final String? apkUrl;
  final String releaseUrl;

  /// 与 CI 约定的附件名：`beancount-trans-<versionName>-<versionCode>.apk`。
  static final RegExp _assetPattern = RegExp(
    r'^beancount-trans-(.+)-(\d+)\.apk$',
  );

  factory _Release.fromJson(Map<String, Object?> json) {
    final tag = (json['tag_name'] as String? ?? '').trim();
    final apk = _findApk(json['assets']);
    final matched = apk == null ? null : _assetPattern.firstMatch(apk.name);
    return _Release(
      versionName: matched?.group(1) ?? tag,
      buildNumber: matched == null ? null : int.tryParse(matched.group(2)!),
      notes: (json['body'] as String? ?? '').trim(),
      apkUrl: apk?.url,
      releaseUrl: (json['html_url'] as String? ?? '').trim(),
    );
  }

  /// 取第一个 `.apk` 附件的名称与下载地址。
  static _Asset? _findApk(Object? assets) {
    if (assets is! List) return null;
    for (final asset in assets) {
      if (asset is! Map) continue;
      final name = (asset['name'] as String? ?? '').trim();
      final url = (asset['browser_download_url'] as String? ?? '').trim();
      if (name.toLowerCase().endsWith('.apk') && url.isNotEmpty) {
        return _Asset(name: name, url: url);
      }
    }
    return null;
  }
}

/// Release 中的 APK 附件：名称 + 下载地址。
class _Asset {
  const _Asset({required this.name, required this.url});

  final String name;
  final String url;
}
