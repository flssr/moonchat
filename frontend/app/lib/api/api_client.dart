import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'models.dart';

String _formatDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// 接口失败只有两类：契约里的 `code`，与根本没拿到响应（网络）。
/// 界面一律按 `code` 分流，`message` 只给人看（`api-contracts.md` §1.3）。
class ApiException implements Exception {
  ApiException({
    required this.code,
    this.message = '',
    this.field,
    this.statusCode,
  });

  factory ApiException.network(Object error) =>
      ApiException(code: 'network', message: error.toString());

  final String code;
  final String message;
  final String? field;
  final int? statusCode;

  bool get isUnauthenticated => code == 'unauthenticated';
  bool get isNotFound => code == 'not_found';

  /// 界面文案。不在界面上出现错误码原文（`DESIGN-SPEC.md` §10）。
  String get displayText {
    switch (code) {
      case 'validation_failed':
        // `field` 是契约里的字段名（可能是 `X-Device-Type` 这种头名），不直接给用户看。
        return '有一项输入不合法，请检查后重试';
      case 'unauthenticated':
        return '邮箱或密码不对';
      case 'forbidden':
        return '这个动作当前账号没有权限';
      case 'account_frozen':
        return '账号已冻结，暂时不能写入';
      case 'not_friend':
        return '只有好友之间才能私聊';
      case 'not_room_member':
        return '你已不在这个群里';
      case 'not_found':
        // 好友关系、群成员也有 `not_found`，别把用户指向错误的对象。
        return '目标不存在或状态已经变了，刷新后再试';
      case 'conflict':
        return '状态已经变了，刷新后再试';
      case 'owner_cannot_leave':
        return '群主不能退群（V1 没有转让）';
      case 'rate_limited':
        return '发得太快了，稍后再试';
      case 'upstream_unavailable':
        return '服务暂时不可用，请重试';
      case 'network':
        return '连不上服务器';
      default:
        return '操作失败，请重试';
    }
  }

  @override
  String toString() => 'ApiException($code/$statusCode): $message';
}

/// 20 条 `/api/*` 的唯一调用点。路径与字段名严格照 `docs/api-contracts.md`。
class ApiClient {
  ApiClient({String? baseUrl, http.Client? client})
      : _base = (baseUrl ?? defaultBaseUrl).replaceAll(RegExp(r'/+$'), ''),
        _client = client ?? http.Client(),
        _ownsClient = client == null;

  /// 默认同源（nginx 反代 `/api`）；开发时用 `--dart-define=MOONCHAT_API_BASE=http://localhost:8080`。
  static const String defaultBaseUrl = String.fromEnvironment(
    'MOONCHAT_API_BASE',
    defaultValue: '',
  );

  /// 写入网关只认这几个取值（`ConversationController.java:31-37`），其余返回 400。
  /// 与 Turms 自己的设备枚举不是一套：`/im` 登录用的 `WEB` 在 `realtime_web.dart`。
  static const String deviceType = 'browser';

  final String _base;
  final http.Client _client;

  /// 注入进来的 client 归调用方所有，`close()` 不能替它关。
  final bool _ownsClient;
  static const Duration _timeout = Duration(seconds: 20);

  /// 401 的统一出口：由 `AppState` 挂上「清凭据回登录页」，不用每个调用点各判一次。
  void Function()? onUnauthenticated;

  /// 只有自己创建的 client 才由自己关：注入进来的（如测试的 `MockClient`）归调用方。
  void close() {
    if (_ownsClient) {
      _client.close();
    }
  }

  Uri _uri(String path, [Map<String, String>? query]) =>
      Uri.parse('$_base$path').replace(queryParameters: query);

  /// 响应不是 JSON 信封（反代 502 HTML、GBK 错误页）时按上游不可用处理，
  /// 别让 `FormatException`/`TypeError` 逃出 `ApiException` 这套分类。
  Future<Map<String, dynamic>> _json(http.Response res) async {
    if (res.body.isEmpty) {
      return const <String, dynamic>{};
    }
    try {
      final Object? decoded = jsonDecode(utf8.decode(res.bodyBytes, allowMalformed: true));
      return decoded is Map<String, dynamic> ? decoded : const <String, dynamic>{};
    } on FormatException {
      throw ApiException(code: 'upstream_unavailable', statusCode: res.statusCode);
    }
  }

