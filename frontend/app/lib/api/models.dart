/// 与 `docs/api-contracts.md` 一一对应的传输模型。
/// 字段名保持契约里的 snake_case，转换只在这一层做，UI 不碰 Map。
library;

int _int(Object? v) => v is int ? v : int.parse(v.toString());
int? _intOrNull(Object? v) => v == null ? null : _int(v);
String _str(Object? v) => v as String? ?? '';
String? _strOrNull(Object? v) => v as String?;
bool _bool(Object? v) => v == true;
DateTime? _date(Object? v) => v == null ? null : DateTime.parse(v as String).toUtc();

/// #1 注册的响应：没有 token。
class RegisteredAccount {
  const RegisteredAccount({
    required this.accountId,
    required this.displayName,
    required this.type,
  });

  factory RegisteredAccount.fromJson(Map<String, dynamic> j) => RegisteredAccount(
        accountId: _int(j['account_id']),
        displayName: _str(j['display_name']),
        type: _str(j['type']),
      );

  final int accountId;
  final String displayName;
  final String type;
}

class Account {
  const Account({
    required this.accountId,
    required this.type,
    required this.displayName,
  });

  factory Account.fromJson(Map<String, dynamic> j) => Account(
        accountId: _int(j['account_id']),
        type: _str(j['type']),
        displayName: _str(j['display_name']),
      );

  final int accountId;
  final String type;
  final String displayName;

  bool get isAgent => type == 'agent';
}

/// #2 登录 / #20 续期：登录 JWT 与它归属的账号。
class LoginResult {
  const LoginResult({
    required this.token,
    required this.expiresAt,
    required this.account,
  });

  factory LoginResult.fromJson(Map<String, dynamic> j) => LoginResult(
        token: _str(j['token']),
        expiresAt: _date(j['expires_at']),
        account: Account.fromJson(j['account'] as Map<String, dynamic>),
      );

  final String token;
  final DateTime? expiresAt;
  final Account account;
}

/// #3 换 Turms 凭据的响应。`login_token` 只在「归属者切账号」形态出现。
class AccountSession {
  const AccountSession({
    required this.account,
    required this.loginToken,
    required this.loginExpiresAt,
    required this.turms,
  });

  factory AccountSession.fromJson(Map<String, dynamic> j) {
    final Map<String, dynamic> turms = (j['turms'] as Map<String, dynamic>?) ?? const <String, dynamic>{};
    return AccountSession(
      account: Account(
        accountId: _int(j['account_id']),
        type: _str(j['type']),
        displayName: _str(j['display_name']),
      ),
      loginToken: _strOrNull(j['login_token']),
      loginExpiresAt: _date(j['login_expires_at']),
      turms: TurmsCredential(
        userId: _int(turms['user_id']),
        credential: _str(turms['credential']),
        gatewayUrl: _str(turms['gateway_url']),
        expiresAt: _date(j['expires_at']),
      ),
    );
  }

  final Account account;
  final String? loginToken;
  final DateTime? loginExpiresAt;
  final TurmsCredential turms;
}

/// Turms 客户端的登录材料：`credential` 当 password 用，只授 QUERY。
class TurmsCredential {
  const TurmsCredential({
    required this.userId,
    required this.credential,
    required this.gatewayUrl,
    required this.expiresAt,
  });

  final int userId;
  final String credential;
  final String gatewayUrl;
  final DateTime? expiresAt;
}

/// #5 建 agent：明文密钥只在这个响应里出现一次。
class CreatedAgent {
  const CreatedAgent({
    required this.accountId,
    required this.displayName,
    required this.accountKey,
  });

  factory CreatedAgent.fromJson(Map<String, dynamic> j) => CreatedAgent(
        accountId: _int(j['account_id']),
        displayName: _str(j['display_name']),
        accountKey: _str(j['account_key']),
      );

  final int accountId;
  final String displayName;
  final String accountKey;
}

