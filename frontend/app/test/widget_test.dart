import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moonchat/state/app_state.dart';
import 'package:moonchat/theme.dart';
import 'package:moonchat/ui/login_screen.dart';

void main() {
  testWidgets('登录页给出邮箱、密码与登录入口', (WidgetTester tester) async {
    final AppState state = AppState();
    addTearDown(state.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildMoonTheme(Brightness.light),
        home: LoginScreen(state: state),
      ),
    );

    expect(find.text('MoonChat'), findsOneWidget);
    expect(find.text('邮箱'), findsOneWidget);
    expect(find.text('密码'), findsOneWidget);
    expect(find.text('登录'), findsOneWidget);
  });

  testWidgets('空邮箱提交后贴字段错误，不发请求', (WidgetTester tester) async {
    final AppState state = AppState();
    addTearDown(state.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildMoonTheme(Brightness.light),
        home: LoginScreen(state: state),
      ),
    );

    await tester.tap(find.text('登录'));
    await tester.pump();

    expect(find.text('需要一个带 @ 的邮箱'), findsOneWidget);
  });
}
