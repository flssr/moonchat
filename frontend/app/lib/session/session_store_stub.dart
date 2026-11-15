import 'session_store.dart';

/// 非 Web 平台（测试、VM）没有浏览器存储：只在本次进程内记住。
class _MemorySessionStore implements SessionStore {
  StoredSession? _session;

  @override
  StoredSession? load() => _session;

  @override
  void save(StoredSession session) => _session = session;

  @override
  void clear() => _session = null;
}

SessionStore createSessionStore() => _MemorySessionStore();
