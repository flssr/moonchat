import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../api/models.dart';
import '../state/app_state.dart';
import '../theme.dart';
import 'widgets.dart';

/// S6 资料页的内容：只有名字、账号 ID、关系状态（`SCREEN-MAP.md` §4）。
/// 非好友只有「加好友」，好友才有「发消息」「删除好友」。
class ProfilePanel extends StatefulWidget {
  const ProfilePanel({
    super.key,
    required this.state,
    required this.accountId,
    this.onMessage,
    this.onChanged,
  });

  final AppState state;
  final int accountId;
  final VoidCallback? onMessage;

  /// 关系变化后通知外层刷新（同意申请后私聊入口立刻出现）。
  final VoidCallback? onChanged;

  @override
  State<ProfilePanel> createState() => _ProfilePanelState();
}

class _ProfilePanelState extends State<ProfilePanel> {
  Profile? _profile;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant ProfilePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.accountId != widget.accountId) {
      _profile = null;
      _error = null;
      _load();
    }
  }

  Future<void> _load() async {
    try {
      final Profile p = await widget.state.profile(widget.accountId);
      if (!mounted) {
        return;
      }
      setState(() {
        _profile = p;
        _error = null;
      });
    } on ApiException catch (e) {
      if (!mounted) {
        return;
      }
      setState(() => _error = e.displayText);
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
      await _load();
      widget.onChanged?.call();
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.displayText, style: TextStyle(color: context.moon.ink))),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  bool get _isSelf => widget.state.account?.accountId == widget.accountId;

  bool get _hasIncoming => widget.state.pending.any((Friendship f) => f.peerAccountId == widget.accountId);

  @override
  Widget build(BuildContext context) {
    final MoonPalette p = context.moon;
    if (_error != null) {
      return MoonEmpty(title: _error!);
    }
    final Profile? profile = _profile;
    if (profile == null) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 1.5)),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              MoonAvatar(name: profile.displayName, seed: profile.accountId, size: 44),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(profile.displayName, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: p.ink)),
                    const SizedBox(height: 2),
                    MonoText('#${profile.accountId}', selectable: true),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_isSelf)
            Text('这是你自己。', style: TextStyle(fontSize: 12, color: p.ink3))
          else if (profile.isFriend) ...<Widget>[
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                MoonButton(
                  label: '发消息',
                  kind: MoonButtonKind.secondary,
                  small: true,
                  onPressed: widget.onMessage,
                ),
                MoonButton(
                  label: '删除好友',
                  kind: MoonButtonKind.danger,
                  small: true,
                  onPressed: _busy ? null : () => _confirmDelete(profile),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text('删除后会话保留、历史只读，不能再发新消息。', style: TextStyle(fontSize: 11.5, color: p.ink3)),
          ] else if (_hasIncoming) ...<Widget>[
            Wrap(
              spacing: 8,
              children: <Widget>[
                MoonButton(
                  label: '同意',
                  small: true,
                  onPressed: _busy ? null : () => _run(() => widget.state.respondFriend(profile.accountId, 'accept')),
                ),
                MoonButton(
                  label: '拒绝',
                  kind: MoonButtonKind.secondary,
                  small: true,
                  onPressed: _busy ? null : () => _run(() => widget.state.respondFriend(profile.accountId, 'reject')),
                ),
              ],
            ),
          ] else
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                MoonButton(
                  label: '加好友',
                  small: true,
                  onPressed: _busy ? null : () => _run(() => widget.state.requestFriend(profile.accountId)),
                ),
                const SizedBox(height: 8),
                Text('非好友看不到发消息入口：私聊只从好友列表进入。', style: TextStyle(fontSize: 11.5, color: p.ink3)),
              ],
            ),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(Profile profile) async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        backgroundColor: context.moon.surface,
        title: Text('删除好友', style: TextStyle(fontSize: 16, color: context.moon.ink)),
        content: Text(
          '确认删除 ${profile.displayName}？会话会保留，历史只读。',
          style: TextStyle(fontSize: 13, color: context.moon.ink2),
        ),
        actions: <Widget>[
          MoonButton(
            label: '取消',
            kind: MoonButtonKind.text,
            small: true,
            onPressed: () => Navigator.of(context).pop(false),
          ),
          MoonButton(
            label: '删除',
            kind: MoonButtonKind.danger,
            small: true,
            onPressed: () => Navigator.of(context).pop(true),
          ),
        ],
      ),
    );
    if (ok == true) {
      await _run(() => widget.state.deleteFriend(profile.accountId));
      widget.onChanged?.call();
    }
  }
}

/// 右侧抽屉形态的资料页（群成员、会话信息栏用）。
Future<void> showProfileSheet(BuildContext context, AppState state, int accountId, {VoidCallback? onMessage}) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: '关闭资料页',
    barrierColor: Colors.black.withValues(alpha: 0.18),
    transitionDuration: const Duration(milliseconds: 200),
    pageBuilder: (BuildContext context, Animation<double> a, Animation<double> b) => const SizedBox.shrink(),
    transitionBuilder: (BuildContext context, Animation<double> a, Animation<double> b, Widget child) {
      final Animation<Offset> slide = Tween<Offset>(
        begin: const Offset(0.04, 0),
        end: Offset.zero,
      ).animate(CurvedAnimation(parent: a, curve: const Cubic(.2, .7, .2, 1)));
      return Align(
        alignment: Alignment.centerRight,
        child: FractionalTranslation(
          translation: slide.value,
          child: Material(
            color: context.moon.surface,
            child: Container(
              width: MediaQuery.sizeOf(context).width < 480
                  ? MediaQuery.sizeOf(context).width * 0.88
                  : 352,
              height: double.infinity,
              decoration: BoxDecoration(
                border: Border(left: BorderSide(color: context.moon.line)),
              ),
              child: SafeArea(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Align(
                      alignment: Alignment.centerRight,
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: IconButton(
                          onPressed: () => Navigator.of(context).pop(),
                          icon: Icon(Icons.close, size: 16, color: context.moon.ink3),
                          tooltip: '关闭',
                        ),
                      ),
                    ),
                    Expanded(
                      child: SingleChildScrollView(
                        child: ProfilePanel(
                          state: state,
                          accountId: accountId,
                          onMessage: onMessage == null
                              ? null
                              : () {
                                  onMessage();
                                  Navigator.of(context).pop();
                                },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}
