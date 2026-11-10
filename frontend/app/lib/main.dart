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

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MoonChat',
      debugShowCheckedModeBanner: false,
      theme: buildMoonTheme(Brightness.light),
      darkTheme: buildMoonTheme(Brightness.dark),
      themeMode: _mode,
      home: AnimatedBuilder(
        animation: _state,
        builder: (BuildContext context, Widget? _) {
          if (!_state.isReady) {
            return LoginScreen(state: _state);
          }
          return HomeShell(
            state: _state,
            onToggleTheme: _toggleTheme,
            brightness: Theme.of(context).brightness,
          );
        },
      ),
    );
  }
}
