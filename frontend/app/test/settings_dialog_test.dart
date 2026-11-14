import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:mondchat/api/api_client.dart';
import 'package:mondchat/api/models.dart';
import 'package:mondchat/state/app_state.dart';
import 'package:mondchat/theme.dart';
import 'package:mondchat/ui/home_shell.dart';

AppState _state() {
  final Account account = const Account(
    accountId: 1,
    type: 'human',
    displayName: '阿月',
  );
  return AppState(
      api: ApiClient(
        baseUrl: 'http://mock.local',
        client: MockClient(
          (_) async => throw StateError('no request expected'),
        ),
      ),
    )
    ..loginToken = 'login-jwt'
    ..identityToken = 'login-jwt'
    ..phase = AuthPhase.ready
    ..account = account
    ..accounts = <Account>[account];
}

Future<void> _pumpShell(
  WidgetTester tester,
  AppState state, {
  required ValueChanged<double> onTextScale,
  required ValueChanged<String> onLanguage,
  Locale locale = const Locale('zh', 'CN'),
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: buildMoonTheme(Brightness.light),
      locale: locale,
      supportedLocales: const <Locale>[
        Locale('zh', 'CN'),
        Locale('en'),
        Locale('ja'),
        Locale('de'),
      ],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: HomeShell(
        state: state,
        onToggleTheme: (_) {},
        brightness: Brightness.light,
        textScale: 1.0,
        onTextScaleChanged: onTextScale,
        onLanguageChanged: onLanguage,
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('设置页列出字体、语言与隐私', (WidgetTester tester) async {
    final AppState state = _state();
    addTearDown(state.dispose);
    final List<double> scales = <double>[];
    final List<String> languages = <String>[];

    await _pumpShell(
      tester,
      state,
      onTextScale: scales.add,
      onLanguage: languages.add,
    );
    await tester.tap(find.byTooltip('设置'));
    await tester.pumpAndSettle();

    expect(find.text('设置'), findsOneWidget);
    expect(find.text('字体'), findsOneWidget);
    expect(find.text('语言'), findsOneWidget);
    expect(find.text('隐私'), findsOneWidget);
    expect(find.text('黑名单管理'), findsOneWidget);
    expect(find.text('我的友情关系'), findsOneWidget);
    expect(find.text('敬请期待'), findsOneWidget);
    expect(find.text('待接入'), findsOneWidget);

    await tester.tap(find.text('小'));
    await tester.pump();
    expect(scales, <double>[0.9]);

    await tester.tap(find.text('English'));
    await tester.pumpAndSettle();
    expect(languages, <String>['en']);
    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Blocklist'), findsOneWidget);
  });

  testWidgets('导航栏文案跟随 languageCode', (WidgetTester tester) async {
    final AppState state = _state();
    addTearDown(state.dispose);

    await _pumpShell(
      tester,
      state,
      onTextScale: (_) {},
      onLanguage: (_) {},
      locale: const Locale('en'),
    );

    expect(find.byTooltip('Settings'), findsOneWidget);
    expect(find.byTooltip('Messages'), findsOneWidget);
    expect(find.byTooltip('Sign out'), findsOneWidget);
  });
}
