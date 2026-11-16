import 'package:flutter/material.dart';
import 'package:mondchat/api/api_client.dart';
import 'package:mondchat/main.dart';
import 'package:mondchat/state/app_state.dart';

import 'realtime.dart';
import 'storage.dart';

/// 桌面端没有网页同源，必须给绝对地址；生产默认走反代入口，
/// 开发时用 `--dart-define=MONDCHAT_API_BASE=http://127.0.0.1:8080` 覆盖。
const String _apiBase = String.fromEnvironment(
  'MONDCHAT_API_BASE',
  defaultValue: 'https://api.mondchat.com',
);

void main() {
  final DesktopSettingsStore settings = DesktopSettingsStore();
  // AppState 的生命周期就是进程本身，桌面入口自己持有，不交给 MondChatApp 释放。
  final AppState state = AppState(
    api: ApiClient(baseUrl: _apiBase, deviceType: 'desktop'),
    realtime: DesktopRealtime(),
    store: settings,
    session: DesktopSessionStore(),
  );
  runApp(MondChatApp(state: state, store: settings));
}
