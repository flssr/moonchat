import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mondchat/api/api_client.dart';
import 'package:mondchat/api/models.dart';
import 'package:mondchat/message_cache.dart';
import 'package:mondchat/session/session_store.dart';
import 'package:mondchat/settings/settings.dart';
import 'package:mondchat/state/app_state.dart';
import 'package:mondchat/theme.dart';
import 'package:mondchat/ui/home_shell.dart';
import 'package:mondchat/ui/widgets.dart';

class _MemorySessionStore implements SessionStore {
  StoredSession? _session;

  @override
  StoredSession? load() => _session;

  @override
  void save(StoredSession session) => _session = session;

  @override
  void clear() => _session = null;
}

class _MemoryCacheStore implements MessageCacheStore {
  final Map<int, Map<String, dynamic>> saved = <int, Map<String, dynamic>>{};

  @override
  Map<String, dynamic>? load(int accountId) => saved[accountId];

  @override
  void save(int accountId, Map<String, dynamic> data) => saved[accountId] = data;

  @override
  void clear(int accountId) => saved.remove(accountId);
}

class _MemorySettingsStore implements SettingsStore {
  MoonSettings settings = MoonSettings.defaults;
  Map<int, String> avatars = <int, String>{};
  String? lastEmail;

  @override
  MoonSettings load() => settings;

  @override
  void save(MoonSettings value) => settings = value;

  @override
  Map<int, String> loadAvatars() => avatars;

  @override
  void saveAvatars(Map<int, String> value) => avatars = value;

  @override
  String? loadLastEmail() => lastEmail;

  @override
  void saveLastEmail(String email) => lastEmail = email;
}

const Account _human = Account(accountId: 1, type: 'human', displayName: '阿月');

AppState _readyState({
  required http.Client client,
  _MemorySessionStore? session,
  _MemoryCacheStore? cache,
  _MemorySettingsStore? store,
}) {
  final AppState state = AppState(
    api: ApiClient(baseUrl: 'http://mock.local', client: client),
    session: session,
    cache: cache,
    store: store,
    primeOnLogin: false,
  );
  state
    ..loginToken = 'login-jwt'
    ..identityToken = 'login-jwt'
    ..phase = AuthPhase.ready
    ..account = _human
    ..accounts = const <Account>[_human];
  return state;
}

void main() {
  test('注销成功：DELETE 带密码，清本机会话、缓存与头像', () async {
    final _MemorySessionStore session = _MemorySessionStore()
      ..save(const StoredSession(token: 'login-jwt', accountId: 1));
    final _MemoryCacheStore cache = _MemoryCacheStore()..saved[1] = <String, dynamic>{'active': 'dm:2'};
    final _MemorySettingsStore store = _MemorySettingsStore()
      ..avatars = <int, String>{1: 'male_01', 2: 'female_01'};
    String? seenMethod;
    String? seenPath;
    String? seenBody;

    final AppState state = _readyState(
      session: session,
      cache: cache,
      store: store,
      client: MockClient((http.Request request) async {
        seenMethod = request.method;
        seenPath = request.url.path;
        seenBody = request.body;
        return http.Response('', 204);
      }),
    );
    addTearDown(state.dispose);

    await state.deleteAccount(password: 'secret123');

    expect(seenMethod, 'DELETE');
    expect(seenPath, '/api/accounts/me');
    expect(seenBody, '{"password":"secret123"}');
    expect(state.phase, AuthPhase.loggedOut);
    expect(state.loginToken, isNull);
    expect(session.load(), isNull);
    expect(cache.saved, isEmpty);
    expect(store.avatars, <int, String>{2: 'female_01'});
  });

  test('密码错误不改本机会话', () async {
    final _MemorySessionStore session = _MemorySessionStore()
      ..save(const StoredSession(token: 'login-jwt', accountId: 1));
    final AppState state = _readyState(
      session: session,
      client: MockClient(
        (_) async => http.Response(
          '{"code":"invalid_password","message":"密码不正确"}',
          401,
          headers: <String, String>{'content-type': 'application/json'},
        ),
      ),
    );
    addTearDown(state.dispose);

    await expectLater(
      state.deleteAccount(password: 'wrong'),
      throwsA(isA<ApiException>().having((ApiException e) => e.code, 'code', 'invalid_password')),
    );
    expect(state.phase, AuthPhase.ready);
    expect(state.loginToken, 'login-jwt');
    expect(session.load()?.token, 'login-jwt');
  });

  testWidgets('设置里的注销入口：5 秒冷却后才可确认', (WidgetTester tester) async {
    bool requested = false;
    final AppState state = _readyState(
      client: MockClient((http.Request request) async {
        expect(request.method, 'DELETE');
        expect(request.url.path, '/api/accounts/me');
        requested = true;
        return http.Response('', 204);
      }),
    );
    addTearDown(state.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildMoonTheme(Brightness.light),
        locale: const Locale('zh', 'CN'),
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
    expect(find.text('注销账号'), findsOneWidget);

    await tester.ensureVisible(find.text('注销账号'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('注销账号'));
    await tester.pumpAndSettle();
    expect(find.text('是否要注销账号，注销账号数据将不再保留'), findsOneWidget);
    expect(find.text('请稍候 5 秒'), findsOneWidget);
    await tester.enterText(
      find.descendant(
        of: find.widgetWithText(MoonField, '密码'),
        matching: find.byType(TextField),
      ),
      'secret123',
    );

    // 冷却期内确认键不可用：点了也不发请求。
    await tester.tap(find.text('确认注销'));
    await tester.pump();
    expect(requested, isFalse);

    for (int i = 0; i < 5; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
    expect(find.text('请稍候 5 秒'), findsNothing);
    await tester.tap(find.text('确认注销'));
    await tester.pumpAndSettle();
    expect(requested, isTrue);
    expect(state.phase, AuthPhase.loggedOut);
  });
}
