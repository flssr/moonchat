import 'package:flutter_test/flutter_test.dart';
import 'package:mondchat/api/models.dart';

void main() {
  test('资料回显缺 gender 或类型不对不算成功', () {
    final UpdatedProfile missing = UpdatedProfile.fromJson(<String, dynamic>{
      'account_id': 1,
      'display_name': '阿月',
      'gender': null,
    });
    expect(missing.hasProfileFields, isFalse);

    final UpdatedProfile wrongType = UpdatedProfile.fromJson(<String, dynamic>{
      'account_id': 1,
      'display_name': '阿月',
      'gender': 1,
    });
    expect(wrongType.hasProfileFields, isFalse);
    expect(wrongType.gender, isNull);
    expect(wrongType.displayName, '阿月');
  });

  test('生日只取日历日，坏值不抛', () {
    final Account offset = Account.fromJson(<String, dynamic>{
      'account_id': 1,
      'type': 'human',
      'display_name': '阿月',
      'birthday': '2000-01-20T00:00:00+08:00',
    });
    expect(offset.birthday, DateTime(2000, 1, 20));

    final Account malformed = Account.fromJson(<String, dynamic>{
      'account_id': 1,
      'type': 'human',
      'display_name': '阿月',
      'birthday': 'not-a-date',
    });
    expect(malformed.birthday, isNull);
  });
}
