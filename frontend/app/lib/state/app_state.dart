import 'dart:async';

import 'package:flutter/foundation.dart';

import '../api/api_client.dart';
import '../api/models.dart';
import '../avatars.dart';
import '../session/session_store.dart';
import '../settings/settings.dart';
import '../settings/settings_store.dart';
import '../message_cache.dart';
import '../notify.dart';
import '../turms/realtime.dart';

enum AuthPhase { loggedOut, busy, ready }

enum MessageState { sending, sent, failed }

/// 会话坐标：私聊是对端账号 id，群聊是 `room_id`（`docs/truth/frontend/README.md`）。
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
    required this.senderAccountId,
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

  /// 群聊里用来取发送者的名字与头像；私聊对端就是会话的目标账号。
  int senderAccountId;
}

/// 客户端唯一的可变状态源。视图只读它、只调它的动作。
///
/// 读（会话列表 / 历史）本该由 Turms 会话给出，见 `realtime.dart`；
/// 这里只放 REST 能给的东西：身份、账号、好友、群、成员、发送结果。
class AppState extends ChangeNotifier {
  AppState({
    ApiClient? api,
    RealtimeClient? realtime,
    SettingsStore? store,
    SessionStore? session,
    MessageNotifier? notifier,
    MessageCacheStore? cache,
    this.primeOnLogin = true,
  })  : api = api ?? ApiClient(),
        realtime = realtime ?? createRealtime(),
        _store = store ?? createSettingsStore(),
        _session = session ?? createSessionStore(),
        _notifier = notifier ?? const NoopNotifier(),
        _cache = cache ?? const NoopMessageCacheStore() {
    // 401 一律回登录页（`docs/truth/frontend/README.md`）：凭据没了就别再让界面假装还在线。
    this.api.onUnauthenticated = logout;
    avatars = _store.loadAvatars();
  }

  final ApiClient api;
  final MessageNotifier _notifier;
  final MessageCacheStore _cache;
  final bool primeOnLogin;
  Timer? _cacheTimer;
  DateTime? _cacheSavedAt;
  bool _cacheRestored = false;

  /// 收到消息时的通知开关（设置页）；未读与列表预览不受它影响。
  bool notifyOnMessage = true;

  /// 窗口是否在前台；桌面壳监听焦点变化后写进来。
  bool windowFocused = true;

  final Map<String, int> _unread = <String, int>{};
  final Set<int> _blocked = <int>{};

  final SettingsStore _store;

  /// 本机记住的登录态：刷新页面后用它恢复会话（issue #24）。
  final SessionStore _session;

  /// 关系列表的轮询间隔：好友与群没有推送通道，只能定时重拉。
  static const Duration _pollInterval = Duration(seconds: 15);

  Timer? _pollTimer;

  /// 本机头像偏好：账号 id → 默认头像 key。服务端还没有这一列（issue #10），
  /// 所以换设备不跟随；服务端回了 `avatar` 之后再改成服务端优先。
  Map<int, String> avatars = const <int, String>{};

  /// 读取通道：客户端自己的 Turms 会话。
  final RealtimeClient realtime;
  bool realtimeUp = false;

  AuthPhase phase = AuthPhase.loggedOut;

  /// 切账号进行中：外壳保持挂载，只显示忙碌态。
  bool switching = false;

  /// 正在用本机凭据恢复会话：外壳据此显示启动页，而不是闪一下登录表单。
  bool restoring = false;

