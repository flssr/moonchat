import 'package:flutter_test/flutter_test.dart';
import 'package:mondchat/account_id.dart';

void main() {
  test('账号 id 折成从 1 起的短号', () {
    expect(shortAccountId(100000000), '1');
    expect(shortAccountId(100000001), '2');
    expect(shortAccountId(100000002), '3');
    // 短号区间外的 id（测试夹具）原样显示。
    expect(shortAccountId(1), '1');
  });

  test('短号与完整 id 都能解析，非法输入回 null', () {
    expect(accountIdFromInput('1'), 100000000);
    expect(accountIdFromInput('2'), 100000001);
    expect(accountIdFromInput(' 3 '), 100000002);
    expect(accountIdFromInput('100000001'), 100000001);
    expect(accountIdFromInput('0'), isNull);
    expect(accountIdFromInput('-1'), isNull);
    expect(accountIdFromInput('abc'), isNull);
  });
}
