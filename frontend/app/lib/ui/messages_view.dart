import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api/api_client.dart';
import '../api/models.dart';
import '../i18n/context_tr.dart';
import '../state/app_state.dart';
import '../theme.dart';
import 'profile_panel.dart';
import 'widgets.dart';

/// S3 消息：会话列表 + 消息区 + 信息栏（`SCREEN-MAP.md` §4）。
/// 当前会话、筛选、跳转都在 `AppState` 里，这里只读状态、只调动作。
class MessagesView extends StatefulWidget {
  const MessagesView({
    super.key,
    required this.state,
    this.showInfo = true,
    this.showList = true,
    this.onToggleList,
  });

  final AppState state;

  /// 容器 ≤860 收起信息栏，≤620 收起会话列表（`MoonBreakpoints`）。
  final bool showInfo;
  final bool showList;

  /// 窄屏下的列表开关；宽屏为 null。
  final VoidCallback? onToggleList;

  @override
  State<MessagesView> createState() => _MessagesViewState();
}

class _MessagesViewState extends State<MessagesView> {
  /// 草稿按会话存：给 A 打的话切到 B 不会跟着过去。
  final Map<String, TextEditingController> _drafts = <String, TextEditingController>{};
  final FocusNode _composerFocus = FocusNode();

  /// 发送错误也按会话存。
  final Map<String, String> _sendErrors = <String, String>{};
  bool _sending = false;

  /// 已经为哪个会话拉过历史：防止重建时反复翻页。
  String? _loadedKey;

  @override
  void dispose() {
    for (final TextEditingController c in _drafts.values) {
      c.dispose();
    }
    _composerFocus.dispose();
    super.dispose();
  }

