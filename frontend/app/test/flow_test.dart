import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:moonchat/api/api_client.dart';
import 'package:moonchat/api/models.dart';
import 'package:moonchat/state/app_state.dart';
import 'package:moonchat/turms/realtime.dart';

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
}
