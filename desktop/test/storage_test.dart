import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mondchat/session/session_store.dart';
import 'package:mondchat/settings/settings.dart';
import 'package:mondchat_desktop/storage.dart';

void main() {
  late Directory dir;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('mondchat-desktop-test');
  });

  tearDown(() {
    if (dir.existsSync()) {
      dir.deleteSync(recursive: true);
    }
  });

  test('设置与头像写入本机文件后重新读取', () {
    final DesktopSettingsStore store = DesktopSettingsStore(dir: dir);
    store.save(const MoonSettings(
      textScale: 1.12,
      languageCode: 'en',
      themeMode: ThemeMode.dark,
    ));
    store.saveAvatars(<int, String>{7: 'female_01'});

    final DesktopSettingsStore reopened = DesktopSettingsStore(dir: dir);
    final MoonSettings settings = reopened.load();
    expect(settings.textScale, 1.12);
    expect(settings.languageCode, 'en');
    expect(settings.themeMode, ThemeMode.dark);
    expect(reopened.loadAvatars(), <int, String>{7: 'female_01'});
  });

  test('会话缓存写入本机文件后重新读取', () {
    final DesktopMessageCacheStore store = DesktopMessageCacheStore(dir: dir);
    store.save(1, <String, dynamic>{
      'active': 'dm:2',
      'messages': <String, dynamic>{
        'dm:2': <Map<String, dynamic>>[
          <String, dynamic>{'text': '缓存这条', 'sent_at': '2026-11-16T20:00:00Z'},
        ],
      },
    });

    final DesktopMessageCacheStore reopened = DesktopMessageCacheStore(dir: dir);
    final Map<String, dynamic>? data = reopened.load(1);
    expect(data?['active'], 'dm:2');
    expect((data?['messages'] as Map<String, dynamic>)['dm:2'], hasLength(1));
  });

  test('本机文件里的未知头像 key 当作没选过', () {
    File('${dir.path}\\avatars.json').writeAsStringSync(
      '{"7":"female_01","8":"not_an_avatar"}',
    );
    final DesktopSettingsStore store = DesktopSettingsStore(dir: dir);
    expect(store.loadAvatars(), <int, String>{7: 'female_01'});
  });

  test('登录态保存、恢复与清除', () {
    final DesktopSessionStore store = DesktopSessionStore(dir: dir);
    store.save(const StoredSession(token: 'jwt', accountId: 7));

    final DesktopSessionStore reopened = DesktopSessionStore(dir: dir);
    expect(reopened.load()?.token, 'jwt');
    expect(reopened.load()?.accountId, 7);

    reopened.clear();
    expect(DesktopSessionStore(dir: dir).load(), isNull);
  });
}
