import 'dart:async';

import 'package:flutter/foundation.dart';

import '../api/api_client.dart';
import '../api/models.dart';
import '../turms/realtime.dart';

enum AuthPhase { loggedOut, busy, ready }

enum MessageState { sending, sent, failed }

/// 会话坐标：私聊是对端账号 id，群聊是 `room_id`（`SCREEN-MAP.md` §2）。
class Conversation {
  Conversation({
    required this.type,
    required this.targetId,
    required this.title,
    this.ownerAccountId,
    this.memberCount,
  });

  final String type; // 'dm' | 'room'
  final int targetId;
  final String title;
  final int? ownerAccountId;
  final int? memberCount;

  String get key => '$type:$targetId';
  bool get isRoom => type == 'room';
}

class ChatMessage {
  ChatMessage({
    required this.localId,
    required this.conversationKey,
    required this.text,
    required this.sentAt,
    required this.state,
    required this.mine,
    this.serverId,
    this.senderName,
  });

  final String localId;
  final String conversationKey;
  String text;
  DateTime sentAt;
  MessageState state;
  final bool mine;
  int? serverId;
  String? senderName;
}

/// 客户端唯一的可变状态源。视图只读它、只调它的动作。
///
/// 读（会话列表 / 历史）本该由 Turms 会话给出，见 `realtime.dart`；
/// 这里只放 REST 能给的东西：身份、账号、好友、群、成员、发送结果。
class AppState extends ChangeNotifier {
  AppState({ApiClient? api, RealtimeClient? realtime})
      : api = api ?? ApiClient(),
        realtime = realtime ?? createRealtime();

  final ApiClient api;

  /// 读取通道：客户端自己的 Turms 会话。
  final RealtimeClient realtime;
  bool realtimeUp = false;

  AuthPhase phase = AuthPhase.loggedOut;
  String? loginToken;
  DateTime? loginExpiresAt;
  Account? account;
  List<Account> accounts = const <Account>[];

  TurmsCredential? turms;

  List<Friendship> friends = const <Friendship>[];
  List<Friendship> pending = const <Friendship>[];
  List<Room> rooms = const <Room>[];

  final Map<int, Paged<RoomMember>> _members = <int, Paged<RoomMember>>{};
  final Map<String, List<ChatMessage>> _messages = <String, List<ChatMessage>>{};

  String? lastError;
  Timer? _renewTimer;

  bool get isReady => phase == AuthPhase.ready;
  bool get isBusy => phase == AuthPhase.busy;

  Paged<RoomMember>? membersOf(int roomId) => _members[roomId];

  List<ChatMessage> messagesOf(String key) => _messages[key] ?? const <ChatMessage>[];

  /// 会话列表：好友 → 私聊，我加入的群 → 群聊。顺序稳定，不按活跃度排。
  List<Conversation> get conversations {
    final List<Conversation> out = <Conversation>[
      for (final Friendship f in friends)
        Conversation(type: 'dm', targetId: f.peerAccountId, title: f.displayName),
      for (final Room r in rooms)
        Conversation(
          type: 'room',
          targetId: r.roomId,
          title: r.name,
          ownerAccountId: r.ownerAccountId,
          memberCount: _members[r.roomId]?.total,
        ),
    ];
    return out;
  }

  Conversation? conversationOf(String key) {
    for (final Conversation c in conversations) {
      if (c.key == key) {
        return c;
      }
    }
    return null;
  }

  // —— 认证 ——

  /// 注册成功后不自动登录（#1 不签发 JWT），调用方自己再调 [login]。
  Future<void> register({
    required String email,
    required String password,
    required String displayName,
  }) async {
    await api.register(email: email, password: password, displayName: displayName);
  }

  Future<void> login({required String email, required String password}) async {
    phase = AuthPhase.busy;
    lastError = null;
    notifyListeners();
    try {
      final LoginResult result = await api.login(email: email, password: password);
      loginToken = result.token;
      loginExpiresAt = result.expiresAt;
      account = result.account;
      await _openSession(result.account.accountId);
      phase = AuthPhase.ready;
      _scheduleLoginRenewal();
    } catch (e) {
      phase = AuthPhase.loggedOut;
      rethrow;
    } finally {
      notifyListeners();
    }
  }

