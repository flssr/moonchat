import 'package:flutter_test/flutter_test.dart';
import 'package:moonchat/i18n/moon_strings.dart';

void main() {
  test('设置页与导航用到的文案在四种语言里都有', () {
    const List<String> keys = <String>[
      '消息',
      '联系人',
      '账号',
      '个人资料',
      '设置',
      '切到亮色',
      '切到暗色',
      '退出登录',
      '字体',
      '小',
      '中',
      '大',
      '语言',
      '隐私',
      '黑名单管理',
      '我的友情关系',
      '敬请期待',
      '待接入',
      '关闭',
    ];
    for (final String code in <String>['en', 'ja', 'de']) {
      for (final String key in keys) {
        expect(moonHasText(code, key), isTrue, reason: '$key 在 $code 缺翻译');
      }
    }
    expect(moonText('zh', '设置'), '设置');
  });
}
