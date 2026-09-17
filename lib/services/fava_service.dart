import 'dart:convert';

import 'package:dio/dio.dart';

import '../core/api_client.dart';
import '../core/api_exception.dart';
import '../core/config.dart';

/// Fava 服务：解析实例地址与停止实例。
///
/// `GET /api/fava/` 在 `dynamic` 模式返回 302 + `Location: /{uuid}/`，
/// 在 `static` 模式返回 200 + `{url, deploy_mode}`。**必须禁止自动跟随重定向**。
class FavaService {
  FavaService._();

  static final FavaService instance = FavaService._();

  final ApiClient _client = ApiClient.instance;

  static final RegExp _uuidPattern = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
    caseSensitive: false,
  );

  /// 解析 Fava 访问前缀（绝对地址，不含末尾斜杠）。
  Future<String> resolveFavaUrl() async {
    final Response<Object?> response;
    try {
      response = await _client.dio.get<Object?>(
        '/fava/',
        options: Options(
          responseType: ResponseType.plain,
          followRedirects: false,
          validateStatus: (_) => true,
        ),
      );
    } on DioException catch (error) {
      throw _client.toApiException(error);
    }

    final status = response.statusCode ?? 0;
    if (status == 301 || status == 302 || status == 303 || status == 307) {
      final location = response.headers.value('location');
      final resolved = _absolute(location);
      if (resolved != null) return resolved;
      throw ApiException(message: 'Fava 重定向地址异常');
    }

    if (status == 200) {
      final raw = response.data;
      if (raw is String && raw.trim().isNotEmpty) {
        try {
          final decoded = jsonDecode(raw);
          if (decoded is Map) {
            final url = decoded['url'];
            if (url is String && url.isNotEmpty) {
              return _stripTrailingSlash(url);
            }
          }
        } catch (_) {
          // 非 JSON 响应，继续走错误分支
        }
      }
      throw ApiException(message: 'Fava 未返回可用地址');
    }

    if (status == 404) {
      throw ApiException(
        statusCode: status,
        message: '未配置 Fava 入口，请联系管理员',
      );
    }

    throw ApiException.fromResponse(status, response.data, fallback: '打开 Fava 失败');
  }

  /// 停止当前用户的 Fava 实例（退出登录时调用）。
  Future<void> stopFava() async {
    await _client.post<Object?>('/fava/stop/');
  }

  /// 拼接 Fava 深链：`prefix` + 相对路径。
  static String join(String prefix, String relativePath) {
    final normalizedPrefix = prefix.replaceAll(RegExp(r'/+$'), '');
    final normalizedPath = relativePath.replaceAll(RegExp(r'^/+'), '');
    if (normalizedPath.isEmpty) return normalizedPrefix;
    return '$normalizedPrefix/$normalizedPath';
  }

  String? _absolute(String? location) {
    if (location == null || location.trim().isEmpty) return null;
    final trimmed = location.trim();
    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      return _stripTrailingSlash(trimmed);
    }
    final uri = Uri.tryParse(trimmed);
    if (uri == null) return null;
    final segments = uri.pathSegments;
    if (segments.isNotEmpty && _uuidPattern.hasMatch(segments.first)) {
      return '${ApiConfig.apiOrigin}/${segments.first}';
    }
    // 非 uuid 前缀时，原样用完整 path（去掉末尾斜杠）
    return _stripTrailingSlash('${ApiConfig.apiOrigin}${uri.path}');
  }

  String _stripTrailingSlash(String url) {
    var value = url.trim();
    if (!value.startsWith('http://') && !value.startsWith('https://')) {
      value = '${ApiConfig.apiOrigin}$value';
    }
    return value.replaceAll(RegExp(r'/+$'), '');
  }
}
