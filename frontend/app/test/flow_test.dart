import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:moonchat/api/api_client.dart';
import 'package:moonchat/api/models.dart';
import 'package:moonchat/state/app_state.dart';
import 'package:moonchat/theme.dart';
import 'package:moonchat/turms/realtime.dart';
import 'package:moonchat/ui/home_shell.dart';

/// 读取通道在测试里不连 Turms：只验证 REST 链路与状态机。
class _FakeRealtime implements RealtimeClient {
  bool connected = false;
  void Function(IncomingMessage message)? _onMessage;

  @override
  Future<void> connect({
    required TurmsCredential credential,
    required int myAccountId,
    required void Function(IncomingMessage message) onMessage,
    void Function(bool connected)? onConnected,
    void Function(Object error)? onError,
  }) async {
    // 替身也要看凭据：忽略 credential / myAccountId 的话，签发链路断了测试照样绿。
    expect(credential.credential, isNotEmpty);
    expect(credential.gatewayUrl, isNotEmpty);
    expect(myAccountId, greaterThan(0));
    connected = true;
    _onMessage = onMessage;
    onConnected?.call(true);
  }

  /// 模拟服务端推来一条消息。
  void emit(IncomingMessage message) => _onMessage?.call(message);

  @override
  Future<List<IncomingMessage>> history({
    required String conversationType,
    required int targetId,
    DateTime? before,
    int maxCount = 50,
  }) async =>
      const <IncomingMessage>[];

  @override
  Future<void> disconnect() async {
    connected = false;
  }
}

Map<String, Object?> _account(int id, String name, {String type = 'human'}) =>
    <String, Object?>{'account_id': id, 'display_name': name, 'type': type};

http.Response _json(Object? body, int status) => http.Response(
      jsonEncode(body),
      status,
      headers: <String, String>{'content-type': 'application/json; charset=utf-8'},
    );

/// 假 Biz：只实现客户端会打到的那几条，字段与 `docs/api-contracts.md` 一致。
MockClient _mockBiz({int sendStatus = 201}) {
  return MockClient((http.Request req) async {
    final String path = req.url.path;
    final String method = req.method;

    if (method == 'POST' && path == '/api/auth/login') {
      return _json(<String, Object?>{
        'token': 'login-jwt',
        'expires_at': '2026-11-20T00:00:00Z',
        'account': _account(1, '阿月'),
      }, 200);
    }
    if (method == 'POST' && path == '/api/sessions') {
      final Map<String, dynamic> body = jsonDecode(req.body) as Map<String, dynamic>;
      final int id = (body['account_id'] as num?)?.toInt() ?? 1;
      return _json(<String, Object?>{
        'account_id': id,
        'display_name': id == 1 ? '阿月' : '小助手',
        'type': id == 1 ? 'human' : 'agent',
        'login_token': 'login-jwt-$id',
        'login_expires_at': '2026-11-20T00:00:00Z',
        'turms': <String, Object?>{
          'user_id': id,
          'credential': 'turms-jwt-$id',
          'gateway_url': 'ws://localhost:20510',
        },
        'expires_at': '2026-11-11T10:00:00Z',
      }, 200);
    }
    if (method == 'GET' && path == '/api/accounts/mine') {
      return _json(<String, Object?>{
        'items': <Object?>[_account(1, '阿月'), _account(2, '小助手', type: 'agent')],
      }, 200);
    }
    if (method == 'GET' && path == '/api/friendships') {
      final String status = req.url.queryParameters['status'] ?? 'accepted';
      if (status == 'pending') {
        return _json(<String, Object?>{
          'items': <Object?>[
            <String, Object?>{
              'peer_account_id': 3,
              'display_name': '阿星',
              'status': 'pending',
              'incoming': true,
              'requested_at': '2026-11-10T09:00:00Z',
            },
          ],
        }, 200);
      }
      return _json(<String, Object?>{
        'items': <Object?>[
          <String, Object?>{
            'peer_account_id': 2,
            'display_name': '小助手',
            'status': 'accepted',
            'incoming': false,
            'requested_at': '2026-11-09T09:00:00Z',
          },
        ],
      }, 200);
    }
    if (method == 'GET' && path == '/api/rooms') {
      return _json(<String, Object?>{
        'items': <Object?>[
          <String, Object?>{
            'room_id': 7,
            'name': '月球基地',
            'owner_account_id': 1,
            'joined_at': '2026-11-09T10:00:00Z',
          },
        ],
      }, 200);
    }
    if (method == 'POST' && path.startsWith('/api/conversations/')) {
      if (sendStatus != 201) {
        return _json(<String, Object?>{'code': 'rate_limited', 'message': 'too many'}, sendStatus);
      }
      return _json(<String, Object?>{
        'message_id': 9001,
        'conversation': <String, Object?>{'type': 'dm', 'id': 2},
        'sent_at': '2026-11-10T12:00:00Z',
      }, 201);
    }
    return _json(<String, Object?>{'code': 'not_found', 'message': 'no route'}, 404);
  });
}

