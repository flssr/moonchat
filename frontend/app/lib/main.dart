import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'i18n/moon_strings.dart';
import 'settings/settings.dart';
import 'settings/settings_store.dart';
import 'state/app_state.dart';
import 'theme.dart';
import 'ui/home_shell.dart';
import 'ui/login_screen.dart';

void main() {
  final SettingsStore store = createSettingsStore();
  runApp(MondChatApp(settings: store.load(), store: store));
}

class MondChatApp extends StatefulWidget {
  /// [state] 只给测试注入；生产入口不传，由外壳自己持有并负责释放。
  const MondChatApp({
    super.key,
    this.state,
    this.settings,
    this.store,
    this.chrome,
    this.edgeToEdge = false,
  });

  final AppState? state;
  final MoonSettings? settings;
  final SettingsStore? store;

  /// 桌面壳用它在 `MaterialApp` 内插一条自定义标题栏；Web 传 null。
  /// 放在 builder 里才能拿到应用自己的主题（标题栏跟随亮/暗色）。
  final Widget Function(BuildContext context, Widget child)? chrome;

  /// 登录页铺满可用区域（桌面无边框窗口）；Web 保持居中的卡片。
  final bool edgeToEdge;

  @override
  State<MondChatApp> createState() => _MondChatAppState();
}

class _MondChatAppState extends State<MondChatApp> with WidgetsBindingObserver {
  late final AppState _state = widget.state ?? AppState();
  late final bool _ownsState = widget.state == null;
  late final SettingsStore _store = widget.store ?? createSettingsStore();
  late final MoonSettings _initial = widget.settings ?? _store.load();

  /// 弹窗（设置/黑名单/资料编辑）挂在根 Navigator 上：登出要统一收掉。
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  bool _wasHome = false;

  late ThemeMode _mode;
  late double _textScale;
  late Locale _locale;
  late bool _notify;

  /// `?theme=` 是预览参数，不能把被强制的值写回用户偏好。
  bool _themeForced = false;

  /// 登录成功后，登录页要把登舱过渡播完再交棒；这里等它的回调。
  /// 不复用 `phase`：登录态与「动画播完没有」是两件事，塞进 AppState 会污染状态机。
  bool _arrived = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // 预览参数优先于上次保存；其余设置从本地偏好恢复。
    final String? forced = Uri.base.queryParameters['theme'];
    _themeForced = forced == 'light' || forced == 'dark';
    _mode = switch (forced) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => _initial.themeMode,
    };
    _textScale = _initial.textScale;
    _locale = _localeFor(_initial.languageCode);
    _notify = _initial.notifyOnMessage;
    _state.setNotifyOnMessage(_notify);
    _state.setLanguageCode(_locale.languageCode);
    // 本机记住的账号由登录页的“记住我”卡片显示，点登录再恢复；不再自动跳过登录页。
  }

  /// 浏览器/桌面切到后台也算“不在看”：否则后台标签页收到消息会直接上报已读。
  @override
  void didChangeAppLifecycleState(AppLifecycleState lifecycle) {
    _state.setWindowFocused(lifecycle == AppLifecycleState.resumed);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (_ownsState) {
      _state.dispose();
    }
    super.dispose();
  }

  void _persist() {
    _store.save(MoonSettings(
      textScale: _textScale,
      languageCode: _locale.languageCode,
      themeMode: _themeForced ? _initial.themeMode : _mode,
      notifyOnMessage: _notify,
    ));
  }

  void _setNotify(bool value) {
    setState(() => _notify = value);
    _state.setNotifyOnMessage(value);
    _persist();
  }

  void _toggleTheme(Brightness current) {
    _themeForced = false;
    setState(() => _mode = current == Brightness.dark ? ThemeMode.light : ThemeMode.dark);
    _persist();
  }

  /// 设置页的三档主题：把它设成 system 后导航栏二态切换仍可覆盖，但能再选回跟随系统。
  void _setThemeMode(ThemeMode mode) {
    _themeForced = false;
    setState(() => _mode = mode);
    _persist();
  }

  void _setTextScale(double value) {
    setState(() => _textScale = value);
    _persist();
  }

  void _setLanguage(String code) {
    setState(() => _locale = _localeFor(code));
    _state.setLanguageCode(code);
    _persist();
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
  bool? _gateNotify;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: _navigatorKey,
      title: 'MondChat',
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
        final Widget content = MediaQuery(
          data: data.copyWith(textScaler: TextScaler.linear(systemScale * _textScale)),
          child: child!,
        );
        return widget.chrome == null ? content : widget.chrome!(context, content);
      },
      home: ListenableBuilder(
        listenable: _state,
        builder: (BuildContext context, Widget? _) {
          final bool ready = _state.isReady;
          // 登出（含 401）把交棒标记复位；否则下一次登录会直接跳过过渡。
          if (!ready) {
            _arrived = false;
          }
          // 两条入口（密码登录 / 「记住我」卡片）都由登录页播完登舱过渡再置 `_arrived`。
          final bool showHome = ready && _arrived;
          if (_wasHome && !showHome) {
            // 登出时设置/黑名单/资料编辑这些弹窗还挂在根路由上，
            // 不 pop 就会盖在登录页上露出上个账号的数据。
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _navigatorKey.currentState?.popUntil((Route<dynamic> r) => r.isFirst);
            });
          }
          _wasHome = showHome;
          final Brightness brightness = Theme.of(context).brightness;
          if (_gate == null ||
              showHome != _gateHome ||
              brightness != _gateBrightness ||
              _textScale != _gateTextScale ||
              _locale != _gateLocale ||
              _notify != _gateNotify) {
            _gateHome = showHome;
            _gateBrightness = brightness;
            _gateTextScale = _textScale;
            _gateLocale = _locale;
            _gateNotify = _notify;
            _gate = showHome
                ? HomeShell(
                    state: _state,
                    onToggleTheme: _toggleTheme,
                    brightness: brightness,
                    textScale: _textScale,
                    themeMode: _mode,
                    onThemeModeChanged: _setThemeMode,
                    onLanguageChanged: _setLanguage,
                    onTextScaleChanged: _setTextScale,
                    notifyOnMessage: _notify,
                    onNotifyChanged: _setNotify,
                  )
                : LoginScreen(
                    state: _state,
                    onArrived: _onArrived,
                    edgeToEdge: widget.edgeToEdge,
                    languageCode: _locale.languageCode,
                    onLanguageChanged: _setLanguage,
                  );
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
