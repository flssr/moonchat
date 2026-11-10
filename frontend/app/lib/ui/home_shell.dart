import 'package:flutter/material.dart';

import '../state/app_state.dart';
import '../theme.dart';
import 'account_view.dart';
import 'contacts_view.dart';
import 'messages_view.dart';
import 'profile_panel.dart';

/// 客户端外壳：56 导航 + 各视图自己的列表 / 内容 / 信息栏。
/// 断点按容器宽度走（DESIGN-SPEC §5：860 收信息栏，620 收列表栏）。
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
  String _view = 'messages';
  String? _activeKey;
  String _filter = 'all';

  void _openConversation(String key) {
    setState(() {
      _view = 'messages';
      _activeKey = key;
    });
  }

  @override
  Widget build(BuildContext context) {
    final MoonPalette p = context.moon;
    return Scaffold(
      backgroundColor: p.bg,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints c) {
            final bool showList = c.maxWidth >= 700;
            final bool showInfo = c.maxWidth >= 1000;
            final String? effectiveKey = _activeKey ??
                (!showList && widget.state.conversations.isNotEmpty
                    ? widget.state.conversations.first.key
                    : null);

            final Widget body = switch (_view) {
              'contacts' => ContactsView(
                  state: widget.state,
                  onMessage: (int id) => _openConversation('dm:$id'),
                  onSelectConversation: _openConversation,
                ),
              'account' => AccountView(state: widget.state),
              _ => MessagesView(
                  state: widget.state,
                  activeKey: effectiveKey,
                  onSelect: (String key) => setState(() => _activeKey = key),
                  filter: _filter,
                  onFilter: (String f) => setState(() => _filter = f),
                  onOpenProfile: (int id) {
                    if (id > 0) {
                      showProfileSheet(
                        context,
                        widget.state,
                        id,
                        onMessage: () => _openConversation('dm:$id'),
                      );
                    } else {
                      setState(() => _activeKey = null);
                    }
                  },
                  showInfo: showInfo,
                  showList: showList,
                ),
            };

            return Row(
              children: <Widget>[
                _NavRail(
                  view: _view,
                  onSelect: (String v) => setState(() {
                    _view = v;
                    if (v != 'messages') {
                      _activeKey = null;
                    }
                  }),
                  pendingCount: widget.state.pending.length,
                  brightness: widget.brightness,
                  onToggleTheme: widget.onToggleTheme,
                  onLogout: widget.state.logout,
                ),
                Expanded(child: body),
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
