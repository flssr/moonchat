import 'session_store_stub.dart'
    if (dart.library.js_interop) 'session_store_web.dart' as impl;

/// 本机记住的登录态：归属者 JWT 与最后使用的账号 id（issue #24）。
///
/// 不给过期时间：刷新页面后直接用这份令牌换 `/api/sessions`，令牌失效由服务端 401 判定，
/// 客户端不自己算。
class StoredSession {
  const StoredSession({required this.token, required this.accountId, this.displayName});

  final String token;
  final int accountId;
  final String? displayName;

  Map<String, Object?> toJson() => <String, Object?>{
        'token': token,
        'account_id': accountId,
        if (displayName != null) 'display_name': displayName,
      };

  /// 本地数据是信任边界：字段缺失或类型不对就当没存过。
  static StoredSession? fromJson(Map<String, dynamic> json) {
    final Object? token = json['token'];
    final Object? accountId = json['account_id'];
    if (token is! String || token.isEmpty || accountId is! num) {
      return null;
    }
    final Object? name = json['display_name'];
    return StoredSession(
      token: token,
      accountId: accountId.toInt(),
      displayName: name is String && name.isNotEmpty ? name : null,
    );
  }
}

abstract interface class SessionStore {
  StoredSession? load();
  void save(StoredSession session);
  void clear();
}

SessionStore createSessionStore() => impl.createSessionStore();