/// #7 资料页：只有三项，没有 type、邮箱、归属者。
class Profile {
  const Profile({
    required this.accountId,
    required this.displayName,
    required this.isFriend,
  });

  factory Profile.fromJson(Map<String, dynamic> j) => Profile(
        accountId: _int(j['account_id']),
        displayName: _str(j['display_name']),
        isFriend: _bool(j['is_friend']),
      );

  final int accountId;
  final String displayName;
  final bool isFriend;
}

class Friendship {
  const Friendship({
    required this.peerAccountId,
    required this.displayName,
    required this.status,
    required this.incoming,
    required this.requestedAt,
  });

  factory Friendship.fromJson(Map<String, dynamic> j) => Friendship(
        peerAccountId: _int(j['peer_account_id']),
        displayName: _str(j['display_name']),
        status: _str(j['status']),
        incoming: _bool(j['incoming']),
        requestedAt: _date(j['requested_at']),
      );

  final int peerAccountId;
  final String displayName;
  final String status;
  final bool incoming;
  final DateTime? requestedAt;
}

class Room {
  const Room({
    required this.roomId,
    required this.name,
    required this.ownerAccountId,
    required this.joinedAt,
  });

  /// 列表返回带 `joined_at`；`POST /api/rooms` 的返回只有 `created_at`（自己刚建的群，
  /// 加入时间就是创建时间），缺哪个用另一个顶上，而不是留空。
  factory Room.fromJson(Map<String, dynamic> j) => Room(
        roomId: _int(j['room_id']),
        name: _str(j['name']),
        ownerAccountId: _int(j['owner_account_id']),
        joinedAt: _date(j['joined_at'] ?? j['created_at']),
      );

  final int roomId;
  final String name;
  final int ownerAccountId;
  final DateTime? joinedAt;
}

class RoomDetail {
  const RoomDetail({
    required this.name,
    required this.ownerAccountId,
    required this.memberCount,
    required this.createdAt,
  });

  factory RoomDetail.fromJson(Map<String, dynamic> j) => RoomDetail(
        name: _str(j['name']),
        ownerAccountId: _int(j['owner_account_id']),
        memberCount: _intOrNull(j['member_count']) ?? 0,
        createdAt: _date(j['created_at']),
      );

  final String name;
  final int ownerAccountId;
  final int memberCount;
  final DateTime? createdAt;
}

class RoomMember {
  const RoomMember({
    required this.accountId,
    required this.displayName,
    required this.isFriend,
    required this.joinedAt,
  });

  factory RoomMember.fromJson(Map<String, dynamic> j) => RoomMember(
        accountId: _int(j['account_id']),
        displayName: _str(j['display_name']),
        isFriend: _bool(j['is_friend']),
        joinedAt: _date(j['joined_at']),
      );

  final int accountId;
  final String displayName;
  final bool isFriend;
  final DateTime? joinedAt;
}

/// 唯一分页的接口（群成员）额外的三个字段。
class Paged<T> {
  const Paged({required this.items, required this.page, required this.size, required this.total});

  final List<T> items;
  final int page;
  final int size;
  final int total;
}

/// #19 发言的响应：201 只表示 Turms 已落库并接下投递。
class SentMessage {
  const SentMessage({
    required this.messageId,
    required this.conversationType,
    required this.conversationId,
    required this.sentAt,
  });

  factory SentMessage.fromJson(Map<String, dynamic> j) {
    final Map<String, dynamic> conv = (j['conversation'] as Map<String, dynamic>?) ?? const <String, dynamic>{};
    return SentMessage(
      messageId: _int(j['message_id']),
      conversationType: _str(conv['type']),
      conversationId: _intOrNull(conv['id']) ?? 0,
      sentAt: _date(j['sent_at']),
    );
  }

  final int messageId;
  final String conversationType;
  final int conversationId;
  final DateTime? sentAt;
}
