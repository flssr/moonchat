import '../api/models.dart';
import 'realtime_stub.dart' if (dart.library.js_interop) 'realtime_web.dart' as impl;

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

/// 读取通道：客户端自己的 Turms 会话（`docs/truth/backend/messaging.md`）。
/// 它只授 QUERY，能收推送与查历史，发不出消息——写仍然只有 Biz 的写入网关。
abstract class RealtimeClient {
  /// 用 `POST /api/sessions` 拿到的凭据登录 `/im`。
  Future<void> connect({
    required TurmsCredential credential,
    required int myAccountId,
    required void Function(IncomingMessage message) onMessage,
    void Function(bool connected)? onConnected,
    void Function(Object error)? onError,
  });

  /// 按 `deliveryDate` 往回翻；`before` 传当前最早一条的时间。
  /// `targetId` 是 Turms 认的 id：私聊是对端账号 id，群是 `turms_group_id`。
  Future<List<IncomingMessage>> history({
    required String conversationType,
    required String targetId,
    DateTime? before,
    int maxCount = 50,
  });

  /// 会话的服务端已读时间（issue #37）：私聊取会话的 `readDate`，群取成员表里自己那条。
  /// 键是 `dm:<对端账号 id>` / `room:<turms 群 id>`；查不到的会话不出现在结果里，
  /// 查到了但从未上报过已读的，值是 null。未读与登录通知都以它为准。
  Future<Map<String, DateTime?>> readDates({
    required int myAccountId,
    required List<int> peerAccountIds,
    required List<String> turmsGroupIds,
  });

  Future<void> disconnect();
}

RealtimeClient createRealtime() => impl.createRealtime();
