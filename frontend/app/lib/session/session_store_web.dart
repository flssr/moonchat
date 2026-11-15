import 'dart:convert';
import 'dart:js_interop';

import 'session_store.dart';

@JS('localStorage')
external _Storage get _storage;

extension type _Storage(JSObject _) implements JSObject {
  external String? getItem(String key);
  external void setItem(String key, String value);
  external void removeItem(String key);
}

/// Web 客户端没有 HttpOnly Cookie，要跨刷新保住登录只能放浏览器本地；
/// 代价是页面里任何脚本都能读到这份 JWT（决策记录见 `docs/history/frontend-doc/`）。
class _LocalSessionStore implements SessionStore {
  static const String _key = 'mondchat.session.v1';

  @override
  StoredSession? load() {
    try {
      final String? raw = _storage.getItem(_key);
      if (raw == null || raw.isEmpty) {
        return null;
      }
      final Object? decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        return null;
      }
      return StoredSession.fromJson(decoded);
    } catch (_) {
      return null;
    }
  }

  @override
  void save(StoredSession session) {
    try {
      _storage.setItem(_key, jsonEncode(session.toJson()));
    } catch (_) {
      // 隐私模式 / 配额满：这次刷新仍要重新登录，但不阻断界面。
    }
  }

  @override
  void clear() {
    try {
      _storage.removeItem(_key);
    } catch (_) {
      // 同上。
    }
  }
}

SessionStore createSessionStore() => _LocalSessionStore();