AppState _newState({int sendStatus = 201, _FakeRealtime? realtime}) {
  return AppState(
    api: ApiClient(baseUrl: 'http://mock.local', client: _mockBiz(sendStatus: sendStatus)),
    realtime: realtime ?? _FakeRealtime(),
  );
}

void main() {
  test('登录后拉齐账号、好友、待处理与群，会话列表由好友与群拼出', () async {
    final AppState state = _newState();
    addTearDown(state.dispose);

    await state.login(email: 'a@b.c', password: 'password1');

    expect(state.isReady, isTrue);
    expect(state.account?.displayName, '阿月');
    expect(state.accounts.length, 2);
    expect(state.friends.single.peerAccountId, 2);
    expect(state.pending.single.displayName, '阿星');
    expect(state.rooms.single.name, '月球基地');

    final List<Conversation> convs = state.conversations;
    expect(convs.map((Conversation c) => c.key), <String>['dm:2', 'room:7']);
  });

  test('登录后接上读取通道', () async {
    final _FakeRealtime realtime = _FakeRealtime();
    final AppState state = _newState(realtime: realtime);
    addTearDown(state.dispose);

    await state.login(email: 'a@b.c', password: 'password1');

    expect(realtime.connected, isTrue);
    expect(state.realtimeUp, isTrue);
  });

  test('发言成功：本地先落「发送中」，确认后落定并带服务端 id', () async {
    final AppState state = _newState();
    addTearDown(state.dispose);
    await state.login(email: 'a@b.c', password: 'password1');

    final Conversation dm = state.conversations.first;
    await state.sendMessage(dm, '  你好  ');

    final ChatMessage msg = state.messagesOf(dm.key).single;
    expect(msg.text, '你好');
    expect(msg.state, MessageState.sent);
    expect(msg.serverId, 9001);
    expect(msg.sentAt, DateTime.parse('2026-11-10T12:00:00Z'));
  });

  test('发言被限流：消息标失败并保留正文，异常带 rate_limited', () async {
    final AppState state = _newState(sendStatus: 429);
    addTearDown(state.dispose);
    await state.login(email: 'a@b.c', password: 'password1');

    final Conversation dm = state.conversations.first;
    await expectLater(
      state.sendMessage(dm, '再说一句'),
      throwsA(isA<ApiException>().having((ApiException e) => e.code, 'code', 'rate_limited')),
    );

    final ChatMessage msg = state.messagesOf(dm.key).single;
    expect(msg.state, MessageState.failed);
    expect(msg.text, '再说一句');
  });

  test('切账号：换成新账号的登录凭据并重算列表', () async {
    final AppState state = _newState();
    addTearDown(state.dispose);
    await state.login(email: 'a@b.c', password: 'password1');
    expect(state.account?.accountId, 1);

    await state.switchAccount(2);

    expect(state.account?.accountId, 2);
    expect(state.account?.isAgent, isTrue);
    expect(state.loginToken, 'login-jwt-2');
  });

  test('推送消息按会话坐标落盘，重复 id 不重复插入', () async {
    final _FakeRealtime realtime = _FakeRealtime();
    final AppState state = _newState(realtime: realtime);
    addTearDown(state.dispose);
    await state.login(email: 'a@b.c', password: 'password1');

    // 走读取通道的回调注入一条推送。
    realtime.emit(const IncomingMessage(
      id: '501',
      text: '在吗',
      senderId: 2,
      sentAt: null,
      recipientId: 1,
    ));
    realtime.emit(const IncomingMessage(
      id: '501',
      text: '在吗',
      senderId: 2,
      sentAt: null,
      recipientId: 1,
    ));

    final List<ChatMessage> list = state.messagesOf('dm:2');
    expect(list.length, 1);
    expect(list.single.mine, isFalse);
  });

  test('加好友：申请成功后重新拉取，待处理里出现对方', () async {
    final _FakeBiz biz = _FakeBiz();
    final AppState state = _stateOn(biz);
    addTearDown(state.dispose);
    await state.login(email: 'a@b.c', password: 'password1');
    expect(state.pending, isEmpty);

    await state.requestFriend(4);

    expect(biz.pending.single['peer_account_id'], 4);
    expect(state.pending.single.peerAccountId, 4);
  });

  test('同意申请：申请移出待处理、进好友列表', () async {
    final _FakeBiz biz = _FakeBiz();
    final AppState state = _stateOn(biz);
    addTearDown(state.dispose);
    await state.login(email: 'a@b.c', password: 'password1');
    await state.requestFriend(4);

    await state.respondFriend(4, 'accept');

    expect(state.pending, isEmpty);
    expect(biz.friends.map((Map<String, Object?> f) => f['peer_account_id']), contains(4));
    expect(state.friends.length, 2);
  });

  test('删好友：写 tombstone 后从列表消失', () async {
    final _FakeBiz biz = _FakeBiz();
    final AppState state = _stateOn(biz);
    addTearDown(state.dispose);
    await state.login(email: 'a@b.c', password: 'password1');
    await state.requestFriend(4);
    await state.respondFriend(4, 'accept');

    await state.deleteFriend(4);

    expect(state.friends.map((Friendship f) => f.peerAccountId), isNot(contains(4)));
  });

  test('建群：创建后群列表立刻包含它', () async {
    final _FakeBiz biz = _FakeBiz();
    final AppState state = _stateOn(biz);
    addTearDown(state.dispose);
    await state.login(email: 'a@b.c', password: 'password1');
    expect(state.rooms.length, 1);

    final Room room = await state.createRoom('新群');

    expect(room.name, '新群');
    expect(state.rooms.map((Room r) => r.roomId), contains(room.roomId));
    expect(state.conversations.map((Conversation c) => c.key), contains('room:${room.roomId}'));
  });

  test('退群：群列表移除，会话也消失', () async {
    final _FakeBiz biz = _FakeBiz();
    final AppState state = _stateOn(biz);
    addTearDown(state.dispose);
    await state.login(email: 'a@b.c', password: 'password1');

    await state.leaveRoom(7);

    expect(state.rooms, isEmpty);
    expect(state.conversations.map((Conversation c) => c.key), isNot(contains('room:7')));
  });

  test('401 一律回登录页并清掉凭据', () async {
    final _FakeBiz biz = _FakeBiz();
    final AppState state = _stateOn(biz);
    addTearDown(state.dispose);
    await state.login(email: 'a@b.c', password: 'password1');
    expect(state.isReady, isTrue);

    biz.unauthorized = true;
    await expectLater(
      state.refreshAll(),
      throwsA(isA<ApiException>().having((ApiException e) => e.code, 'code', 'unauthenticated')),
    );

    expect(state.isReady, isFalse);
    expect(state.loginToken, isNull);
    expect(state.account, isNull);
  });

  test('注册不签发 JWT，注册后自己再登录', () async {
    final _FakeBiz biz = _FakeBiz();
    final AppState state = _stateOn(biz);
    addTearDown(state.dispose);

    await state.register(email: 'new@b.c', password: 'password1', displayName: '新人');
    expect(state.isReady, isFalse, reason: '注册不建立会话');
    expect(biz.registered.single['email'], 'new@b.c');

    await state.login(email: 'new@b.c', password: 'password1');
    expect(state.isReady, isTrue);
  });

  testWidgets('三个主视图靠状态切换，切走时清掉当前会话', (WidgetTester tester) async {
    final AppState state = await _loggedIn();
    await tester.pumpWidget(_shell(state));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('联系人'));
    await tester.pumpAndSettle();
    expect(state.view, 'contacts');
    expect(find.text('好友 1'), findsOneWidget);

    await tester.tap(find.byTooltip('账号'));
    await tester.pumpAndSettle();
    expect(state.view, 'account');
    expect(find.text('当前账号'), findsOneWidget);

    // 选中会话后切到别的视图，当前会话要清掉，回来时不保留旧上下文。
    state.selectConversation('dm:2');
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('联系人'));
    await tester.pumpAndSettle();
    expect(state.activeConversationKey, isNull);
    state.dispose();
  });

  testWidgets('资料页由状态开关，内容只读状态', (WidgetTester tester) async {
    final AppState state = await _loggedIn();
    await tester.pumpWidget(_shell(state));
    await tester.pumpAndSettle();
    expect(find.text('发消息'), findsNothing);

    state.openProfile(2);
    await tester.pumpAndSettle();
    expect(find.text('小助手'), findsWidgets);
    expect(find.text('发消息'), findsOneWidget);

    await tester.tap(find.byTooltip('关闭'));
    await tester.pumpAndSettle();
    expect(state.profileAccountId, isNull);
    expect(find.text('发消息'), findsNothing);
    state.dispose();
  });

  testWidgets('草稿按会话隔离：给 A 打的话不会跟着切到 B', (WidgetTester tester) async {
    final AppState state = await _loggedIn();
    await tester.pumpWidget(_shell(state));
    await tester.pumpAndSettle();

    state.selectConversation('dm:2');
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '给甲的草稿');
    await tester.pump();

    await tester.tap(find.text('月球基地'));
    await tester.pumpAndSettle();

    final TextField composer = tester.widget<TextField>(find.byType(TextField).last);
    expect(composer.controller?.text, isEmpty, reason: '群会话的输入框不该带着私聊的草稿');
    expect(state.messagesOf('room:7'), isEmpty);
    state.dispose();
  });
}

