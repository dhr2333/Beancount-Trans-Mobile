import 'package:beancount_trans/models/parse_review.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('UploadParseResult.fromJson', () {
    test('完整字段解析', () {
      final result = UploadParseResult.fromJson(<String, Object?>{
        'file_name': '账单.csv',
        'entry_count': 3,
        'duplicate_count': 1,
        'pending_total': 5,
        'entry_review_task_id': 9,
      });

      expect(result.fileName, '账单.csv');
      expect(result.entryCount, 3);
      expect(result.duplicateCount, 1);
      expect(result.pendingTotal, 5);
      expect(result.entryReviewTaskId, 9);
      expect(result.hasEntries, isTrue);
    });

    test('缺省字段回退为零值', () {
      final result = UploadParseResult.fromJson(const <String, Object?>{});

      expect(result.fileName, '');
      expect(result.entryCount, 0);
      expect(result.duplicateCount, 0);
      expect(result.pendingTotal, 0);
      expect(result.entryReviewTaskId, isNull);
      expect(result.hasEntries, isFalse);
    });
  });
}
