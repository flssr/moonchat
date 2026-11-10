import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api/api_client.dart';
import '../api/models.dart';
import '../state/app_state.dart';
import '../theme.dart';
import 'profile_panel.dart';
import 'widgets.dart';

/// S3 消息：会话列表 + 消息区 + 信息栏（`SCREEN-MAP.md` §4）。
class MessagesView extends StatefulWidget {
  const MessagesView({
    super.key,
    required this.state,
    required this.activeKey,
    required this.onSelect,
    required this.filter,
    required this.onFilter,
    required this.onOpenProfile,
    this.showInfo = true,
    this.showList = true,
  });

  final AppState state;
  final String? activeKey;
  final ValueChanged<String> onSelect;
  final String filter; // all | dm | room
  final ValueChanged<String> onFilter;
  final ValueChanged<int> onOpenProfile;

  /// 容器 ≤1000 收起信息栏，≤700 收起会话列表（DESIGN-SPEC §5）。
  final bool showInfo;
  final bool showList;

  @override
  State<MessagesView> createState() => _MessagesViewState();
}

class _MessagesViewState extends State<MessagesView> {
  final TextEditingController _composer = TextEditingController();
  final FocusNode _composerFocus = FocusNode();
  String? _sendError;
  bool _sending = false;

  @override
  void dispose() {
    _composer.dispose();
    _composerFocus.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadActive());
  }

  @override
  void didUpdateWidget(covariant MessagesView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.activeKey != widget.activeKey) {
      _loadActive();
    }
  }

  /// 打开会话时拉一页历史；游标与去重在 `AppState.loadHistory` 里。
  void _loadActive() {
    final String? key = widget.activeKey;
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
    if (widget.filter == 'dm') {
      return all.where((Conversation c) => c.type == 'dm').toList();
    }
    if (widget.filter == 'room') {
      return all.where((Conversation c) => c.isRoom).toList();
    }
    return all;
  }

  Future<void> _send(Conversation conv) async {
    final String text = _composer.text;
    if (text.trim().isEmpty || _sending) {
      return;
    }
    setState(() {
      _sending = true;
      _sendError = null;
    });
    try {
      await widget.state.sendMessage(conv, text);
      if (mounted) {
        _composer.clear();
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _sendError = e.displayText);
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
    final Conversation? active =
        widget.activeKey == null ? null : widget.state.conversationOf(widget.activeKey!);

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
                    Text('消息', style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: p.ink)),
                    const Spacer(),
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
                          onTap: () => widget.onFilter(key),
                          child: Container(
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              border: Border(
                                bottom: BorderSide(
                                  color: widget.filter == key ? p.ink : Colors.transparent,
                                  width: 1,
                                ),
                              ),
                            ),
                            child: Text(
                              label,
                              style: TextStyle(
                                fontSize: 11.5,
                                color: widget.filter == key ? p.ink : p.ink3,
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
                        title: '这个账号还没有会话',
                        hint: '先加好友，或被拉进群。',
                      )
                    : ListView.builder(
                        padding: EdgeInsets.zero,
                        itemCount: _filtered.length,
                        itemBuilder: (BuildContext context, int i) {
                          final Conversation c = _filtered[i];
                          final bool selected = c.key == widget.activeKey;
                          return InkWell(
                            onTap: () => widget.onSelect(c.key),
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
                                              ? (c.memberCount == null ? '群聊' : '群聊 · ${c.memberCount} 人')
                                              : '私聊',
                                          style: TextStyle(fontSize: 11.5, color: p.ink3),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (c.isRoom && c.ownerAccountId == widget.state.account?.accountId)
                                    const MoonTag(text: '群主'),
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
              ? const MoonEmpty(title: '选一个会话', hint: '私聊只能从好友进入，群聊只能从自己已加入的群进入。')
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
                                        ? '群聊'
                                        : '群聊 · ${active.memberCount} 人')
                                    : '私聊',
                                style: TextStyle(fontSize: 11, color: p.ink3),
                              ),
                            ],
                          ),
                          const Spacer(),
                          if (widget.state.realtimeUp) const MoonTag(text: '实时'),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Container(
                        color: p.surface,
                        child: _MessageList(
                          state: widget.state,
                          conversation: active,
                          onRetry: (ChatMessage m) => widget.state.retryMessage(active, m),
                        ),
                      ),
                    ),
                    if (_sendError != null)
                      Container(
                        width: double.infinity,
                        color: p.surface,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                        child: Text(_sendError!, style: TextStyle(fontSize: 11.5, color: p.accent)),
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
                                controller: _composer,
                                focusNode: _composerFocus,
                                minLines: 1,
                                maxLines: 4,
                                maxLength: 500,
                                style: TextStyle(fontSize: 13.5, color: p.ink),
                                decoration: InputDecoration(
                                  isDense: true,
                                  border: InputBorder.none,
                                  counterText: '',
                                  hintText: '写点什么…',
                                  hintStyle: TextStyle(fontSize: 13.5, color: p.ink3),
                                ),
                                onSubmitted: (_) => _send(active),
                                onChanged: (_) => setState(() {}),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          MoonButton(
                            label: '发送',
                            busy: _sending,
                            onPressed: _composer.text.trim().isEmpty ? null : () => _send(active),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
        ),
        // 信息栏：236 宽，容器 ≤1000 时收起（由外层控制）。
        if (active != null && widget.showInfo)
          Container(
            width: 236,
            decoration: BoxDecoration(
              color: p.bg,
              border: Border(left: BorderSide(color: p.line)),
            ),
            child: active.isRoom
                ? _RoomInfo(state: widget.state, roomId: active.targetId, onOpenProfile: widget.onOpenProfile)
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
  const _MessageList({required this.state, required this.conversation, required this.onRetry});

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
      return const MoonEmpty(
        title: '关系已经成立，发第一句话吧',
        hint: '历史消息由客户端持 Turms 凭据直接查，Biz 不在读路径上。',
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
                      MessageState.sending => '发送中…',
                      MessageState.sent => formatClock(m.sentAt),
                      MessageState.failed => '未发出',
                    }),
                    if (failed) ...<Widget>[
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: () => widget.onRetry(m),
                        child: Text('重试', style: TextStyle(fontSize: 10.5, color: p.accent)),
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
  const _RoomInfo({required this.state, required this.roomId, required this.onOpenProfile});

  final AppState state;
  final int roomId;
  final ValueChanged<int> onOpenProfile;

  @override
  State<_RoomInfo> createState() => _RoomInfoState();
}

class _RoomInfoState extends State<_RoomInfo> {
  final TextEditingController _invite = TextEditingController();
  RoomDetail? _detail;
  Paged<RoomMember>? _members;
  String? _inviteError;
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

  Future<void> _load() async {
    try {
      final List<Object> r = await Future.wait(<Future<Object>>[
        widget.state.api.room(token: widget.state.loginToken!, roomId: widget.roomId),
        widget.state.loadMembers(widget.roomId, force: true),
      ]);
      if (!mounted) {
        return;
      }
      setState(() {
        _detail = r[0] as RoomDetail;
        _members = r[1] as Paged<RoomMember>;
      });
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
      await widget.state.addMember(widget.roomId, id);
      _invite.clear();
      await _load();
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
      await widget.state.leaveRoom(widget.roomId);
      if (mounted) {
        widget.onOpenProfile(-1); // 触发外层重算会话
      }
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
    final bool isOwner = _detail?.ownerAccountId == me;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 20),
      children: <Widget>[
        Text(
          widget.state.conversationOf('room:${widget.roomId}')?.title ?? '群',
          style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: p.ink),
        ),
        const SizedBox(height: 4),
        MonoText('群 ${widget.roomId} · ${_detail?.memberCount ?? 0} 人'),
        const SizedBox(height: 16),
        Text('成员', style: TextStyle(fontSize: 11, letterSpacing: 1, color: p.ink3)),
        const SizedBox(height: 6),
        for (final RoomMember m in _members?.items ?? const <RoomMember>[])
          InkWell(
            onTap: () => widget.onOpenProfile(m.accountId),
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
                  if (m.accountId == _detail?.ownerAccountId) const MoonTag(text: '群主', strong: true),
                  if (isOwner && m.accountId != me)
                    IconButton(
                      tooltip: '移除',
                      visualDensity: VisualDensity.compact,
                      onPressed: _busy
                          ? null
                          : () async {
                              try {
                                await widget.state.removeMember(widget.roomId, m.accountId);
                                await _load();
                              } on ApiException catch (e) {
                                if (context.mounted) {
                                  setState(() => _inviteError = e.displayText);
                                }
                              }
                            },
                      icon: Icon(Icons.person_remove_outlined, size: 14, color: p.accent),
                    ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 16),
        Text('邀请', style: TextStyle(fontSize: 11, letterSpacing: 1, color: p.ink3)),
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
                    hintText: '账号 ID',
                    hintStyle: TextStyle(fontSize: 12.5, color: p.ink3),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 6),
            MoonButton(label: '邀请', small: true, onPressed: _busy ? null : _inviteById),
          ],
        ),
        if (_inviteError != null) ...<Widget>[
          const SizedBox(height: 6),
          Text(_inviteError!, style: TextStyle(fontSize: 11, color: p.accent)),
        ],
        const SizedBox(height: 16),
        if (isOwner)
          Align(
            alignment: Alignment.centerLeft,
            child: Tooltip(
              message: '群主不能退群：V1 没有群主转让，也没有解散群',
              child: Opacity(
                opacity: 0.4,
                child: MoonButton(
                  label: '退群',
                  kind: MoonButtonKind.secondary,
                  small: true,
                  onPressed: null,
                ),
              ),
            ),
          )
        else
          MoonButton(
            label: '退群',
            kind: MoonButtonKind.secondary,
            small: true,
            onPressed: _busy ? null : _leave,
          ),
        const SizedBox(height: 8),
        Text(
          isOwner ? '群主不能退群（V1 没有转让）。' : '邀请即入群，不需要对方同意。',
          style: TextStyle(fontSize: 11, height: 1.5, color: p.ink3),
        ),
      ],
    );
  }
}
