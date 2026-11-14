import 'package:flutter/material.dart';

import '../api/models.dart';
import '../i18n/context_tr.dart';
import '../state/app_state.dart';
import '../theme.dart';
import 'account_view.dart';
import 'contacts_view.dart';
import 'messages_view.dart';
import 'profile_editor.dart';
import 'profile_panel.dart';
import 'settings_dialog.dart';
import 'widgets.dart';

/// 客户端外壳：56 导航 + 各视图自己的列表 / 内容 / 信息栏。
/// 当前视图与当前会话都在 `AppState` 里，这里只负责布局与窄屏的列表开关。
class HomeShell extends StatefulWidget {
  const HomeShell({
    super.key,
    required this.state,
    required this.onToggleTheme,
    required this.brightness,
    required this.textScale,
    required this.onLanguageChanged,
    required this.onTextScaleChanged,
  });

  final AppState state;
  final ValueChanged<Brightness> onToggleTheme;
  final Brightness brightness;
  final double textScale;
  final ValueChanged<String> onLanguageChanged;
  final ValueChanged<double> onTextScaleChanged;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  /// 窄屏下会话列表是否展开；null 表示按「有没有选中会话」自动决定。
  bool? _listOpen;
  String? _lastActiveKey;

  @override
  Widget build(BuildContext context) {
    // 外壳自己监听状态：视图切换、资料页开关都靠它重建，不依赖外层有没有 AnimatedBuilder。
    return ListenableBuilder(
      listenable: widget.state,
      builder: (BuildContext context, Widget? _) => _buildShell(context),
    );
  }

  Widget _buildShell(BuildContext context) {
    final MoonPalette p = context.moon;
    final AppState state = widget.state;
    return Scaffold(
      backgroundColor: p.bg,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints c) {
            // 断点按整个客户端宽度判定（`docs/truth/frontend/design.md` 的容器查询对象是 .app），
            // 联系人与账号页也复用同一个 narrow，避免各自再按「扣掉导航栏后的宽度」量一次。
            final bool narrow = c.maxWidth <= MoonBreakpoints.hideList;
            final bool showInfo = c.maxWidth > MoonBreakpoints.hideInfo;
            // 选中/清空会话后回到自动模式，否则窄屏会卡在「列表 + 被挤扁的消息区」。
            if (state.activeConversationKey != _lastActiveKey) {
              _lastActiveKey = state.activeConversationKey;
              _listOpen = null;
            }
            // 没有选中会话时列表就是唯一可用的导航，不能再被收起；选中后才允许手动开合。
            final bool listVisible = !narrow ||
                state.activeConversationKey == null ||
                (_listOpen ?? false);

            final Widget body = switch (state.view) {
              'contacts' => ContactsView(state: state, narrow: narrow),
              'account' => AccountView(state: state, narrow: narrow),
              _ => MessagesView(
                  state: state,
                  showInfo: showInfo,
                  showList: listVisible,
                  onToggleList: narrow
                      ? () => setState(() => _listOpen = !listVisible)
                      : null,
                ),
            };

            return Stack(
              children: <Widget>[
                Row(
                  children: <Widget>[
                    _NavRail(
                      view: state.view,
                      account: state.account,
                      avatar: state.account == null ? null : state.avatarOf(state.account!.accountId),
                      onOpenProfile: () => showProfileEditor(context, state),
                      onOpenSettings: () => showSettingsDialog(
                        context,
                        textScale: widget.textScale,
                        onTextScaleChanged: widget.onTextScaleChanged,
                        onLanguageChanged: widget.onLanguageChanged,
                      ),
                      onSelect: state.showView,
                      pendingCount: state.pending.length,
                      brightness: widget.brightness,
                      onToggleTheme: widget.onToggleTheme,
                      onLogout: state.logout,
                    ),
                    Expanded(child: body),
                  ],
                ),
                // 资料页是覆盖层，不改变左侧选中项（`docs/truth/frontend/README.md`）。
                if (state.profileAccountId != null)
                  ProfileOverlay(state: state),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _NavRail extends StatelessWidget {
  const _NavRail({
    required this.view,
    required this.account,
    required this.avatar,
    required this.onOpenProfile,
    required this.onOpenSettings,
    required this.onSelect,
    required this.pendingCount,
    required this.brightness,
    required this.onToggleTheme,
    required this.onLogout,
  });

  final String view;
  final Account? account;
  final String? avatar;
  final VoidCallback onOpenProfile;
  final VoidCallback onOpenSettings;
  final ValueChanged<String> onSelect;
  final int pendingCount;
  final Brightness brightness;
  final ValueChanged<Brightness> onToggleTheme;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    final MoonPalette p = context.moon;
    return Container(
      width: 56,
      decoration: BoxDecoration(
        color: p.surface,
        border: Border(right: BorderSide(color: p.line)),
      ),
      child: Column(
        children: <Widget>[
          const SizedBox(height: 8),
          Tooltip(
            message: context.tr('个人资料'),
            child: InkWell(
              onTap: onOpenProfile,
              child: SizedBox(
                width: 56,
                height: 44,
                child: Center(
                  child: MoonAvatar(
                    name: account?.displayName ?? '',
                    seed: account?.accountId ?? 0,
                    avatar: avatar,
                    size: 28,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          _RailButton(
            icon: Icons.chat_bubble_outline,
            label: context.tr('消息'),
            selected: view == 'messages',
            onTap: () => onSelect('messages'),
          ),
          _RailButton(
            icon: Icons.people_outline,
            label: context.tr('联系人'),
            selected: view == 'contacts',
            badge: pendingCount,
            onTap: () => onSelect('contacts'),
          ),
          _RailButton(
            icon: Icons.person_outline,
            label: context.tr('账号'),
            selected: view == 'account',
            onTap: () => onSelect('account'),
          ),
          const Spacer(),
          _RailButton(
            icon: Icons.settings_outlined,
            label: context.tr('设置'),
            selected: false,
            onTap: onOpenSettings,
          ),
          _RailButton(
            icon: brightness == Brightness.dark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
            label: context.tr(brightness == Brightness.dark ? '切到亮色' : '切到暗色'),
            selected: false,
            onTap: () => onToggleTheme(brightness),
          ),
          _RailButton(
            icon: Icons.logout,
            label: context.tr('退出登录'),
            selected: false,
            onTap: onLogout,
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}

class _RailButton extends StatelessWidget {
  const _RailButton({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.badge = 0,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final int badge;

  @override
  Widget build(BuildContext context) {
    final MoonPalette p = context.moon;
    return Tooltip(
      message: label,
      child: InkWell(
        onTap: onTap,
        child: Container(
          width: 56,
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            border: Border(left: BorderSide(color: selected ? p.ink : Colors.transparent, width: 2)),
          ),
          child: Stack(
            clipBehavior: Clip.none,
            children: <Widget>[
              Icon(icon, size: 19, color: selected ? p.ink : p.ink3),
              if (badge > 0)
                Positioned(
                  right: -6,
                  top: -4,
                  child: Container(
                    height: 14,
                    constraints: const BoxConstraints(minWidth: 14),
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: p.accent, borderRadius: BorderRadius.circular(999)),
                    child: Text(
                      badge > 9 ? '9+' : '$badge',
                      style: TextStyle(fontSize: 9, color: p.accentInk),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
