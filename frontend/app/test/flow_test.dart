import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mondchat/api/api_client.dart';
import 'package:mondchat/api/models.dart';
import 'package:mondchat/main.dart';
import 'package:mondchat/session/session_store.dart';
import 'package:mondchat/state/app_state.dart';
import 'package:mondchat/theme.dart';
import 'package:mondchat/turms/realtime.dart';
import 'package:mondchat/ui/home_shell.dart';
import 'package:mondchat/ui/profile_panel.dart';

/// 读取通道在测试里不连 Turms：只验证 REST 链路与状态机。
class _FakeRealtime implements RealtimeClient {
  bool connected = false;
  int? connectedAccountId;
  void Function(IncomingMessage message)? _onMessage;
  void Function(Object error)? _onError;

  /// 每次 `history()` 收到的游标与目标 id，以及要返回的页（按调用顺序消费）。
  final List<DateTime?> beforeCursors = <DateTime?>[];
  final List<String> targetIds = <String>[];
  final List<List<IncomingMessage>> pages = <List<IncomingMessage>>[];

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
    connectedAccountId = myAccountId;
    _onMessage = onMessage;
    _onError = onError;
    onConnected?.call(true);
  }

  /// 模拟服务端推来一条消息。
  void emit(IncomingMessage message) => _onMessage?.call(message);

  /// 模拟读通道报错（断线/凭据失效）。
  void fail(Object error) => _onError?.call(error);

  @override
  Future<List<IncomingMessage>> history({
    required String conversationType,
    required String targetId,
    DateTime? before,
    int maxCount = 50,
  }) async {
    targetIds.add(targetId);
    beforeCursors.add(before);
    if (pages.isEmpty) {
      return const <IncomingMessage>[];
    }
    return pages.removeAt(0);
  }

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

