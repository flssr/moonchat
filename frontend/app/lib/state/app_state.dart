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
    this.turmsGroupId,
  });

  final String type; // 'dm' | 'room'
  final int targetId;
  final String title;
  final int? ownerAccountId;
  final int? memberCount;

  /// 群会话的 Turms 句柄：查历史与归并推送用，不参与 Biz 写接口。
  final String? turmsGroupId;

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
    this.serverIdText,
    this.senderName,
  });

  final String localId;
  final String conversationKey;
  String text;
  DateTime sentAt;
  MessageState state;
  final bool mine;

  /// 雪花 id 超过 JS 的 2^53，`int` 在 Web 上会丢精度；比较一律用 [serverIdText]。
  int? serverId;
  String? serverIdText;
  String? senderName;
}

/// 客户端唯一的可变状态源。视图只读它、只调它的动作。
///
/// 读（会话列表 / 历史）本该由 Turms 会话给出，见 `realtime.dart`；
/// 这里只放 REST 能给的东西：身份、账号、好友、群、成员、发送结果。
class AppState extends ChangeNotifier {
  AppState({ApiClient? api, RealtimeClient? realtime})
      : api = api ?? ApiClient(),
        realtime = realtime ?? createRealtime() {
    // 401 一律回登录页（`docs/frontend/API-MAPPING.md` §4）：凭据没了就别再让界面假装还在线。
    this.api.onUnauthenticated = logout;
  }

  final ApiClient api;

  /// 读取通道：客户端自己的 Turms 会话。
  final RealtimeClient realtime;
  bool realtimeUp = false;

  AuthPhase phase = AuthPhase.loggedOut;

  /// 切账号进行中：外壳保持挂载，只显示忙碌态。
  bool switching = false;

  /// 归属者的登录 JWT：切号与 `GET /api/accounts/mine` 永远用它。
  /// 切进 agent 后 `loginToken` 会变成该 agent 的 JWT，但 agent 不能替归属者再切号。
  String? identityToken;

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

  /// Turms group id → PG room id：群推送归并与群历史查询都靠它。
  final Map<String, int> _roomIdByTurmsGroupId = <String, int>{};

  Timer? _renewTimer;
  Timer? _turmsTimer;

  // —— 导航状态：唯一一份，登出与切账号都会复位 ——
  /// 当前视图：`messages` / `contacts` / `account`（`SCREEN-MAP.md` §2）。
  String view = 'messages';
  String? activeConversationKey;
  String filter = 'all'; // all | dm | room
  String contactsTab = 'friends'; // friends | pending
  int? selectedContactId;

  /// 资料页正在看的账号；null 表示没开。
  int? profileAccountId;

  void showView(String v) {
    view = v;
    if (v != 'messages') {
      activeConversationKey = null;
    }
    notifyListeners();
  }

  void selectConversation(String? key) {
    view = 'messages';
    activeConversationKey = key;
    if (key != null) {
      // 重新打开会话时允许再试一次历史（上次可能只是读通道没连上）。
      _historyFailed.remove(key);
    }
    notifyListeners();
  }

  void setFilter(String f) {
    filter = f;
    notifyListeners();
  }

  void setContactsTab(String t) {
    contactsTab = t;
    notifyListeners();
  }

  void setSelectedContact(int? id) {
    selectedContactId = id;
    notifyListeners();
  }

  void openProfile(int id) {
    profileAccountId = id;
    notifyListeners();
  }

  void closeProfile() {
    profileAccountId = null;
    notifyListeners();
  }

  void _resetNavigation() {
    view = 'messages';
    activeConversationKey = null;
    filter = 'all';
    contactsTab = 'friends';
    selectedContactId = null;
    profileAccountId = null;
  }

  /// 历史翻页的运行状态：同一个会话不并发拉；空页即到底；失败后先不重试。
  final Set<String> _historyLoading = <String>{};
  final Set<String> _historyDone = <String>{};
  final Set<String> _historyFailed = <String>{};

  /// Turms 续期失败后的重试计数：连续失败 3 次才认为读通道不可用。
  int _turmsRenewFailures = 0;

  bool _disposed = false;

  // 资料页与群详情的缓存：视图只读，不再各自请求（避免 token 与错误映射出现第二份）。
  final Map<int, Profile> _profiles = <int, Profile>{};
  final Map<int, RoomDetail> _roomDetails = <int, RoomDetail>{};

