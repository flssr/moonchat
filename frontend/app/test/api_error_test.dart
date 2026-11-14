import 'package:flutter_test/flutter_test.dart';
import 'package:mondchat/api/api_client.dart';
import 'package:mondchat/i18n/moon_strings.dart';

void main() {
  test('后端每条错误码都有专门文案，且四语言齐全', () {
    // 与 `ApiException` 里的 code 全集对齐（docs/api-contracts.md §1.3、§7）。
    // 后端加了码而前端不映射时，这里会红——避免界面把它显示成笼统的「操作失败」。
    const List<String> codes = <String>[
      'validation_failed',
      'unauthenticated',
      'forbidden',
      'account_frozen',
      'not_friend',
      'blocked',
      'blocklist_full',
      'not_room_member',
      'not_found',
      'conflict',
      'owner_cannot_leave',
      'rate_limited',
      'upstream_unavailable',
      'network',
    ];
    for (final String code in codes) {
      final String text = ApiException(code: code).displayText;
      expect(text, isNot('操作失败，请重试'), reason: '$code 没有专门文案');
      for (final String language in <String>['en', 'ja', 'de']) {
        expect(moonHasText(language, text), isTrue, reason: '$text 在 $language 缺翻译');
      }
    }
  });
}
