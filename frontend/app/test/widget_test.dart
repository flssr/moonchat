import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:moonchat/api/api_client.dart';
import 'package:moonchat/state/app_state.dart';
import 'package:moonchat/theme.dart';
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
      home: LoginScreen(state: state),
    );

AppState _stateOn(_Recorder recorder) =>
    AppState(api: ApiClient(baseUrl: 'http://mock.local', client: recorder.client));

void main() {
  testWidgets('登录页给出邮箱、密码与登录入口', (WidgetTester tester) async {
    final AppState state = AppState();
    addTearDown(state.dispose);

    await tester.pumpWidget(_page(state));

    expect(find.text('MoonChat'), findsOneWidget);
    expect(find.text('邮箱'), findsOneWidget);
    expect(find.text('密码'), findsOneWidget);
    expect(find.text('登录'), findsOneWidget);
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
}
