import 'dart:convert';
import 'dart:js_interop';

import '../avatars.dart';
import 'settings.dart';

@JS('localStorage')
external _Storage get _storage;

extension type _Storage(JSObject _) implements JSObject {
  external String? getItem(String key);
  external void setItem(String key, String value);
}

class _LocalSettingsStore implements SettingsStore {
  static const String _key = 'mondchat.settings.v1';
  static const String _avatarsKey = 'mondchat.avatars.v1';
  static const String _lastEmailKey = 'mondchat.last_email.v1';

  @override
  MoonSettings load() {
    try {
      final String? raw = _storage.getItem(_key);
      if (raw == null || raw.isEmpty) {
        return MoonSettings.defaults;
      }
      final Object? decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        return MoonSettings.defaults;
      }
      return MoonSettings.fromJson(decoded);
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

  @override
  Map<int, String> loadAvatars() {
    try {
      final String? raw = _storage.getItem(_avatarsKey);
      if (raw == null || raw.isEmpty) {
        return <int, String>{};
      }
      final Object? decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        return <int, String>{};
      }
      final Map<int, String> avatars = <int, String>{};
      decoded.forEach((String id, Object? key) {
        final int? accountId = int.tryParse(id);
        if (accountId != null && key is String && isKnownAvatar(key)) {
          avatars[accountId] = key;
        }
      });
      return avatars;
    } catch (_) {
      return <int, String>{};
    }
  }

  @override
  void saveAvatars(Map<int, String> avatars) {
    try {
      _storage.setItem(
        _avatarsKey,
        jsonEncode(avatars.map((int id, String key) => MapEntry('$id', key))),
      );
    } catch (_) {
      // 同 save：存不下就只在本会话生效。
    }
  }

  @override
  String? loadLastEmail() {
    try {
      final String? value = _storage.getItem(_lastEmailKey);
      return value == null || value.isEmpty ? null : value;
    } catch (_) {
      return null;
    }
  }

  @override
  void saveLastEmail(String email) {
    try {
      _storage.setItem(_lastEmailKey, email.trim());
    } catch (_) {
      // 同 save：存不下就只在本会话生效。
    }
  }
}

SettingsStore createSettingsStore() => _LocalSettingsStore();
