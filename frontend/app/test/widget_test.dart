import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:moonchat/api/api_client.dart';
import 'package:moonchat/main.dart';
import 'package:moonchat/state/app_state.dart';
import 'package:moonchat/theme.dart';
import 'package:moonchat/ui/home_shell.dart';
import 'package:moonchat/ui/login_quotes.dart';
import 'package:moonchat/ui/login_screen.dart';

/// 记录调用次数的假 Biz：用来断言「校验没过就一个请求都不发」。
class _Recorder {
  int calls = 0;

  late final MockClient client = MockClient((http.Request req) async {
    calls++;
    return http.Response('{}', 500);
  });
}

Widget _page(AppState state) => MaterialApp(
      theme: buildMoonTheme(Brightness.light),
      locale: const Locale('zh', 'CN'),
      supportedLocales: const <Locale>[Locale('zh', 'CN')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: LoginScreen(state: state),
    );

LoginQuote? _visibleQuote() {
  for (final LoginQuote quote in kLoginQuotes) {
    if (find.textContaining(quote.text).evaluate().isNotEmpty) {
      return quote;
    }
  }
  return null;
}

AppState _stateOn(_Recorder recorder) =>
    AppState(api: ApiClient(baseUrl: 'http://mock.local', client: recorder.client));

void main() {
  setUp(resetLoginQuoteHistory);

  testWidgets('登录页给出邮箱、密码与登录入口', (WidgetTester tester) async {
    final AppState state = AppState();
    addTearDown(state.dispose);

    await tester.pumpWidget(_page(state));

    expect(find.text('MoonChat'), findsOneWidget);
    expect(find.text('邮箱'), findsOneWidget);
    expect(find.text('密码'), findsOneWidget);
    expect(find.text('登录'), findsOneWidget);
  });

  testWidgets('每次进入登录页显示不同的引言', (WidgetTester tester) async {
    final AppState state = AppState();
    addTearDown(state.dispose);

    await tester.pumpWidget(_page(state));
    final LoginQuote? first = _visibleQuote();
    expect(first, isNotNull);
    expect(find.text('— ${first!.author}'), findsOneWidget);

    // 切注册模式会 setState，但引言只属于这一次进入，不能跟着换。
    await tester.tap(find.text('注册'));
    await tester.pump();
    expect(_visibleQuote()?.text, first.text);

    // 卸载再挂载，模拟退出登录后重新进入登录页。
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(_page(state));
    final LoginQuote? second = _visibleQuote();
    expect(second, isNotNull);
    expect(second!.text, isNot(first.text));
    expect(find.text('— ${second.author}'), findsOneWidget);
  });

  testWidgets('宽屏注册表单全量错误不溢出', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(920, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final AppState state = AppState();
    addTearDown(state.dispose);
    await tester.pumpWidget(_page(state));

    await tester.tap(find.text('注册'));
    await tester.pump();
    await tester.tap(find.text('注册并登录'));
    await tester.pump();

    expect(find.text('名字 1–20 字'), findsOneWidget);
    expect(find.text('需要一个带 @ 的邮箱'), findsOneWidget);
    expect(find.text('密码 8–72 位'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('空邮箱提交后贴字段错误，不发请求', (WidgetTester tester) async {
    final _Recorder recorder = _Recorder();
    final AppState state = _stateOn(recorder);
    addTearDown(state.dispose);

    await tester.pumpWidget(_page(state));
    await tester.tap(find.text('登录'));
    await tester.pump();

    expect(find.text('需要一个带 @ 的邮箱'), findsOneWidget);
    expect(recorder.calls, 0, reason: '校验没过就不该发请求');
  });

  testWidgets('密码 7 位与纯数字都拦在入口', (WidgetTester tester) async {
    final _Recorder recorder = _Recorder();
    final AppState state = _stateOn(recorder);
    addTearDown(state.dispose);
    await tester.pumpWidget(_page(state));

    await tester.enterText(find.byType(TextField).first, 'a@b.c');
    await tester.enterText(find.byType(TextField).last, '1234567');
    await tester.tap(find.text('登录'));
    await tester.pump();
    expect(find.text('密码 8–72 位'), findsOneWidget);

    await tester.enterText(find.byType(TextField).last, '12345678');
    await tester.tap(find.text('登录'));
    await tester.pump();
    expect(find.text('密码不能是纯数字'), findsOneWidget);
    expect(recorder.calls, 0);
  });

  testWidgets('注册模式没有名字会被拦住', (WidgetTester tester) async {
    final _Recorder recorder = _Recorder();
    final AppState state = _stateOn(recorder);
    addTearDown(state.dispose);
    await tester.pumpWidget(_page(state));

    await tester.tap(find.text('注册'));
    await tester.pump();
    expect(find.text('注册并登录'), findsOneWidget);

    await tester.enterText(find.byType(TextField).at(1), 'a@b.c');
    await tester.enterText(find.byType(TextField).at(2), 'password1');
    await tester.tap(find.text('注册并登录'));
    await tester.pump();

    expect(find.text('名字 1–20 字'), findsOneWidget);
    expect(recorder.calls, 0);
  });

  testWidgets('登录成功后先播完登舱过渡再切主界面', (WidgetTester tester) async {
    final AppState state = AppState(
      api: ApiClient(baseUrl: 'http://mock.local', client: _loginBiz()),
    );
    addTearDown(state.dispose);
    await tester.pumpWidget(MoonChatApp(state: state));
    await tester.pump();

    await tester.enterText(find.byType(TextField).at(0), 'a@b.c');
    await tester.enterText(find.byType(TextField).at(1), 'password1');
    await tester.tap(find.text('登录'));

    // 等 REST 链路跑完；此时登录态已经 ready，但过渡还没播完。
    for (int i = 0; i < 10 && !state.isReady; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(state.isReady, isTrue);
    expect(find.byType(HomeShell), findsNothing, reason: '登录成功不能同帧换屏，否则登舱过渡永远看不到');
    expect(find.text('MoonChat'), findsOneWidget);

    await tester.pumpAndSettle();
    expect(find.byType(HomeShell), findsOneWidget);

    // 登录会排 7 天 / 12 小时的续期定时器；测试结束前拆掉，别让 fake_async 报残留。
    await tester.pumpWidget(const SizedBox.shrink());
    state.dispose();
  });
}

/// 只跑登录链路：登录 → 换 Turms 凭据 → 拉账号 / 好友 / 群。
MockClient _loginBiz() {
  http.Response ok(Object? body, [int status = 200]) => http.Response(
        jsonEncode(body),
        status,
        headers: <String, String>{'content-type': 'application/json; charset=utf-8'},
      );
  return MockClient((http.Request req) async {
    switch (req.url.path) {
      case '/api/auth/login':
        return ok(<String, Object?>{
          'token': 'login-jwt',
          'expires_at': '2026-11-20T00:00:00Z',
          'account': <String, Object?>{'account_id': 1, 'display_name': '阿月', 'type': 'human'},
        });
      case '/api/sessions':
        return ok(<String, Object?>{
          'account_id': 1,
          'display_name': '阿月',
          'type': 'human',
          'login_token': 'login-jwt-1',
          'login_expires_at': '2026-11-20T00:00:00Z',
          'turms': <String, Object?>{
            'user_id': 1,
            'credential': 'turms-jwt-1',
            'gateway_url': 'ws://localhost:20510',
          },
          'expires_at': '2026-11-11T10:00:00Z',
        });
      case '/api/accounts/mine':
        return ok(<String, Object?>{
          'items': <Object?>[
            <String, Object?>{'account_id': 1, 'display_name': '阿月', 'type': 'human'},
          ],
        });
      case '/api/friendships':
        return ok(<String, Object?>{'items': <Object?>[]});
      case '/api/rooms':
        return ok(<String, Object?>{'items': <Object?>[]});
      default:
        return ok(<String, Object?>{'code': 'not_found', 'message': 'no route'}, 404);
    }
  });
}