  Future<Map<String, dynamic>> _send(
    String method,
    String path, {
    String? token,
    Object? body,
    Map<String, String>? query,
    Map<String, String>? headers,
  }) async {
    final http.Request req = http.Request(method, _uri(path, query));
    req.headers['Accept'] = 'application/json';
    if (token != null && token.isNotEmpty) {
      req.headers['Authorization'] = 'Bearer $token';
    }
    if (headers != null) {
      req.headers.addAll(headers);
    }
    if (body != null) {
      req.headers['Content-Type'] = 'application/json';
      req.body = jsonEncode(body);
    }

    http.Response res;
    try {
      // 两段都要设超时：只包读 body 的话，对端只接 socket 不回响应头时会永久挂住。
      final http.StreamedResponse streamed = await _client.send(req).timeout(_timeout);
      res = await http.Response.fromStream(streamed).timeout(_timeout);
    } on TimeoutException catch (e) {
      throw ApiException.network(e);
    } catch (e) {
      throw ApiException.network(e);
    }

    final Map<String, dynamic> json = await _json(res);
    if (res.statusCode >= 200 && res.statusCode < 300) {
      return json;
    }
    final ApiException error = ApiException(
      code: (json['code'] as String?) ?? 'internal_error',
      message: (json['message'] as String?) ?? '',
      field: json['field'] as String?,
      statusCode: res.statusCode,
    );
    // 只有「带着凭据还被拒」才是会话失效；登录接口的 401 是密码错，不能顺手把会话拆了。
    if (error.isUnauthenticated && token != null && token.isNotEmpty) {
      onUnauthenticated?.call();
    }
    throw error;
  }

  List<Map<String, dynamic>> _items(Map<String, dynamic> json) =>
      ((json['items'] as List<dynamic>?) ?? const <dynamic>[])
          .cast<Map<String, dynamic>>();

  // —— 认证与凭据 ——

  /// #1 注册真人账号。不签发 JWT。
  Future<RegisteredAccount> register({
    required String email,
    required String password,
    required String displayName,
  }) async {
    final json = await _send('POST', '/api/auth/register', body: {
      'email': email,
      'password': password,
      'display_name': displayName,
    });
    return RegisteredAccount.fromJson(json);
  }

  /// #2 换登录 JWT。
  Future<LoginResult> login({required String email, required String password}) async {
    final json = await _send('POST', '/api/auth/login', body: {
      'email': email,
      'password': password,
    });
    return LoginResult.fromJson(json);
  }

  /// #3 归属者切账号形态（带登录 JWT）。
  Future<AccountSession> sessionForOwner({required String token, required int accountId}) async {
    final json = await _send('POST', '/api/sessions', token: token, body: {'account_id': accountId});
    return AccountSession.fromJson(json);
  }

  /// #3 agent 换凭据形态（不带认证头，只用一次性密钥）。
  Future<AccountSession> sessionForAgentKey(String accountKey) async {
    final json = await _send('POST', '/api/sessions', body: {'account_key': accountKey});
    return AccountSession.fromJson(json);
  }

  /// #20 登录 JWT 滑动续期。
  Future<LoginResult> refresh(String token) async {
    final json = await _send('POST', '/api/auth/refresh', token: token);
    return LoginResult.fromJson(json);
  }

  // —— 账号与归属 ——

  /// #4 我的账号 + 我名下的 agent。
  Future<List<Account>> mine(String token) async {
    final json = await _send('GET', '/api/accounts/mine', token: token);
    return _items(json).map(Account.fromJson).toList();
  }

  /// #5 建 agent 账号，返回一次性明文密钥。
  Future<CreatedAgent> createAgent({required String token, required String displayName}) async {
    final json = await _send('POST', '/api/agent-accounts', token: token, body: {
      'display_name': displayName,
    });
    return CreatedAgent.fromJson(json);
  }