/// 假 Biz：只实现客户端会打到的那几条，字段与 `docs/truth/backend/README.md` 一致。
MockClient _mockBiz({int sendStatus = 201, int Function()? statusOf}) {
  return MockClient((http.Request req) async {
    final String path = req.url.path;
    final String method = req.method;

    // 发送路径也要校验契约头：token 掉了、设备头写错，测试必须红（`X-Device-Type` 就是这么漏过去的）。
    if (path.startsWith('/api/conversations/')) {
      expect(req.headers['authorization'] ?? req.headers['Authorization'], startsWith('Bearer '));
      expect(
        const <String>['desktop', 'browser', 'ios', 'android', 'others']
            .contains(req.headers['x-device-type'] ?? req.headers['X-Device-Type']),
        isTrue,
        reason: 'X-Device-Type 必须是写入网关认的枚举',
      );
    }

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
            'turms_group_id': '7000000000000000007',
          },
        ],
      }, 200);
    }
    if (method == 'POST' && path.startsWith('/api/conversations/')) {
      final int status = statusOf?.call() ?? sendStatus;
      if (status != 201) {
        return _json(<String, Object?>{'code': 'rate_limited', 'message': 'too many'}, status);
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

AppState _newState({int sendStatus = 201, int Function()? statusOf, _FakeRealtime? realtime}) {
  return AppState(
    api: ApiClient(
      baseUrl: 'http://mock.local',
      client: _mockBiz(sendStatus: sendStatus, statusOf: statusOf),
    ),
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

  test('群推送按 turms_group_id 归到 room:<room_id>，群历史用句柄查', () async {
    final _FakeRealtime realtime = _FakeRealtime();
    final AppState state = _newState(realtime: realtime);
    addTearDown(state.dispose);
    await state.login(email: 'a@b.c', password: 'password1');

    realtime.emit(const IncomingMessage(
      id: '9001',
      text: '群里说的',
      senderId: 2,
      groupId: '7000000000000000007',
      sentAt: null,
    ));
    expect(state.messagesOf('room:7').length, 1, reason: 'Turms 群 id 要映射回 PG room_id');

    final Conversation room = state.conversations.firstWhere((Conversation c) => c.isRoom);
    await state.loadHistory(room);
    expect(realtime.targetIds.last, '7000000000000000007', reason: '群历史查的是 Turms 句柄');
  });

  test('发好友申请后重新拉取，outgoing 不混进待处理', () async {
    final _FakeBiz biz = _FakeBiz();
    final AppState state = _stateOn(biz);
    addTearDown(state.dispose);
    await state.login(email: 'a@b.c', password: 'password1');
    expect(state.pending, isEmpty);

    await state.requestFriend(4);

    // GET /api/friendships?status=pending 只返回发给我的申请（§5.1），
    // 我发出去的那条不能出现在 state.pending 里。
    expect(biz.outgoing.single['peer_account_id'], 4);
    expect(state.pending, isEmpty);
  });

  test('同意申请：申请移出待处理、进好友列表', () async {
    final _FakeBiz biz = _FakeBiz();
    biz.pending.add(<String, Object?>{
      'peer_account_id': 4,
      'display_name': '阿星',
      'status': 'pending',
      'incoming': true,
      'requested_at': '2026-11-10T09:00:00Z',
    });
    final AppState state = _stateOn(biz);
    addTearDown(state.dispose);
    await state.login(email: 'a@b.c', password: 'password1');

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

  test('退群：群列表移除，当前群会话也清掉', () async {
    final _FakeBiz biz = _FakeBiz();
    final AppState state = _stateOn(biz);
    addTearDown(state.dispose);
    await state.login(email: 'a@b.c', password: 'password1');
    state.selectConversation('room:7');

    await state.leaveRoom(7);

    expect(state.rooms, isEmpty);
    expect(state.conversations.map((Conversation c) => c.key), isNot(contains('room:7')));
    expect(state.activeConversationKey, isNull, reason: '窄屏不能停在一个已经不存在的会话上');
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

  testWidgets('窄屏下联系人与账号上下堆叠，不横向溢出', (WidgetTester tester) async {
    // 正好 620 也要堆叠（docs/truth/frontend/design.md 的 ≤620）；再缩到 390 验窄屏不溢出。
    tester.view.physicalSize = const Size(620, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final AppState state = await _loggedIn();
    await tester.pumpWidget(_shell(state));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('联系人'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    // 没有选中会话时列表就是唯一导航，不能再给「收起会话列表」。
    expect(find.byTooltip('收起会话列表'), findsNothing);
    state.setSelectedContact(2);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    // 详情要真的渲染出来，否则「不溢出」是空转；位置也要在列表下方，而不是并排。
    expect(find.text('发消息'), findsOneWidget, reason: '窄屏下详情也要真的渲染出来');
    expect(
      tester.getTopLeft(find.byType(ProfilePanel)).dy,
      greaterThan(tester.getTopLeft(find.text('联系人')).dy),
      reason: '详情在列表下方，不是并排',
    );

    tester.view.physicalSize = const Size(390, 844);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tester.tap(find.byTooltip('账号'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    state.dispose();
  });

  testWidgets('窄屏建群表单展开且高度被键盘压缩时联系人不溢出', (WidgetTester tester) async {
    // 390×500 模拟移动端键盘弹出后的正文高度：固定头 + 表单曾会把 Column 撑爆。
    tester.view.physicalSize = const Size(390, 500);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final AppState state = await _loggedIn();
    await tester.pumpWidget(_shell(state));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('联系人'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('建群'));
    await tester.pumpAndSettle();
    expect(find.text('创建'), findsOneWidget);
    expect(tester.takeException(), isNull);
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

  test('历史往前翻：首屏无游标，第二次取最早一条减 1ms，空页收尾', () async {
    final _FakeRealtime rt = _FakeRealtime();
    final AppState state = _newState(realtime: rt);
    addTearDown(state.dispose);
    await state.login(email: 'a@b.c', password: 'password1');
    final Conversation dm = state.conversations.first;

    rt.pages.add(<IncomingMessage>[
      const IncomingMessage(
        id: '501',
        text: '早一点',
        senderId: 2,
        recipientId: 1,
        sentAt: null,
      ),
      IncomingMessage(
        id: '502',
        text: '晚一点',
        senderId: 2,
        recipientId: 1,
        sentAt: DateTime.parse('2026-11-10T09:01:00Z'),
      ),
    ]);
    rt.pages.add(<IncomingMessage>[
      IncomingMessage(
        id: '500',
        text: '更早一条',
        senderId: 2,
        recipientId: 1,
        sentAt: DateTime.parse('2026-11-10T08:00:00Z'),
      ),
    ]);

    await state.loadHistory(dm);
    expect(rt.beforeCursors.first, isNull, reason: '首屏没有游标');
    expect(rt.targetIds.first, '2', reason: '私聊查的是对端账号 id');
    expect(state.messagesOf(dm.key).length, 2);
    expect(state.isHistoryDone(dm.key), isFalse);

    // 第二次：游标必须是「最早一条（09:01）减 1ms」——闭区间的边界消息要排除掉。
    await state.loadHistory(dm);
    expect(rt.beforeCursors[1], DateTime.parse('2026-11-10T09:00:59.999Z'));
    expect(state.messagesOf(dm.key).length, 3);

    // 第三次返回空页：到底，之后再调用不再打请求。
    await state.loadHistory(dm);
    expect(state.isHistoryDone(dm.key), isTrue);
    final int calls = rt.beforeCursors.length;
    await state.loadHistory(dm);
    expect(rt.beforeCursors.length, calls, reason: '到底后不该再查');
  });

  test('读通道报错时 realtimeUp 变 false，历史不再被误判为到底', () async {
    final _FakeRealtime rt = _FakeRealtime();
    final AppState state = _newState(realtime: rt);
    addTearDown(state.dispose);
    await state.login(email: 'a@b.c', password: 'password1');
    expect(state.realtimeUp, isTrue);

    rt.fail(StateError('socket closed'));

    expect(state.realtimeUp, isFalse);
    // 未连上时不发请求，也不把「空」写成到底。
    await state.loadHistory(state.conversations.first);
    expect(rt.beforeCursors, isEmpty);
    expect(state.isHistoryDone(state.conversations.first.key), isFalse);
  });

  test('失败消息重试成功：同一个气泡变成已发送', () async {
    int status = 429;
    final AppState state = _newState(statusOf: () => status);
    addTearDown(state.dispose);
    await state.login(email: 'a@b.c', password: 'password1');
    final Conversation dm = state.conversations.first;

    await expectLater(state.sendMessage(dm, '重试我'), throwsA(isA<ApiException>()));
    final ChatMessage bubble = state.messagesOf(dm.key).single;
    expect(bubble.state, MessageState.failed);

    status = 201;
    await state.retryMessage(dm, bubble);
    expect(state.messagesOf(dm.key).single.state, MessageState.sent);
    expect(state.messagesOf(dm.key).single.serverId, 9001);
    // message_id 在 Web 上会丢精度，精确去重键等 Turms 推送回来再填。
    expect(state.messagesOf(dm.key).single.serverIdText, isNull);
  });

  test('自己消息推送回来认领本地气泡，不插重复', () async {
    final _FakeRealtime rt = _FakeRealtime();
    final AppState state = _newState(realtime: rt);
    addTearDown(state.dispose);
    await state.login(email: 'a@b.c', password: 'password1');
    final Conversation dm = state.conversations.first;

    await state.sendMessage(dm, '回声');
    expect(state.messagesOf(dm.key).single.serverIdText, isNull);

    rt.emit(const IncomingMessage(
      id: '1881590000000000001',
      text: '回声',
      senderId: 1,
      recipientId: 2,
      sentAt: null,
    ));
    expect(state.messagesOf(dm.key), hasLength(1), reason: '同一条消息不能一真一假两条');
    expect(state.messagesOf(dm.key).single.serverIdText, '1881590000000000001');
  });

  test('切进 agent 后还能切回真人：账号列表用归属者 token 查', () async {
    final AppState state = _stateOn(_FakeBiz());
    addTearDown(state.dispose);
    await state.login(email: 'a@b.c', password: 'password1');

    await state.switchAccount(2);
    expect(state.loginToken, 'login-jwt-2');
    expect(state.accounts.length, 2, reason: 'agent 视角的 mine 只回它自己，切号列表会丢真人');

    // 切回来必须用归属者的 JWT，而不是 agent 的 JWT。
    await state.switchAccount(1);
    expect(state.account?.accountId, 1);
    expect(state.loginToken, 'login-jwt-1');
  });

  test('401 之后读通道要拆掉，本地消息清空', () async {
    final _FakeRealtime rt = _FakeRealtime();
    final _FakeBiz biz = _FakeBiz();
    final AppState state = _stateOn(biz, realtime: rt);
    addTearDown(state.dispose);
    await state.login(email: 'a@b.c', password: 'password1');
    expect(rt.connected, isTrue);

    biz.unauthorized = true;
    await expectLater(state.refreshAll(), throwsA(isA<ApiException>()));

    expect(rt.connected, isFalse, reason: '登出要断开读通道');
    expect(state.realtimeUp, isFalse);
    expect(state.turms, isNull);
    expect(state.messagesOf('dm:2'), isEmpty);
  });

  test('切账号会带着新账号重连读通道，并清掉上一个账号的消息', () async {
    final _FakeRealtime rt = _FakeRealtime();
    final AppState state = _stateOn(_FakeBiz(), realtime: rt);
    addTearDown(state.dispose);
    await state.login(email: 'a@b.c', password: 'password1');
    expect(rt.connectedAccountId, 1);

    rt.emit(const IncomingMessage(id: '900', text: '甲的消息', senderId: 2, recipientId: 1, sentAt: null));
    expect(state.messagesOf('dm:2').length, 1);

    await state.switchAccount(2);

    expect(rt.connectedAccountId, 2, reason: '要用新账号的凭据重连');
    expect(state.messagesOf('dm:2'), isEmpty, reason: '上一个账号的缓存不能留');
  });

  test('登录后记住本机凭据，刷新用同一份凭据直接恢复会话', () async {
    final _FakeBiz biz = _FakeBiz();
    final _MemorySessionStore session = _MemorySessionStore();
    final AppState first = _stateOn(biz, session: session);
    await first.login(email: 'a@b.c', password: 'password1');
    expect(session.session?.token, 'login-jwt');
    expect(session.session?.accountId, 1);
    first.dispose();

    // 新实例 = 刷新页面：手里只有本机那串令牌，没有密码。
    final AppState restored = _stateOn(_FakeBiz(), session: session);
    addTearDown(restored.dispose);
    await restored.restore();

    expect(restored.isReady, isTrue);
    expect(restored.account?.accountId, 1);
  });

  testWidgets('刷新后恢复会话直接进主界面，不再闪登录表单', (WidgetTester tester) async {
    final _MemorySessionStore session = _MemorySessionStore()
      ..session = const StoredSession(token: 'login-jwt', accountId: 1);
    final AppState state = _stateOn(_FakeBiz(), session: session);
    addTearDown(state.dispose);

    // 外壳自己在 initState 里调 restore()：没有登舱过渡可播，恢复完就得直接交棒。
    await tester.pumpWidget(MondChatApp(state: state));
    for (int i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 20));
      expect(find.text('登录'), findsNothing, reason: '恢复会话期间不能闪登录表单');
    }
    await tester.pumpAndSettle();

    expect(state.isReady, isTrue);
    expect(find.byType(HomeShell), findsOneWidget);
    state.dispose();
  });

  test('本机记住的令牌失效：清掉副本并回登录页', () async {    final _MemorySessionStore session = _MemorySessionStore()
      ..session = const StoredSession(token: 'stale', accountId: 1);
    final AppState state = _stateOn(_FakeBiz()..unauthorized = true, session: session);
    addTearDown(state.dispose);

    await state.restore();

    expect(state.isReady, isFalse);
    expect(session.session, isNull, reason: '失效凭据不能一直留在本机');
  });

  test('关系列表靠轮询更新：别人发来的申请与别的群会出现', () async {
    final _FakeBiz biz = _FakeBiz();
    final AppState state = _stateOn(biz);
    addTearDown(state.dispose);
    await state.login(email: 'a@b.c', password: 'password1');

    int notified = 0;
    state.addListener(() => notified++);
    await state.refreshRelations();
    expect(notified, 0, reason: '没变化就不要通知，避免整棵树每轮重建');

    // 别人那边改出来的数据：没有推送，只有重拉才看得见。
    biz.pending.add(<String, Object?>{
      'peer_account_id': 3,
      'display_name': '阿星',
      'status': 'pending',
      'incoming': true,
      'requested_at': '2026-11-10T09:00:00Z',
    });
    biz.rooms.add(<String, Object?>{
      'room_id': 9,
      'name': '别人的群',
      'owner_account_id': 4,
      'joined_at': '2026-11-10T10:00:00Z',
      'turms_group_id': '7000000000000000009',
    });
    await state.refreshRelations();

    expect(notified, 1);
    expect(state.pending.single.peerAccountId, 3);
    expect(state.conversations.map((Conversation c) => c.key), contains('room:9'));
  });

  testWidgets('Enter 发送，Shift+Enter 只换行', (WidgetTester tester) async {
    final AppState state = await _loggedIn();
    await tester.pumpWidget(_shell(state));
    await tester.pumpAndSettle();

    state.selectConversation('dm:2');
    await tester.pumpAndSettle();

    final Finder composer = find.byType(TextField).last;
    await tester.enterText(composer, '晚安');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(state.messagesOf('dm:2').single.text, '晚安');
    expect(tester.widget<TextField>(composer).controller?.text, isEmpty);

    await tester.enterText(composer, '第二行');
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pumpAndSettle();

    expect(state.messagesOf('dm:2').length, 1, reason: 'Shift+Enter 是换行，不能发出去');
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
      locale: const Locale('zh', 'CN'),
      supportedLocales: const <Locale>[Locale('zh', 'CN')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: HomeShell(
        state: state,
        onToggleTheme: (Brightness _) {},
        brightness: Brightness.light,
        textScale: 1.0,
        onLanguageChanged: (String _) {},
        onTextScaleChanged: (double _) {},
      ),
    );


AppState _stateOn(_FakeBiz biz, {_FakeRealtime? realtime, SessionStore? session}) => AppState(
      api: ApiClient(baseUrl: 'http://mock.local', client: biz.client),
      realtime: realtime ?? _FakeRealtime(),
      session: session,
    );

/// 假的会话存储：只在本测试进程里记住一份。
class _MemorySessionStore implements SessionStore {
  StoredSession? session;

  @override
  StoredSession? load() => session;

  @override
  void save(StoredSession value) => session = value;

  @override
  void clear() => session = null;
}

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
  final List<Map<String, Object?>> outgoing = <Map<String, Object?>>[];
  final List<Map<String, Object?>> rooms = <Map<String, Object?>>[
    <String, Object?>{
      'room_id': 7,
      'name': '月球基地',
      'owner_account_id': 1,
      'joined_at': '2026-11-09T10:00:00Z',
      'turms_group_id': '7000000000000000007',
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
      final List<String> parts = path.split('/');
      return _json(<String, Object?>{
        'message_id': 9001,
        'conversation': <String, Object?>{'type': parts[3], 'id': int.parse(parts[4])},
        'sent_at': '2026-11-10T12:00:00Z',
      }, 201);
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
      // 回显请求的 account_id：写死的话，切账号/多账号的用例永远看不出身份错位。
      final int id = (body['account_id'] as num?)?.toInt() ?? 1;
      final String auth = req.headers['authorization'] ?? req.headers['Authorization'] ?? '';
      // agent 的 JWT 切不回它归属者的真人账号；真实服务端也会 403。
      if (auth == 'Bearer login-jwt-2' && id != 2) {
        return _json(<String, Object?>{'code': 'forbidden', 'message': '这个账号不在你名下'}, 403);
      }
      return _json(<String, Object?>{
        'account_id': id,
        'display_name': id == 1 ? '阿月' : '小助手',
        'type': id == 1 ? 'human' : 'agent',
        'login_token': 'login-jwt-$id',
        'login_expires_at': '2027-11-20T00:00:00Z',
        'turms': <String, Object?>{
          'user_id': id,
          'credential': 'turms-jwt-$id',
          'gateway_url': 'ws://localhost:20510',
        },
        'expires_at': '2027-11-11T10:00:00Z',
      }, 200);
    }
    if (method == 'GET' && path == '/api/accounts/mine') {
      final String auth = req.headers['authorization'] ?? req.headers['Authorization'] ?? '';
      // 与真实 #4 一致：按当前账号查，agent 查不到归属者的账号。
      final bool asAgent = auth == 'Bearer login-jwt-2';
      return _json(<String, Object?>{
        'items': asAgent
            ? <Object?>[_account(2, '小助手', type: 'agent')]
            : <Object?>[_account(1, '阿月'), _account(2, '小助手', type: 'agent')],
      }, 200);
    }
    if (method == 'GET' && path == '/api/friendships') {
      final bool wantPending = req.url.queryParameters['status'] == 'pending';
      return _json(<String, Object?>{'items': wantPending ? pending : friends}, 200);
    }
    if (method == 'POST' && path == '/api/friendships') {
      final int peer = (body['peer_account_id'] as num).toInt();
      outgoing.add(<String, Object?>{
        'peer_account_id': peer,
        'display_name': '阿星',
        'status': 'pending',
        'incoming': false,
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
      final int roomId = _nextRoom++;
      final Map<String, Object?> room = <String, Object?>{
        'room_id': roomId,
        'name': body['name'],
        'owner_account_id': 1,
        // 建群响应只有 created_at；joined_at 只出现在 GET /api/rooms 的列表里。
        'created_at': '2026-11-10T12:00:00Z',
        'turms_group_id': '7000000000000000$roomId',
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

