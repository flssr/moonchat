import 'package:flutter/material.dart';

import '../state/app_state.dart';
import '../theme.dart';
import 'account_view.dart';
import 'contacts_view.dart';
import 'messages_view.dart';
import 'profile_panel.dart';

/// 容器断点：单点定义，代码与本文件说明、`DESIGN-SPEC.md` §5 三处对齐。
class MoonBreakpoints {
  const MoonBreakpoints._();

  static const double hideInfo = 860;
  static const double hideList = 620;
}

/// 客户端外壳：56 导航 + 各视图自己的列表 / 内容 / 信息栏。
/// 当前视图与当前会话都在 `AppState` 里，这里只负责布局与窄屏的列表开关。
class HomeShell extends StatefulWidget {
  const HomeShell({
    super.key,
    required this.state,
    required this.onToggleTheme,
    required this.brightness,
  });

  final AppState state;
  final ValueChanged<Brightness> onToggleTheme;
  final Brightness brightness;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  /// 窄屏下会话列表是否展开；宽屏恒为 false（由断点决定直接常显）。
  bool _listOpen = false;

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
            final bool narrow = c.maxWidth < MoonBreakpoints.hideList;
            final bool showInfo = c.maxWidth >= MoonBreakpoints.hideInfo;
            // 窄屏默认收起列表；没有选中会话时直接展开，避免开局是一块空白。
            final bool listVisible = !narrow || _listOpen || state.activeConversationKey == null;

            final Widget body = switch (state.view) {
              'contacts' => ContactsView(state: state),
              'account' => AccountView(state: state),
              _ => MessagesView(
                  state: state,
                  showInfo: showInfo,
                  showList: listVisible,
                  onToggleList: narrow
                      ? () => setState(() => _listOpen = !_listOpen)
                      : null,
                ),
            };

            return Stack(
              children: <Widget>[
                Row(
                  children: <Widget>[
                    _NavRail(
                      view: state.view,
                      onSelect: state.showView,
                      pendingCount: state.pending.length,
                      brightness: widget.brightness,
                      onToggleTheme: widget.onToggleTheme,
                      onLogout: state.logout,
                    ),
                    Expanded(child: body),
                  ],
                ),
                // 资料页是覆盖层，不改变左侧选中项（`SCREEN-MAP.md` §2）。
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
    required this.onSelect,
    required this.pendingCount,
    required this.brightness,
    required this.onToggleTheme,
    required this.onLogout,
  });

  final String view;
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
          const SizedBox(height: 12),
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: p.surface2,
              shape: BoxShape.circle,
              border: Border.all(color: p.lineStrong),
            ),
          ),
          const SizedBox(height: 20),
          _RailButton(
            icon: Icons.chat_bubble_outline,
            label: '消息',
            selected: view == 'messages',
            onTap: () => onSelect('messages'),
          ),
          _RailButton(
            icon: Icons.people_outline,
            label: '联系人',
            selected: view == 'contacts',
            badge: pendingCount,
            onTap: () => onSelect('contacts'),
          ),
          _RailButton(
            icon: Icons.person_outline,
            label: '账号',
            selected: view == 'account',
            onTap: () => onSelect('account'),
          ),
          const Spacer(),
          _RailButton(
            icon: brightness == Brightness.dark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
            label: brightness == Brightness.dark ? '切到亮色' : '切到暗色',
            selected: false,
            onTap: () => onToggleTheme(brightness),
          ),
          _RailButton(
            icon: Icons.logout,
            label: '退出登录',
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
