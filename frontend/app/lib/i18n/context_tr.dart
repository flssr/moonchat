import 'package:flutter/widgets.dart';

import '../api/api_client.dart';
import 'moon_strings.dart';

/// 从当前 `Localizations` 取语言，按中文 key 查译文。
extension MoonContextText on BuildContext {
  String tr(String zh) => moonText(Localizations.localeOf(this).languageCode, zh);
}

/// 带占位符的文案：`{n}`、`{m}`、`{name}`、`{id}` 由调用方替换。
String trArgs(BuildContext context, String zh, Map<String, String> args) {
  String text = context.tr(zh);
  args.forEach((String key, String value) {
    text = text.replaceAll('{$key}', value);
  });
  assert(
    !RegExp(r'\{[a-zA-Z]+\}').hasMatch(text),
    'unfilled placeholder in "$text"',
  );
  return text;
}

/// 接口错误文案在 `ApiException` 里只有中文，这里按当前语言再查一次。
extension MoonApiErrorText on ApiException {
  String displayTextIn(BuildContext context) =>
      moonText(Localizations.localeOf(context).languageCode, displayText);
}
