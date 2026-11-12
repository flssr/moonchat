import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:moonchat/i18n/moon_strings.dart';

void main() {
  final List<String> translated = kMoonLanguages
      .map(((String, String) item) => item.$1)
      .where((String code) => code != 'zh')
      .toList(growable: false);

  test('所有语言的 key 与占位符集合一致', () {
    final RegExp placeholder = RegExp(r'\{[a-zA-Z]+\}');
    for (final String key in moonAllKeys()) {
      final Set<String> expected =
          placeholder.allMatches(key).map((RegExpMatch m) => m.group(0)!).toSet();
      for (final String code in translated) {
        expect(moonHasText(code, key), isTrue, reason: '$key 在 $code 缺翻译');
        final Set<String> actual = placeholder
            .allMatches(moonText(code, key))
            .map((RegExpMatch m) => m.group(0)!)
            .toSet();
        expect(actual, expected, reason: '$key 在 $code 的占位符不一致');
      }
    }
  });

  test('lib 下所有界面中文字面量都有译文', () {
    final List<RegExp> literals = <RegExp>[
      RegExp(r"'([^']*[\u4e00-\u9fff][^']*)'"),
      RegExp(r'"([^"]*[\u4e00-\u9fff][^"]*)"'),
    ];
    final Set<String> nativeNames =
        kMoonLanguages.map(((String, String) item) => item.$2).toSet();
    for (final FileSystemEntity entity in Directory('lib').listSync(recursive: true)) {
      final String path = entity.path.replaceAll('\\', '/');
      if (entity is! File ||
          !path.endsWith('.dart') ||
          path.endsWith('moon_strings.dart') ||
          (!path.contains('/ui/') && !path.endsWith('api_client.dart'))) {
        continue;
      }
      final List<String> lines = entity.readAsLinesSync();
      for (int i = 0; i < lines.length; i++) {
        final String line = lines[i].trimLeft();
        if (line.startsWith('//') || line.startsWith('*') || line.contains('assert(')) {
          continue;
        }
        for (final RegExp literal in literals) {
          for (final RegExpMatch match in literal.allMatches(lines[i])) {
            final String key = match.group(1)!;
            if (nativeNames.contains(key) || key.contains(r'$')) {
              continue; // 语言名是自名的；动态拼接由调用处拆 key。
            }
            expect(
              translated.every((String code) => moonHasText(code, key)),
              isTrue,
              reason: '${entity.path}:${i + 1} 缺译文：$key',
            );
          }
        }
      }
    }
    expect(moonText('zh', '设置'), '设置');
  });
}
