import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:moonchat/api/api_client.dart';
import 'package:moonchat/api/models.dart';
import 'package:moonchat/state/app_state.dart';
import 'package:moonchat/theme.dart';
import 'package:moonchat/ui/home_shell.dart';

http.Response _json(Object? body) => http.Response(
  jsonEncode(body),
  200,
  headers: <String, String>{'content-type': 'application/json; charset=utf-8'},
);

MockClient _biz({
  required bool echoProfileFields,
  Map<String, Object?>? lastPatch,
}) {
  return MockClient((http.Request req) async {
    if (req.method == 'PATCH' && req.url.path == '/api/accounts/me') {
      final Map<String, dynamic> body =
          jsonDecode(req.body) as Map<String, dynamic>;
      lastPatch?.addAll(body);
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
    if (req.method == 'GET' && req.url.path == '/api/accounts/mine') {
      return _json(<String, Object?>{
        'items': <Object?>[
          <String, Object?>{
            'account_id': 1,
            'type': 'human',
            'display_name': echoProfileFields ? '新名字' : '阿月',
            'gender': echoProfileFields ? 'female' : null,
            'birthday': null,
          },
        ],
      });
    }
    if (req.method == 'GET' &&
        (req.url.path == '/api/friendships' || req.url.path == '/api/rooms')) {
      return _json(<String, Object?>{'items': <Object?>[]});
    }
    return http.Response('{}', 404);
  });
}

AppState _state(MockClient client, {bool withProfile = false}) {
  final Account account = Account(
    accountId: 1,
    type: 'human',
    displayName: '阿月',
    gender: withProfile ? 'female' : null,
    birthday: withProfile ? DateTime(1998, 6, 15) : null,
  );
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

Future<void> _tapSave(WidgetTester tester) async {
  // 800×600 的测试视口里保存按钮在折叠线以下，先滚进来再点。
  await tester.ensureVisible(find.text('保存'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('保存'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('头像入口打开资料编辑并保存昵称、性别', (WidgetTester tester) async {
    final Map<String, Object?> patch = <String, Object?>{};
    final AppState state = _state(
      _biz(echoProfileFields: true, lastPatch: patch),
    );
    addTearDown(state.dispose);
    await _pumpShell(tester, state);

    await tester.tap(find.byTooltip('个人资料'));
    await tester.pumpAndSettle();
    expect(find.text('个人资料'), findsOneWidget);
    expect(find.text('昵称'), findsOneWidget);
    expect(find.text('生日'), findsOneWidget);
    expect(find.text('星座'), findsOneWidget);
    expect(find.text('选择默认头像'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, '新名字');
    await tester.tap(find.text('女'));
    await tester.pump();
    await _tapSave(tester);

    expect(find.text('个人资料'), findsNothing);
    expect(state.account!.displayName, '新名字');
    expect(state.account!.gender, 'female');
    expect(state.account!.birthday, isNull);
    expect(patch['display_name'], '新名字');
    expect(patch['gender'], 'female');
    expect(patch.containsKey('birthday'), isFalse);
  });

  testWidgets('昵称为空时不发请求', (WidgetTester tester) async {
    final Map<String, Object?> patch = <String, Object?>{};
    final AppState state = _state(
      _biz(echoProfileFields: true, lastPatch: patch),
    );
    addTearDown(state.dispose);
    await _pumpShell(tester, state);

    await tester.tap(find.byTooltip('个人资料'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '   ');
    await _tapSave(tester);

    expect(find.text('昵称 1–20 字'), findsOneWidget);
    expect(patch, isEmpty);
  });

  testWidgets('选生日后星座跟着算出来并原样发出', (WidgetTester tester) async {
    final Map<String, Object?> patch = <String, Object?>{};
    final AppState state = _state(
      _biz(echoProfileFields: true, lastPatch: patch),
    );
    addTearDown(state.dispose);
    await _pumpShell(tester, state);

    await tester.tap(find.byTooltip('个人资料'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('选择生日'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('20'));
    await tester.pump();
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();

    expect(find.text('2000年1月20日'), findsOneWidget);
    expect(find.text('水瓶座'), findsOneWidget);

    await _tapSave(tester);
    expect(patch['birthday'], '2000-01-20');
    expect(state.account!.birthday, DateTime(2000, 1, 20));
  });

  testWidgets('资料页回填账号上的性别和生日', (WidgetTester tester) async {
    final AppState state = _state(
      _biz(echoProfileFields: true),
      withProfile: true,
    );
    addTearDown(state.dispose);
    await _pumpShell(tester, state);

    await tester.tap(find.byTooltip('个人资料'));
    await tester.pumpAndSettle();

    expect(find.text('1998年6月15日'), findsOneWidget);
    expect(find.text('双子座'), findsOneWidget);
  });

  testWidgets('清空生日时明确发 null', (WidgetTester tester) async {
    final Map<String, Object?> patch = <String, Object?>{};
    final AppState state = _state(
      _biz(echoProfileFields: true, lastPatch: patch),
      withProfile: true,
    );
    addTearDown(state.dispose);
    await _pumpShell(tester, state);

    await tester.tap(find.byTooltip('个人资料'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('清除'));
    await tester.pump();
    await _tapSave(tester);

    expect(patch.containsKey('birthday'), isTrue);
    expect(patch['birthday'], isNull);
    expect(state.account!.birthday, isNull);
  });

  testWidgets('后端没回显资料字段时保存失败并保留旧值', (WidgetTester tester) async {
    final AppState state = _state(_biz(echoProfileFields: false));
    addTearDown(state.dispose);
    await _pumpShell(tester, state);

    await tester.tap(find.byTooltip('个人资料'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '新名字');
    await _tapSave(tester);

    expect(find.text('个人资料'), findsOneWidget);
    expect(find.text('服务暂时不可用，请重试'), findsOneWidget);
    expect(state.account!.displayName, '阿月');
  });
}