  /// 登录后必须先换 Turms 凭据，再拉账号、好友、群（`HANDOFF.md` §4）。
  Future<void> _openSession(int accountId) async {
    final AccountSession session = await api.sessionForOwner(token: loginToken!, accountId: accountId);
    account = session.account;
    turms = session.turms;
    if (session.loginToken != null) {
      loginToken = session.loginToken;
      loginExpiresAt = session.loginExpiresAt;
    }
    await refreshAll();
    await _connectRealtime();
  }

  /// 登录 / 切账号之后接上该账号的 Turms 会话：收全部会话的推送，历史由客户端自己查。
  Future<void> _connectRealtime() async {
    final TurmsCredential? credential = turms;
    final Account? me = account;
    if (credential == null || me == null) {
      return;
    }
    await realtime.connect(
      credential: credential,
      myAccountId: me.accountId,
      onConnected: (bool up) {
        realtimeUp = up;
        notifyListeners();
      },
      onMessage: _ingest,
      onError: (Object error) {
        realtimeUp = false;
        notifyListeners();
      },
    );
  }

  /// 推送进来的一条消息：按会话坐标落到本地列表，同一个 `messageId` 不重复插入。
  void _ingest(IncomingMessage incoming) {
    final int me = account?.accountId ?? 0;
    if (me == 0) {
      return;
    }
    final String key = incoming.conversationKeyFor(me);
    final List<ChatMessage> list = _messages.putIfAbsent(key, () => <ChatMessage>[]);
    if (incoming.id.isNotEmpty &&
        list.any((ChatMessage m) => m.serverId != null && m.serverId.toString() == incoming.id)) {
      return;
    }
    list.add(ChatMessage(
      localId: 'srv:${incoming.id}',
      conversationKey: key,
      text: incoming.text,
      sentAt: incoming.sentAt ?? DateTime.now().toUtc(),
      state: MessageState.sent,
      mine: incoming.senderId == me,
      serverId: int.tryParse(incoming.id),
    ));
    list.sort((ChatMessage a, ChatMessage b) => a.sentAt.compareTo(b.sentAt));
    notifyListeners();
  }

  /// 打开会话时往回翻一页：游标是最早一条的 `deliveryDate`（Turms 没有消息 id 分页）。
  Future<void> loadHistory(Conversation conv) async {
    final int me = account?.accountId ?? 0;
    if (me == 0) {
      return;
    }
    final List<ChatMessage> existing = _messages[conv.key] ?? const <ChatMessage>[];
    final DateTime? oldest = existing.isEmpty ? null : existing.first.sentAt;
    try {
      final List<IncomingMessage> page = await realtime.history(
        conversationType: conv.type,
        targetId: conv.targetId,
        before: oldest,
      );
      for (final IncomingMessage m in page.reversed) {
        _ingest(m);
      }
    } catch (_) {
      // 读通道不可用时只是没有历史，不影响发送与其它动作。
    }
  }

  /// 清凭据回登录页。
  void logout() {
    _renewTimer?.cancel();
    realtime.disconnect();
    realtimeUp = false;
    loginToken = null;
    loginExpiresAt = null;
    account = null;
    turms = null;
    accounts = const <Account>[];
    friends = const <Friendship>[];
    pending = const <Friendship>[];
    rooms = const <Room>[];
    _members.clear();
    _messages.clear();
    phase = AuthPhase.loggedOut;
    notifyListeners();
  }

  void _scheduleLoginRenewal() {
    _renewTimer?.cancel();
    final DateTime? expires = loginExpiresAt;
    if (expires == null) {
      return;
    }
    final Duration lead = expires.difference(DateTime.now().toUtc()) - const Duration(hours: 1);
    final Duration wait = lead.isNegative ? const Duration(minutes: 5) : lead;
    _renewTimer = Timer(wait, () async {
      try {
        final LoginResult r = await api.refresh(loginToken!);
        loginToken = r.token;
        loginExpiresAt = r.expiresAt;
        _scheduleLoginRenewal();
      } catch (_) {
        logout();
      }
    });
  }

  // —— 账号 ——

  Future<void> refreshAll() async {
    final String token = loginToken!;
    final results = await Future.wait(<Future<Object>>[
      api.mine(token),
      api.friendships(token: token, status: 'accepted'),
      api.friendships(token: token, status: 'pending'),
      api.rooms(token),
    ]);
    accounts = results[0] as List<Account>;
    friends = results[1] as List<Friendship>;
    pending = (results[2] as List<Friendship>).where((Friendship f) => f.incoming).toList();
    rooms = results[3] as List<Room>;
    notifyListeners();
  }

