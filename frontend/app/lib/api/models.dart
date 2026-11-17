/// 与 `docs/truth/backend/README.md` 一一对应的传输模型。
/// 字段名保持契约里的 snake_case，转换只在这一层做，UI 不碰 Map。
library;

/// 契约里的整数可能是 Jackson 的 `long` 或 `double`（如 `1.0`），两种都接受；
/// 解析不出来就让异常冒出去，由 `ApiClient` 统一转成 `upstream_unavailable`。
int _int(Object? v) => v is num ? v.toInt() : int.parse(v.toString());
int? _intOrNull(Object? v) => v == null ? null : _int(v);
String _str(Object? v) => v as String? ?? '';
String? _strOrNull(Object? v) => v as String?;
bool _bool(Object? v) => v == true;
DateTime? _date(Object? v) => v == null ? null : DateTime.parse(v as String).toUtc();

/// 生日是日历日，不是时刻：只取年月日。
/// 契约是 `YYYY-MM-DD`；带偏移的完整时间戳先截日期段，避免按 UTC 取「日」差一天。
DateTime? _dateOnly(Object? v) {
  if (v is! String) {
    return null;
  }
  final String raw = v.length > 10 ? v.substring(0, 10) : v;
  final DateTime? parsed = DateTime.tryParse(raw);
  return parsed == null ? null : DateTime(parsed.year, parsed.month, parsed.day);
}

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
    this.avatar,
    this.gender,
    this.birthday,
  });

  factory Account.fromJson(Map<String, dynamic> j) => Account(
        accountId: _int(j['account_id']),
        type: _str(j['type']),
        displayName: _str(j['display_name']),
        avatar: _strOrNull(j['avatar']),
        gender: _strOrNull(j['gender']),
        birthday: _dateOnly(j['birthday']),
      );

  final int accountId;
  final String type;
  final String displayName;

  /// 平台默认头像 key；null 表示客户端按 id 生成首字头像（服务端头像列见 issue #10）。
  final String? avatar;

  /// `male` / `female` / `other` / `private`；后端未上线时为空。
  final String? gender;

  /// 只到日；星座由客户端按它推导，不落库。
  final DateTime? birthday;

  bool get isAgent => type == 'agent';
}

/// #6 / #24 本人完整资料：`GET /api/accounts/me` 与 `PUT /api/accounts/me` 同形。
class MyProfile {
  const MyProfile({
    required this.accountId,
    required this.displayName,
    required this.gender,
    required this.birthday,
    this.avatar,
  });

  factory MyProfile.fromJson(Map<String, dynamic> j) => MyProfile(
        accountId: j.containsKey('account_id') ? _int(j['account_id']) : 0,
        displayName: j['display_name'] is String ? j['display_name'] as String : '',
        gender: j['gender'] is String ? j['gender'] as String : null,
        birthday: _dateOnly(j['birthday']),
        avatar: j['avatar'] is String ? j['avatar'] as String : null,
      );

  final int accountId;
  final String displayName;
  final String? gender;
  final DateTime? birthday;
  final String? avatar;
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
      account: Account.fromJson(j),
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
    this.avatar,
  });

  factory Profile.fromJson(Map<String, dynamic> j) => Profile(
        accountId: _int(j['account_id']),
        displayName: _str(j['display_name']),
        isFriend: _bool(j['is_friend']),
        avatar: _strOrNull(j['avatar']),
      );

  final int accountId;
  final String displayName;
  final bool isFriend;
  final String? avatar;
}

class Friendship {
  const Friendship({
    required this.peerAccountId,
    required this.displayName,
    required this.status,
    required this.incoming,
    required this.requestedAt,
    this.avatar,
  });

  factory Friendship.fromJson(Map<String, dynamic> j) => Friendship(
        peerAccountId: _int(j['peer_account_id']),
        displayName: _str(j['display_name']),
        status: _str(j['status']),
        incoming: _bool(j['incoming']),
        requestedAt: _date(j['requested_at']),
        avatar: _strOrNull(j['avatar']),
      );

  final int peerAccountId;
  final String displayName;
  final String status;
  final bool incoming;
  final DateTime? requestedAt;
  final String? avatar;
}

class Room {
  const Room({
    required this.roomId,
    required this.name,
    required this.ownerAccountId,
    required this.joinedAt,
    this.turmsGroupId,
  });

  /// 列表返回带 `joined_at`；`POST /api/rooms` 的返回只有 `created_at`（自己刚建的群，
  /// 加入时间就是创建时间），缺哪个用另一个顶上，而不是留空。
  factory Room.fromJson(Map<String, dynamic> j) => Room(
        roomId: _int(j['room_id']),
        name: _str(j['name']),
        ownerAccountId: _int(j['owner_account_id']),
        joinedAt: _date(j['joined_at'] ?? j['created_at']),
        // 只在 GET /api/rooms 出现；字符串是 Turms 雪花 id，不能走 int。
        turmsGroupId: _strOrNull(j['turms_group_id']),
      );

  final int roomId;
  final String name;
  final int ownerAccountId;
  final DateTime? joinedAt;

  /// Turms 的群句柄：查群历史、把群推送归回 `room_id` 用；不是对外标识。
  final String? turmsGroupId;
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
    this.avatar,
  });

  factory RoomMember.fromJson(Map<String, dynamic> j) => RoomMember(
        accountId: _int(j['account_id']),
        displayName: _str(j['display_name']),
        isFriend: _bool(j['is_friend']),
        joinedAt: _date(j['joined_at']),
        avatar: _strOrNull(j['avatar']),
      );

  final int accountId;
  final String displayName;
  final bool isFriend;
  final DateTime? joinedAt;
  final String? avatar;
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
class BlocklistItem {
  const BlocklistItem({
    required this.accountId,
    required this.displayName,
    this.createdAt,
  });

  factory BlocklistItem.fromJson(Map<String, dynamic> j) => BlocklistItem(
        accountId: _int(j['account_id']),
        displayName: _str(j['display_name']),
        createdAt: _date(j['created_at']),
      );

  final int accountId;
  final String displayName;
  final DateTime? createdAt;
}

class BlocklistPage {
  const BlocklistPage({required this.items, required this.total});

  factory BlocklistPage.fromJson(Map<String, dynamic> j) {
    final List<dynamic> raw = (j['items'] as List<dynamic>?) ?? const <dynamic>[];
    return BlocklistPage(
      items: raw
          .map((dynamic e) => BlocklistItem.fromJson(e as Map<String, dynamic>))
          .toList(growable: false),
      total: _intOrNull(j['total']) ?? 0,
    );
  }

  final List<BlocklistItem> items;
  final int total;
}

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
