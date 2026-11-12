import 'dart:convert';
import 'dart:js_interop';

import 'package:flutter/material.dart';

import 'settings.dart';

@JS('localStorage')
external _Storage get _storage;

extension type _Storage(JSObject _) implements JSObject {
  external String? getItem(String key);
  external void setItem(String key, String value);
}

class _LocalSettingsStore implements SettingsStore {
  static const String _key = 'moonchat.settings.v1';
  static const String _legacyThemeKey = 'moonchat-theme';

  ThemeMode _legacyTheme() => switch (_storage.getItem(_legacyThemeKey)) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };

  @override
  MoonSettings load() {
    try {
      final String? raw = _storage.getItem(_key);
      if (raw == null || raw.isEmpty) {
        return MoonSettings(themeMode: _legacyTheme());
      }
      final Object? decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        return MoonSettings.defaults;
      }
      final MoonSettings settings = MoonSettings.fromJson(decoded);
      if (decoded.containsKey('theme')) {
        return settings;
      }
      return MoonSettings(
        textScale: settings.textScale,
        languageCode: settings.languageCode,
        themeMode: _legacyTheme(),
      );
    } catch (_) {
      return MoonSettings.defaults;
    }
  }

  @override
  void save(MoonSettings settings) {
    try {
      _storage.setItem(_key, jsonEncode(settings.toJson()));
    } catch (_) {
      // 隐私模式 / 配额满：设置只在本次会话生效，不阻断界面。
    }
  }
}

SettingsStore createSettingsStore() => _LocalSettingsStore();