/// 登录后的状态，供 widget 测试用。
Future<AppState> _loggedIn() async {
  final AppState state = _stateOn(_FakeBiz());
  await state.login(email: 'a@b.c', password: 'password1');
  return state;
}

Widget _shell(AppState state) => MaterialApp(
      theme: buildMoonTheme(Brightness.light),
      home: HomeShell(
        state: state,
        onToggleTheme: (Brightness _) {},
        brightness: Brightness.light,
      ),
    );


AppState _stateOn(_FakeBiz biz) => AppState(api: ApiClient(baseUrl: 'http://mock.local', client: biz.client), realtime: _FakeRealtime());

/// 有状态的假 Biz：好友与群会真的增删，用来验「动作 → 重新拉取」这条链。
class _FakeBiz {
  final List<Map<String, Object?>> friends = <Map<String, Object?>>[
    <String, Object?>{
      'peer_account_id': 2,
      'display_name': '小助手',
      'status': 'accepted',
      'incoming': false,
      'requested_at': '2026-11-09T09:00:00Z',
    },
  ];
  final List<Map<String, Object?>> pending = <Map<String, Object?>>[];
  final List<Map<String, Object?>> rooms = <Map<String, Object?>>[
    <String, Object?>{
      'room_id': 7,
      'name': '月球基地',
      'owner_account_id': 1,
      'joined_at': '2026-11-09T10:00:00Z',
    },
  ];
  bool unauthorized = false;
  final List<Map<String, Object?>> registered = <Map<String, Object?>>[];
  int _nextRoom = 8;

