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

http.Response _json(Object? body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: <String, String>{'content-type': 'application/json; charset=utf-8'},
);

/// 资料接口契约：`GET /api/accounts/me` 回填，`PUT` 全量提交三个字段。
MockClient _biz({
  bool echoProfileFields = true,
  Map<String, Object?>? lastPut,
  String name = '阿月',
  String gender = 'private',
  String? birthday,
  int failGetTimes = 0,
}) {
  int gets = 0;
  return MockClient((http.Request req) async {
    final String path = req.url.path;
    if (req.method == 'GET' && path == '/api/accounts/me') {
      gets++;
      if (gets <= failGetTimes) {
        return _json(<String, Object?>{
          'code': 'upstream_unavailable',
          'message': 'boom',
        }, 503);
      }
      return _json(<String, Object?>{
        'account_id': 1,
        'display_name': name,
        'gender': gender,
        'birthday': birthday,
        'updated_at': '2026-11-12T00:00:00Z',
      });
    }
    if (req.method == 'PUT' && path == '/api/accounts/me') {
      final Map<String, dynamic> body = jsonDecode(req.body) as Map<String, dynamic>;
      lastPut?.addAll(body);
      if (!echoProfileFields) {
        return _json(<String, Object?>{
          'account_id': 1,
          'display_name': body['display_name'],
          'updated_at': '2026-11-12T00:00:00Z',
        });
      }
      return _json(<String, Object?>{
        'account_id': 1,
        'display_name': body['display_name'],
        'gender': body['gender'],
        'birthday': body['birthday'],
        'updated_at': '2026-11-12T00:00:00Z',
      });
    }
    if (req.method == 'GET' && path == '/api/accounts/mine') {
      return _json(<String, Object?>{
        'items': <Object?>[
          <String, Object?>{'account_id': 1, 'type': 'human', 'display_name': name},
        ],
      });
    }
    if (req.method == 'GET' && (path == '/api/friendships' || path == '/api/rooms')) {
      return _json(<String, Object?>{'items': <Object?>[]});
    }
    return http.Response('{}', 404);
  });
}

AppState _state(MockClient client) {
  final Account account = Account(accountId: 1, type: 'human', displayName: '阿月');
  return AppState(
    api: ApiClient(baseUrl: 'http://mock.local', client: client),
  )
    ..loginToken = 'login-jwt'
    ..identityToken = 'login-jwt'
    ..phase = AuthPhase.ready
    ..account = account
    ..accounts = <Account>[account];
}

Future<void> _pumpShell(WidgetTester tester, AppState state) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: buildMoonTheme(Brightness.light),
      locale: const Locale('zh', 'CN'),
      supportedLocales: const <Locale>[Locale('zh', 'CN')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: HomeShell(
        state: state,
        onToggleTheme: (_) {},
        brightness: Brightness.light,
        textScale: 1.0,
        onLanguageChanged: (_) {},
        onTextScaleChanged: (_) {},
      ),
    ),
  );
  await tester.pump();
}

Future<void> _openEditor(WidgetTester tester) async {
  await tester.tap(find.byTooltip('个人资料'));
  await tester.pumpAndSettle();
}

Future<void> _tapSave(WidgetTester tester) async {
  // 800×600 的测试视口里保存按钮在折叠线以下，先滚进来再点。
  await tester.ensureVisible(find.text('保存'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('保存'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('打开资料编辑先用 GET 回填，保存用 PUT 全量提交', (WidgetTester tester) async {
    final Map<String, Object?> put = <String, Object?>{};
    final AppState state = _state(
      _biz(lastPut: put, gender: 'female', birthday: '1998-06-15'),
    );
    addTearDown(state.dispose);
    await _pumpShell(tester, state);

    await _openEditor(tester);
    expect(find.text('个人资料'), findsOneWidget);
    expect(find.text('昵称'), findsOneWidget);
    expect(find.text('生日'), findsOneWidget);
    expect(find.text('星座'), findsOneWidget);
    expect(find.text('1998年6月15日'), findsOneWidget);
    expect(find.text('双子座'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, '新名字');
    await tester.tap(find.text('女'));
    await tester.pump();
    await _tapSave(tester);

    expect(find.text('个人资料'), findsNothing);
    expect(state.account!.displayName, '新名字');
    expect(state.account!.gender, 'female');
    expect(state.account!.birthday, DateTime(1998, 6, 15));
    expect(put['display_name'], '新名字');
    expect(put['gender'], 'female');
    expect(put['birthday'], '1998-06-15');
  });

  testWidgets('昵称为空时不发请求', (WidgetTester tester) async {
    final Map<String, Object?> put = <String, Object?>{};
    final AppState state = _state(_biz(lastPut: put));
    addTearDown(state.dispose);
    await _pumpShell(tester, state);

    await _openEditor(tester);
    await tester.enterText(find.byType(TextField).first, '   ');
    await _tapSave(tester);

    expect(find.text('昵称 1–20 字'), findsOneWidget);
    expect(put, isEmpty);
  });

  testWidgets('选生日后星座跟着算出来并原样发出', (WidgetTester tester) async {
    final Map<String, Object?> put = <String, Object?>{};
    final AppState state = _state(_biz(lastPut: put));
    addTearDown(state.dispose);
    await _pumpShell(tester, state);

    await _openEditor(tester);
    await tester.tap(find.text('选择生日'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('20'));
    await tester.pump();
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();

    expect(find.text('2000年1月20日'), findsOneWidget);
    expect(find.text('水瓶座'), findsOneWidget);

    await _tapSave(tester);
    expect(put['birthday'], '2000-01-20');
    expect(state.account!.birthday, DateTime(2000, 1, 20));
  });

  testWidgets('清空生日时 PUT 明确发 null', (WidgetTester tester) async {
    final Map<String, Object?> put = <String, Object?>{};
    final AppState state = _state(
      _biz(lastPut: put, gender: 'female', birthday: '1998-06-15'),
    );
    addTearDown(state.dispose);
    await _pumpShell(tester, state);

    await _openEditor(tester);
    await tester.tap(find.text('清除'));
    await tester.pump();
    await _tapSave(tester);

    expect(put.containsKey('birthday'), isTrue);
    expect(put['birthday'], isNull);
    expect(state.account!.birthday, isNull);
  });

  testWidgets('资料加载失败时显示错误，重试后能回填', (WidgetTester tester) async {
    final AppState state = _state(_biz(failGetTimes: 1, gender: 'female'));
    addTearDown(state.dispose);
    await _pumpShell(tester, state);

    await _openEditor(tester);
    expect(find.text('服务暂时不可用，请重试'), findsOneWidget);
    expect(find.text('昵称'), findsNothing);

    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(find.text('昵称'), findsOneWidget);
    expect(find.text('女'), findsOneWidget);
  });

  testWidgets('PUT 没回显 gender 时保存失败并保留旧值', (WidgetTester tester) async {
    final AppState state = _state(_biz(echoProfileFields: false));
    addTearDown(state.dispose);
    await _pumpShell(tester, state);

    await _openEditor(tester);
    await tester.enterText(find.byType(TextField).first, '新名字');
    await _tapSave(tester);

    expect(find.text('个人资料'), findsOneWidget);
    expect(find.text('服务暂时不可用，请重试'), findsOneWidget);
    expect(state.account!.displayName, '阿月');
  });
}
