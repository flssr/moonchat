import 'dart:async';

import 'package:flutter/foundation.dart';

import '../api/api_client.dart';
import '../api/models.dart';
import '../avatars.dart';
import '../session/session_store.dart';
import '../settings/settings.dart';
import '../settings/settings_store.dart';
import '../account_id.dart';
import '../i18n/moon_strings.dart';
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
    this.recalled = false,
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

  /// 服务端撤回通知到了就把正文藏掉；历史重拉后该条可能直接消失。
  bool recalled;

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

  /// 收到消息时的通知开关（设置页）；未读与列表预览不受它影响。
  bool notifyOnMessage = true;

  /// 窗口是否在前台；桌面壳监听焦点变化后写进来。
  bool windowFocused = true;

  final Map<String, int> _unread = <String, int>{};
  final Set<int> _blocked = <int>{};
  final Map<String, String> _drafts = <String, String>{};
  final Map<String, String> _dmTitles = <String, String>{};

  /// 群聊里被 @ 的会话（“有人@我”），打开会话或切号时清掉。
  final Set<String> _mentioned = <String>{};

  /// 正在输入的会话 → 过期定时器；对端每发一次输入状态就顺延 3 秒。
  final Map<String, Timer> _typingTimers = <String, Timer>{};
  final Set<String> _typing = <String>{};

  /// 每个会话上一次发出“正在输入”的时间：别让每个按键都打一次 Turms。
  final Map<String, DateTime> _typingSentAt = <String, DateTime>{};

  /// 服务端读时间基线（只取自己的那条），本地只用于算未读。
  final Map<String, DateTime> _readDates = <String, DateTime>{};
  final Set<String> _pendingReadReports = <String>{};
  Timer? _readTimer;

  /// Web 端断线后的退避重连（桌面壳自己会重连，见 `reconnectsByItself`）。
  Timer? _reconnectTimer;
  int _reconnectAttempt = 0;

  /// 欢迎语撞上好友投影延迟时的单次补发（见 `respondFriend`）。
  Timer? _welcomeRetryTimer;

  /// 登录页“记住我”的选择：续期与切号要沿用，不能当成一次新的“记住”。
  bool _rememberSession = true;

  /// 当前界面语言：通知正文这类没有 widget 上下文的文案按它翻译。
  String languageCode = 'zh';

  String draftFor(String key) => _drafts[key] ?? '';

  void setDraft(String key, String text) {
    if (text.trim().isEmpty) {
      _drafts.remove(key);
    } else {
      _drafts[key] = text;
    }
    _scheduleCacheSave();
    notifyListeners();
  }

  final SettingsStore _store;

  /// 本机记住的登录态：刷新页面后用它恢复会话（issue #24）。
  final SessionStore _session;

  /// 上次登录用的邮箱（本机偏好）：登录页预填，不跟“记住我”绑定。
  String? get lastEmail => _store.loadLastEmail();

  void rememberEmail(String email) => _store.saveLastEmail(email);

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
  String filter = 'dm'; // dm | room
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
      // 打开会话就把“有人@我”的提醒消费掉。
      _mentioned.remove(key);
      // 重新打开会话时允许再试一次历史（上次可能只是读通道没连上）。
      _historyFailed.remove(key);
      if ((_unread[key] ?? 0) > 0) {
        _scheduleReadReport(key);
      }
    }
    notifyListeners();
    _scheduleCacheSave();
  }

  int unreadFor(String key) => _unread[key] ?? 0;

  bool isMentioned(String key) => _mentioned.contains(key);

  bool isTyping(String key) => _typing.contains(key);

  /// 会话分类的未读合计：私聊/群聊页签右上角用它。
  int unreadForType(String type) => conversations
      .where((Conversation c) => type == 'dm' ? c.type == 'dm' : c.isRoom)
      .fold<int>(0, (int sum, Conversation c) => sum + unreadFor(c.key));

  int get totalUnread => _unread.values.fold<int>(0, (int sum, int n) => sum + n);

  ChatMessage? lastMessage(String key) {
    final List<ChatMessage>? list = _messages[key];
    return list == null || list.isEmpty ? null : list.last;
  }

  bool isBlocked(int accountId) => _blocked.contains(accountId);

  void setNotifyOnMessage(bool value) => notifyOnMessage = value;

  /// 界面语言变了：通知正文等非 widget 文案跟着换。
  void setLanguageCode(String code) => languageCode = code;

  void setWindowFocused(bool value) {
    if (windowFocused == value) {
      return;
    }
    windowFocused = value;
    final String? key = activeConversationKey;
    if (value && key != null && (_unread[key] ?? 0) > 0) {
      _scheduleReadReport(key);
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
      _hideBlockedConversation(accountId);
    }
    notifyListeners();
  }

  /// 拉黑之后聊天界面不再出现这个人：会话列表里过滤掉（`conversations` getter），
  /// 正开着的那条也要退出，否则会停在一条已经不该出现的会话上。
  void _hideBlockedConversation(int accountId) {
    final String key = 'dm:$accountId';
    _unread.remove(key);
    if (activeConversationKey == key) {
      activeConversationKey = null;
    }
  }

  /// 黑名单管理弹窗的列表：一次取到上限（100 人），顺带让本地集合与服务端对齐。
  Future<List<BlocklistItem>> loadBlocklist() async {
    final BlocklistPage page = await api.blocklist(token: loginToken!, size: 100);
    _blocked
      ..clear()
      ..addAll(page.items.map((BlocklistItem item) => item.accountId));
    notifyListeners();
    return page.items;
  }

  Future<void> unblockAccount(int accountId) async {
    await api.unblockAccount(token: loginToken!, accountId: accountId);
    _blocked.remove(accountId);
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
    filter = 'dm';
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

  /// 1105 / 1300 触发的换凭据只跑一份，避免每次发送失败都并发换。
  bool _recoveringRealtime = false;

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
    _syncAvatars(<(int, String?)>[(accountId, p.avatar)]);
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
  /// 我拉黑的人不出现在聊天界面（解黑后自动回来）；拉黑不删好友，联系人页仍然看得见。
  List<Conversation> get conversations {
    final List<Conversation> out = <Conversation>[
      for (final Friendship f in friends)
        if (!_blocked.contains(f.peerAccountId))
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
    // 删好友后历史私聊仍然保留：被删的一方不会收到通知，下一次刷新好友列表后就靠
    // 本地消息把会话补回来，发送时再提示“不是好友”。
    final Set<String> known = out.map((Conversation c) => c.key).toSet();
    for (final String key in _messages.keys) {
      if (!key.startsWith('dm:') || known.contains(key)) {
        continue;
      }
      final int? id = int.tryParse(key.substring(3));
      if (id == null || _blocked.contains(id)) {
        continue;
      }
      out.add(Conversation(
        type: 'dm',
        targetId: id,
        title: _dmTitles[key] ?? '#${shortAccountId(id)}',
      ));
    }
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

  Future<void> login({
    required String email,
    required String password,
    bool remember = true,
  }) async {
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
      _rememberSession = remember;
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

  /// 用本机记住的登录态恢复会话：登录页的「记住我」卡片点登录时调用。
  ///
  /// 只负责把会话恢复成 `ready`；登舱过渡由登录页播完再交棒（两条入口同一条出口）。
  /// 令牌失效时由 `ApiClient.onUnauthenticated` 统一登出并清掉本机副本；
  /// 网络失败也回登录页，不在界面上留半截会话。
  Future<void> restore() async {
    final StoredSession? saved = _session.load();
    if (saved == null || phase != AuthPhase.loggedOut) {
      return;
    }
    identityToken = saved.token;
    loginToken = saved.token;
    phase = AuthPhase.busy;
    notifyListeners();
    try {
      await _openSession(saved.accountId);
      phase = AuthPhase.ready;
      _scheduleLoginRenewal();
      _rememberSession = true;
      _persistSession();
      _startPolling();
    } catch (_) {
      logout();
    } finally {
      notifyListeners();
    }
  }

  /// 记住当前登录态：归属者 JWT + 最后用的账号 id（切号后是 agent 的 id）。
  void _persistSession() {
    if (!_rememberSession) {
      _session.clear();
      return;
    }
    final String? token = identityToken;
    final Account? me = account;
    if (token == null || me == null) {
      return;
    }
    _session.save(StoredSession(
      token: token,
      accountId: me.accountId,
      displayName: me.displayName,
    ));
  }

  /// 登录页“记住我”用的本机会话；没有就还是账号密码表单。
  StoredSession? get rememberedSession => _session.load();

  /// 登录后必须先换 Turms 凭据，再拉账号、好友、群（`docs/truth/frontend/README.md`）。
  Future<void> _openSession(int accountId) async {
    _readTimer?.cancel();
    _readTimer = null;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _reconnectAttempt = 0;
    _welcomeRetryTimer?.cancel();
    _welcomeRetryTimer = null;
    _pendingReadReports.clear();
    _readDates.clear();
    // 上一个账号的草稿、会话标题与黑名单不能带进新账号：缓存会按账号各自恢复。
    _drafts.clear();
    _dmTitles.clear();
    _blocked.clear();
    _mentioned.clear();
    for (final Timer timer in _typingTimers.values) {
      timer.cancel();
    }
    _typingTimers.clear();
    _typing.clear();
    _typingSentAt.clear();
    _recoveringRealtime = false;
    // 用归属者 JWT 换目标账号的会话；切进 agent 后仍靠它切回来。
    final AccountSession session = await api.sessionForOwner(token: identityToken!, accountId: accountId);
    account = session.account;
    _syncAvatars(<(int, String?)>[(session.account.accountId, session.account.avatar)]);
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
    final Object? rawTitles = data['dm_titles'];
    if (rawTitles is Map<String, dynamic>) {
      _dmTitles.clear();
      rawTitles.forEach((String key, Object? value) {
        if (value is String && value.isNotEmpty) {
          _dmTitles[key] = value;
        }
      });
    }
    final Object? rawDrafts = data['drafts'];
    if (rawDrafts is Map<String, dynamic>) {
      _drafts.clear();
      rawDrafts.forEach((String key, Object? value) {
        if (value is String && value.trim().isNotEmpty) {
          _drafts[key] = value;
        }
      });
    }
    final Object? rawUnread = data['unread'];
    if (rawUnread is Map<String, dynamic>) {
      _unread.clear();
      rawUnread.forEach((String key, Object? value) {
        if (value is num && value > 0) {
          _unread[key] = value.toInt();
        }
      });
    }
    final Object? rawReadDates = data['read_dates'];
    if (rawReadDates is Map<String, dynamic>) {
      rawReadDates.forEach((String key, Object? value) {
        final DateTime? parsed = value is String ? DateTime.tryParse(value) : null;
        if (parsed != null) {
          _readDates[key] = parsed.toUtc();
        }
      });
    }
    final Object? rawMentioned = data['mentioned'];
    if (rawMentioned is List<dynamic>) {
      _mentioned
        ..clear()
        ..addAll(rawMentioned.whereType<String>());
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
            recalled: item['recalled'] == true,
          ));
        }
        if (parsed.isNotEmpty) {
          parsed.sort((ChatMessage a, ChatMessage b) => a.sentAt.compareTo(b.sentAt));
          _messages[key] = parsed;
        }
      });
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
  ///
  /// 未读基线：私聊用本机已读时间（`read_dates` 随缓存落盘）；Turms 的会话查询只能查到
  /// 「对方对我的会话」，拿不到自己的读时间（#37），所以不拿它当私聊基线。
  /// 群取 Turms `memberIdToReadDate[自己]`。没有任何基线说明本机第一次读这个会话：
  /// 静默上报一次，别把历史全算成未读。
  Future<void> _primeConversations() async {
    if (!realtimeUp || _disposed) {
      return;
    }
    final int me = account?.accountId ?? 0;
    if (me == 0) {
      return;
    }
    final DateTime primeStarted = DateTime.now().toUtc();
    bool stillMine() => !_disposed && realtimeUp && account?.accountId == me;
    final List<Conversation> convs = conversations;
    final List<String> groups = <String>[
      for (final Conversation c in convs)
        if (c.isRoom && (c.turmsGroupId?.isNotEmpty ?? false)) c.turmsGroupId!,
    ];
    bool baselineLoaded = true;
    try {
      final Map<String, DateTime?> groupDates = await realtime.groupReadDates(
        turmsGroupIds: groups,
        selfAccountId: me,
      );
      for (final Conversation c in convs) {
        if (!c.isRoom || c.turmsGroupId == null) {
          continue;
        }
        final DateTime? date = groupDates[c.turmsGroupId];
        if (date != null) {
          _readDates[c.key] = date;
        }
      }
    } catch (_) {
      // 基线拿不到时宁可这轮不弹未读，也不要按「全都没读过」处理。
      baselineLoaded = false;
    }
    for (final Conversation c in convs) {
      if (!stillMine()) {
        return;
      }
      await loadHistory(c);
    }
    if (!baselineLoaded) {
      notifyListeners();
      _scheduleCacheSave();
      return;
    }
    for (final Conversation c in convs) {
      if (!stillMine()) {
        return;
      }
      final DateTime? readDate = _readDates[c.key];
      if (readDate == null) {
        // 补拉期间实时到的消息不能被这次静默上报吞掉：留着角标，只把基线钉在补拉起点。
        final bool arrivedDuringPrime = (_messages[c.key] ?? const <ChatMessage>[])
            .any((ChatMessage m) => !m.mine && m.sentAt.isAfter(primeStarted));
        if (arrivedDuringPrime) {
          _readDates[c.key] = primeStarted;
        } else {
          // 从未上报过：上报一次并跳过未读，否则首登的历史会话会一次性全红。
          _unread.remove(c.key);
          await _reportRead(c.key);
        }
        continue;
      }
      int missed = 0;
      ChatMessage? latest;
      for (final ChatMessage m in _messages[c.key] ?? const <ChatMessage>[]) {
        // 已撤回的消息不参与未读与通知正文（`docs/truth/frontend/messages.md` 的「未删除」）。
        if (!m.mine && !m.recalled && m.sentAt.isAfter(readDate)) {
          missed++;
          latest = m;
        }
      }
      if (missed == 0 || latest == null) {
        // 读时间之后没有对端消息：旧缓存里的未读不能留下来。
        _unread.remove(c.key);
        continue;
      }
      // 登录补拉到的离线消息用户还没看过，即使恢复的当前会话就是它也要提示；
      // 在线实时推送才按“当前会话 + 窗口在前台”算已读。
      _unread[c.key] = missed;
      if (notifyOnMessage) {
        // 和在线提示一样走桌面通知，把离线期间收到的条数和最后一条内容带上。
        final String line =
            moonText(languageCode, '{n} 条新消息').replaceAll('{n}', '$missed');
        unawaited(_notifier.show(
          title: c.title,
          body: '$line\n${latest.text}',
        ));
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
            'recalled': m.recalled,
          },
      ];
    });
    return <String, dynamic>{
      'active': activeConversationKey,
      'unread': _unread,
      'drafts': _drafts,
      'dm_titles': _dmTitles,
      'read_dates': <String, String>{
        for (final MapEntry<String, DateTime> entry in _readDates.entries)
          entry.key: entry.value.toUtc().toIso8601String(),
      },
      'mentioned': _mentioned.toList(growable: false),
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
      if (await _renewTurmsSession()) {
        return;
      }
      // 单次续期失败不等于读通道死了：先按 1 分钟退避重试，连续 3 次才认输。
      _turmsRenewFailures++;
      if (_turmsRenewFailures >= 3) {
        realtimeUp = false;
        notifyListeners();
        return;
      }
      _turmsTimer = Timer(const Duration(minutes: 1), _scheduleTurmsRenewal);
    });
  }

  /// 换一份 Turms 凭据并重连；发送遇到 1105 / 1300 时也走这里。
  Future<bool> _renewTurmsSession() async {
    final Account? me = account;
    final String? token = loginToken;
    if (me == null || token == null) {
      return false;
    }
    try {
      final AccountSession session =
          await api.sessionForOwner(token: token, accountId: me.accountId);
      // 换凭据期间可能已经登出或切号：别把旧会话又接回去。
      if (account?.accountId != me.accountId) {
        return false;
      }
      turms = session.turms;
      if (session.loginToken != null) {
        loginToken = session.loginToken;
        loginExpiresAt = session.loginExpiresAt;
      }
      _turmsRenewFailures = 0;
      await _connectRealtime();
      _scheduleTurmsRenewal();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Turms 报会话没建起来 / 凭据失效：换凭据重连一次，别只把错误甩给界面。
  void _recoverRealtime(TurmsException error) {
    if (!error.needsReconnect || _disposed || _recoveringRealtime) {
      return;
    }
    _recoveringRealtime = true;
    realtimeUp = false;
    notifyListeners();
    unawaited(() async {
      try {
        await _renewTurmsSession();
      } finally {
        _recoveringRealtime = false;
      }
    }());
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
        if (up) {
          _reconnectTimer?.cancel();
          _reconnectAttempt = 0;
          if (!wasUp) {
            unawaited(_refreshActiveMessages());
          }
        } else if (!realtime.reconnectsByItself) {
          _scheduleRealtimeReconnect();
        }
        notifyListeners();
      },
      onMessage: _ingest,
      onMessageUpdated: _ingestUpdate,
      onTyping: _onTyping,
      onError: (Object error) {
        realtimeUp = false;
        if (!realtime.reconnectsByItself) {
          _scheduleRealtimeReconnect();
        }
        notifyListeners();
      },
    );
  }

  /// Web 断线后自己按 1/2/4/8/16/30 秒退避重连（桌面壳有自己的重连，不走这里）。
  void _scheduleRealtimeReconnect() {
    if (_disposed || realtime.reconnectsByItself) {
      return;
    }
    if (account == null || phase != AuthPhase.ready) {
      return;
    }
    _reconnectTimer?.cancel();
    final int seconds = 1 << (_reconnectAttempt < 5 ? _reconnectAttempt : 5);
    _reconnectAttempt++;
    _reconnectTimer = Timer(Duration(seconds: seconds > 30 ? 30 : seconds), () {
      if (_disposed || account == null || phase != AuthPhase.ready) {
        return;
      }
      unawaited(() async {
        final bool ok = await _renewTurmsSession();
        if (!ok) {
          _scheduleRealtimeReconnect();
        }
      }());
    });
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
    // Turms 会把发送者自己的消息也推回来。若本地那条「发送中」还没拿到直写响应，
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
    if (live && incoming.senderId != me) {
      if (reading) {
        // 正在看这条就把读游标推上去，否则另一端点开时还会看到未读。
        _scheduleReadReport(key);
      } else {
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
    } else if (live && incoming.senderId != me && reading) {
      // 正看着这条会话：把服务端已读也推到这条消息上，下次登录才不会又算成未读。
      _scheduleReadReport(key);
    }
    if (live && incoming.senderId != me && incoming.groupId != null && !reading &&
        _mentionsMe(incoming.text)) {
      // 群聊里被点名：会话行显示“有人@我”，打开会话时清掉。
      _mentioned.add(key);
    }
    notifyListeners();
    _scheduleCacheSave();
  }

  /// 群消息是否 @ 了我：按自己的显示名做文本匹配（Turms 不提供结构化 mentions）。
  bool _mentionsMe(String text) {
    final String me = account?.displayName ?? '';
    if (me.isEmpty) {
      return false;
    }
    final String escaped = RegExp.escape(me);
    // 显示名是另一个名字的前缀时（@张三 vs @张三丰）不算被 @。
    return RegExp('@$escaped(?![A-Za-z0-9_\\u4e00-\\u9fff])').hasMatch(text);
  }

  /// 输入状态：同一会话 2 秒最多发一次；没权限或断线都静默跳过（只是锦上添花）。
  Future<void> sendTyping(Conversation conv) async {
    final DateTime now = DateTime.now();
    final DateTime? last = _typingSentAt[conv.key];
    if (last != null && now.difference(last).inMilliseconds < 2000) {
      return;
    }
    final String? targetId = conv.isRoom ? conv.turmsGroupId : '${conv.targetId}';
    if (targetId == null || targetId.isEmpty) {
      return;
    }
    _typingSentAt[conv.key] = now;
    try {
      await realtime.sendTyping(conversationType: conv.type, targetId: targetId);
    } catch (_) {
      // 输入状态不挡聊天。
    }
  }

  /// 对端正在输入：3 秒没有新的输入状态就自动消失。
  void _onTyping(IncomingTyping typing) {
    final int me = account?.accountId ?? 0;
    if (me == 0 || typing.senderId == me) {
      return;
    }
    String? key;
    if (typing.isGroup) {
      final int? roomId = _roomIdByTurmsGroupId[typing.toId];
      if (roomId == null) {
        return;
      }
      key = 'room:$roomId';
    } else {
      key = 'dm:${typing.senderId}';
    }
    if (!conversations.any((Conversation c) => c.key == key)) {
      return;
    }
    _typing.add(key);
    _typingTimers.remove(key)?.cancel();
    _typingTimers[key] = Timer(const Duration(seconds: 3), () {
      if (_disposed) {
        return;
      }
      _typingTimers.remove(key);
      if (_typing.remove(key)) {
        notifyListeners();
      }
    });
    notifyListeners();
  }

  /// 服务端发来的消息更新：撤回把正文藏掉，编辑替换正文。找不到就丢弃。
  void _ingestUpdate(MessageUpdate update) {
    bool changed = false;
    for (final List<ChatMessage> list in _messages.values) {
      for (final ChatMessage m in list) {
        if (m.serverIdText != update.id) {
          continue;
        }
        if (update.isRecall) {
          m.recalled = true;
          changed = true;
        } else if (update.text != null) {
          m.text = update.text!;
          changed = true;
        }
      }
    }
    if (!changed) {
      return;
    }
    notifyListeners();
    _scheduleCacheSave();
  }

  /// 撤回自己发的消息。成功后先改本地，失败由调用方提示；服务端仍按 5 分钟时限判定。
  Future<void> recallMessage(ChatMessage message) async {
    final String? id = message.serverIdText;
    if (id == null || id.isEmpty) {
      throw TurmsException(turmsCode: 5200, message: '消息还没有服务端 id');
    }
    try {
      await realtime.recall(messageId: id);
      message.recalled = true;
      notifyListeners();
      _scheduleCacheSave();
    } on TurmsException catch (e) {
      _recoverRealtime(e);
      rethrow;
    }
  }

  /// 已读上报按会话合并：打开会话或正看着它时，1 秒内的多次触发只写一次。
  void _scheduleReadReport(String key) {
    final Conversation? conv = conversationOf(key);
    if (conv == null || (conv.isRoom && (conv.turmsGroupId?.isEmpty ?? true))) {
      return;
    }
    _pendingReadReports.add(key);
    _readTimer?.cancel();
    _readTimer = Timer(const Duration(seconds: 1), () {
      final List<String> keys = _pendingReadReports.toList(growable: false);
      _pendingReadReports.clear();
      for (final String key in keys) {
        unawaited(_reportRead(key));
      }
    });
  }

  /// 写自己的读游标。已读失败不影响聊天：群可能关闭已读、会话可能已被移除，都静默跳过。
  Future<bool> _reportRead(String key) async {
    final Conversation? conv = conversationOf(key);
    if (conv == null) {
      return false;
    }
    final String? targetId = conv.isRoom ? conv.turmsGroupId : '${conv.targetId}';
    if (targetId == null || targetId.isEmpty) {
      return false;
    }
    try {
      await realtime.markRead(conversationType: conv.type, targetId: targetId);
      _readDates[key] = DateTime.now().toUtc();
      if (_unread.remove(key) != null) {
        notifyListeners();
      }
      // 私聊基线只在本机：读时间要跟着缓存落盘，重启后未读才不会算错。
      _scheduleCacheSave();
      return true;
    } on TurmsException catch (e) {
      _recoverRealtime(e);
      return false;
    } catch (_) {
      return false;
    }
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
    _readTimer?.cancel();
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _reconnectAttempt = 0;
    _welcomeRetryTimer?.cancel();
    _welcomeRetryTimer = null;
    for (final Timer timer in _typingTimers.values) {
      timer.cancel();
    }
    _typingTimers.clear();
    _typing.clear();
    _typingSentAt.clear();
    _mentioned.clear();
    _pendingReadReports.clear();
    _readDates.clear();
    _recoveringRealtime = false;
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
    _syncAvatars(<(int, String?)>[
      ...accounts.map((Account a) => (a.accountId, a.avatar)),
      ...friends.map((Friendship f) => (f.peerAccountId, f.avatar)),
    ]);
    for (final Friendship f in friends) {
      _dmTitles['dm:${f.peerAccountId}'] = f.displayName;
    }
    pending = (results[2] as List<Friendship>).where((Friendship f) => f.incoming).toList();
    rooms = results[3] as List<Room>;
    _roomIdByTurmsGroupId
      ..clear()
      ..addEntries(rooms.where((Room r) => r.turmsGroupId != null)
          .map((Room r) => MapEntry<String, int>(r.turmsGroupId!, r.roomId)));
    // 资料页/群详情的缓存按需失效：关系动作各自删掉受影响的那一条，
    // 不在这里整片清空，否则已经打开的资料栏会停在加载态（用户看不到重拉）。
    _dropStaleActive();
    try {
      // 与黑名单弹窗一致取满 100 人；服务端上限也是 100。
      final BlocklistPage page = await api.blocklist(token: token, size: 100);
      _blocked
        ..clear()
        ..addAll(page.items.map((BlocklistItem item) => item.accountId));
    } catch (_) {
      // 黑名单拉不到不影响主流程。
    }
    notifyListeners();
  }

  /// 会话已经不存在（被移出群、被处理掉）时把选中项放掉：
  /// 否则窄屏会停在“列表已收起 + 一个不存在的会话”的死路上。
  void _dropStaleActive() {
    final String? key = activeConversationKey;
    if (key != null && conversationOf(key) == null) {
      activeConversationKey = null;
    }
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
      _syncAvatars(nextFriends.map((Friendship f) => (f.peerAccountId, f.avatar)));
      _roomIdByTurmsGroupId
        ..clear()
        ..addEntries(nextRooms.where((Room r) => r.turmsGroupId != null)
            .map((Room r) => MapEntry<String, int>(r.turmsGroupId!, r.roomId)));
      _dropStaleActive();
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
      if (a[i].peerAccountId != b[i].peerAccountId ||
          a[i].displayName != b[i].displayName ||
          a[i].avatar != b[i].avatar) {
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
    final MyProfile profile = await api.myProfile(token);
    _syncAvatars(<(int, String?)>[(profile.accountId, profile.avatar)]);
    return profile;
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
      avatar: updated.avatar,
      gender: updated.gender,
      birthday: updated.birthday,
    );
    _syncAvatars(<(int, String?)>[(current.accountId, updated.avatar)]);
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

  // —— 头像（服务端是真相，本机只做渲染缓存）——

  String? avatarOf(int accountId) => avatars[accountId];

  /// 把服务端 payload 里的头像写进本机缓存：登录、`mine`、好友、群成员、资料页、资料保存都走这里。
  /// 返回是否有变化，调用方决定要不要 notify。
  bool _syncAvatars(Iterable<(int, String?)> entries) {
    final Map<int, String> next = Map<int, String>.of(avatars);
    bool changed = false;
    for (final (int accountId, String? key) in entries) {
      final String? known = key != null && isKnownAvatar(key) ? key : null;
      if (next[accountId] == known) {
        continue;
      }
      if (known == null) {
        next.remove(accountId);
      } else {
        next[accountId] = known;
      }
      changed = true;
    }
    if (changed) {
      avatars = next;
      _store.saveAvatars(next);
    }
    return changed;
  }

  /// 改当前账号头像：`PUT /api/accounts/me/avatar`，`null` = 清回生成的首字头像。
  /// 服务端是真相，成功后把回显写进本机缓存。
  Future<void> updateAvatar(String? key) async {
    final Account? current = account;
    final String? token = loginToken;
    if (current == null || token == null) {
      throw ApiException(code: 'unauthenticated', message: 'signed out');
    }
    final String? saved = await api.updateAvatar(token: token, avatar: key);
    _syncAvatars(<(int, String?)>[(current.accountId, saved)]);
    notifyListeners();
  }

  Future<CreatedAgent> createAgent(String displayName) async {
    final CreatedAgent created = await api.createAgent(token: loginToken!, displayName: displayName);
    // 密钥只在创建响应里出现一次；列表刷新失败不能把这次响应一起吞掉，否则密钥永久丢失。
    try {
      accounts = await api.mine(identityToken ?? loginToken!);
      // 新 agent 的默认头像由服务端在创建时分配，跟着 `mine` 回显进本机缓存。
      _syncAvatars(accounts.map((Account a) => (a.accountId, a.avatar)));
    } catch (_) {
      // 账号列表下次 refreshAll 会补回来；这里保住 created 才是第一优先级。
    }
    // 后端在建 agent 的同一事务里把归属者与 agent 设成 accepted 好友：立刻重拉关系，
    // 不等 15 秒轮询，创建完就能在好友列表里看到它。
    await refreshRelations();
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
    _profiles.remove(peerAccountId);
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
    final String key = conv.key;
    try {
      // 被加的一方同意后自动打招呼（限一次，失败不回滚好友关系）。
      await sendMessage(conv, '我们已经是好友啦，一起来聊天吧OWO');
    } catch (_) {
      // 新好友在 Turms 的投影有秒级延迟，第一次发送可能撞 `5001`：
      // 2 秒后拿同一个气泡补发一次，仍失败就留给用户手动重试。
      _welcomeRetryTimer?.cancel();
      _welcomeRetryTimer = Timer(const Duration(seconds: 2), () {
        if (_disposed) {
          return;
        }
        final ChatMessage? msg = lastMessage(key);
        final Conversation? live = conversationOf(key);
        if (msg == null || msg.state != MessageState.failed || live == null) {
          return;
        }
        unawaited(retryMessage(live, msg).catchError((Object _) {}));
      });
    }
  }

  Future<void> deleteFriend(int peerAccountId) async {
    await api.deleteFriend(token: loginToken!, peerAccountId: peerAccountId);
    _profiles.remove(peerAccountId);
    _drafts.remove('dm:$peerAccountId');
    if (activeConversationKey == 'dm:$peerAccountId') {
      activeConversationKey = null;
    }
    await refreshAll();
  }

  /// 删除好友并拉黑：被删的一方无法再主动加回来（后端拉黑拦截好友申请）。
  Future<void> deleteFriendAndBlock(int peerAccountId) async {
    await api.deleteFriend(token: loginToken!, peerAccountId: peerAccountId);
    try {
      await api.blockAccount(token: loginToken!, accountId: peerAccountId);
      _blocked.add(peerAccountId);
    } catch (_) {
      // 好友已经删了；拉黑失败不回滚。
    }
    _drafts.remove('dm:$peerAccountId');
    _profiles.remove(peerAccountId);
    if (activeConversationKey == 'dm:$peerAccountId') {
      activeConversationKey = null;
    }
    await refreshAll();
  }

  // —— 群 ——

  Future<Room> createRoom(String name, {String? description}) async {
    final Room room =
        await api.createRoom(token: loginToken!, name: name, description: description);
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
    _roomDetails.remove(roomId);
    // 会话行没了以后没有入口能把它清零，角标会一直挂在导航栏上。
    _unread.remove('room:$roomId');
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
    _syncAvatars(page.items.map((RoomMember m) => (m.accountId, m.avatar)));
    // 视图读 `membersOf`，不通知的话它要等下一次无关的状态变化才会看到这批成员。
    notifyListeners();
    return page;
  }

  // —— 发言 ——

  /// 本地先插「发送中」，Turms 用服务端 `messageId` 落定（时间等自己的推送回声）；
  /// 失败保留正文可重试。
  Future<void> sendMessage(Conversation conv, String text) async {
    final String body = text.trim();
    if (body.isEmpty) {
      return;
    }
    _drafts.remove(conv.key);
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
    await _writeMessage(conv, local);
  }

  Future<void> retryMessage(Conversation conv, ChatMessage message) async {
    message.state = MessageState.sending;
    notifyListeners();
    await _writeMessage(conv, message);
  }

  /// Turms 直写：群用 `turms_group_id`，私聊用对端账号 id；没有 Biz 回执。
  Future<void> _writeMessage(Conversation conv, ChatMessage message) async {
    final String? targetId = conv.isRoom ? conv.turmsGroupId : '${conv.targetId}';
    try {
      if (targetId == null || targetId.isEmpty) {
        // 群句柄还没投影回来：这不是「发送失败」，但当前确实发不出去。
        throw TurmsException(turmsCode: 5006, message: '群尚未完成投影');
      }
      final String messageId = await realtime.send(
        conversationType: conv.type,
        targetId: targetId,
        text: message.text,
      );
      // 雪花 id 在 Web 上会丢精度：精确去重键只认字符串，`serverId` 只作内部用。
      // 推送回声可能先到，已认领的就别覆盖。
      message
        ..state = MessageState.sent
        ..serverIdText ??= messageId
        ..serverId ??= int.tryParse(messageId);
    } on TurmsException catch (e) {
      message.state = MessageState.failed;
      _recoverRealtime(e);
      rethrow;
    } catch (_) {
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
    _readTimer?.cancel();
    _reconnectTimer?.cancel();
    _welcomeRetryTimer?.cancel();
    for (final Timer timer in _typingTimers.values) {
      timer.cancel();
    }
    _typingTimers.clear();
    _stopPolling();
    flushCache();
    // 先摘掉回调再关连接：晚到的 401 或推送不能对已 dispose 的 notifier 调 notifyListeners。
    api.onUnauthenticated = null;
    realtime.disconnect();
    api.close();
    super.dispose();
  }
}
