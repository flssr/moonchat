import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:mondchat/i18n/context_tr.dart';
import 'package:mondchat/state/app_state.dart';
import 'package:mondchat/theme.dart';
import 'package:mondchat/ui/widgets.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import 'title_bar.dart';

/// 无边框窗口的外壳：自定义标题栏、关闭确认、托盘、窗口焦点。
///
/// 关闭按钮和任务栏/Alt+F4 都走同一个确认层；选「最小化到托盘」时窗口隐藏、
/// 进程继续收消息，托盘菜单可以再显示或彻底退出。
class DesktopShell extends StatefulWidget {
  const DesktopShell({super.key, required this.state, required this.child});

  final AppState state;
  final Widget child;

  @override
  State<DesktopShell> createState() => _DesktopShellState();
}

class _DesktopShellState extends State<DesktopShell> with WindowListener, TrayListener {
  bool _confirmClose = false;
  bool _quitting = false;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    trayManager.addListener(this);
    windowManager.setPreventClose(true);
    widget.state.setWindowFocused(true);
    _initTray();
  }

  Future<void> _initTray() async {
    try {
      await trayManager.setIcon(
        Platform.isWindows ? 'assets/tray_icon.ico' : 'assets/mondchat-logo.png',
      );
      await trayManager.setToolTip('MondChat');
      await trayManager.setContextMenu(
        Menu(
          items: <MenuItem>[
            MenuItem(key: 'show', label: '显示 MondChat'),
            MenuItem.separator(),
            MenuItem(key: 'quit', label: '退出'),
          ],
        ),
      );
    } catch (_) {
      // 托盘图标没起来也不影响最小化：窗口始终留在任务栏。
    }
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    trayManager.removeListener(this);
    super.dispose();
  }

  void _requestClose() {
    setState(() => _confirmClose = true);
  }

  Future<void> _show() async {
    await windowManager.show();
    await windowManager.focus();
  }

  Future<void> _minimizeToTaskbar() async {
    setState(() => _confirmClose = false);
    // 托盘插件在部分 Windows 上图标不出现，hide() 会让人以为应用被关了。
    // 最小化到任务栏最稳：窗口还有入口，进程继续收消息、弹通知。
    await windowManager.minimize();
  }

  Future<void> _quit() async {
    _quitting = true;
    // 先同步把会话缓存落盘，再硬退出：窗口 manager 的关闭链路在 Windows 上要等
    // 插件回调，用户体感是“点了没反应”，直接 exit 比逐层 close 快。
    widget.state.flushCache();
    try {
      await windowManager.setPreventClose(false);
    } catch (_) {
      // 已经关了也无所谓。
    }
    unawaited(windowManager.destroy());
    exit(0);
  }

  @override
  void onWindowClose() {
    if (!_quitting) {
      _requestClose();
    }
  }

  @override
  void onWindowFocus() => widget.state.setWindowFocused(true);

  @override
  void onWindowBlur() => widget.state.setWindowFocused(false);

  @override
  void onTrayIconMouseDown() => _show();

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    if (menuItem.key == 'show') {
      _show();
    } else if (menuItem.key == 'quit') {
      _quit();
    }
  }

  @override
  Widget build(BuildContext context) {
    final MoonPalette p = context.moon;
    return Stack(
      children: <Widget>[
        Column(
          children: <Widget>[
            DesktopTitleBar(onClose: _requestClose),
            Expanded(child: widget.child),
          ],
        ),
        if (_confirmClose)
          Positioned.fill(
            child: Material(
              color: const Color(0x66000000),
              child: Center(
                child: Container(
                  width: 320,
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
                  decoration: BoxDecoration(
                    color: p.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: p.line),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Text(
                        context.tr('要关闭 MondChat 吗？'),
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: p.ink),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        context.tr('可以关掉应用，也可以最小化到任务栏继续收消息。'),
                        style: TextStyle(fontSize: 12, color: p.ink3),
                      ),
                      const SizedBox(height: 16),
                      MoonButton(
                        label: context.tr('关闭应用程序'),
                        kind: MoonButtonKind.danger,
                        onPressed: _quit,
                      ),
                      const SizedBox(height: 8),
                      MoonButton(
                        label: context.tr('最小化到任务栏'),
                        kind: MoonButtonKind.secondary,
                        onPressed: _minimizeToTaskbar,
                      ),
                      const SizedBox(height: 4),
                      TextButton(
                        onPressed: () => setState(() => _confirmClose = false),
                        child: Text(context.tr('取消'), style: TextStyle(color: p.ink3)),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
