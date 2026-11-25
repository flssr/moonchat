import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mondchat/api/api_client.dart';
import 'package:mondchat/api/models.dart';
import 'package:mondchat/state/app_state.dart';
import 'package:mondchat/theme.dart';
import 'package:mondchat/ui/home_shell.dart';

AppState _state(List<String> calls) {
  final Account account = const Account(accountId: 1, type: 'human', displayName: '阿月');
  return AppState(
    api: ApiClient(
      baseUrl: 'http://mock.local',
      client: MockClient((http.Request req) async {
        calls.add('${req.method} ${req.url.path}');
        if (req.method == 'GET' && req.url.path == '/api/blocklist') {
          return http.Response(
            jsonEncode(<String, Object?>{
              'items': <Object?>[
                <String, Object?>{
                  'account_id': 3,
                  'display_name': '阿星',
                  'created_at': '2026-11-10T09:00:00Z',
                },
              ],
              'page': 1,
              'size': 50,
              'total': 1,
            }),
            200,
            headers: <String, String>{'content-type': 'application/json; charset=utf-8'},
          );
        }
        if (req.method == 'DELETE' && req.url.path == '/api/blocklist/3') {
          return http.Response('', 204);
        }
        return http.Response(
          jsonEncode(<String, Object?>{'code': 'not_found', 'message': 'no route'}),
          404,
          headers: <String, String>{'content-type': 'application/json; charset=utf-8'},
        );
      }),
    ),
  )
    ..loginToken = 'login-jwt'
    ..identityToken = 'login-jwt'
    ..phase = AuthPhase.ready
    ..account = account
    ..accounts = <Account>[account];
}

void main() {
  testWidgets('设置 → 黑名单管理能列出被拉黑的人并解除', (WidgetTester tester) async {
    final List<String> calls = <String>[];
    final AppState state = _state(calls);
    addTearDown(state.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildMoonTheme(Brightness.light),
        locale: const Locale('zh', 'CN'),
        supportedLocales: const <Locale>[Locale('zh', 'CN'), Locale('en'), Locale('ja'), Locale('de')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: HomeShell(
          state: state,
          onToggleTheme: (_) {},
          brightness: Brightness.light,
          textScale: 1.0,
          themeMode: ThemeMode.system,
          onThemeModeChanged: (_) {},
          onTextScaleChanged: (_) {},
          onLanguageChanged: (_) {},
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byTooltip('设置'));
    await tester.pumpAndSettle();
    // 入口不再是「待接入」占位。
    expect(find.text('待接入'), findsNothing);

    await tester.tap(find.text('黑名单管理'));
    await tester.pumpAndSettle();
    expect(calls, contains('GET /api/blocklist'));
    expect(find.text('阿星'), findsOneWidget);
    expect(find.text('#3'), findsOneWidget);

    await tester.tap(find.text('解除'));
    await tester.pumpAndSettle();
    expect(calls, contains('DELETE /api/blocklist/3'));
    expect(find.text('阿星'), findsNothing);
    expect(find.text('黑名单是空的'), findsOneWidget);
  });
}
