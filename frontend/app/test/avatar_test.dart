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

http.Response _ok(String body) => http.Response(
      body,
      200,
      headers: <String, String>{'content-type': 'application/json; charset=utf-8'},
    );

AppState _state(_MemoryStore store, {List<String>? requests}) {
  final Account account = Account(accountId: 1, type: 'human', displayName: '阿月');
  return AppState(
    api: ApiClient(
      baseUrl: 'http://mock.local',
      client: MockClient((http.Request req) async {
        requests?.add('${req.method} ${req.url.path}');
        // 资料编辑打开时会先 GET 完整资料，其余接口这个测试不关心。
        if (req.method == 'GET' && req.url.path == '/api/accounts/me') {
          return _ok('{"account_id":1,"display_name":"阿月","gender":"private",'
              '"birthday":null,"avatar":null,"updated_at":"2026-11-12T00:00:00Z"}');
        }
        if (req.method == 'GET' && req.url.path == '/api/accounts/2') {
          return _ok('{"account_id":2,"display_name":"小助手","avatar":"agent_gold","is_friend":false}');
        }
        // 头像走服务端：回显请求里的 key，null 原样回 null。
        if (req.method == 'PUT' && req.url.path == '/api/accounts/me/avatar') {
          final Object? value = (jsonBody(req.body) as Map<String, dynamic>)['avatar'];
          return _ok('{"avatar":${value == null ? 'null' : '"$value"'}}');
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

Object? jsonBody(String body) {
  // 只用来拆测试里的假请求体，不值得引入 dart:convert 的完整解析语义。
  if (body.contains('"avatar":null')) {
    return <String, dynamic>{'avatar': null};
  }
  final RegExpMatch? match = RegExp(r'"avatar":"([^"]*)"').firstMatch(body);
  return <String, dynamic>{'avatar': match?.group(1)};
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

  test('新建 agent 的默认头像跟着 mine 回显进本机缓存', () async {
    final _MemoryStore store = _MemoryStore();
    final AppState state = AppState(
      api: ApiClient(
        baseUrl: 'http://mock.local',
        client: MockClient((http.Request req) async {
          if (req.method == 'POST' && req.url.path == '/api/agent-accounts') {
            return _ok('{"account_id":100000003,"display_name":"小帮手","account_key":"key-1"}');
          }
          if (req.method == 'GET' && req.url.path == '/api/accounts/mine') {
            // 默认头像由服务端在创建时分配，这里是回显。
            return _ok('{"items":[{"account_id":100000001,"display_name":"阿月","type":"human",'
                '"avatar":null},{"account_id":100000003,"display_name":"小帮手","type":"agent",'
                '"avatar":"agent_pink"}]}');
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

    expect(state.avatarOf(created.accountId), 'agent_pink');
    expect(store.avatars[created.accountId], 'agent_pink');
    expect(kAgentAvatars, contains(state.avatarOf(created.accountId)));
  });

  test('新建 agent 后立刻出现在好友与会话列表', () async {
    final AppState state = AppState(
      api: ApiClient(
        baseUrl: 'http://mock.local',
        client: MockClient((http.Request req) async {
          final String path = req.url.path;
          if (req.method == 'POST' && path == '/api/agent-accounts') {
            return _ok('{"account_id":100000003,"display_name":"小帮手","account_key":"key-1"}');
          }
          if (req.method == 'GET' && path == '/api/accounts/mine') {
            return _ok('{"items":[{"account_id":100000001,"display_name":"阿月","type":"human"},'
                '{"account_id":100000003,"display_name":"小帮手","type":"agent"}]}');
          }
          if (req.method == 'GET' && path == '/api/friendships') {
            if (req.url.queryParameters['status'] == 'pending') {
              return _ok('{"items":[]}');
            }
            return _ok('{"items":[{"peer_account_id":100000003,"display_name":"小帮手",'
                '"status":"accepted","incoming":false,"requested_at":"2026-11-23T20:00:00Z"}]}');
          }
          if (req.method == 'GET' && path == '/api/rooms') {
            return _ok('{"items":[]}');
          }
          return http.Response('{}', 404);
        }),
      ),
      store: _MemoryStore(),
    )
      ..loginToken = 'login-jwt'
      ..identityToken = 'login-jwt'
      ..phase = AuthPhase.ready;
    addTearDown(state.dispose);

    final CreatedAgent created = await state.createAgent('小帮手');

    expect(
      state.friends.map((Friendship f) => f.peerAccountId),
      contains(created.accountId),
      reason: '后端建 agent 时已建立归属者好友关系，客户端应立刻重拉',
    );
    expect(
      state.conversations.map((Conversation c) => c.key),
      contains('dm:${created.accountId}'),
    );
  });

  test('选头像走服务端，回显写回本机缓存；清空也走服务端', () async {
    final _MemoryStore store = _MemoryStore();
    final List<String> requests = <String>[];
    final AppState state = _state(store, requests: requests);
    addTearDown(state.dispose);
    expect(state.avatarOf(1), isNull);

    await state.updateAvatar('female_02');
    expect(requests, contains('PUT /api/accounts/me/avatar'));
    expect(state.avatarOf(1), 'female_02');
    expect(store.avatars[1], 'female_02');

    await state.updateAvatar(null);
    expect(state.avatarOf(1), isNull);
    expect(store.avatars.containsKey(1), isFalse);
  });

  test('资料页拿到的头像也进本机缓存', () async {
    final _MemoryStore store = _MemoryStore();
    final AppState state = _state(store);
    addTearDown(state.dispose);

    await state.loadProfile(2);

    expect(state.avatarOf(2), 'agent_gold');
    expect(store.avatars[2], 'agent_gold');
  });

  testWidgets('资料编辑里点一张默认头像就存到服务端', (WidgetTester tester) async {
    final _MemoryStore store = _MemoryStore();
    final List<String> requests = <String>[];
    final AppState state = _state(store, requests: requests);
    addTearDown(state.dispose);
    await _pumpShell(tester, state);

    await tester.tap(find.byTooltip('个人资料'));
    await tester.pumpAndSettle();
    expect(find.text('选择默认头像'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('头像 2'));
    await tester.pumpAndSettle();

    expect(requests, contains('PUT /api/accounts/me/avatar'));
    expect(state.avatarOf(1), 'female_02');
    expect(store.avatars[1], 'female_02');
  });
}