  late final MockClient client = MockClient(_handle);

  Future<http.Response> _handle(http.Request req) async {
    if (unauthorized) {
      return _json(<String, Object?>{'code': 'unauthenticated', 'message': 'expired'}, 401);
    }
    final String path = req.url.path;
    final String method = req.method;
    final Map<String, dynamic> body = req.body.isEmpty
        ? <String, dynamic>{}
        : jsonDecode(req.body) as Map<String, dynamic>;

    // 替身也校验契约头：头写错、凭据丢失必须被测试挡下（X-Device-Type 就是这么漏过去的）。
    final bool needsAuth = path != '/api/auth/login' &&
        path != '/api/auth/register' &&
        !(path == '/api/sessions' && body.containsKey('account_key'));
    if (needsAuth) {
      final String? auth = req.headers['authorization'] ?? req.headers['Authorization'];
      if (auth == null || !auth.startsWith('Bearer ') || auth.length <= 7) {
        return _json(<String, Object?>{'code': 'unauthenticated', 'message': 'no token'}, 401);
      }
    }
    if (path.startsWith('/api/conversations/')) {
      final String device = req.headers['x-device-type'] ?? req.headers['X-Device-Type'] ?? '';
      if (!const <String>['desktop', 'browser', 'ios', 'android', 'others'].contains(device)) {
        return _json(
            <String, Object?>{'code': 'validation_failed', 'message': 'device', 'field': 'x-device-type'},
            400);
      }
    }

    if (method == 'POST' && path == '/api/auth/register') {
      registered.add(<String, Object?>{
        'email': body['email'],
        'display_name': body['display_name'],
      });
      return _json(<String, Object?>{
        'account_id': 5,
        'display_name': body['display_name'],
        'type': 'human',
      }, 201);
    }
    if (method == 'POST' && path == '/api/auth/login') {
      if (body['email'] == 'new@b.c') {
        return _json(<String, Object?>{
          'token': 'login-jwt',
          'expires_at': '2026-11-20T00:00:00Z',
          'account': _account(5, '新人'),
        }, 200);
      }
      return _json(<String, Object?>{
        'token': 'login-jwt',
        'expires_at': '2026-11-20T00:00:00Z',
        'account': _account(1, '阿月'),
      }, 200);
    }
    if (method == 'POST' && path == '/api/sessions') {
      return _json(<String, Object?>{
        'account_id': 1,
        'display_name': '阿月',
        'type': 'human',
        'login_token': 'login-jwt',
        'login_expires_at': '2026-11-20T00:00:00Z',
        'turms': <String, Object?>{
          'user_id': 1,
          'credential': 'turms-jwt',
          'gateway_url': 'ws://localhost:20510',
        },
        'expires_at': '2026-11-11T10:00:00Z',
      }, 200);
    }
    if (method == 'GET' && path == '/api/accounts/mine') {
      return _json(<String, Object?>{'items': <Object?>[_account(1, '阿月')]}, 200);
    }
    if (method == 'GET' && path == '/api/friendships') {
      final bool wantPending = req.url.queryParameters['status'] == 'pending';
      return _json(<String, Object?>{'items': wantPending ? pending : friends}, 200);
    }
    if (method == 'POST' && path == '/api/friendships') {
      final int peer = (body['peer_account_id'] as num).toInt();
      pending.add(<String, Object?>{
        'peer_account_id': peer,
        'display_name': '阿星',
        'status': 'pending',
        'incoming': true,
        'requested_at': '2026-11-10T09:00:00Z',
      });
      return _json(<String, Object?>{
        'peer_account_id': peer,
        'status': 'pending',
        'incoming': false,
      }, 201);
    }
    if (method == 'POST' && path.startsWith('/api/friendships/')) {
      final int peer = int.parse(path.split('/').last);
      if (body['action'] == 'accept') {
        pending.removeWhere((Map<String, Object?> f) => f['peer_account_id'] == peer);
        friends.add(<String, Object?>{
          'peer_account_id': peer,
          'display_name': '阿星',
          'status': 'accepted',
          'incoming': false,
          'requested_at': '2026-11-10T09:00:00Z',
        });
        return _json(<String, Object?>{'peer_account_id': peer, 'status': 'accepted'}, 200);
      }
      pending.removeWhere((Map<String, Object?> f) => f['peer_account_id'] == peer);
      return http.Response('', 204);
    }
    if (method == 'DELETE' && path.startsWith('/api/friendships/')) {
      final int peer = int.parse(path.split('/').last);
      friends.removeWhere((Map<String, Object?> f) => f['peer_account_id'] == peer);
      return http.Response('', 204);
    }
    if (method == 'GET' && path == '/api/rooms') {
      return _json(<String, Object?>{'items': rooms}, 200);
    }
    if (method == 'POST' && path == '/api/rooms') {
      final Map<String, Object?> room = <String, Object?>{
        'room_id': _nextRoom++,
        'name': body['name'],
        'owner_account_id': 1,
        'joined_at': '2026-11-10T12:00:00Z',
      };
      rooms.add(room);
      return _json(room, 201);
    }
    if (method == 'DELETE' && path.endsWith('/members/me')) {
      final int roomId = int.parse(path.split('/')[3]);
      rooms.removeWhere((Map<String, Object?> r) => r['room_id'] == roomId);
      return http.Response('', 204);
    }
    if (method == 'GET' && path.startsWith('/api/accounts/')) {
      final int id = int.parse(path.split('/').last);
      return _json(<String, Object?>{
        'account_id': id,
        'display_name': id == 2 ? '小助手' : '阿星',
        'is_friend': id == 2,
      }, 200);
    }
    return _json(<String, Object?>{'code': 'not_found', 'message': 'no route'}, 404);
  }
}

