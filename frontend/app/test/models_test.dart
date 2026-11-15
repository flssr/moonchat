import 'package:flutter_test/flutter_test.dart';
import 'package:mondchat/api/models.dart';

void main() {
  test('本人资料按契约解析：gender 与生日可缺、可坏', () {
    final MyProfile full = MyProfile.fromJson(<String, dynamic>{
      'account_id': 1,
      'display_name': '阿月',
      'gender': 'female',
      'birthday': '1998-06-15',
    });
    expect(full.displayName, '阿月');
    expect(full.gender, 'female');
    expect(full.birthday, DateTime(1998, 6, 15));

    final MyProfile bare = MyProfile.fromJson(<String, dynamic>{
      'account_id': 1,
      'display_name': '阿月',
      'gender': null,
      'birthday': null,
    });
    expect(bare.gender, isNull);
    expect(bare.birthday, isNull);

    final MyProfile wrongType = MyProfile.fromJson(<String, dynamic>{
      'account_id': 1,
      'display_name': '阿月',
      'gender': 1,
    });
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
