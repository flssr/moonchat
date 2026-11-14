import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api/api_client.dart';
import '../api/models.dart';
import '../i18n/context_tr.dart';
import '../state/app_state.dart';
import '../theme.dart';
import 'profile_panel.dart';
import 'widgets.dart';

/// S5 联系人：好友、待处理、按账号 ID 加好友、建群。
/// 没有搜人：定位账号只有账号 ID 与主页链接两条路。
class ContactsView extends StatefulWidget {
  const ContactsView({super.key, required this.state, required this.narrow});

  final AppState state;

  /// 外壳按整个客户端宽度判定的 ≤620：与消息页共用同一个断点来源。
  final bool narrow;

  @override
  State<ContactsView> createState() => _ContactsViewState();
}

class _ContactsViewState extends State<ContactsView> {
  final TextEditingController _lookup = TextEditingController();
  final TextEditingController _roomName = TextEditingController();
  String? _lookupError;

  /// 建群表单自己的错误，别借搜索框下面那行显示。
  String? _roomError;
  bool _showRoomForm = false;
  bool _busy = false;

  /// 页签与选中项都在状态层（`docs/truth/frontend/README.md` 的 `friendsTab` / `selectedContact`）。
  String get _tab => widget.state.contactsTab;
  int? get _selectedId => widget.state.selectedContactId;

  @override
  void dispose() {
    _lookup.dispose();
    _roomName.dispose();
    super.dispose();
  }

