import 'dart:convert';
import 'dart:js_interop';

import 'settings.dart';

@JS('localStorage')
external _Storage get _storage;

extension type _Storage(JSObject _) implements JSObject {
  external String? getItem(String key);
  external void setItem(String key, String value);
}

class _LocalSettingsStore implements SettingsStore {
  static const String _key = 'moonchat.settings.v1';

  @override
  MoonSettings load() {
    try {
      final String? raw = _storage.getItem(_key);
      if (raw == null || raw.isEmpty) {
        return MoonSettings.defaults;
      }
      final Object? decoded = jsonDecode(raw);
      return decoded is Map<String, dynamic>
          ? MoonSettings.fromJson(decoded)
          : MoonSettings.defaults;
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
