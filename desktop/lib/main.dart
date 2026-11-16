import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mondchat/api/api_client.dart';
import 'package:mondchat/main.dart';
import 'package:mondchat/state/app_state.dart';
import 'package:window_manager/window_manager.dart';

import 'realtime.dart';
import 'storage.dart';
import 'title_bar.dart';

/// 桌面端没有网页同源，必须给绝对地址；生产默认走反代入口，
/// 开发时用 `--dart-define=MONDCHAT_API_BASE=http://127.0.0.1:8080` 覆盖。
const String _apiBase = String.fromEnvironment(
  'MONDCHAT_API_BASE',
  defaultValue: 'https://api.mondchat.com',
);

/// 无边框窗口里的自定义标题栏：在 MaterialApp 的 builder 内插入，
/// 这样标题栏能用应用自己的主题色；下面的内容铺满剩余区域。
Widget _chrome(BuildContext context, Widget child) {
  return Column(
    children: <Widget>[
      const DesktopTitleBar(),
      Expanded(child: child),
    ],
  );
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();
  const WindowOptions options = WindowOptions(
    size: Size(1280, 800),
    minimumSize: Size(960, 640),
    center: true,
    backgroundColor: Colors.transparent,
    // 去掉系统标题栏，窗口控件由 DesktopTitleBar 画；窗口仍然可缩放。
    titleBarStyle: TitleBarStyle.hidden,
  );
  unawaited(
    windowManager.waitUntilReadyToShow(options, () async {
      await windowManager.show();
      await windowManager.focus();
    }),
  );

  final DesktopSettingsStore settings = DesktopSettingsStore();
  // AppState 的生命周期就是进程本身，桌面入口自己持有，不交给 MondChatApp 释放。
  final AppState state = AppState(
    api: ApiClient(baseUrl: _apiBase, deviceType: 'desktop'),
    realtime: DesktopRealtime(),
    store: settings,
    session: DesktopSessionStore(),
  );
  runApp(
    MondChatApp(
      state: state,
      store: settings,
      chrome: _chrome,
      edgeToEdge: true,
    ),
  );
}