  /// 本次会话由本机凭据恢复而来：没有登舱过渡可播，外壳要直接交棒。
  bool restored = false;

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
  /// 当前视图：`messages` / `contacts` / `account`（`docs/truth/frontend/README.md`）。
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
      _unread.remove(key);
    }
    notifyListeners();
    _scheduleCacheSave();
  }

  int unreadFor(String key) => _unread[key] ?? 0;

  int get totalUnread => _unread.values.fold<int>(0, (int sum, int n) => sum + n);

  ChatMessage? lastMessage(String key) {
    final List<ChatMessage>? list = _messages[key];
    return list == null || list.isEmpty ? null : list.last;
  }

  bool isBlocked(int accountId) => _blocked.contains(accountId);

  void setNotifyOnMessage(bool value) => notifyOnMessage = value;

  void setWindowFocused(bool value) {
    if (windowFocused == value) {
      return;
    }
    windowFocused = value;
    final String? key = activeConversationKey;
    if (value && key != null) {
      _unread.remove(key);
    }
    notifyListeners();
  }

  void openProfileById(int accountId) {
    openProfile(accountId);
    unawaited(() async {
      try {
        await loadProfile(accountId);
      } catch (_) {
        // 资料页自己会显示失败态。
      }
    }());
  }

  Future<void> toggleBlock(int accountId) async {
    if (_blocked.contains(accountId)) {
      await api.unblockAccount(token: loginToken!, accountId: accountId);
      _blocked.remove(accountId);
    } else {
      await api.blockAccount(token: loginToken!, accountId: accountId);
      _blocked.add(accountId);
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
    _unread.clear();
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
      _persistSession();
      _startPolling();
    } catch (e) {
      // 会话可能已经建了一半（token、读通道、推送订阅）：清干净再回登录页。
      logout();
      rethrow;
    } finally {
      notifyListeners();
    }
  }

  /// 用本机记住的登录态恢复会话：刷新页面不再要求重新登录（issue #24）。
  ///
  /// 令牌失效时由 `ApiClient.onUnauthenticated` 统一登出并清掉本机副本；
  /// 网络失败也回登录页，不在界面上留半截会话。
  Future<void> restore() async {
    final StoredSession? saved = _session.load();
    if (saved == null || phase != AuthPhase.loggedOut) {
      return;
    }
    identityToken = saved.token;
    loginToken = saved.token;
    restoring = true;
    phase = AuthPhase.busy;
    notifyListeners();
    try {
      await _openSession(saved.accountId);
      phase = AuthPhase.ready;
      restored = true;
      _scheduleLoginRenewal();
      _persistSession();
      _startPolling();
    } catch (_) {
      logout();
    } finally {
      restoring = false;
      notifyListeners();
    }
  }

  /// 记住当前登录态：归属者 JWT + 最后用的账号 id（切号后是 agent 的 id）。
  void _persistSession() {
    final String? token = identityToken;
    final Account? me = account;
    if (token == null || me == null) {
      return;
    }
    _session.save(StoredSession(token: token, accountId: me.accountId));
  }

  /// 登录后必须先换 Turms 凭据，再拉账号、好友、群（`docs/truth/frontend/README.md`）。
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
    _restoreCache(accountId);
    await _connectRealtime();
    _scheduleTurmsRenewal();
    if (primeOnLogin) {
      unawaited(_primeConversations());
    }
  }

  /// 重登先把本机缓存的最后一段消息和上次会话铺回去，再让 Turms 历史和推送覆盖。
  void _restoreCache(int accountId) {
    final Map<String, dynamic>? data = _cache.load(accountId);
    if (data == null) {
      return;
    }
    _cacheRestored = true;
    _cacheSavedAt = DateTime.tryParse(data['saved_at'] as String? ?? '');
    final Object? rawUnread = data['unread'];
    if (rawUnread is Map<String, dynamic>) {
      _unread.clear();
      rawUnread.forEach((String key, Object? value) {
        if (value is num && value > 0) {
          _unread[key] = value.toInt();
        }
      });
    }
    final Object? rawMessages = data['messages'];
    if (rawMessages is Map<String, dynamic>) {
      _messages.clear();
      rawMessages.forEach((String key, Object? list) {
        if (list is! List<dynamic>) {
          return;
        }
        final List<ChatMessage> parsed = <ChatMessage>[];
        for (final Object? item in list) {
          if (item is! Map<String, dynamic>) {
            continue;
          }
          final DateTime? sentAt = DateTime.tryParse(item['sent_at'] as String? ?? '');
          final String text = item['text'] as String? ?? '';
          if (sentAt == null || text.isEmpty) {
            continue;
          }
          parsed.add(ChatMessage(
            localId: item['local_id'] as String? ?? 'cache:${parsed.length}',
            conversationKey: key,
            text: text,
            sentAt: sentAt,
            state: MessageState.values.firstWhere(
              (MessageState s) => s.name == item['state'],
              orElse: () => MessageState.sent,
            ),
            mine: item['mine'] == true,
            senderAccountId: (item['sender'] as num?)?.toInt() ?? 0,
            serverId: (item['server_id'] as num?)?.toInt(),
            serverIdText: item['server_id_text'] as String?,
            senderName: item['sender_name'] as String?,
          ));
        }
        if (parsed.isNotEmpty) {
          parsed.sort((ChatMessage a, ChatMessage b) => a.sentAt.compareTo(b.sentAt));
          _messages[key] = parsed;
        }
      });
    }
    // 旧版本缓存没有 saved_at：用缓存里最新一条消息的时间当“上次在线”的近似基线。
    if (_cacheSavedAt == null) {
      DateTime? newest;
      for (final List<ChatMessage> list in _messages.values) {
        if (list.isNotEmpty && (newest == null || list.last.sentAt.isAfter(newest))) {
          newest = list.last.sentAt;
        }
      }
      _cacheSavedAt = newest;
    }
    final Object? active = data['active'];
    if (active is String && conversations.any((Conversation c) => c.key == active)) {
      activeConversationKey = active;
      view = 'messages';
      _unread.remove(active);
    }
    notifyListeners();
  }

  /// 登录后把每个会话的最新一页拉回来：会话列表的预览、离线期间的消息和未读都靠这一步。
  Future<void> _primeConversations() async {
    if (!realtimeUp || _disposed) {
      return;
    }
    final Map<String, DateTime?> baseline = <String, DateTime?>{};
    for (final Conversation c in conversations) {
      final List<ChatMessage>? list = _messages[c.key];
      baseline[c.key] = list != null && list.isNotEmpty
          ? list.last.sentAt
          : (_cacheRestored ? _cacheSavedAt : null);
    }
    for (final Conversation c in conversations) {
      if (_disposed || !realtimeUp) {
        return;
      }
      await loadHistory(c);
    }
    for (final Conversation c in conversations) {
      if (_disposed) {
        return;
      }
      final DateTime? base = baseline[c.key];
      if (base == null) {
        continue;
      }
      final int missed = (_messages[c.key] ?? const <ChatMessage>[])
          .where((ChatMessage m) => !m.mine && m.sentAt.isAfter(base))
          .length;
      if (missed == 0) {
        continue;
      }
      final bool reading = c.key == activeConversationKey && windowFocused;
      if (!reading) {
        _unread[c.key] = (_unread[c.key] ?? 0) + missed;
      }
    }
    notifyListeners();
    _scheduleCacheSave();
  }

  Map<String, dynamic> _exportCache() {
    final Map<String, dynamic> messages = <String, dynamic>{};
    _messages.forEach((String key, List<ChatMessage> list) {
      final int start = list.length > 200 ? list.length - 200 : 0;
      messages[key] = <Map<String, dynamic>>[
        for (final ChatMessage m in list.skip(start))
          <String, dynamic>{
            'local_id': m.localId,
            'text': m.text,
            'sent_at': m.sentAt.toIso8601String(),
            'state': m.state.name,
            'mine': m.mine,
            'sender': m.senderAccountId,
            'server_id': m.serverId,
            'server_id_text': m.serverIdText,
            'sender_name': m.senderName,
          },
      ];
    });
    return <String, dynamic>{
      'active': activeConversationKey,
      'saved_at': DateTime.now().toUtc().toIso8601String(),
      'unread': _unread,
      'messages': messages,
    };
  }

  void _scheduleCacheSave() {
    _cacheTimer?.cancel();
    _cacheTimer = Timer(const Duration(milliseconds: 300), flushCache);
  }

  /// 退出前同步落盘；桌面壳在关闭时直接调用。
  void flushCache() {
    _cacheTimer?.cancel();
    final int? id = account?.accountId;
    if (id == null) {
      return;
    }
    _cache.save(id, _exportCache());
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
        final bool wasUp = realtimeUp;
        realtimeUp = up;
        // 断线期间 Turms 不会补推：重连成功后补拉一次当前会话最新一页。
        if (up && !wasUp) {
          unawaited(_refreshActiveMessages());
        }
        notifyListeners();
      },
      onMessage: _ingest,
      onError: (Object error) {
        realtimeUp = false;
        notifyListeners();
      },
    );
  }

  /// 重连后补拉当前会话最新一页：断线/挂机期间丢失的推送只能靠历史补回来。
  Future<void> _refreshActiveMessages() async {
    final String? key = activeConversationKey;
    if (key == null || !realtimeUp) {
      return;
    }
    final Conversation? conv = conversationOf(key);
    if (conv == null) {
      return;
    }
    final String? targetId = conv.isRoom ? conv.turmsGroupId : '${conv.targetId}';
    if (targetId == null || targetId.isEmpty) {
      return;
    }
    try {
      final List<IncomingMessage> page = await realtime.history(
        conversationType: conv.type,
        targetId: targetId,
        maxCount: 50,
      );
      for (final IncomingMessage m in page.reversed) {
        _ingest(m, live: false);
      }
    } catch (_) {
      // 下一次重连再补。
    }
  }

  /// 推送进来的一条消息：按会话坐标落到本地列表，同一条只落一次。
  void _ingest(IncomingMessage incoming, {bool live = true}) {
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
    //
    // 只能认领「自己发的」回声：双方同时发同一句话（比如都发 666）时，对端那条
    // 的发送者是对方；这里若按文本认领，会把对端消息吞进自己的待发气泡，表现就是
    // “对面发了但我这边没出现/列表两边对不上”。
    if (incoming.id.isNotEmpty && incoming.senderId == me) {
      for (final ChatMessage m in list) {
        if (m.serverIdText == null && m.mine && m.text == incoming.text) {
          m
            ..serverIdText = incoming.id
            ..serverId = int.tryParse(incoming.id)
            ..sentAt = incoming.sentAt ?? m.sentAt
            ..state = MessageState.sent;
          list.sort((ChatMessage a, ChatMessage b) => a.sentAt.compareTo(b.sentAt));
          notifyListeners();
          _scheduleCacheSave();
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
      senderAccountId: incoming.senderId,
      serverId: int.tryParse(incoming.id),
      serverIdText: incoming.id.isEmpty ? null : incoming.id,
    ));
    list.sort((ChatMessage a, ChatMessage b) => a.sentAt.compareTo(b.sentAt));
    final bool reading = key == activeConversationKey && windowFocused;
    if (live && incoming.senderId != me && !reading) {
      _unread[key] = (_unread[key] ?? 0) + 1;
      if (notifyOnMessage) {
        Conversation? conv;
        for (final Conversation c in conversations) {
          if (c.key == key) {
            conv = c;
            break;
          }
        }
        if (conv != null) {
          unawaited(_notifier.show(title: conv.title, body: incoming.text));
        }
      }
    }
    notifyListeners();
    _scheduleCacheSave();
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
        _ingest(m, live: false);
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
    flushCache();
    _renewTimer?.cancel();
    _turmsTimer?.cancel();
    _stopPolling();
    _session.clear();
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
    restored = false;
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
        _persistSession();
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
    try {
      final BlocklistPage page = await api.blocklist(token: token);
      _blocked
        ..clear()
        ..addAll(page.items.map((BlocklistItem item) => item.accountId));
    } catch (_) {
      // 黑名单拉不到不影响主流程。
    }
    notifyListeners();
  }

  /// 关系与群列表没有推送通道（Biz 只校验不投递），只能定时重拉，
  /// 否则别人发来的好友申请、别人建的群在这个页面上永远不出现（issue #24）。
  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(_pollInterval, (Timer _) => refreshRelations());
  }

  void _stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  /// 轮询的一轮：只重拉会因别人操作而变化的三份列表。
  ///
  /// 刻意不碰 `_profiles` / `_roomDetails`：清掉它们会让已经打开的资料页停在加载态，
  /// 而那两处的过期只在 15 秒级别，不值得每轮重建。
  Future<void> refreshRelations() async {
    final String? token = loginToken;
    if (!isReady || switching || token == null) {
      return;
    }
    try {
      final List<Object> results = await Future.wait(<Future<Object>>[
        api.friendships(token: token, status: 'accepted'),
        api.friendships(token: token, status: 'pending'),
        api.rooms(token),
      ]);
      final List<Friendship> nextFriends = results[0] as List<Friendship>;
      final List<Friendship> nextPending =
          (results[1] as List<Friendship>).where((Friendship f) => f.incoming).toList();
      final List<Room> nextRooms = results[2] as List<Room>;
      if (_sameFriends(nextFriends, friends) &&
          _sameFriends(nextPending, pending) &&
          _sameRooms(nextRooms, rooms)) {
        return;
      }
      friends = nextFriends;
      pending = nextPending;
      rooms = nextRooms;
      _roomIdByTurmsGroupId
        ..clear()
        ..addEntries(nextRooms.where((Room r) => r.turmsGroupId != null)
            .map((Room r) => MapEntry<String, int>(r.turmsGroupId!, r.roomId)));
      notifyListeners();
    } catch (_) {
      // 下一轮再试。401 已由 ApiClient 统一登出，其余失败不值得每轮弹一次提示。
    }
  }

  static bool _sameFriends(List<Friendship> a, List<Friendship> b) {
    if (a.length != b.length) {
      return false;
    }
    for (int i = 0; i < a.length; i++) {
      if (a[i].peerAccountId != b[i].peerAccountId || a[i].displayName != b[i].displayName) {
        return false;
      }
    }
    return true;
  }

  static bool _sameRooms(List<Room> a, List<Room> b) {
    if (a.length != b.length) {
      return false;
    }
    for (int i = 0; i < a.length; i++) {
      if (a[i].roomId != b[i].roomId ||
          a[i].name != b[i].name ||
          a[i].ownerAccountId != b[i].ownerAccountId ||
          a[i].turmsGroupId != b[i].turmsGroupId) {
        return false;
      }
    }
    return true;
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
      flushCache();
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
      _persistSession();
    } catch (e) {
      // 换号失败就把会话收回登录页，别把界面留在切换中。
      logout();
      rethrow;
    } finally {
      switching = false;
      notifyListeners();
    }
  }

  /// 本人完整资料：编辑页回填用。登录、切账号与 `mine` 都只有列表字段。
  Future<MyProfile> myProfile() async {
    final String? token = loginToken;
    if (token == null) {
      throw ApiException(code: 'unauthenticated', message: 'signed out');
    }
    return api.myProfile(token);
  }

  /// 改当前账号资料：`PUT` 全量提交三个字段，响应与 `GET /api/accounts/me` 同形。
  Future<void> updateProfile({
    required String displayName,
    required String gender,
    DateTime? birthday,
  }) async {
    final Account? current = account;
    final String? token = loginToken;
    if (current == null || token == null) {
      // 已经登出：让编辑器停在弹窗里报错，别把关闭弹窗当成保存成功。
      throw ApiException(code: 'unauthenticated', message: 'signed out');
    }
    final MyProfile updated = await api.updateProfile(
      token: token,
      displayName: displayName,
      gender: gender,
      birthday: birthday,
    );
    // 契约保证 gender 一定有值；缺了就说明后端版本不对，别把保存当成功。
    if (updated.displayName.isEmpty || updated.gender == null) {
      throw ApiException(code: 'upstream_unavailable', message: 'profile fields missing');
    }
    // 等待期间可能已被 401 / 续期失败登出，或用户切了账号。
    final Account? still = account;
    if (still == null || still.accountId != current.accountId) {
      return;
    }
    account = Account(
      accountId: current.accountId,
      type: current.type,
      displayName: updated.displayName,
      gender: updated.gender,
      birthday: updated.birthday,
    );
    try {
      // 名字变了，好友 / 群 / 会话列表里的旧名字也要跟着换。
      await refreshAll();
    } catch (_) {
      // 资料已经保存；列表刷新失败下次 refreshAll 会补。
    }
    // refreshAll 可能因 401 触发 logout，或者用户切了账号：别把旧账号写回去。
    final Account? me = account;
    if (me == null || me.accountId != current.accountId) {
      return;
    }
    accounts = accounts
        .map((Account a) => a.accountId == current.accountId ? me : a)
        .toList();
    notifyListeners();
  }

  // —— 头像（本机偏好，服务端还没有这一列，issue #10）——

  String? avatarOf(int accountId) => avatars[accountId];

  /// 选中即生效、即落本机；`null` 表示回到按账号 id 生成的首字头像。
  void setAvatar(int accountId, String? key) {
    if (key != null && !isKnownAvatar(key)) {
      return;
    }
    final Map<int, String> next = Map<int, String>.of(avatars);
    if (key == null) {
      next.remove(accountId);
    } else {
      next[accountId] = key;
    }
    avatars = next;
    _store.saveAvatars(next);
    notifyListeners();
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
    if (action != 'accept') {
      return;
    }
    Conversation? conv;
    for (final Conversation c in conversations) {
      if (c.key == 'dm:$peerAccountId') {
        conv = c;
        break;
      }
    }
    if (conv == null) {
      return;
    }
    try {
      // 被加的一方同意后自动打招呼（限一次，失败不回滚好友关系）。
      await sendMessage(conv, '我们已经是好友啦，一起来聊天吧OWO');
    } catch (_) {
      // 好友已经加上了，欢迎语发失败不阻塞。
    }
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
      senderAccountId: account?.accountId ?? 0,
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
      _scheduleCacheSave();
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
      _scheduleCacheSave();
    }
  }

  void _append(ChatMessage message) {
    final List<ChatMessage> list = _messages.putIfAbsent(message.conversationKey, () => <ChatMessage>[]);
    list.add(message);
    notifyListeners();
    _scheduleCacheSave();
  }

  @override
  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _renewTimer?.cancel();
    _turmsTimer?.cancel();
    _stopPolling();
    flushCache();
    // 先摘掉回调再关连接：晚到的 401 或推送不能对已 dispose 的 notifier 调 notifyListeners。
    api.onUnauthenticated = null;
    realtime.disconnect();
    api.close();
    super.dispose();
  }
}
