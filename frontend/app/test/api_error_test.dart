import 'package:flutter_test/flutter_test.dart';
import 'package:mondchat/api/api_client.dart';
import 'package:mondchat/i18n/moon_strings.dart';
import 'package:mondchat/turms/realtime.dart';

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
      'invalid_password',
      'owner_cannot_delete_account',
      'projection_disabled',
      'rate_limited',
      'upstream_unavailable',
      'network',
    ];
    for (final String code in codes) {
      final String text = ApiException(code: code).displayText;
      expect(text, isNot('操作失败，请重试'), reason: '$code 没有专门文案');
      for (final String language in <String>['en', 'ja', 'de']) {
        expect(
          moonHasText(language, text),
          isTrue,
          reason: '$text 在 $language 缺翻译',
        );
      }
    }
  });

  test('Turms 直写错误码按 code 分流，文案四语言齐全', () {
    const List<int> codes = <int>[
      1101,
      1105,
      1106,
      1300,
      5000,
      5001,
      5002,
      5003,
      5004,
      5005,
      5006,
      5007,
      5008,
      5009,
      5010,
      5200,
      5201,
      5202,
      5204,
    ];
    for (final int code in codes) {
      final TurmsException error = TurmsException(turmsCode: code);
      expect(error.displayText, isNot('操作失败，请重试'), reason: '$code 没有专门文案');
      for (final String language in <String>['en', 'ja', 'de']) {
        expect(
          moonHasText(language, error.displayText),
          isTrue,
          reason: '${error.displayText} 在 $language 缺翻译',
        );
      }
    }
    expect(TurmsException(turmsCode: 1105).needsReconnect, isTrue);
    expect(TurmsException(turmsCode: 1300).needsReconnect, isTrue);
    expect(TurmsException(turmsCode: 1101).needsReconnect, isFalse);
  });
}