  TextEditingController _draftFor(String key) => _drafts.putIfAbsent(key, TextEditingController.new);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadActive());
  }

  @override
  void didUpdateWidget(covariant MessagesView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 外壳每次 notifyListeners 都会重建这个 widget；只有「换了个会话」才该拉历史，
    // 否则新消息/筛选/资料页加载都会触发一次翻页，历史会被无声地整段抽干。
    final String? key = widget.state.activeConversationKey;
    if (key != _loadedKey) {
      _loadedKey = key;
      _loadActive();
    }
  }

  /// 打开会话时拉一页历史；游标与去重在 `AppState.loadHistory` 里。
  void _loadActive() {
    final String? key = widget.state.activeConversationKey;
    if (key == null) {
      return;
    }
    final Conversation? conv = widget.state.conversationOf(key);
    if (conv != null) {
      widget.state.loadHistory(conv);
    }
  }

  List<Conversation> get _filtered {
    final List<Conversation> all = widget.state.conversations;
    if (widget.state.filter == 'dm') {
      return all.where((Conversation c) => c.type == 'dm').toList();
    }
    if (widget.state.filter == 'room') {
      return all.where((Conversation c) => c.isRoom).toList();
    }
    return all;
  }

  Future<void> _send(Conversation conv) async {
    final TextEditingController composer = _draftFor(conv.key);
    final String text = composer.text;
    if (text.trim().isEmpty || _sending) {
      return;
    }
    setState(() {
      _sending = true;
      _sendErrors.remove(conv.key);
    });
    try {
      await widget.state.sendMessage(conv, text);
      // 发送期间用户可能接着打字：只有输入框还是刚发出去的那句时才清空。
      if (mounted && composer.text.trim() == text.trim()) {
        composer.clear();
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _sendErrors[conv.key] = e.displayText);
      }
    } finally {
      if (mounted) {
        setState(() => _sending = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final MoonPalette p = context.moon;
    final Conversation? active = widget.state.activeConversationKey == null
        ? null
        : widget.state.conversationOf(widget.state.activeConversationKey!);

    return Row(
      children: <Widget>[
        // 会话列表：252 宽，窄屏由外层收起。
        if (widget.showList)
        Container(
          width: 252,
          decoration: BoxDecoration(
            color: p.surface,
            border: Border(right: BorderSide(color: p.line)),
          ),
          child: Column(
            children: <Widget>[
              Container(
                height: 56,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                alignment: Alignment.centerLeft,
                decoration: BoxDecoration(border: Border(bottom: BorderSide(color: p.line))),
                child: Row(
                  children: <Widget>[
                    Text(context.tr('消息'), style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: p.ink)),
                    const Spacer(),
                    if (widget.onToggleList != null && widget.state.activeConversationKey != null)
                      IconButton(
                        tooltip: context.tr('收起会话列表'),
                        visualDensity: VisualDensity.compact,
                        onPressed: widget.onToggleList,
                        icon: Icon(Icons.chevron_left, size: 18, color: p.ink3),
                      )
                    else
                      const MoonTag(text: 'V1'),
                  ],
                ),
              ),
              SizedBox(
                height: 36,
                child: Row(
                  children: <Widget>[
                    for (final (String key, String label) in <(String, String)>[
                      ('all', '全部'),
                      ('dm', '私聊'),
                      ('room', '群聊'),
                    ])
                      Expanded(
                        child: InkWell(
                          onTap: () => widget.state.setFilter(key),
                          child: Container(
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              border: Border(
                                bottom: BorderSide(
                                  color: widget.state.filter == key ? p.ink : Colors.transparent,
                                  width: 1,
                                ),
                              ),
                            ),
                            child: Text(
                              context.tr(label),
                              style: TextStyle(
                                fontSize: 11.5,
                                color: widget.state.filter == key ? p.ink : p.ink3,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: _filtered.isEmpty
                    ? MoonEmpty(
                        title: context.tr('这个账号还没有会话'),
                        hint: context.tr('先加好友，或被拉进群。'),
                      )
                    : ListView.builder(
                        padding: EdgeInsets.zero,
                        itemCount: _filtered.length,
                        itemBuilder: (BuildContext context, int i) {
                          final Conversation c = _filtered[i];
                          final bool selected = c.key == widget.state.activeConversationKey;
                          return InkWell(
                            onTap: () => widget.state.selectConversation(c.key),
                            child: Container(
                              height: 52,
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              color: selected ? p.surface2 : Colors.transparent,
                              child: Row(
                                children: <Widget>[
                                  MoonAvatar(name: c.title, seed: c.targetId, size: 34),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: <Widget>[
                                        Text(
                                          c.title,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(fontSize: 13, color: p.ink),
                                        ),
                                        Text(
                                          c.isRoom
                                              ? (c.memberCount == null
                                                  ? context.tr('群聊')
                                                  : trArgs(context, '群聊 · {m} 人', <String, String>{
                                                      'm': '${c.memberCount}',
                                                    }))
                                              : context.tr('私聊'),
                                          style: TextStyle(fontSize: 11.5, color: p.ink3),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (c.isRoom && c.ownerAccountId == widget.state.account?.accountId)
                                    MoonTag(text: context.tr('群主')),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
              Container(
                height: 56,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(border: Border(top: BorderSide(color: p.line))),
                child: Row(
                  children: <Widget>[
                    MoonAvatar(
                      name: widget.state.account?.displayName ?? '',
                      seed: widget.state.account?.accountId ?? 0,
                      size: 28,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            widget.state.account?.displayName ?? '',
                            style: TextStyle(fontSize: 12.5, color: p.ink),
                          ),
                          MonoText('#${widget.state.account?.accountId ?? ''}'),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        // 消息区。
        Expanded(
          child: active == null
              ? MoonEmpty(
                  title: context.tr('选一个会话'),
                  hint: context.tr('私聊只能从好友进入，群聊只能从自己已加入的群进入。'),
                )
              : Column(
                  children: <Widget>[
                    Container(
                      height: 56,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(
                        color: p.surface,
                        border: Border(bottom: BorderSide(color: p.line)),
                      ),
                      child: Row(
                        children: <Widget>[
                          if (!widget.showList)
                            IconButton(
                              tooltip: context.tr('会话列表'),
                              visualDensity: VisualDensity.compact,
                              onPressed: widget.onToggleList,
                              icon: Icon(Icons.menu, size: 18, color: p.ink3),
                            ),
                          MoonAvatar(name: active.title, seed: active.targetId, size: 30),
                          const SizedBox(width: 10),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: <Widget>[
                              Text(
                                active.title,
                                style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: p.ink),
                              ),
                              Text(
                                active.isRoom
                                    ? (active.memberCount == null
                                        ? context.tr('群聊')
                                        : trArgs(context, '群聊 · {m} 人', <String, String>{
                                            'm': '${active.memberCount}',
                                          }))
                                    : context.tr('私聊'),
                                style: TextStyle(fontSize: 11, color: p.ink3),
                              ),
                            ],
                          ),
                          const Spacer(),
                          if (widget.state.realtimeUp) MoonTag(text: context.tr('实时')),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Container(
                        color: p.surface,
                        child: _MessageList(
                          key: PageStorageKey<String>(active.key),
                          state: widget.state,
                          conversation: active,
                          onRetry: (ChatMessage m) {
                            // retry 失败会 rethrow：这里自己接住，别让它变成无人接的异步错误。
                            widget.state.retryMessage(active, m).catchError((Object e) {
                              if (mounted) {
                                setState(() => _sendErrors[active.key] = e is ApiException ? e.displayText : '重试失败');
                              }
                            });
                          },
                        ),
                      ),
                    ),
                    if (_sendErrors[active.key] != null)
                      Container(
                        width: double.infinity,
                        color: p.surface,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                        child: Text(context.tr(_sendErrors[active.key]!), style: TextStyle(fontSize: 11.5, color: p.accent)),
                      ),
                    Container(
                      padding: const EdgeInsets.fromLTRB(16, 10, 12, 12),
                      decoration: BoxDecoration(
                        color: p.surface,
                        border: Border(top: BorderSide(color: p.line)),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: <Widget>[
                          Expanded(
                            child: Container(
                              decoration: BoxDecoration(
                                border: Border.all(color: p.line),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              child: TextField(
                                controller: _draftFor(active.key),
                                focusNode: _composerFocus,
                                minLines: 1,
                                maxLines: 4,
                                maxLength: 500,
                                style: TextStyle(fontSize: 13.5, color: p.ink),
                                decoration: InputDecoration(
                                  isDense: true,
                                  border: InputBorder.none,
                                  counterText: '',
                                  hintText: context.tr('写点什么…'),
                                  hintStyle: TextStyle(fontSize: 13.5, color: p.ink3),
                                ),
                                onSubmitted: (_) => _send(active),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          // 只让发送按钮跟着输入内容重建，别整屏（含消息列表）跟着每个按键重建。
                          ValueListenableBuilder<TextEditingValue>(
                            valueListenable: _draftFor(active.key),
                            builder: (BuildContext context, TextEditingValue value, Widget? _) => MoonButton(
                              label: context.tr('发送'),
                              busy: _sending,
                              onPressed: value.text.trim().isEmpty ? null : () => _send(active),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
        ),
        // 信息栏：236 宽，容器 ≤860 时收起（由外层控制）。
        if (active != null && widget.showInfo)
          Container(
            width: 236,
            decoration: BoxDecoration(
              color: p.bg,
              border: Border(left: BorderSide(color: p.line)),
            ),
            child: active.isRoom
                ? _RoomInfo(key: ValueKey<int>(active.targetId), state: widget.state, roomId: active.targetId)
                : SingleChildScrollView(
                    child: ProfilePanel(
                      state: widget.state,
                      accountId: active.targetId,
                      onMessage: () => _composerFocus.requestFocus(),
                    ),
                  ),
          ),
      ],
    );
  }
}

class _MessageList extends StatefulWidget {
  const _MessageList({
    super.key,
    required this.state,
    required this.conversation,
    required this.onRetry,
  });

  final AppState state;
  final Conversation conversation;
  final ValueChanged<ChatMessage> onRetry;

  @override
  State<_MessageList> createState() => _MessageListState();
}

class _MessageListState extends State<_MessageList> {
  final ScrollController _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_maybeLoadOlder);
  }

  @override
  void dispose() {
    _scroll
      ..removeListener(_maybeLoadOlder)
      ..dispose();
    super.dispose();
  }

  /// 列表是 reverse 的：滚到 maxScrollExtent 就是最早一条，继续往前翻。
  void _maybeLoadOlder() {
    if (!_scroll.hasClients) {
      return;
    }
    final ScrollPosition pos = _scroll.position;
    if (pos.pixels >= pos.maxScrollExtent - 120) {
      widget.state.loadHistory(widget.conversation);
    }
  }

  @override
  Widget build(BuildContext context) {
    final MoonPalette p = context.moon;
    final List<ChatMessage> messages = widget.state.messagesOf(widget.conversation.key);
    if (messages.isEmpty) {
      return MoonEmpty(
        title: context.tr('关系已经成立，发第一句话吧'),
        hint: context.tr('历史消息由客户端持 Turms 凭据直接查，Biz 不在读路径上。'),
      );
    }
    final bool loadingOlder = widget.state.isHistoryLoading(widget.conversation.key);
    return ListView.builder(
      controller: _scroll,
      reverse: true,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      itemCount: messages.length + (loadingOlder ? 1 : 0),
      itemBuilder: (BuildContext context, int i) {
        if (loadingOlder && i == messages.length) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Center(
              child: SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 1.5)),
            ),
          );
        }
        final ChatMessage m = messages[messages.length - 1 - i];
        final bool failed = m.state == MessageState.failed;
        return Semantics(
          liveRegion: true,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(
              crossAxisAlignment: m.mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: <Widget>[
                Container(
                  constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.72),
                  padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
                  decoration: BoxDecoration(
                    color: m.mine ? p.bubbleMe : p.bubbleThem,
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(12),
                      topRight: const Radius.circular(12),
                      bottomLeft: Radius.circular(m.mine ? 12 : 4),
                      bottomRight: Radius.circular(m.mine ? 4 : 12),
                    ),
                    border: Border.all(color: failed ? p.accent : p.line),
                  ),
                  child: Text(m.text, style: TextStyle(fontSize: 13.5, height: 1.6, color: p.ink)),
                ),
                const SizedBox(height: 3),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    MonoText(switch (m.state) {
                      MessageState.sending => context.tr('发送中…'),
                      MessageState.sent => formatClock(m.sentAt),
                      MessageState.failed => context.tr('未发出'),
                    }),
                    if (failed) ...<Widget>[
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: () => widget.onRetry(m),
                        child: Text(context.tr('重试'), style: TextStyle(fontSize: 10.5, color: p.accent)),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// S4 群信息：群名、群主、成员、邀请、退群 / 移人。
class _RoomInfo extends StatefulWidget {
  const _RoomInfo({super.key, required this.state, required this.roomId});

  final AppState state;
  final int roomId;

  @override
  State<_RoomInfo> createState() => _RoomInfoState();
}

class _RoomInfoState extends State<_RoomInfo> {
  final TextEditingController _invite = TextEditingController();
  String? _inviteError;

  /// 成员行上的错误（移除失败），与邀请输入框的错误分开显示。
  String? _memberError;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _invite.dispose();
    super.dispose();
  }

  /// 数据都由状态层持有：这里只触发加载，不在视图里存第二份。
  /// 顺序执行：两个都完成时各自 notify，成员列表不会因为先到的群详情而空着。
  Future<void> _load() async {
    try {
      await widget.state.loadRoom(widget.roomId);
      await widget.state.loadMembers(widget.roomId, force: true);
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _inviteError = e.displayText);
      }
    }
  }

  Future<void> _inviteById() async {
    final int? id = int.tryParse(_invite.text.trim());
    if (id == null) {
      setState(() => _inviteError = '需要数字账号 ID');
      return;
    }
    setState(() {
      _busy = true;
      _inviteError = null;
    });
    try {
      // `addMember` 已经把成员刷新过了，这里不再整群重拉。
      await widget.state.addMember(widget.roomId, id);
      _invite.clear();
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _inviteError = e.displayText);
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _leave() async {
    setState(() => _busy = true);
    try {
      // 退群是显式动作：状态层会把当前会话清掉，不再用 `-1` 哨兵通知外层。
      await widget.state.leaveRoom(widget.roomId);
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _inviteError = e.displayText);
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final MoonPalette p = context.moon;
    final int me = widget.state.account?.accountId ?? 0;
    final RoomDetail? detail = widget.state.roomOf(widget.roomId);
    final Paged<RoomMember>? members = widget.state.membersOf(widget.roomId);
    final bool isOwner = detail?.ownerAccountId == me;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 20),
      children: <Widget>[
        Text(
          widget.state.conversationOf('room:${widget.roomId}')?.title ?? context.tr('群'),
          style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: p.ink),
        ),
        const SizedBox(height: 4),
        MonoText(trArgs(context, '群 {id} · {m} 人', <String, String>{
          'id': '${widget.roomId}',
          'm': '${detail?.memberCount ?? 0}',
        })),
        const SizedBox(height: 16),
        Text(context.tr('成员'), style: TextStyle(fontSize: 11, letterSpacing: 1, color: p.ink3)),
        const SizedBox(height: 6),
        for (final RoomMember m in members?.items ?? const <RoomMember>[])
          InkWell(
            onTap: () => widget.state.openProfile(m.accountId),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: <Widget>[
                  MoonAvatar(name: m.displayName, seed: m.accountId, size: 24),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      m.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12.5, color: p.ink),
                    ),
                  ),
                  if (m.accountId == detail?.ownerAccountId) MoonTag(text: context.tr('群主'), strong: true),
                  if (isOwner && m.accountId != me)
                    IconButton(
                      tooltip: context.tr('移除'),
                      visualDensity: VisualDensity.compact,
                      onPressed: _busy
                          ? null
                          : () async {
                              setState(() {
                                _busy = true;
                                _memberError = null;
                              });
                              try {
                                await widget.state.removeMember(widget.roomId, m.accountId);
                              } on ApiException catch (e) {
                                if (mounted) {
                                  setState(() => _memberError = e.displayText);
                                }
                              } finally {
                                if (mounted) {
                                  setState(() => _busy = false);
                                }
                              }
                            },
                      icon: Icon(Icons.person_remove_outlined, size: 14, color: p.accent),
                    ),
                ],
              ),
            ),
          ),
        // 成员接口是唯一分页的接口（默认 50）；超过一页时明确告诉用户，别假装是全部。
        if ((members?.total ?? 0) > (members?.items.length ?? 0))
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: MonoText(trArgs(context, '仅显示前 {n} 位，共 {m} 位', <String, String>{
              'n': '${members!.items.length}',
              'm': '${members.total}',
            })),
          ),
        const SizedBox(height: 16),
        if (_memberError != null) ...<Widget>[
          Text(context.tr(_memberError!), style: TextStyle(fontSize: 11, color: p.accent)),
          const SizedBox(height: 8),
        ],
        Text(context.tr('邀请'), style: TextStyle(fontSize: 11, letterSpacing: 1, color: p.ink3)),
        const SizedBox(height: 6),
        Row(
          children: <Widget>[
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(color: p.line),
                  borderRadius: BorderRadius.circular(8),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: TextField(
                  controller: _invite,
                  keyboardType: TextInputType.number,
                  inputFormatters: <TextInputFormatter>[FilteringTextInputFormatter.digitsOnly],
                  style: TextStyle(fontSize: 12.5, color: p.ink),
                  decoration: InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                    hintText: context.tr('账号 ID'),
                    hintStyle: TextStyle(fontSize: 12.5, color: p.ink3),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 6),
            MoonButton(label: context.tr('邀请'), small: true, onPressed: _busy ? null : _inviteById),
          ],
        ),
        if (_inviteError != null) ...<Widget>[
          const SizedBox(height: 6),
          Text(context.tr(_inviteError!), style: TextStyle(fontSize: 11, color: p.accent)),
        ],
        const SizedBox(height: 16),
        if (isOwner)
          Align(
            alignment: Alignment.centerLeft,
            child: Tooltip(
              message: context.tr('群主不能退群：V1 没有群主转让，也没有解散群'),
              child: Opacity(
                opacity: 0.4,
                child: MoonButton(
                  label: context.tr('退群'),
                  kind: MoonButtonKind.secondary,
                  small: true,
                  onPressed: null,
                ),
              ),
            ),
          )
        else
          MoonButton(
            label: context.tr('退群'),
            kind: MoonButtonKind.secondary,
            small: true,
            onPressed: _busy ? null : _leave,
          ),
        const SizedBox(height: 8),
        Text(
          isOwner ? context.tr('群主不能退群（V1 没有转让）。') : context.tr('邀请即入群，不需要对方同意。'),
          style: TextStyle(fontSize: 11, height: 1.5, color: p.ink3),
        ),
      ],
    );
  }
}
