import 'package:dio/dio.dart';

import '../core/api_client.dart';
import '../core/config.dart';
import '../models/parse_review.dart';

/// 账单上传解析服务，对应后端 `/api/translate/upload-parse`。
///
/// 上传的账单文件不会进入文件管理，解析结果直接并入解析审核待办
/// （确认写入时追加到 `trans/collect.bean`）。
class TranslateService {
  TranslateService._();

  static final TranslateService instance = TranslateService._();

  final ApiClient _client = ApiClient.instance;

  /// 上传账单并解析，成功后返回本次入队结果。
  ///
  /// [password] 用于加密的 zip / pdf，为空表示未加密。
  Future<UploadParseResult> uploadBillParse({
    required String filename,
    required List<int> bytes,
    String? password,
  }) async {
    final form = FormData.fromMap({
      'trans': MultipartFile.fromBytes(bytes, filename: filename),
      if (password != null && password.isNotEmpty) 'password': password,
    });
    final response = await _client.post<Object?>(
      '/translate/upload-parse',
      data: form,
      options: Options(
        sendTimeout: ApiConfig.uploadParseTimeout,
        receiveTimeout: ApiConfig.uploadParseTimeout,
      ),
    );
    final data = response.data;
    return data is Map
        ? UploadParseResult.fromJson(data.cast<String, Object?>())
        : UploadParseResult(fileName: filename);
  }
}