  /// #6 改本账号资料。`birthday` 只有非空或明确清除时才发，避免部分快照把服务端生日清掉。
  Future<UpdatedProfile> updateProfile({
    required String token,
    required String displayName,
    required String gender,
    DateTime? birthday,
    bool clearBirthday = false,
  }) async {
    final Map<String, Object?> body = <String, Object?>{
      'display_name': displayName,
      'gender': gender,
    };
    if (birthday != null) {
      body['birthday'] = _formatDate(birthday);
    } else if (clearBirthday) {
      body['birthday'] = null;
    }
    final json = await _send('PATCH', '/api/accounts/me', token: token, body: body);
    return UpdatedProfile.fromJson(json);
  }

  /// #7 资料页。
  Future<Profile> profile({required String token, required int accountId}) async {
    final json = await _send('GET', '/api/accounts/$accountId', token: token);
    return Profile.fromJson(json);
  }

  // —— 好友 ——

  /// #8 `status=accepted` 好友列表 / `status=pending` 发给我的申请。
  Future<List<Friendship>> friendships({required String token, required String status}) async {
    final json = await _send('GET', '/api/friendships', token: token, query: {'status': status});
    return _items(json).map(Friendship.fromJson).toList();
  }

  /// #9 发好友申请。响应只有 `peer_account_id` / `status` / `incoming`，
  /// 没有 `display_name` 与 `requested_at`，所以不拿列表模型去装它（列表由调用方重新拉）。
  Future<void> requestFriend({required String token, required int peerAccountId}) async {
    await _send('POST', '/api/friendships', token: token, body: {
      'peer_account_id': peerAccountId,
    });
  }

  /// #10 同意 / 拒绝。`reject` 返回 204。
  Future<void> respondFriend({
    required String token,
    required int peerAccountId,
    required String action,
  }) async {
    await _send('POST', '/api/friendships/$peerAccountId', token: token, body: {'action': action});
  }

  /// #11 删好友（写 tombstone）。
  Future<void> deleteFriend({required String token, required int peerAccountId}) async {
    await _send('DELETE', '/api/friendships/$peerAccountId', token: token);
  }

  // —— 群与成员 ——

  /// #12 建群。
  Future<Room> createRoom({required String token, required String name}) async {
    final json = await _send('POST', '/api/rooms', token: token, body: {'name': name});
    return Room.fromJson(json);
  }

  /// #13 我加入的群。
  Future<List<Room>> rooms(String token) async {
    final json = await _send('GET', '/api/rooms', token: token);
    return _items(json).map(Room.fromJson).toList();
  }

  /// #14 群信息。
  Future<RoomDetail> room({required String token, required int roomId}) async {
    final json = await _send('GET', '/api/rooms/$roomId', token: token);
    return RoomDetail.fromJson(json);
  }

  /// #15 群成员（唯一分页接口）。
  Future<Paged<RoomMember>> members({
    required String token,
    required int roomId,
    int page = 1,
    int size = 50,
  }) async {
    final json = await _send('GET', '/api/rooms/$roomId/members', token: token, query: {
      'page': '$page',
      'size': '$size',
    });
    return Paged<RoomMember>(
      items: _items(json).map(RoomMember.fromJson).toList(),
      page: (json['page'] as int?) ?? page,
      size: (json['size'] as int?) ?? size,
      total: (json['total'] as int?) ?? 0,
    );
  }

  /// #16 拉人进群（邀请即入群）。
  Future<void> addMember({
    required String token,
    required int roomId,
    required int accountId,
  }) async {
    await _send('POST', '/api/rooms/$roomId/members', token: token, body: {'account_id': accountId});
  }

  /// #17 退群。
  Future<void> leaveRoom({required String token, required int roomId}) async {
    await _send('DELETE', '/api/rooms/$roomId/members/me', token: token);
  }

  /// #18 移除成员（仅群主）。
  Future<void> removeMember({
    required String token,
    required int roomId,
    required int accountId,
  }) async {
    await _send('DELETE', '/api/rooms/$roomId/members/$accountId', token: token);
  }

  // —— 发言（唯一写入口）——

  /// #19 `type` 只有 `dm` / `room`；`id` 是对端账号 id 或 `room_id`。
  Future<SentMessage> sendMessage({
    required String token,
    required String type,
    required int id,
    required String text,
  }) async {
    final json = await _send(
      'POST',
      '/api/conversations/$type/$id/messages',
      token: token,
      body: {'text': text},
      headers: {'X-Device-Type': deviceType},
    );
    return SentMessage.fromJson(json);
  }
}
