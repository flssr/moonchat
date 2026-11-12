import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'i18n/moon_strings.dart';
import 'state/app_state.dart';
import 'theme.dart';
import 'ui/home_shell.dart';
import 'ui/login_screen.dart';

void main() {
  runApp(const MoonChatApp());
}

class MoonChatApp extends StatefulWidget {
  /// [state] 只给测试注入；生产入口不传，由外壳自己持有并负责释放。
  const MoonChatApp({super.key, this.state});

  final AppState? state;

  @override
  State<MoonChatApp> createState() => _MoonChatAppState();
}

class _MoonChatAppState extends State<MoonChatApp> {
  late final AppState _state = widget.state ?? AppState();
  late final bool _ownsState = widget.state == null;

  /// 初始主题：`?theme=light|dark` 强制（预览参数），否则跟随系统（DESIGN-SPEC §8）。
  ThemeMode _mode = switch (Uri.base.queryParameters['theme']) {
    'light' => ThemeMode.light,
    'dark' => ThemeMode.dark,
    _ => ThemeMode.system,
  };

  /// 登录成功后，登录页要把登舱过渡播完再交棒；这里等它的回调。
  /// 不复用 `phase`：登录态与「动画播完没有」是两件事，塞进 AppState 会污染状态机。
  bool _arrived = false;

  /// 设置页的字体与语言偏好只影响本机，跨重启不保留。
  double _textScale = 1.0;
  Locale _locale = const Locale('zh', 'CN');

  @override
  void dispose() {
    if (_ownsState) {
      _state.dispose();
    }
    super.dispose();
  }

  void _toggleTheme(Brightness current) {
    setState(() => _mode = current == Brightness.dark ? ThemeMode.light : ThemeMode.dark);
  }

  void _setTextScale(double value) {
    setState(() => _textScale = value);
  }

  void _setLanguage(String code) {
    setState(() => _locale = _localeFor(code));
  }

  static Locale _localeFor(String code) =>
      code == 'zh' ? const Locale('zh', 'CN') : Locale(code);

  void _onArrived() {
    if (mounted) {
      setState(() => _arrived = true);
    }
  }

  /// 缓存外壳：`HomeShell` 自己监听状态，这里只在「该显示哪一屏或亮度变了」时重建，
  /// 否则每次 notifyListeners 都会把整棵树重建一遍（并触发 didUpdateWidget）。
  Widget? _gate;
  bool? _gateHome;
  Brightness? _gateBrightness;
  double? _gateTextScale;
  Locale? _gateLocale;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MoonChat',
      debugShowCheckedModeBanner: false,
      theme: buildMoonTheme(Brightness.light),
      darkTheme: buildMoonTheme(Brightness.dark),
      themeMode: _mode,
      locale: _locale,
      supportedLocales:
          kMoonLanguages.map(((String, String) item) => _localeFor(item.$1)).toList(growable: false),
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      builder: (BuildContext context, Widget? child) {
        final MediaQueryData data = MediaQuery.of(context);
        // 保留系统字号档位，再叠应用内的小/中/大。
        final double systemScale = data.textScaler.scale(1);
        return MediaQuery(
          data: data.copyWith(textScaler: TextScaler.linear(systemScale * _textScale)),
          child: child!,
        );
      },
      home: ListenableBuilder(
        listenable: _state,
        builder: (BuildContext context, Widget? _) {
          final bool ready = _state.isReady;
          // 登出（含 401）把交棒标记复位；否则下一次登录会直接跳过过渡。
          if (!ready) {
            _arrived = false;
          }
          final bool showHome = ready && _arrived;
          final Brightness brightness = Theme.of(context).brightness;
          if (_gate == null ||
              showHome != _gateHome ||
              brightness != _gateBrightness ||
              _textScale != _gateTextScale ||
              _locale != _gateLocale) {
            _gateHome = showHome;
            _gateBrightness = brightness;
            _gateTextScale = _textScale;
            _gateLocale = _locale;
            _gate = showHome
                ? HomeShell(
                    state: _state,
                    onToggleTheme: _toggleTheme,
                    brightness: brightness,
                    languageCode: _locale.languageCode,
                    textScale: _textScale,
                    onLanguageChanged: _setLanguage,
                    onTextScaleChanged: _setTextScale,
                  )
                : LoginScreen(state: _state, onArrived: _onArrived);
          }
          final bool reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
          return AnimatedSwitcher(
            duration: reduceMotion ? Duration.zero : const Duration(milliseconds: 200),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeOutCubic,
            child: KeyedSubtree(key: ValueKey<bool>(showHome), child: _gate!),
          );
        },
      ),
    );
  }
}