  /// 切到自己名下的另一个账号：与新登录同一条签发路径。
  Future<void> switchAccount(int accountId) async {
    phase = AuthPhase.busy;
    notifyListeners();
    try {
      _members.clear();
      _messages.clear();
      await _openSession(accountId);
      phase = AuthPhase.ready;
    } finally {
      notifyListeners();
    }
  }

  Future<CreatedAgent> createAgent(String displayName) async {
    final CreatedAgent created = await api.createAgent(token: loginToken!, displayName: displayName);
    accounts = await api.mine(loginToken!);
    notifyListeners();
    return created;
  }

  Future<Profile> profile(int accountId) => api.profile(token: loginToken!, accountId: accountId);

  // —— 好友 ——

  Future<void> requestFriend(int peerAccountId) async {
    await api.requestFriend(token: loginToken!, peerAccountId: peerAccountId);
    await refreshAll();
  }

  Future<void> respondFriend(int peerAccountId, String action) async {
    await api.respondFriend(token: loginToken!, peerAccountId: peerAccountId, action: action);
    await refreshAll();
  }

  Future<void> deleteFriend(int peerAccountId) async {
    await api.deleteFriend(token: loginToken!, peerAccountId: peerAccountId);
    await refreshAll();
  }

  // —— 群 ——

  Future<Room> createRoom(String name) async {
    final Room room = await api.createRoom(token: loginToken!, name: name);
    await refreshAll();
    return room;
  }

  Future<void> addMember(int roomId, int accountId) async {
    await api.addMember(token: loginToken!, roomId: roomId, accountId: accountId);
    await loadMembers(roomId, force: true);
    notifyListeners();
  }

  Future<void> leaveRoom(int roomId) async {
    await api.leaveRoom(token: loginToken!, roomId: roomId);
    _members.remove(roomId);
    await refreshAll();
  }

  Future<void> removeMember(int roomId, int accountId) async {
    await api.removeMember(token: loginToken!, roomId: roomId, accountId: accountId);
    await loadMembers(roomId, force: true);
    notifyListeners();
  }

  Future<Paged<RoomMember>> loadMembers(int roomId, {bool force = false}) async {
    if (!force && _members.containsKey(roomId)) {
      return _members[roomId]!;
    }
    final Paged<RoomMember> page = await api.members(token: loginToken!, roomId: roomId);
    _members[roomId] = page;
    return page;
  }

  // —— 发言 ——

  /// 本地先插「发送中」，成功后用服务端 `sent_at` 落定；失败保留正文可重试。
  Future<void> sendMessage(Conversation conv, String text) async {
    final String body = text.trim();
    if (body.isEmpty) {
      return;
    }
    final ChatMessage local = ChatMessage(
      localId: '${DateTime.now().microsecondsSinceEpoch}-${conv.key}',
      conversationKey: conv.key,
      text: body,
      sentAt: DateTime.now().toUtc(),
      state: MessageState.sending,
      mine: true,
    );
    _append(local);
    try {
      final SentMessage sent =
          await api.sendMessage(token: loginToken!, type: conv.type, id: conv.targetId, text: body);
      local
        ..state = MessageState.sent
        ..serverId = sent.messageId
        ..sentAt = sent.sentAt ?? local.sentAt;
    } catch (e) {
      local.state = MessageState.failed;
      rethrow;
    } finally {
      notifyListeners();
    }
  }

  Future<void> retryMessage(Conversation conv, ChatMessage message) async {
    message.state = MessageState.sending;
    notifyListeners();
    try {
      final SentMessage sent =
          await api.sendMessage(token: loginToken!, type: conv.type, id: conv.targetId, text: message.text);
      message
        ..state = MessageState.sent
        ..serverId = sent.messageId
        ..sentAt = sent.sentAt ?? message.sentAt;
    } catch (e) {
      message.state = MessageState.failed;
      rethrow;
    } finally {
      notifyListeners();
    }
  }

  void _append(ChatMessage message) {
    final List<ChatMessage> list = _messages.putIfAbsent(message.conversationKey, () => <ChatMessage>[]);
    list.add(message);
    notifyListeners();
  }

  @override
  void dispose() {
    _renewTimer?.cancel();
    api.close();
    super.dispose();
  }
}
