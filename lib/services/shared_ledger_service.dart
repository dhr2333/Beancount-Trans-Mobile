import '../core/api_client.dart';
import '../models/assistant.dart';

/// 共享账本服务，对应后端 `/api/assistant/shared-ledgers/`。
///
/// 只提供列表与添加；**不实现解绑**（移动端不提供解绑能力）。
class SharedLedgerService {
  SharedLedgerService._();

  static final SharedLedgerService instance = SharedLedgerService._();

  final ApiClient _client = ApiClient.instance;

  /// `GET /assistant/shared-ledgers/`。
  Future<List<SharedLedgerBinding>> list() async {
    final response = await _client.get<Object?>('/assistant/shared-ledgers/');
    final data = response.data;
    if (data is! List) return const [];
    return data
        .whereType<Map>()
        .map((e) => SharedLedgerBinding.fromJson(e.cast<String, Object?>()))
        .toList();
  }

  /// `POST /assistant/shared-ledgers/`，返回新建的绑定。
  Future<SharedLedgerBinding> bind({
    required String token,
    List<String> aliases = const [],
  }) async {
    final response = await _client.post<Object?>(
      '/assistant/shared-ledgers/',
      data: {'token': token, 'aliases': aliases},
    );
    final data = response.data;
    return data is Map
        ? SharedLedgerBinding.fromJson(data.cast<String, Object?>())
        : const SharedLedgerBinding();
  }
}