  bool get isReady => phase == AuthPhase.ready;
  bool get isBusy => phase == AuthPhase.busy;

  /// 晚到的异步回调可能在 dispose 之后才 notify：统一在这里挡掉。
  @override
  void notifyListeners() {
    if (_disposed) {
      return;
    }
    super.notifyListeners();
  }

  Paged<RoomMember>? membersOf(int roomId) => _members[roomId];

  Profile? profileOf(int accountId) => _profiles[accountId];

  RoomDetail? roomOf(int roomId) => _roomDetails[roomId];

  /// 资料页取数：视图只读 `profileOf`，写只走这里。
  Future<Profile> loadProfile(int accountId) async {
    final Profile p = await api.profile(token: loginToken!, accountId: accountId);
    _profiles[accountId] = p;
    notifyListeners();
    return p;
  }

  /// 群详情取数（成员数、群主）。
  Future<RoomDetail> loadRoom(int roomId) async {
    final RoomDetail d = await api.room(token: loginToken!, roomId: roomId);
    _roomDetails[roomId] = d;
    notifyListeners();
    return d;
  }

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
          turmsGroupId: r.turmsGroupId,
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
    notifyListeners();
    try {
      final LoginResult result = await api.login(email: email, password: password);
      identityToken = result.token;
      loginToken = result.token;
      loginExpiresAt = result.expiresAt;
      account = result.account;
      await _openSession(result.account.accountId);
      phase = AuthPhase.ready;
      _scheduleLoginRenewal();
    } catch (e) {
      // 会话可能已经建了一半（token、读通道、推送订阅）：清干净再回登录页。
      logout();
      rethrow;
    } finally {
      notifyListeners();
    }
  }

  /// 登录后必须先换 Turms 凭据，再拉账号、好友、群（`HANDOFF.md` §4）。
  Future<void> _openSession(int accountId) async {
    // 用归属者 JWT 换目标账号的会话；切进 agent 后仍靠它切回来。
    final AccountSession session = await api.sessionForOwner(token: identityToken!, accountId: accountId);
    account = session.account;
    turms = session.turms;
    if (session.loginToken != null) {
      loginToken = session.loginToken;
      loginExpiresAt = session.loginExpiresAt;
    }
    await refreshAll();
    await _connectRealtime();
    _scheduleTurmsRenewal();
  }

  /// Turms 凭据 12 小时过期，到期前重调 `POST /api/sessions` 换新的并重连
  /// （`account-and-ownership.md`「凭据有两种时长」：这一步无状态、可重复调用）。
  void _scheduleTurmsRenewal() {
    _turmsTimer?.cancel();
    final DateTime? expires = turms?.expiresAt;
    final Account? me = account;
    if (expires == null || me == null) {
      return;
    }
    final Duration lead = expires.difference(DateTime.now().toUtc()) - const Duration(minutes: 30);
    final Duration wait = lead.isNegative ? const Duration(minutes: 5) : lead;
    _turmsTimer = Timer(wait, () async {
      try {
        final AccountSession session =
            await api.sessionForOwner(token: loginToken!, accountId: me.accountId);
        turms = session.turms;
        if (session.loginToken != null) {
          loginToken = session.loginToken;
          loginExpiresAt = session.loginExpiresAt;
        }
        _turmsRenewFailures = 0;
        await _connectRealtime();
        _scheduleTurmsRenewal();
      } catch (_) {
        // 单次续期失败不等于读通道死了：先按 1 分钟退避重试，连续 3 次才认输。
        _turmsRenewFailures++;
        if (_turmsRenewFailures >= 3) {
          realtimeUp = false;
          notifyListeners();
          return;
        }
        _turmsTimer = Timer(const Duration(minutes: 1), _scheduleTurmsRenewal);
      }
    });
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

  /// 推送进来的一条消息：按会话坐标落到本地列表，同一条只落一次。
  void _ingest(IncomingMessage incoming) {
    final int me = account?.accountId ?? 0;
    if (me == 0) {
      return;
    }
    final String key;
    if (incoming.groupId != null) {
      final int? roomId = _roomIdByTurmsGroupId[incoming.groupId];
      if (roomId == null) {
        // 这个群还没出现在「我的群」里（刚被拉入、客户端尚未刷新）：先不落，
        // 刷新后历史会把这段时间的消息补进来。
        return;
      }
      key = 'room:$roomId';
    } else {
      key = incoming.conversationKeyFor(me);
      if (key.isEmpty) {
        return;
      }
    }
    final List<ChatMessage> list = _messages.putIfAbsent(key, () => <ChatMessage>[]);
    if (incoming.id.isNotEmpty &&
        list.any((ChatMessage m) => m.serverIdText == incoming.id)) {
      return;
    }
    // Turms 会把发送者自己的消息也推回来。若本地那条「发送中」还没拿到 REST 回执，
    // 认领它而不是再插一条，否则同一个气泡会一真一假地留在列表里。
    if (incoming.id.isNotEmpty) {
      for (final ChatMessage m in list) {
        if (m.serverIdText == null && m.mine && m.text == incoming.text) {
          m
            ..serverIdText = incoming.id
            ..serverId = int.tryParse(incoming.id)
            ..sentAt = incoming.sentAt ?? m.sentAt
            ..state = MessageState.sent;
          list.sort((ChatMessage a, ChatMessage b) => a.sentAt.compareTo(b.sentAt));
          notifyListeners();
          return;
        }
      }
    }
    list.add(ChatMessage(
      localId: 'srv:${incoming.id}',
      conversationKey: key,
      text: incoming.text,
      sentAt: incoming.sentAt ?? DateTime.now().toUtc(),
      state: MessageState.sent,
      mine: incoming.senderId == me,
      serverId: int.tryParse(incoming.id),
      serverIdText: incoming.id.isEmpty ? null : incoming.id,
    ));
    list.sort((ChatMessage a, ChatMessage b) => a.sentAt.compareTo(b.sentAt));
    notifyListeners();
  }

  /// 打开会话时往回翻一页：游标是最早一条的 `deliveryDate`（Turms 没有消息 id 分页）。
  /// 反复调用就是持续往前翻，翻到空页就认为到底了。
  Future<void> loadHistory(Conversation conv) async {
    final int me = account?.accountId ?? 0;
    // 读通道没连上时 `history()` 返回空数组，那不是「到底了」——不能据此写死 `_historyDone`，
    // 否则凭据续期/重连窗口里打开过的会话，重登后永远拉不到历史。
    if (me == 0 ||
        !realtimeUp ||
        _historyLoading.contains(conv.key) ||
        _historyDone.contains(conv.key) ||
        _historyFailed.contains(conv.key)) {
      return;
    }
    // 群历史查的是 Turms 的 group id，不是 room_id；句柄还没回填就先不查。
    final String targetId;
    if (conv.isRoom) {
      final String? handle = conv.turmsGroupId;
      if (handle == null || handle.isEmpty) {
        return;
      }
      targetId = handle;
    } else {
      targetId = '${conv.targetId}';
    }
    _historyLoading.add(conv.key);
    final List<ChatMessage> existing = _messages[conv.key] ?? const <ChatMessage>[];
    // 游标只认服务端确认过的消息：乐观消息的时间戳是客户端时钟，会算偏。
    DateTime? oldest;
    for (final ChatMessage m in existing) {
      if (m.serverIdText != null) {
        oldest = m.sentAt;
        break;
      }
    }
    // 游标要排除边界那条消息本身：`deliveryDateEnd` 是闭区间，原样传会把最早一条再取回来一次，
    // 去重后没有进展，滚动续翻就会原地打转。
    final DateTime? cursor = oldest?.subtract(const Duration(milliseconds: 1));
    final int beforeCount = existing.length;
    try {
      final List<IncomingMessage> page = await realtime.history(
        conversationType: conv.type,
        targetId: targetId,
        before: cursor,
      );
      for (final IncomingMessage m in page.reversed) {
        _ingest(m);
      }
      // 空页，或整页都是重复（游标没前进）：都说明这个会话到头了。
      if (page.isEmpty || (_messages[conv.key]?.length ?? 0) == beforeCount) {
        _historyDone.add(conv.key);
      }
    } catch (_) {
      // 失败就停手，别在滚动里反复打；重新打开会话会清掉这个标记。
      _historyFailed.add(conv.key);
    } finally {
      _historyLoading.remove(conv.key);
      notifyListeners();
    }
  }

  bool isHistoryLoading(String key) => _historyLoading.contains(key);
  bool isHistoryDone(String key) => _historyDone.contains(key);

  /// 清凭据回登录页。
  void logout() {
    _renewTimer?.cancel();
    _turmsTimer?.cancel();
    realtime.disconnect();
    realtimeUp = false;
    identityToken = null;
    loginToken = null;
    loginExpiresAt = null;
    _turmsRenewFailures = 0;
    account = null;
    turms = null;
    accounts = const <Account>[];
    friends = const <Friendship>[];
    pending = const <Friendship>[];
    rooms = const <Room>[];
    _members.clear();
    _messages.clear();
    _roomIdByTurmsGroupId.clear();
    _profiles.clear();
    _roomDetails.clear();
    _historyDone.clear();
    _historyLoading.clear();
    _historyFailed.clear();
    _resetNavigation();
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
      final String? token = identityToken;
      if (token == null) {
        return;
      }
      try {
        final LoginResult r = await api.refresh(token);
        identityToken = r.token;
        // 当前账号就是归属者时，数据调用也跟着换成新 token；切在 agent 上时别覆盖它的 JWT。
        if (loginToken == token) {
          loginToken = r.token;
        }
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
    final String ownerToken = identityToken ?? token;
    final results = await Future.wait(<Future<Object>>[
      // 账号列表永远按归属者查：切进 agent 后也要能把真人账号切回来。
      api.mine(ownerToken),
      api.friendships(token: token, status: 'accepted'),
      api.friendships(token: token, status: 'pending'),
      api.rooms(token),
    ]);
    accounts = results[0] as List<Account>;
    friends = results[1] as List<Friendship>;
    pending = (results[2] as List<Friendship>).where((Friendship f) => f.incoming).toList();
    rooms = results[3] as List<Room>;
    _roomIdByTurmsGroupId
      ..clear()
      ..addEntries(rooms.where((Room r) => r.turmsGroupId != null)
          .map((Room r) => MapEntry<String, int>(r.turmsGroupId!, r.roomId)));
    // 关系变了之后资料页的 `is_friend` 与群详情的成员数都会过期，清掉重取。
    _profiles.clear();
    _roomDetails.clear();
    notifyListeners();
  }

  /// 切到自己名下的另一个账号：与新登录同一条签发路径。
  /// 用独立的 [switching] 而不是 `phase`，否则外壳会被拆掉、整屏跳回登录页。
  Future<void> switchAccount(int accountId) async {
    switching = true;
    notifyListeners();
    try {
      _renewTimer?.cancel();
      _turmsTimer?.cancel();
      _turmsRenewFailures = 0;
      _members.clear();
      _messages.clear();
      _roomIdByTurmsGroupId.clear();
      _profiles.clear();
      _roomDetails.clear();
      _historyDone.clear();
      _historyLoading.clear();
      _historyFailed.clear();
      _resetNavigation();
      await _openSession(accountId);
      _scheduleLoginRenewal();
      phase = AuthPhase.ready;
    } catch (e) {
      // 换号失败就把会话收回登录页，别把界面留在切换中。
      logout();
      rethrow;
    } finally {
      switching = false;
      notifyListeners();
    }
  }

  Future<CreatedAgent> createAgent(String displayName) async {
    final CreatedAgent created = await api.createAgent(token: loginToken!, displayName: displayName);
    // 密钥只在创建响应里出现一次；列表刷新失败不能把这次响应一起吞掉，否则密钥永久丢失。
    try {
      accounts = await api.mine(identityToken ?? loginToken!);
    } catch (_) {
      // 账号列表下次 refreshAll 会补回来；这里保住 created 才是第一优先级。
    }
    notifyListeners();
    return created;
  }

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
    if (activeConversationKey == 'dm:$peerAccountId') {
      activeConversationKey = null;
    }
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
    if (activeConversationKey == 'room:$roomId') {
      activeConversationKey = null;
    }
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
    // 视图读 `membersOf`，不通知的话它要等下一次无关的状态变化才会看到这批成员。
    notifyListeners();
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
      // `message_id` 在 Web 上会丢精度，不能拿来当去重键：保留服务端 id 只作展示/内部用，
      // 真正的精确 id 等 Turms 推送回来再认领（见 `_ingest`）。
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
    if (_disposed) {
      return;
    }
    _disposed = true;
    _renewTimer?.cancel();
    _turmsTimer?.cancel();
    // 先摘掉回调再关连接：晚到的 401 或推送不能对已 dispose 的 notifier 调 notifyListeners。
    api.onUnauthenticated = null;
    realtime.disconnect();
    api.close();
    super.dispose();
  }
}
