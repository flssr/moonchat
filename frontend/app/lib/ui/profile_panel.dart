import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../api/models.dart';
import '../i18n/context_tr.dart';
import '../state/app_state.dart';
import '../theme.dart';
import 'widgets.dart';

/// S6 资料页的内容：只有名字、账号 ID、关系状态（`docs/truth/frontend/README.md`）。
/// 非好友只有「加好友」，好友才有「发消息」「删除好友」。
///
/// 数据从 `AppState` 读（`profileOf` / `loadProfile`），不再自己请求；
/// 内嵌与覆盖层共用这一个组件，行为只有一份。
class ProfilePanel extends StatefulWidget {
  const ProfilePanel({
    super.key,
    required this.state,
    required this.accountId,
    this.onMessage,
  });

  final AppState state;
  final int accountId;
  final VoidCallback? onMessage;

  @override
  State<ProfilePanel> createState() => _ProfilePanelState();
}

class _ProfilePanelState extends State<ProfilePanel> {
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
      _error = null;
      _load();
    }
  }

  Future<void> _load() async {
    try {
      await widget.state.loadProfile(widget.accountId);
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _error = e.displayText);
      }
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
      // 关系动作会让状态层清掉资料页缓存，重新拉一次拿最新的 is_friend。
      await _load();
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.displayTextIn(context), style: TextStyle(color: context.moon.ink)),
            backgroundColor: context.moon.surface,
          ),
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
      return MoonEmpty(title: context.tr(_error!));
    }
    final Profile? profile = widget.state.profileOf(widget.accountId);
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
                    Text(profile.displayName,
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: p.ink)),
                    const SizedBox(height: 2),
                    MonoText('#${profile.accountId}', selectable: true),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_isSelf)
            Text(context.tr('这是你自己。'), style: TextStyle(fontSize: 12, color: p.ink3))
          else if (profile.isFriend) ...<Widget>[
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                MoonButton(
                  label: context.tr('发消息'),
                  kind: MoonButtonKind.secondary,
                  small: true,
                  onPressed: widget.onMessage,
                ),
                MoonButton(
                  label: context.tr('删除好友'),
                  kind: MoonButtonKind.danger,
                  small: true,
                  onPressed: _busy ? null : () => _confirmDelete(profile),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(context.tr('删除后会话保留、历史只读，不能再发新消息。'), style: TextStyle(fontSize: 11.5, color: p.ink3)),
          ] else if (_hasIncoming) ...<Widget>[
            Wrap(
              spacing: 8,
              children: <Widget>[
                MoonButton(
                  label: context.tr('同意'),
                  small: true,
                  onPressed: _busy ? null : () => _run(() => widget.state.respondFriend(profile.accountId, 'accept')),
                ),
                MoonButton(
                  label: context.tr('拒绝'),
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
                  label: context.tr('加好友'),
                  small: true,
                  onPressed: _busy ? null : () => _run(() => widget.state.requestFriend(profile.accountId)),
                ),
                const SizedBox(height: 8),
                Text(context.tr('非好友看不到发消息入口：私聊只从好友列表进入。'), style: TextStyle(fontSize: 11.5, color: p.ink3)),
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
        title: Text(context.tr('删除好友'), style: TextStyle(fontSize: 16, color: context.moon.ink)),
        content: Text(
          trArgs(context, '确认删除 {name}？会话会保留，历史只读。', <String, String>{
            'name': profile.displayName,
          }),
          style: TextStyle(fontSize: 13, color: context.moon.ink2),
        ),
        actions: <Widget>[
          MoonButton(
            label: context.tr('取消'),
            kind: MoonButtonKind.text,
            small: true,
            onPressed: () => Navigator.of(context).pop(false),
          ),
          MoonButton(
            label: context.tr('删除'),
            kind: MoonButtonKind.danger,
            small: true,
            onPressed: () => Navigator.of(context).pop(true),
          ),
        ],
      ),
    );
    if (ok == true) {
      await _run(() => widget.state.deleteFriend(profile.accountId));
    }
  }
}

/// 资料页覆盖层：由外壳按 `AppState.profileAccountId` 渲染。
/// 旧实现把内容放在 `showGeneralDialog` 的 `transitionBuilder` 里、page 是空的，
/// 现在内容归组件、开关归状态，不再依赖一个空路由。
class ProfileOverlay extends StatelessWidget {
  const ProfileOverlay({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final MoonPalette p = context.moon;
    final int accountId = state.profileAccountId!;
    return GestureDetector(
      onTap: state.closeProfile,
      child: ColoredBox(
        color: Colors.black.withValues(alpha: 0.18),
        child: Align(
          alignment: Alignment.centerRight,
          child: GestureDetector(
            onTap: () {},
            child: Material(
              color: p.surface,
              child: Container(
                width: MediaQuery.sizeOf(context).width < 480
                    ? MediaQuery.sizeOf(context).width * 0.88
                    : 352,
                height: double.infinity,
                decoration: BoxDecoration(border: Border(left: BorderSide(color: p.line))),
                child: SafeArea(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Align(
                        alignment: Alignment.centerRight,
                        child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: IconButton(
                            onPressed: state.closeProfile,
                            icon: Icon(Icons.close, size: 16, color: p.ink3),
                            tooltip: context.tr('关闭'),
                          ),
                        ),
                      ),
                      Expanded(
                        child: SingleChildScrollView(
                          child: ProfilePanel(
                            state: state,
                            accountId: accountId,
                            onMessage: () {
                              state.selectConversation('dm:$accountId');
                              state.closeProfile();
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
        ),
      ),
    );
  }
}
