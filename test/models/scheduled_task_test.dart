import 'package:beancount_trans/models/scheduled_task.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ScheduledTask.fromJson', () {
    test('完整字段解析', () {
      final task = ScheduledTask.fromJson(<String, Object?>{
        'id': 12,
        'task_type': 'reconciliation',
        'task_type_display': '对账',
        'scheduled_date': '2026-09-17',
        'completed_date': '2026-09-18',
        'status': 'completed',
        'status_display': '已完成',
        'account_name': 'Assets:Bank',
        'account_type': 'asset',
        'file_name': 'bill.csv',
        'file_id': 7,
        'review_expires_at': 1893456000,
        'entry_count': 5,
        'created': '2026-09-01T00:00:00Z',
        'modified': '2026-09-02T00:00:00Z',
      });

      expect(task.id, 12);
      expect(task.taskType, 'reconciliation');
      expect(task.taskTypeDisplay, '对账');
      expect(task.scheduledDate, '2026-09-17');
      expect(task.completedDate, '2026-09-18');
      expect(task.status, 'completed');
      expect(task.statusDisplay, '已完成');
      expect(task.accountName, 'Assets:Bank');
      expect(task.accountType, 'asset');
      expect(task.fileName, 'bill.csv');
      expect(task.fileId, 7);
      expect(task.reviewExpiresAt, 1893456000);
      expect(task.entryCount, 5);
      expect(task.created, '2026-09-01T00:00:00Z');
      expect(task.modified, '2026-09-02T00:00:00Z');
    });

    test('id 为字符串时解析为整数', () {
      final task = ScheduledTask.fromJson(<String, Object?>{'id': '12'});
      expect(task.id, 12);
    });

    test('entry_count 为 double 时取整', () {
      final task = ScheduledTask.fromJson(<String, Object?>{
        'id': 1,
        'entry_count': 7.0,
      });
      expect(task.entryCount, 7);

      final multiDigit = ScheduledTask.fromJson(<String, Object?>{
        'id': 1,
        'entry_count': 7.9,
      });
      expect(multiDigit.entryCount, 7);
    });

    test('review_expires_at 为 double 时取整', () {
      final task = ScheduledTask.fromJson(<String, Object?>{
        'id': 1,
        'review_expires_at': 1893456000.0,
      });
      expect(task.reviewExpiresAt, 1893456000);
    });

    test('缺失可选字段时使用默认值', () {
      final task = ScheduledTask.fromJson(<String, Object?>{'id': 1});

      expect(task.taskType, '');
      expect(task.taskTypeDisplay, '');
      expect(task.scheduledDate, isNull);
      expect(task.completedDate, isNull);
      expect(task.status, '');
      expect(task.statusDisplay, '');
      expect(task.accountName, isNull);
      expect(task.accountType, isNull);
      expect(task.fileName, isNull);
      expect(task.fileId, isNull);
      expect(task.reviewExpiresAt, isNull);
      expect(task.entryCount, isNull);
      expect(task.created, '');
      expect(task.modified, '');
    });

    test('空字符串的账户与文件字段归为 null', () {
      final task = ScheduledTask.fromJson(<String, Object?>{
        'id': 1,
        'account_name': '',
        'account_type': '',
        'file_name': '',
      });

      expect(task.accountName, isNull);
      expect(task.accountType, isNull);
      expect(task.fileName, isNull);
    });
  });

  group('ScheduledTask 状态判断', () {
    test('isPending 仅在 status = pending 时为 true', () {
      expect(
        ScheduledTask.fromJson(<String, Object?>{'id': 1, 'status': 'pending'})
            .isPending,
        isTrue,
      );
      expect(
        ScheduledTask.fromJson(<String, Object?>{'id': 1, 'status': 'completed'})
            .isPending,
        isFalse,
      );
      expect(
        ScheduledTask.fromJson(<String, Object?>{'id': 1}).isPending,
        isFalse,
      );
    });

    test('isCompleted 仅在 status = completed 时为 true', () {
      expect(
        ScheduledTask.fromJson(<String, Object?>{'id': 1, 'status': 'completed'})
            .isCompleted,
        isTrue,
      );
      expect(
        ScheduledTask.fromJson(<String, Object?>{'id': 1, 'status': 'pending'})
            .isCompleted,
        isFalse,
      );
      expect(
        ScheduledTask.fromJson(<String, Object?>{'id': 1}).isCompleted,
        isFalse,
      );
    });
  });

  group('ScheduledTask.isOverdue', () {
    test('pending 且计划日期在过去时为 true', () {
      final task = ScheduledTask.fromJson(<String, Object?>{
        'id': 1,
        'status': 'pending',
        'scheduled_date': '2000-01-01',
      });
      expect(task.isOverdue, isTrue);
    });

    test('completed 时即使计划日期在过去也为 false', () {
      final task = ScheduledTask.fromJson(<String, Object?>{
        'id': 1,
        'status': 'completed',
        'scheduled_date': '2000-01-01',
      });
      expect(task.isOverdue, isFalse);
    });

    test('计划日期在未来时为 false', () {
      final task = ScheduledTask.fromJson(<String, Object?>{
        'id': 1,
        'status': 'pending',
        'scheduled_date': '2099-01-01',
      });
      expect(task.isOverdue, isFalse);
    });

    test('scheduled_date 为 null 时为 false', () {
      final task = ScheduledTask.fromJson(<String, Object?>{
        'id': 1,
        'status': 'pending',
      });
      expect(task.isOverdue, isFalse);
    });
  });
}
