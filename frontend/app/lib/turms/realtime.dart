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
  final int? groupId;
  final int? recipientId;

  bool get isGroupMessage => groupId != null;

  /// 群消息归到 `room:<groupId>`，私聊归到对端账号。
  /// 解不出来的（自己发的私聊却没有 `recipientId`）返回空串，由调用方丢弃——
  /// 否则会落到 `dm:<自己>` 这种点不开的幽灵会话。
  String conversationKeyFor(int myAccountId) {
    if (groupId != null) {
      return 'room:$groupId';
    }
    final int? peer = senderId == myAccountId ? recipientId : senderId;
    if (peer == null || peer == myAccountId) {
      return '';
    }
    return 'dm:$peer';
  }
}

/// 读取通道：客户端自己的 Turms 会话（`docs/messaging-and-tunnel.md`）。
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
  Future<List<IncomingMessage>> history({
    required String conversationType,
    required int targetId,
    DateTime? before,
    int maxCount = 50,
  });

  Future<void> disconnect();
}

RealtimeClient createRealtime() => impl.createRealtime();
