import 'package:flutter/material.dart';

import 'state/app_state.dart';
import 'theme.dart';
import 'ui/home_shell.dart';
import 'ui/login_screen.dart';

void main() {
  runApp(const MoonChatApp());
}

class MoonChatApp extends StatefulWidget {
  const MoonChatApp({super.key});

  @override
  State<MoonChatApp> createState() => _MoonChatAppState();
}

class _MoonChatAppState extends State<MoonChatApp> {
  final AppState _state = AppState();

  /// 初始主题：`?theme=light|dark` 强制（预览参数），否则跟随系统（DESIGN-SPEC §8）。
  ThemeMode _mode = switch (Uri.base.queryParameters['theme']) {
    'light' => ThemeMode.light,
    'dark' => ThemeMode.dark,
    _ => ThemeMode.system,
  };

  @override
  void dispose() {
    _state.dispose();
    super.dispose();
  }

  void _toggleTheme(Brightness current) {
    setState(() => _mode = current == Brightness.dark ? ThemeMode.light : ThemeMode.dark);
  }

  /// 缓存外壳：`HomeShell` 自己监听状态，这里只在「登录态或亮度变了」时重建，
  /// 否则每次 notifyListeners 都会把整棵树重建一遍（并触发 didUpdateWidget）。
  Widget? _gate;
  bool? _gateReady;
  Brightness? _gateBrightness;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MoonChat',
      debugShowCheckedModeBanner: false,
      theme: buildMoonTheme(Brightness.light),
      darkTheme: buildMoonTheme(Brightness.dark),
      themeMode: _mode,
      home: ListenableBuilder(
        listenable: _state,
        builder: (BuildContext context, Widget? _) {
          final bool ready = _state.isReady;
          final Brightness brightness = Theme.of(context).brightness;
          if (_gate == null || ready != _gateReady || brightness != _gateBrightness) {
            _gateReady = ready;
            _gateBrightness = brightness;
            _gate = ready
                ? HomeShell(state: _state, onToggleTheme: _toggleTheme, brightness: brightness)
                : LoginScreen(state: _state);
          }
          return _gate!;
        },
      ),
    );
  }
}
