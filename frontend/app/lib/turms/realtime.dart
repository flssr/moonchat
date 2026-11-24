import '../api/api_client.dart';
import '../api/models.dart';
import 'realtime_stub.dart'
    if (dart.library.js_interop) 'realtime_web.dart'
    as impl;

/// Turms 直写失败：HTTP 状态不可靠，界面一律按 `code` 分流
/// （`docs/truth/backend/messaging.md`「失败语义」）。
///
/// 继承 `ApiException` 是为了复用界面现有的 `displayText` / `on ApiException` 路径；
/// 业务码仍然是 REST 那套，Turms 的数值码放在 [turmsCode]。
class TurmsException extends ApiException {
  TurmsException({required this.turmsCode, super.message})
    : super(code: 'turms_$turmsCode');

  final int turmsCode;

  /// 会话没建起来或凭据过期：调用方应换一次 Turms 凭据并重连，而不是当成发送失败。
  bool get needsReconnect => turmsCode == 1105 || turmsCode == 1300;

  @override
  String get displayText {
    switch (turmsCode) {
      case 1101:
        return '发得太快了，稍后再试';
      case 1105:
        return '连接已断开，正在重连，请稍后再试';
      case 1106:
        return '当前账号没有发言权限';
      case 1300:
        return '登录状态已过期，正在重新连接';
      case 5000:
        return '对方账号当前不可用';
      case 5001:
        return '只有好友之间才能私聊';
      case 5002:
        return '对方已拒收你的消息或申请';
      case 5003:
        return '你已被禁止在这个群里发言';
      case 5004:
      case 5006:
        return '这个群当前不可用';
      case 5005:
      case 5008:
      case 5009:
        return '你当前不能在这个群里发言';
      case 5007:
        return '不能给自己发消息';
      case 5010:
        return '消息内容不合规，请修改后再发';
      case 5200:
        return '这条消息已经不存在了';
      case 5201:
        return '撤回功能当前已关闭';
      case 5202:
        return '只能撤回自己发的消息';
      case 5204:
        return '超过撤回时限，不能撤回了';
      default:
        return '操作失败，请重试';
    }
  }
}

/// 一条消息的更新通知：撤回带 `recallAt`，编辑带新 `text`，两者不会同时来。
class MessageUpdate {
  const MessageUpdate({
    required this.id,
    required this.senderId,
    this.text,
    this.recallAt,
  });

  final String id;
  final int senderId;
  final String? text;
  final DateTime? recallAt;

  bool get isRecall => recallAt != null;
}

/// 一条从 Turms 收到的消息。字段与 `ParsedModel.Message` 对齐，转换只在这一层做。
class IncomingMessage {
  const IncomingMessage({
    required this.id,
    required this.text,
    required this.senderId,
    required this.sentAt,
    this.groupId,
    this.recipientId,
  });

  final String id;
  final String text;
  final int senderId;
  final DateTime? sentAt;

  /// Turms 的群句柄（雪花 id，字符串）：不是 PG `room_id`，归并与历史查询都要先映射。
  final String? groupId;
  final int? recipientId;

  bool get isGroupMessage => groupId != null;

  /// 私聊归到对端账号；群消息的 key 由 `AppState` 用 `turms_group_id → room_id` 映射后拼，
  /// 这里返回空串，由调用方丢弃或改走群映射。
  String conversationKeyFor(int myAccountId) {
    if (groupId != null) {
      return '';
    }
    final int? peer = senderId == myAccountId ? recipientId : senderId;
    if (peer == null || peer == myAccountId) {
      return '';
    }
    return 'dm:$peer';
  }
}

/// 读写共用的 Turms 通道：收推送、查历史、直写消息与已读
/// （`docs/truth/backend/messaging.md`）。
///
/// `targetId` 是 Turms 认的 id：私聊是对端账号 id，群是 `turms_group_id`，不是业务 `room_id`。
abstract class RealtimeClient {
  /// 用 `POST /api/sessions` 拿到的凭据登录 `/im`。
  Future<void> connect({
    required TurmsCredential credential,
    required int myAccountId,
    required void Function(IncomingMessage message) onMessage,
    void Function(MessageUpdate update)? onMessageUpdated,
    void Function(bool connected)? onConnected,
    void Function(Object error)? onError,
  });

  /// 按 `deliveryDate` 往回翻；`before` 传当前最早一条的时间。
  Future<List<IncomingMessage>> history({
    required String conversationType,
    required String targetId,
    DateTime? before,
    int maxCount = 50,
  });

  /// 在已有会话上直写一条消息，返回服务端生成的 id（雪花 id 用字符串）。
  Future<String> send({
    required String conversationType,
    required String targetId,
    required String text,
  });

  /// 撤回自己发的消息；服务端按「本人 + 5 分钟内」判定。
  Future<void> recall({required String messageId});

  /// 私聊读时间基线。只取自己的那条，返回值里没有的会话视为从未上报。
  Future<Map<int, DateTime?>> privateReadDates(List<int> peerAccountIds);

  /// 群聊读时间基线。`memberIdToReadDate` 里可能有全群成员，这里只取 [selfAccountId]。
  Future<Map<String, DateTime?>> groupReadDates({
    required List<String> turmsGroupIds,
    required int selfAccountId,
  });

  /// 把自己的读游标推到服务端当前时间（`readReceipt.useServerTime=true`）。
  Future<void> markRead({
    required String conversationType,
    required String targetId,
  });

  Future<void> disconnect();
}

RealtimeClient createRealtime() => impl.createRealtime();
