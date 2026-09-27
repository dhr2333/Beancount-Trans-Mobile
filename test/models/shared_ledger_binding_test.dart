import 'package:beancount_trans/models/assistant.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SharedLedgerBinding.fromJson', () {
    test('完整字段解析', () {
      final binding = SharedLedgerBinding.fromJson(<String, Object?>{
        'id': 3,
        'owner_username': 'alice',
        'aliases': ['老婆的账本', '老婆'],
        'usable': true,
        'expires_at': '2026-12-31T00:00:00Z',
        'last_used_at': '2026-09-20T08:00:00Z',
        'created': '2026-09-01T00:00:00Z',
      });

      expect(binding.id, 3);
      expect(binding.ownerUsername, 'alice');
      expect(binding.aliases, ['老婆的账本', '老婆']);
      expect(binding.usable, isTrue);
      expect(binding.expiresAt, '2026-12-31T00:00:00Z');
      expect(binding.lastUsedAt, '2026-09-20T08:00:00Z');
      expect(binding.created, '2026-09-01T00:00:00Z');
    });

    test('id 为数字字符串时解析为整数', () {
      final binding = SharedLedgerBinding.fromJson(<String, Object?>{
        'id': '12',
      });
      expect(binding.id, 12);
    });

    test('id 缺失或非数字时为 0', () {
      expect(SharedLedgerBinding.fromJson(const <String, Object?>{}).id, 0);
      expect(
        SharedLedgerBinding.fromJson(<String, Object?>{'id': 'abc'}).id,
        0,
      );
    });

    test('aliases 缺失或为 null 时为空列表', () {
      expect(
        SharedLedgerBinding.fromJson(const <String, Object?>{}).aliases,
        isEmpty,
      );
      expect(
        SharedLedgerBinding.fromJson(<String, Object?>{
          'aliases': null,
        }).aliases,
        isEmpty,
      );
    });

    test('aliases 含非字符串项时被过滤', () {
      final binding = SharedLedgerBinding.fromJson(<String, Object?>{
        'aliases': ['老婆', 1, true, '老婆的账本'],
      });
      expect(binding.aliases, ['老婆', '老婆的账本']);
    });

    test('aliases 为纯非字符串列表时为空', () {
      final binding = SharedLedgerBinding.fromJson(<String, Object?>{
        'aliases': [1, 2, 3],
      });
      expect(binding.aliases, isEmpty);
    });

    test('时间字段为 null 时为空串', () {
      final binding = SharedLedgerBinding.fromJson(<String, Object?>{
        'expires_at': null,
        'last_used_at': null,
        'created': null,
      });
      expect(binding.expiresAt, '');
      expect(binding.lastUsedAt, '');
      expect(binding.created, '');
    });

    test('usable 缺失时为 false', () {
      expect(
        SharedLedgerBinding.fromJson(const <String, Object?>{}).usable,
        isFalse,
      );
    });
  });

  group('SharedLedgerBinding 展示字段', () {
    test('displayName 优先取第一个别名', () {
      final binding = SharedLedgerBinding.fromJson(<String, Object?>{
        'owner_username': 'alice',
        'aliases': ['老婆的账本', '老婆'],
      });
      expect(binding.displayName, '老婆的账本');
    });

    test('displayName 无别名时回退为来源用户名', () {
      final binding = SharedLedgerBinding.fromJson(<String, Object?>{
        'owner_username': 'alice',
      });
      expect(binding.displayName, 'alice');
    });

    test('aliasesLabel 无别名时为占位符', () {
      final binding = SharedLedgerBinding.fromJson(const <String, Object?>{});
      expect(binding.aliasesLabel, '—');
    });

    test('aliasesLabel 用顿号连接', () {
      final binding = SharedLedgerBinding.fromJson(<String, Object?>{
        'aliases': ['老婆', '老婆的账本'],
      });
      expect(binding.aliasesLabel, '老婆、老婆的账本');
    });
  });

  group('AssistantStatus.canChat', () {
    AssistantStatus status({
      required bool apiKey,
      required bool ledger,
      required bool shared,
    }) => AssistantStatus.fromJson(<String, Object?>{
      'api_key_configured': apiKey,
      'ledger_exists': ledger,
      'has_usable_shared_ledger': shared,
    });

    test('读取 has_usable_shared_ledger', () {
      expect(
        status(apiKey: false, ledger: false, shared: true)
            .hasUsableSharedLedger,
        isTrue,
      );
      expect(
        status(apiKey: false, ledger: false, shared: false)
            .hasUsableSharedLedger,
        isFalse,
      );
    });

    test('apiKey 已配置且本人有账本时可对话', () {
      expect(status(apiKey: true, ledger: true, shared: false).canChat, isTrue);
    });

    test('apiKey 已配置、本人无账本但有共享账本时可对话', () {
      expect(status(apiKey: true, ledger: false, shared: true).canChat, isTrue);
    });

    test('apiKey 已配置但无任何账本时不可对话', () {
      expect(
        status(apiKey: true, ledger: false, shared: false).canChat,
        isFalse,
      );
    });

    test('未配置 apiKey 时即使有共享账本也不可对话', () {
      expect(
        status(apiKey: false, ledger: true, shared: true).canChat,
        isFalse,
      );
      expect(
        status(apiKey: false, ledger: false, shared: true).canChat,
        isFalse,
      );
    });
  });

  group('QueryRecord.ledger', () {
    test('fromJson 读取 ledger', () {
      final record = QueryRecord.fromJson(<String, Object?>{
        'bql': 'SELECT 1',
        'result_preview': 'ok',
        'ledger': '老婆的账本',
      });
      expect(record.ledger, '老婆的账本');
    });

    test('fromJson 缺失 ledger 时为空串', () {
      final record = QueryRecord.fromJson(const <String, Object?>{
        'bql': 'SELECT 1',
      });
      expect(record.ledger, '');
    });

    test('toJson 非空时输出 ledger', () {
      const record = QueryRecord(bql: 'q', resultPreview: 'r', ledger: '老婆');
      expect(record.toJson()['ledger'], '老婆');
    });

    test('toJson 空 ledger 时不输出', () {
      const record = QueryRecord(bql: 'q', resultPreview: 'r');
      expect(record.toJson().containsKey('ledger'), isFalse);
    });
  });
}
