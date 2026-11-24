import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../account_id.dart';
import '../api/api_client.dart';
import '../api/models.dart';
import '../i18n/context_tr.dart';
import '../state/app_state.dart';
import '../theme.dart';
import 'friend_picker.dart';
import 'profile_panel.dart';
import 'widgets.dart';

/// S3 消息：会话列表 + 消息区 + 信息栏（`docs/truth/frontend/README.md`）。
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

  /// 已经拉过成员的群：消息区的头像与顶部头像堆叠都要用成员名字。
  final Set<int> _membersRequested = <int>{};

  @override
  void dispose() {
    for (final TextEditingController c in _drafts.values) {
      c.dispose();
    }
    _composerFocus.dispose();
    super.dispose();
  }

  TextEditingController _draftFor(String key) => _drafts.putIfAbsent(
        key,
        () => TextEditingController(text: widget.state.draftFor(key)),
      );

  /// 上一次看到的资料浮层账号；用来识别「浮层刚关掉」。
  int? _profileSeen;

  @override
  void initState() {
    super.initState();
    _profileSeen = widget.state.profileAccountId;
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadActive());
  }

  @override
  void didUpdateWidget(covariant MessagesView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 外壳每次 notifyListeners 都会重建这个 widget；只有「换了个会话」才该拉历史，
    // 否则新消息/筛选/资料页加载都会触发一次翻页，历史会被无声地整段抽干。
    final String? key = widget.state.activeConversationKey;
    final bool switched = key != _loadedKey;
    if (switched) {
      _loadedKey = key;
      _loadActive();
    }
    // 资料浮层是全屏遮罩：用户在浮层里点「发消息」或点遮罩关掉后，
    // 焦点要交还输入框；否则他以为能直接打字，输入其实还停在别处。
    final int? profile = widget.state.profileAccountId;
    final bool profileClosed = _profileSeen != null && profile == null;
    _profileSeen = profile;
    if (profileClosed || (switched && key != null)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _composerFocus.requestFocus();
        }
      });
    }
  }

  /// 打开会话时拉一页历史；游标与去重在 `AppState.loadHistory` 里。
  void _loadActive() {
    final String? key = widget.state.activeConversationKey;
    if (key == null) {
      return;
    }
    final Conversation? conv = widget.state.conversationOf(key);
    if (conv == null) {
      return;
    }
    widget.state.loadHistory(conv);
    if (conv.isRoom && _membersRequested.add(conv.targetId)) {
      // 失败就静默：没有成员名字时，消息里退回账号 id，头像退回首字头像。
      widget.state.loadMembers(conv.targetId).ignore();
    }
  }

  List<Conversation> get _filtered {
    final List<Conversation> all = widget.state.conversations;
    final List<Conversation> list = widget.state.filter == 'dm'
        ? all.where((Conversation c) => c.type == 'dm').toList()
        : widget.state.filter == 'room'
            ? all.where((Conversation c) => c.isRoom).toList()
            : List<Conversation>.of(all);
    // 有新消息的会话排到最前，按最后一条消息时间倒序；没有消息的留在后面。
    list.sort((Conversation a, Conversation b) {
      final DateTime? ta = widget.state.lastMessage(a.key)?.sentAt;
      final DateTime? tb = widget.state.lastMessage(b.key)?.sentAt;
      if (ta == null && tb == null) {
        return a.title.compareTo(b.title);
      }
      if (ta == null) {
        return 1;
      }
      if (tb == null) {
        return -1;
      }
      return tb.compareTo(ta);
    });
    return list;
  }

  /// 输入框里的 Enter：直接发送；Shift+Enter 交给默认行为换行（issue #24）。
  ///
  /// 输入法组词中（中文候选还没上屏）的 Enter 必须放过，否则会把半截候选当成消息发出去。
  KeyEventResult _handleComposerKey(Conversation conv, KeyEvent event) {
    if (event is! KeyDownEvent || event.logicalKey != LogicalKeyboardKey.enter) {
      return KeyEventResult.ignored;
    }
    if (HardwareKeyboard.instance.isShiftPressed) {
      return KeyEventResult.ignored;
    }
    final TextRange composing = _draftFor(conv.key).value.composing;
    if (composing.isValid && !composing.isCollapsed) {
      return KeyEventResult.ignored;
    }
    _send(conv);
    return KeyEventResult.handled;
  }

  Future<void> _send(Conversation conv) async {
    final TextEditingController composer = _draftFor(conv.key);
    final String text = composer.text;
    if (text.trim().isEmpty || _sending) {
      return;
    }
    // 删好友后历史会话还在，但私聊必须仍是好友；后端也会拒，先在客户端给出提示。
    if (!conv.isRoom &&
        !widget.state.friends.any((Friendship f) => f.peerAccountId == conv.targetId)) {
      if (mounted) {
        await showDialog<void>(
          context: context,
          builder: (BuildContext context) => AlertDialog(
            backgroundColor: context.moon.surface,
            content: Text(
              context.tr('当前不是对方好友，请添加后再进行会话'),
              style: TextStyle(fontSize: 13, color: context.moon.ink),
            ),
            actions: <Widget>[
              MoonButton(
                label: context.tr('知道了'),
                small: true,
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        );
      }
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
                              // 大字号 + 英文时页签会放不下：单行省略，别换行压到会话行上。
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
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
                              decoration: BoxDecoration(
                                color: selected ? p.surface2 : Colors.transparent,
                                border: Border(
                                  left: BorderSide(
                                    color: selected ? p.ink : Colors.transparent,
                                    width: 2,
                                  ),
                                ),
                              ),
                              child: Row(
                                children: <Widget>[
                                  GestureDetector(
                                    onTap: c.isRoom
                                        ? null
                                        : () => widget.state.openProfileById(c.targetId),
                                    child: MoonAvatar(
                                      name: c.title,
                                      seed: c.targetId,
                                      avatar: c.isRoom ? null : widget.state.avatarOf(c.targetId),
                                      size: 34,
                                    ),
                                  ),
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
                                        Builder(
                                          builder: (BuildContext context) {
                                            final String draft = widget.state.draftFor(c.key);
                                            if (draft.trim().isNotEmpty) {
                                              return Text.rich(
                                                TextSpan(children: <InlineSpan>[
                                                  TextSpan(
                                                    text: context.tr('【草稿】'),
                                                    style: const TextStyle(
                                                      fontSize: 11.5,
                                                      color: Color(0xFFE81123),
                                                    ),
                                                  ),
                                                  TextSpan(
                                                    text: draft,
                                                    style: TextStyle(fontSize: 11.5, color: p.ink3),
                                                  ),
                                                ]),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              );
                                            }
                                            final ChatMessage? last = widget.state.lastMessage(c.key);
                                            return Text(
                                              (last?.recalled ?? false)
                                                  ? context.tr('已撤回')
                                                  : (last?.text ??
                                                      (c.isRoom
                                                          ? (c.memberCount == null
                                                              ? context.tr('群聊')
                                                              : trArgs(context, '群聊 · {m} 人', <String, String>{
                                                                  'm': '${c.memberCount}',
                                                                }))
                                                          : context.tr('私聊'))),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(fontSize: 11.5, color: p.ink3),
                                            );
                                          },
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (c.isRoom && c.ownerAccountId == widget.state.account?.accountId)
                                    MoonTag(text: context.tr('群主')),
                                  if (widget.state.unreadFor(c.key) > 0)
                                    Container(
                                      margin: const EdgeInsets.only(left: 6),
                                      constraints: const BoxConstraints(minWidth: 18),
                                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                      decoration: BoxDecoration(
                                        color: p.accent,
                                        borderRadius: BorderRadius.circular(9),
                                      ),
                                      child: Text(
                                        widget.state.unreadFor(c.key) > 99
                                            ? '99+'
                                            : '${widget.state.unreadFor(c.key)}',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(fontSize: 10, color: p.accentInk),
                                      ),
                                    ),
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
                      avatar: widget.state.account == null
                          ? null
                          : widget.state.avatarOf(widget.state.account!.accountId),
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
                          MonoText(
                            widget.state.account == null
                                ? ''
                                : '#${shortAccountId(widget.state.account!.accountId)}',
                          ),
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
                          _ConversationMark(state: widget.state, conversation: active),
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
                            // 重试成功要收掉旧的横幅：否则「连接已断开」会一直挂着。
                            setState(() => _sendErrors.remove(active.key));
                            // retry 失败会 rethrow：这里自己接住，别让它变成无人接的异步错误。
                            widget.state.retryMessage(active, m).catchError((Object e) {
                              if (mounted) {
                                setState(() => _sendErrors[active.key] = e is ApiException ? e.displayText : '重试失败');
                              }
                            });
                          },
                          onRecall: (ChatMessage m) {
                            widget.state.recallMessage(m).catchError((Object e) {
                              if (mounted) {
                                setState(() => _sendErrors[active.key] = e is ApiException ? e.displayText : '操作失败，请重试');
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
                              child: Focus(
                                // 只借它接按键冒泡，本身不要抢焦点、不进 Tab 顺序。
                                canRequestFocus: false,
                                skipTraversal: true,
                                onKeyEvent: (FocusNode _, KeyEvent event) =>
                                    _handleComposerKey(active, event),
                                child: TextField(
                                  controller: _draftFor(active.key),
                                  focusNode: _composerFocus,
                                  onChanged: (String value) =>
                                      widget.state.setDraft(active.key, value),
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
                                ),
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
    required this.onRecall,
  });

  final AppState state;
  final Conversation conversation;
  final ValueChanged<ChatMessage> onRetry;
  final ValueChanged<ChatMessage> onRecall;

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
    final List<ChatMessage> messages = widget.state.messagesOf(widget.conversation.key);
    if (messages.isEmpty) {
      return const SizedBox.shrink();
    }
    final bool loadingOlder = widget.state.isHistoryLoading(widget.conversation.key);
    final Map<int, RoomMember> members = <int, RoomMember>{
      for (final RoomMember m
          in widget.state.membersOf(widget.conversation.targetId)?.items ?? const <RoomMember>[])
        m.accountId: m,
    };
    final List<Object> rows = _rows(messages);
    return ListView.builder(
      controller: _scroll,
      reverse: true,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      itemCount: rows.length + (loadingOlder ? 1 : 0),
      itemBuilder: (BuildContext context, int i) {
        if (loadingOlder && i == rows.length) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Center(
              child: SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 1.5)),
            ),
          );
        }
        final Object row = rows[rows.length - 1 - i];
        if (row is DateTime) {
          return _DayDivider(day: row);
        }
        return _MessageGroup(
          group: row as List<ChatMessage>,
          state: widget.state,
          conversation: widget.conversation,
          members: members,
          onRetry: widget.onRetry,
          onRecall: widget.onRecall,
        );
      },
    );
  }

  /// 同一人、五分钟内、同一天的消息并成一组；跨天插一行日期。
  List<Object> _rows(List<ChatMessage> messages) {
    final List<Object> rows = <Object>[];
    List<ChatMessage> current = <ChatMessage>[];
    DateTime? day;
    ChatMessage? previous;

    void flush() {
      if (current.isNotEmpty) {
        rows.add(List<ChatMessage>.unmodifiable(current));
        current = <ChatMessage>[];
      }
    }

    for (final ChatMessage m in messages) {
      // 日期线按本地日历日切：气泡时钟用的是本地时间，按 UTC 切会在午夜前后错一天。
      final DateTime local = m.sentAt.toLocal();
      final DateTime d = DateTime(local.year, local.month, local.day);
      if (day != d) {
        flush();
        rows.add(d);
        day = d;
      } else if (previous != null &&
          (previous.senderAccountId != m.senderAccountId ||
              previous.state != MessageState.sent ||
              m.state != MessageState.sent ||
              m.sentAt.difference(previous.sentAt).inMinutes >= 5)) {
        flush();
      }
      current.add(m);
      previous = m;
    }
    flush();
    return rows;
  }
}

/// 跨天的分隔：一条细线夹着本地的日期。
class _DayDivider extends StatelessWidget {
  const _DayDivider({required this.day});

  final DateTime day;

  @override
  Widget build(BuildContext context) {
    final MoonPalette p = context.moon;
    final String label = MaterialLocalizations.of(context).formatMediumDate(day);
    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 14),
      child: Row(
        children: <Widget>[
          Expanded(child: Container(height: 1, color: p.line)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: MonoText(label),
          ),
          Expanded(child: Container(height: 1, color: p.line)),
        ],
      ),
    );
  }
}

/// 一组消息：头像只在第一条出现，时间/状态只挂在最后一条。
class _MessageGroup extends StatelessWidget {
  const _MessageGroup({
    required this.group,
    required this.state,
    required this.conversation,
    required this.members,
    required this.onRetry,
    required this.onRecall,
  });

  final List<ChatMessage> group;
  final AppState state;
  final Conversation conversation;
  final Map<int, RoomMember> members;
  final ValueChanged<ChatMessage> onRetry;
  final ValueChanged<ChatMessage> onRecall;

  /// 只给本人、已落定、未撤回且仍在 5 分钟窗口内的消息入口；服务端还会再判一次。
  bool _canRecall(ChatMessage m) =>
      m.mine &&
      m.state == MessageState.sent &&
      !m.recalled &&
      m.serverIdText != null &&
      DateTime.now().toUtc().difference(m.sentAt) < const Duration(minutes: 5);

  String _name() {
    final ChatMessage first = group.first;
    if (first.mine) {
      return state.account?.displayName ?? '';
    }
    if (conversation.isRoom) {
      return members[first.senderAccountId]?.displayName ??
          '#${shortAccountId(first.senderAccountId)}';
    }
    return conversation.title;
  }

  String? _avatar() {
    final ChatMessage first = group.first;
    if (conversation.isRoom) {
      return state.avatarOf(first.senderAccountId);
    }
    return state.avatarOf(first.mine ? first.senderAccountId : conversation.targetId);
  }

  @override
  Widget build(BuildContext context) {
    final ChatMessage first = group.first;
    final ChatMessage last = group.last;
    final bool mine = first.mine;
    final String name = _name();

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: mine ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: <Widget>[
          if (!mine) ...<Widget>[
            GestureDetector(
              onTap: () => state.openProfileById(first.senderAccountId),
              child: MoonAvatar(
                name: name,
                seed: first.senderAccountId,
                avatar: _avatar(),
                size: 26,
              ),
            ),
            const SizedBox(width: 10),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment: mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                if (!mine && name.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(left: 2, bottom: 3),
                    child: MonoText(name),
                  ),
                for (int i = 0; i < group.length; i++)
                  Padding(
                    padding: EdgeInsets.only(top: i == 0 ? 0 : 3),
                    child: _bubble(context, group[i], i == group.length - 1),
                  ),
                const SizedBox(height: 4),
                _meta(context, last),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _bubble(BuildContext context, ChatMessage m, bool isLast) {
    final MoonPalette p = context.moon;
    final bool failed = m.state == MessageState.failed;
    final Widget bubble = Container(
      constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.66),
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
      decoration: BoxDecoration(
        color: m.mine ? p.bubbleMe : p.bubbleThem,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(14),
          topRight: const Radius.circular(14),
          bottomLeft: Radius.circular(m.mine ? 14 : (isLast ? 4 : 14)),
          bottomRight: Radius.circular(m.mine ? (isLast ? 4 : 14) : 14),
        ),
        border: Border.all(color: failed ? p.accent : p.line),
      ),
      child: m.recalled
          ? Text(
              context.tr('已撤回'),
              style: TextStyle(
                fontSize: 13.5,
                height: 1.6,
                color: p.ink3,
                fontStyle: FontStyle.italic,
              ),
            )
          : Text(m.text, style: TextStyle(fontSize: 13.5, height: 1.6, color: p.ink)),
    );
    if (!_canRecall(m)) {
      return bubble;
    }
    // 右键或长按自己刚发的气泡也能撤回；组尾的「撤回」是更明显的入口。
    return GestureDetector(
      onSecondaryTap: () => onRecall(m),
      onLongPress: () => onRecall(m),
      child: bubble,
    );
  }

  Widget _meta(BuildContext context, ChatMessage last) {
    final MoonPalette p = context.moon;
    final bool failed = last.state == MessageState.failed;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        MonoText(switch (last.state) {
          MessageState.sending => context.tr('发送中…'),
          MessageState.sent => formatClock(last.sentAt),
          MessageState.failed => context.tr('未发出'),
        }),
        if (failed) ...<Widget>[
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () => onRetry(last),
            child: Text(context.tr('重试'), style: TextStyle(fontSize: 10.5, color: p.accent)),
          ),
        ],
        if (_canRecall(last)) ...<Widget>[
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () => onRecall(last),
            child: Text(context.tr('撤回'), style: TextStyle(fontSize: 10.5, color: p.ink3)),
          ),
        ],
      ],
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
  String? _inviteError;

  /// 成员行上的错误（移除/邀请失败）。
  String? _memberError;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
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

  Future<void> _openInvite() async {
    final Set<int> memberIds = (widget.state.membersOf(widget.roomId)?.items ?? const <RoomMember>[])
        .map((RoomMember m) => m.accountId)
        .toSet();
    final List<int>? picked = await showFriendPicker(
      context,
      state: widget.state,
      exclude: memberIds,
      multi: false,
    );
    if (picked == null || picked.isEmpty || !mounted) {
      return;
    }
    setState(() {
      _busy = true;
      _memberError = null;
    });
    try {
      // `addMember` 已经把成员刷新过了，这里不再整群重拉。
      await widget.state.addMember(widget.roomId, picked.first);
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _memberError = e.displayText);
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
          // 邀请/移除后 `loadMembers` 已刷新总数，群详情里的旧值会滞后。
          'm': '${members?.total ?? detail?.memberCount ?? 0}',
        })),
        if (detail?.description != null && detail!.description!.trim().isNotEmpty) ...<Widget>[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: p.surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: p.line),
            ),
            child: Text(
              detail.description!,
              style: TextStyle(fontSize: 12.5, height: 1.6, color: p.ink2),
            ),
          ),
        ],
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
                  MoonAvatar(
                    name: m.displayName,
                    seed: m.accountId,
                    avatar: widget.state.avatarOf(m.accountId),
                    size: 24,
                  ),
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
        InkWell(
          onTap: _busy ? null : _openInvite,
          borderRadius: BorderRadius.circular(18),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: <Widget>[
                Container(
                  width: 24,
                  height: 24,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: p.line),
                  ),
                  child: Icon(Icons.add, size: 14, color: p.ink3),
                ),
                const SizedBox(width: 8),
                Text(
                  context.tr('邀请'),
                  style: TextStyle(fontSize: 12.5, color: p.ink3),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        if (_memberError != null) ...<Widget>[
          Text(context.tr(_memberError!), style: TextStyle(fontSize: 11, color: p.accent)),
          const SizedBox(height: 8),
        ],
        if (_inviteError != null) ...<Widget>[
          Text(context.tr(_inviteError!), style: TextStyle(fontSize: 11, color: p.accent)),
          const SizedBox(height: 8),
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


/// 会话标题旁的头像：私聊是对方；群聊是前三位成员叠在一起，超出用 +N。
class _ConversationMark extends StatelessWidget {
  const _ConversationMark({required this.state, required this.conversation});

  final AppState state;
  final Conversation conversation;

  @override
  Widget build(BuildContext context) {
    final MoonPalette p = context.moon;
    if (!conversation.isRoom) {
      return GestureDetector(
        onTap: () => state.openProfileById(conversation.targetId),
        child: MoonAvatar(
          name: conversation.title,
          seed: conversation.targetId,
          avatar: state.avatarOf(conversation.targetId),
          size: 30,
        ),
      );
    }
    final Paged<RoomMember>? page = state.membersOf(conversation.targetId);
    final List<RoomMember> items = page?.items ?? const <RoomMember>[];
    if (items.isEmpty) {
      return MoonAvatar(name: conversation.title, seed: conversation.targetId, size: 30);
    }
    final List<RoomMember> shown = items.take(3).toList(growable: false);
    final int extra = (page?.total ?? 0) - shown.length;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        SizedBox(
          width: 22 + (shown.length - 1) * 13,
          height: 30,
          child: Stack(
            children: <Widget>[
              for (int i = 0; i < shown.length; i++)
                Positioned(
                  left: i * 13,
                  top: 4,
                  child: Container(
                    padding: const EdgeInsets.all(1),
                    decoration: BoxDecoration(shape: BoxShape.circle, color: p.surface),
                    child: MoonAvatar(
                      name: shown[i].displayName,
                      seed: shown[i].accountId,
                      avatar: state.avatarOf(shown[i].accountId),
                      size: 20,
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (extra > 0) ...<Widget>[
          const SizedBox(width: 6),
          MonoText('+$extra'),
        ],
      ],
    );
  }
}
