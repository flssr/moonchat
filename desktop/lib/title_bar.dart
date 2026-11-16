import 'package:flutter/material.dart';
import 'package:mondchat/i18n/context_tr.dart';
import 'package:mondchat/theme.dart';
import 'package:window_manager/window_manager.dart';

/// Windows 无边框窗口的顶栏：拖动、双击最大化、最小化/最大化/关闭。
///
/// 原生标题栏由 `TitleBarStyle.hidden` 去掉，所以拖动与按钮都画在 Flutter 里；
/// 颜色走应用自己的 `MoonPalette`，亮/暗色切换时跟着变。
class DesktopTitleBar extends StatefulWidget {
  const DesktopTitleBar({super.key});

  static const double height = 32;

  @override
  State<DesktopTitleBar> createState() => _DesktopTitleBarState();
}

class _DesktopTitleBarState extends State<DesktopTitleBar> with WindowListener {
  bool _maximized = false;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    windowManager.isMaximized().then((bool value) {
      if (mounted) {
        setState(() => _maximized = value);
      }
    });
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  @override
  void onWindowMaximize() {
    if (mounted) {
      setState(() => _maximized = true);
    }
  }

  @override
  void onWindowUnmaximize() {
    if (mounted) {
      setState(() => _maximized = false);
    }
  }

  Future<void> _toggleMaximize() async {
    if (_maximized) {
      await windowManager.unmaximize();
    } else {
      await windowManager.maximize();
    }
  }

  @override
  Widget build(BuildContext context) {
    final MoonPalette p = context.moon;
    return Material(
      color: p.bg,
      child: SizedBox(
        height: DesktopTitleBar.height,
        child: Row(
          children: <Widget>[
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanStart: (_) => windowManager.startDragging(),
                onDoubleTap: _toggleMaximize,
                child: Padding(
                  padding: const EdgeInsets.only(left: 12),
                  child: Row(
                    children: <Widget>[
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: Image.asset(
                          'assets/mondchat-logo.png',
                          width: 16,
                          height: 16,
                          filterQuality: FilterQuality.high,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'MondChat',
                        style: TextStyle(fontSize: 12, color: p.ink3),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            _BarButton(
              icon: Icons.remove,
              label: context.tr('最小化'),
              onPressed: windowManager.minimize,
            ),
            _BarButton(
              icon: _maximized ? Icons.filter_none : Icons.crop_square,
              label: context.tr(_maximized ? '还原' : '最大化'),
              onPressed: _toggleMaximize,
            ),
            _BarButton(
              icon: Icons.close,
              label: context.tr('关闭'),
              onPressed: windowManager.close,
              danger: true,
            ),
          ],
        ),
      ),
    );
  }
}

class _BarButton extends StatefulWidget {
  const _BarButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.danger = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final bool danger;

  @override
  State<_BarButton> createState() => _BarButtonState();
}

class _BarButtonState extends State<_BarButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final MoonPalette p = context.moon;
    final Color background = _hover
        ? (widget.danger ? const Color(0xFFE81123) : p.line)
        : Colors.transparent;
    final Color foreground =
        _hover && widget.danger ? Colors.white : p.ink3;
    return Semantics(
      button: true,
      label: widget.label,
      child: Tooltip(
        message: widget.label,
        waitDuration: const Duration(milliseconds: 600),
        child: MouseRegion(
          onEnter: (_) => setState(() => _hover = true),
          onExit: (_) => setState(() => _hover = false),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onPressed,
            child: Container(
              width: 44,
              height: DesktopTitleBar.height,
              color: background,
              alignment: Alignment.center,
              child: Icon(widget.icon, size: 15, color: foreground),
            ),
          ),
        ),
      ),
    );
  }
}
