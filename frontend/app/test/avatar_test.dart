import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mondchat/api/api_client.dart';
import 'package:mondchat/api/models.dart';
import 'package:mondchat/avatars.dart';
import 'package:mondchat/settings/settings.dart';
import 'package:mondchat/state/app_state.dart';
import 'package:mondchat/theme.dart';
import 'package:mondchat/ui/home_shell.dart';

class _MemoryStore implements SettingsStore {
  MoonSettings settings = MoonSettings.defaults;
  Map<int, String> avatars = <int, String>{};

  @override
  MoonSettings load() => settings;

  @override
  void save(MoonSettings next) => settings = next;

  @override
  Map<int, String> loadAvatars() => avatars;

  @override
  void saveAvatars(Map<int, String> next) => avatars = next;
}

AppState _state(_MemoryStore store) {
  final Account account = Account(accountId: 1, type: 'human', displayName: '阿月');
  return AppState(
    api: ApiClient(
      baseUrl: 'http://mock.local',
      client: MockClient((http.Request req) async {
        // 资料编辑打开时会先 GET 完整资料，其余接口这个测试不关心。
        if (req.method == 'GET' && req.url.path == '/api/accounts/me') {
          return http.Response(
            '{"account_id":1,"display_name":"阿月","gender":"private","birthday":null,'
            '"updated_at":"2026-11-12T00:00:00Z"}',
            200,
            headers: <String, String>{'content-type': 'application/json; charset=utf-8'},
          );
        }
        return http.Response('{}', 404);
      }),
    ),
    store: store,
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

void main() {
  test('默认头像集：真人 6 张、agent 3 张，且图都在资源目录里', () {
    expect(kHumanAvatars.length, 6);
    expect(kAgentAvatars.length, 3);
    expect(avatarsFor('human'), kHumanAvatars);
    expect(avatarsFor('agent'), kAgentAvatars);
    for (final String key in <String>[...kHumanAvatars, ...kAgentAvatars]) {
      expect(File(avatarAsset(key)).existsSync(), isTrue, reason: '$key 缺图');
    }
  });

  test('头像 key 只认这一套', () {
    expect(isKnownAvatar('female_01'), isTrue);
    expect(isKnownAvatar('agent_gold'), isTrue);
    expect(isKnownAvatar('uploaded.png'), isFalse);
  });

  test('新建 agent 自动带一枚平台 agent 头像', () async {
    final _MemoryStore store = _MemoryStore();
    http.Response ok(String body) => http.Response(
          body,
          200,
          headers: <String, String>{'content-type': 'application/json; charset=utf-8'},
        );
    final AppState state = AppState(
      api: ApiClient(
        baseUrl: 'http://mock.local',
        client: MockClient((http.Request req) async {
          if (req.method == 'POST' && req.url.path == '/api/agent-accounts') {
            return ok('{"account_id":100000003,"display_name":"小帮手","account_key":"key-1"}');
          }
          if (req.method == 'GET' && req.url.path == '/api/accounts/mine') {
            return ok('{"items":[{"account_id":100000001,"display_name":"阿月","type":"human"},'
                '{"account_id":100000003,"display_name":"小帮手","type":"agent"}]}');
          }
          return http.Response('{}', 404);
        }),
      ),
      store: store,
    )
      ..loginToken = 'login-jwt'
      ..identityToken = 'login-jwt'
      ..phase = AuthPhase.ready;
    addTearDown(state.dispose);

    final CreatedAgent created = await state.createAgent('小帮手');

    final String? avatar = state.avatarOf(created.accountId);
    expect(avatar, isNotNull, reason: '新 agent 不能只剩首字头像');
    expect(kAgentAvatars, contains(avatar));
    expect(store.avatars[created.accountId], avatar, reason: '默认头像也要落本机偏好');
    expect(state.accounts.map((Account a) => a.accountId), contains(created.accountId));
  });

  test('选头像按账号落本机偏好，清掉回默认', () {
    final _MemoryStore store = _MemoryStore();
    final AppState state = _state(store);
    addTearDown(state.dispose);

    state.setAvatar(7, 'agent_gold');
    expect(state.avatarOf(7), 'agent_gold');
    expect(store.avatars[7], 'agent_gold');

    state.setAvatar(7, 'not_a_key');
    expect(state.avatarOf(7), 'agent_gold');

    state.setAvatar(7, null);
    expect(state.avatarOf(7), isNull);
    expect(store.avatars.containsKey(7), isFalse);
  });

  testWidgets('资料编辑里点一张默认头像就按账号存下', (WidgetTester tester) async {
    final _MemoryStore store = _MemoryStore();
    final AppState state = _state(store);
    addTearDown(state.dispose);
    await _pumpShell(tester, state);

    await tester.tap(find.byTooltip('个人资料'));
    await tester.pumpAndSettle();
    expect(find.text('选择默认头像'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('头像 2'));
    await tester.pump();
    expect(state.avatarOf(1), 'female_02');
    expect(store.avatars[1], 'female_02');
  });
}
