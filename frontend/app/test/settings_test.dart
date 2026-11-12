import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moonchat/main.dart';
import 'package:moonchat/settings/settings.dart';
import 'package:moonchat/settings/settings_store.dart';
import 'package:moonchat/state/app_state.dart';

void main() {
  test('设置 JSON 往返', () {
    const MoonSettings settings = MoonSettings(
      textScale: 0.9,
      languageCode: 'de',
      themeMode: ThemeMode.dark,
    );
    final MoonSettings restored = MoonSettings.fromJson(
      jsonDecode(jsonEncode(settings.toJson())) as Map<String, dynamic>,
    );
    expect(restored.textScale, 0.9);
    expect(restored.languageCode, 'de');
    expect(restored.themeMode, ThemeMode.dark);
  });

  test('非法本地值回默认', () {
    final MoonSettings settings = MoonSettings.fromJson(<String, dynamic>{
      'text_scale': 0.5,
      'language': 123,
      'theme': 'blue',
    });
    expect(settings.textScale, 1.0);
    expect(settings.languageCode, 'zh');
    expect(settings.themeMode, ThemeMode.system);
    expect(
      MoonSettings.fromJson(<String, dynamic>{'language': 'fr'}).languageCode,
      'zh',
    );
  });

  test('内存 store 存取', () {
    final SettingsStore store = createSettingsStore();
    store.save(const MoonSettings(textScale: 1.12, languageCode: 'en'));
    expect(store.load().textScale, 1.12);
    expect(store.load().languageCode, 'en');
  });

  testWidgets('启动时恢复上次语言与字号', (WidgetTester tester) async {
    final AppState state = AppState();
    await tester.pumpWidget(MoonChatApp(
      state: state,
      settings: const MoonSettings(languageCode: 'en', textScale: 1.12),
    ));
    await tester.pump();

    expect(find.text('Sign in'), findsOneWidget);
    expect(find.text('EMAIL'), findsOneWidget);
    expect(find.text('PASSWORD'), findsOneWidget);
    final BuildContext context = tester.element(find.text('Sign in'));
    expect(MediaQuery.textScalerOf(context).scale(10), closeTo(11.2, 0.001));
    await tester.pumpWidget(const SizedBox.shrink());
    state.dispose();
  });

  testWidgets('启动时恢复上次主题', (WidgetTester tester) async {
    final AppState state = AppState();
    await tester.pumpWidget(MoonChatApp(
      state: state,
      settings: const MoonSettings(themeMode: ThemeMode.dark),
    ));
    await tester.pump();

    final BuildContext context = tester.element(find.text('登录'));
    expect(Theme.of(context).brightness, Brightness.dark);
    await tester.pumpWidget(const SizedBox.shrink());
    state.dispose();
  });
}