  Future<void> _find() async {
    if (_busy) {
      return;
    }
    final int? id = int.tryParse(_lookup.text.trim());
    if (id == null) {
      setState(() => _lookupError = '需要数字账号 ID');
      return;
    }
    setState(() {
      _lookupError = null;
      _busy = true;
    });
    try {
      await widget.state.loadProfile(id);
      widget.state.setSelectedContact(id);
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _lookupError = e.displayText);
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  /// 同意/拒绝走同一处：置忙、接住异常、复位，别把失败丢成无人接的异步错误。
  Future<void> _respond(int peerAccountId, String action) async {
    setState(() {
      _busy = true;
      _lookupError = null;
    });
    try {
      await widget.state.respondFriend(peerAccountId, action);
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _lookupError = e.displayText);
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _createRoom() async {
    if (_busy) {
      return;
    }
    final String name = _roomName.text.trim();
    if (name.isEmpty || name.length > 20) {
      setState(() => _roomError = '群名 1–20 字');
      return;
    }
    setState(() {
      _busy = true;
      _roomError = null;
    });
    try {
      final Room room = await widget.state.createRoom(name);
      if (!mounted) {
        return;
      }
      _roomName.clear();
      setState(() => _showRoomForm = false);
      widget.state.selectConversation('room:${room.roomId}');
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _roomError = e.displayText);
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
    final List<Friendship> friends = widget.state.friends;
    final List<Friendship> pending = widget.state.pending;

    return MoonSplitLayout(
      narrow: widget.narrow,
      list: _list(p, friends, pending, widget.narrow),
      detail: _detail(p, widget.narrow),
    );
  }

  Widget _list(MoonPalette p, List<Friendship> friends, List<Friendship> pending, bool narrow) {
    final List<Widget> header = <Widget>[
              Container(
                height: 56,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                alignment: Alignment.centerLeft,
                decoration: BoxDecoration(border: Border(bottom: BorderSide(color: p.line))),
                child: Text(context.tr('联系人'), style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: p.ink)),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Container(
                        height: 34,
                        decoration: BoxDecoration(
                          border: Border.all(color: p.line),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        child: Row(
                          children: <Widget>[
                            Icon(Icons.search, size: 14, color: p.ink3),
                            const SizedBox(width: 6),
                            Expanded(
                              child: TextField(
                                controller: _lookup,
                                keyboardType: TextInputType.number,
                                inputFormatters: <TextInputFormatter>[FilteringTextInputFormatter.digitsOnly],
                                style: TextStyle(fontSize: 12.5, color: p.ink),
                                decoration: InputDecoration(
                                  isDense: true,
                                  border: InputBorder.none,
                                  hintText: context.tr('按账号 ID 查找'),
                                  hintStyle: TextStyle(fontSize: 12.5, color: p.ink3),
                                ),
                                onSubmitted: (_) => _find(),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    MoonButton(label: context.tr('查找'), small: true, busy: _busy, onPressed: _find),
                  ],
                ),
              ),
              if (_lookupError != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(context.tr(_lookupError!), style: TextStyle(fontSize: 11, color: p.accent)),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Row(
                  children: <Widget>[
                    MoonButton(
                      label: _showRoomForm ? context.tr('取消建群') : context.tr('建群'),
                      kind: MoonButtonKind.secondary,
                      small: true,
                      onPressed: () => setState(() {
                        _showRoomForm = !_showRoomForm;
                        _lookupError = null;
                      }),
                    ),
                  ],
                ),
              ),
              if (_showRoomForm)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Container(
                        decoration: BoxDecoration(
                          border: Border.all(color: p.line),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        child: TextField(
                          controller: _roomName,
                          maxLength: 20,
                          style: TextStyle(fontSize: 12.5, color: p.ink),
                          decoration: InputDecoration(
                            isDense: true,
                            border: InputBorder.none,
                            counterText: '',
                            hintText: context.tr('群名（1–20 字）'),
                            hintStyle: TextStyle(fontSize: 12.5, color: p.ink3),
                          ),
                          onSubmitted: (_) => _createRoom(),
                        ),
                      ),
                      const SizedBox(height: 8),
                      MoonButton(label: context.tr('创建'), small: true, busy: _busy, onPressed: _createRoom),
                      if (_roomError != null) ...<Widget>[
                        const SizedBox(height: 6),
                        Text(context.tr(_roomError!), style: TextStyle(fontSize: 11, color: p.accent)),
                      ],
                    ],
                  ),
                ),
              SizedBox(
                height: 36,
                child: Row(
                  children: <Widget>[
                    for (final (String key, String label, int count) in <(String, String, int)>[
                      ('friends', '好友', friends.length),
                      ('pending', '待处理', pending.length),
                    ])
                      Expanded(
                        child: InkWell(
                          onTap: () => widget.state.setContactsTab(key),
                          child: Container(
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              border: Border(
                                bottom: BorderSide(
                                  color: _tab == key ? p.ink : Colors.transparent,
                                ),
                              ),
                            ),
                            child: Text(
                              '${context.tr(label)} $count',
                              style: TextStyle(
                                fontSize: 11.5,
                                color: _tab == key ? p.ink : p.ink3,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ];
    // 窄屏整段可滚：固定头 + 表单 + 列表一起滚，键盘压缩高度时不会把 Column 撑爆。
    final Widget entries = _tab == 'friends'
                    ? (friends.isEmpty
                        ? MoonEmpty(
                            title: context.tr('还没有好友'),
                            hint: context.tr('加好友需要对方的账号 ID 或主页链接。'),
                          )
                        : ListView.builder(
                            shrinkWrap: narrow,
                            physics: narrow ? const NeverScrollableScrollPhysics() : null,
                            itemCount: friends.length,
                            itemBuilder: (BuildContext context, int i) {
                              final Friendship f = friends[i];
                              return InkWell(
                                onTap: () => widget.state.setSelectedContact(f.peerAccountId),
                                child: Container(
                                  height: 52,
                                  padding: const EdgeInsets.symmetric(horizontal: 16),
                                  color: _selectedId == f.peerAccountId ? p.surface2 : Colors.transparent,
                                  child: Row(
                                    children: <Widget>[
                                      MoonAvatar(
                                        name: f.displayName,
                                        seed: f.peerAccountId,
                                        avatar: widget.state.avatarOf(f.peerAccountId),
                                        size: 30,
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          f.displayName,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(fontSize: 13, color: p.ink),
                                        ),
                                      ),
                                      IconButton(
                                        tooltip: context.tr('发消息'),
                                        visualDensity: VisualDensity.compact,
                                        onPressed: () => widget.state.selectConversation('dm:${f.peerAccountId}'),
                                        icon: Icon(Icons.chat_bubble_outline, size: 15, color: p.ink3),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ))
                    : (pending.isEmpty
                        ? MoonEmpty(title: context.tr('没有待处理的申请。'))
                        : ListView.builder(
                            shrinkWrap: narrow,
                            physics: narrow ? const NeverScrollableScrollPhysics() : null,
                            itemCount: pending.length,
                            itemBuilder: (BuildContext context, int i) {
                              final Friendship f = pending[i];
                              return Padding(
                                padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
                                child: Row(
                                  children: <Widget>[
                                    MoonAvatar(
                                      name: f.displayName,
                                      seed: f.peerAccountId,
                                      avatar: widget.state.avatarOf(f.peerAccountId),
                                      size: 30,
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        f.displayName,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(fontSize: 13, color: p.ink),
                                      ),
                                    ),
                                    IconButton(
                                      tooltip: context.tr('同意'),
                                      visualDensity: VisualDensity.compact,
                                      onPressed: _busy ? null : () => _respond(f.peerAccountId, 'accept'),
                                      icon: Icon(Icons.check, size: 16, color: p.ink),
                                    ),
                                    IconButton(
                                      tooltip: context.tr('拒绝'),
                                      visualDensity: VisualDensity.compact,
                                      onPressed: _busy ? null : () => _respond(f.peerAccountId, 'reject'),
                                      icon: Icon(Icons.close, size: 16, color: p.accent),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ));
    final Widget content = Column(
      children: <Widget>[
        ...header,
        if (narrow) entries else Expanded(child: entries),
      ],
    );
    return Container(
      decoration: BoxDecoration(
        color: p.surface,
        border: narrow
            ? Border(bottom: BorderSide(color: p.line))
            : Border(right: BorderSide(color: p.line)),
      ),
      child: narrow ? SingleChildScrollView(child: content) : content,
    );
  }

  Widget _detail(MoonPalette p, bool narrow) {
    return Container(
      color: p.bg,
      padding: narrow ? const EdgeInsets.all(18) : EdgeInsets.zero,
      child: _selectedId == null
          ? MoonEmpty(
              title: context.tr('选一个人'),
              hint: context.tr('群成员、好友、按账号 ID 查找的结果都在这里打开资料页。'),
            )
          : SingleChildScrollView(
              child: Align(
                alignment: Alignment.topLeft,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: ProfilePanel(
                    state: widget.state,
                    accountId: _selectedId!,
                    onMessage: () => widget.state.selectConversation('dm:$_selectedId'),
                  ),
                ),
              ),
            ),
    );
  }
}
