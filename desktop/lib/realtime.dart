import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:fixnum/fixnum.dart';
import 'package:mondchat/api/models.dart';
import 'package:mondchat/turms/realtime.dart';
import 'package:turms_client_dart/turms_client.dart';

/// Turms 只提供 TCP 的 Dart 客户端（11510），部署出来的只有 `/im` WebSocket（10510）。
/// 这里按 `turms-client-js` 的线上格式走 WebSocket：一帧一个 `TurmsRequest` /
/// `TurmsNotification`，用仓库固定版本的 Dart proto 类编解码，请求与响应按 `requestId` 配对。
/// 覆盖客户端要的四件事：登录会话、查历史、直写消息与已读
/// （`docs/truth/backend/messaging.md`）。
class DesktopRealtime implements RealtimeClient {
  static const Duration _connectTimeout = Duration(seconds: 15);
  static const Duration _requestTimeout = Duration(seconds: 20);
  static const Duration _heartbeatIdle = Duration(seconds: 30);
  static const Duration _heartbeatCheck = Duration(seconds: 10);
  static const Duration _heartbeatTimeout = Duration(seconds: 90);
  static const Duration _reconnectBase = Duration(seconds: 2);
  static const int _reconnectMaxSeconds = 30;

  WebSocket? _socket;
  Timer? _heartbeat;
  Timer? _reconnectTimer;
  int _lastRequestAt = 0;

  /// 最后一次收到服务器帧（包括心跳空帧）的时间；半开连接靠它发现。
  int _lastFrameAt = 0;
  int _nextRequestId = 0;
  int _reconnectAttempt = 0;
  bool _manualClose = true;
  _ReconnectArgs? _reconnectArgs;

  /// 代次：disconnect 或新连接会自增；旧连接晚到的帧与关闭回调按代次丢弃。
  int _generation = 0;
  bool _up = false;

  final Map<int, Completer<TurmsNotification>> _pending =
      <int, Completer<TurmsNotification>>{};

  void Function(IncomingMessage)? _onMessage;
  void Function(MessageUpdate)? _onMessageUpdated;
  void Function(bool)? _onConnected;
  void Function(Object)? _onError;

  @override
  Future<void> connect({
    required TurmsCredential credential,
    required int myAccountId,
    required void Function(IncomingMessage message) onMessage,
    void Function(MessageUpdate update)? onMessageUpdated,
    void Function(bool connected)? onConnected,
    void Function(Object error)? onError,
  }) async {
    await disconnect();
    _manualClose = false;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _reconnectArgs = _ReconnectArgs(
      credential: credential,
      myAccountId: myAccountId,
      onMessage: onMessage,
      onMessageUpdated: onMessageUpdated,
      onConnected: onConnected,
      onError: onError,
    );
    _lastFrameAt = DateTime.now().millisecondsSinceEpoch;
    final int generation = ++_generation;
    _onMessage = onMessage;
    _onMessageUpdated = onMessageUpdated;
    _onConnected = onConnected;
    _onError = onError;
    try {
      final WebSocket socket = await WebSocket.connect(_wsUrl(credential.gatewayUrl))
          .timeout(_connectTimeout);
      if (generation != _generation) {
        await socket.close();
        return;
      }
      _socket = socket;
      socket.listen(
        (Object? frame) => _handleFrame(generation, frame),
        onDone: () => _markDown(generation),
        onError: (Object error, StackTrace _) => _markDown(generation, error),
        cancelOnError: false,
      );
      final TurmsNotification response = await _sessionRequest(
        CreateSessionRequest(
          // 与 turms-client-js / turms-client-dart 一致：网关按它判断客户端兼容性。
          version: 1,
          userId: Int64(myAccountId),
          password: credential.credential,
          // 与 Web 的 BROWSER 区分：同一账号的桌面端和浏览器是两种在线设备。
          deviceType: DeviceType.DESKTOP,
        ),
      );
      _ensureSuccess(response, 'Turms 会话');
      _up = true;
      _reconnectAttempt = 0;
      _startHeartbeat();
      _onConnected?.call(true);
    } catch (e) {
      _markDown(generation, e);
    }
  }

  @override
  Future<List<IncomingMessage>> history({
    required String conversationType,
    required String targetId,
    DateTime? before,
    int maxCount = 50,
  }) async {
    if (!_up) {
      throw StateError('Turms 会话尚未连接');
    }
    final TurmsNotification response = await _queryRequest(
      QueryMessagesRequest(
        areGroupMessages: conversationType == 'room',
        areSystemMessages: false,
        fromIds: <Int64>[Int64.parseInt(targetId)],
        deliveryDateEnd:
            before == null ? null : Int64(before.millisecondsSinceEpoch),
        maxCount: maxCount,
        descending: true,
      ),
    );
    _ensureSuccess(response, '查历史消息');
    if (!response.hasData() || !response.data.hasMessages()) {
      return const <IncomingMessage>[];
    }
    return response.data.messages.messages
        .map(_toIncoming)
        .toList(growable: false);
  }

  @override
  Future<String> send({
    required String conversationType,
    required String targetId,
    required String text,
  }) async {
    final bool isGroup = conversationType == 'room';
    final TurmsNotification response = await _request(
      TurmsRequest.create()
        ..createMessageRequest = CreateMessageRequest(
          groupId: isGroup ? Int64.parseInt(targetId) : null,
          recipientId: isGroup ? null : Int64.parseInt(targetId),
          text: text,
        ),
    );
    _ensureSuccess(response, '发送消息');
    if (!response.hasData() || !response.data.hasLong()) {
      throw TurmsException(turmsCode: 0, message: '发送响应没有消息 id');
    }
    return response.data.long.toString();
  }

  @override
  Future<void> recall({required String messageId}) async {
    final TurmsNotification response = await _request(
      TurmsRequest.create()
        ..updateMessageRequest = UpdateMessageRequest(
          messageId: Int64.parseInt(messageId),
          // 服务端校验 pastOrPresent 且 recallDate 不能早于 deliveryDate；
          // 省略会被当成「没有更新」，所以用本地当前时间。
          recallDate: Int64(DateTime.now().millisecondsSinceEpoch),
        ),
    );
    _ensureSuccess(response, '撤回消息');
  }

  @override
  Future<Map<int, DateTime?>> privateReadDates(List<int> peerAccountIds) async {
    if (peerAccountIds.isEmpty) {
      return const <int, DateTime?>{};
    }
    final TurmsNotification response = await _request(
      TurmsRequest.create()
        ..queryConversationsRequest = QueryConversationsRequest(
          userIds: peerAccountIds.map((int id) => Int64(id)),
        ),
    );
    _ensureSuccess(response, '查私聊读时间');
    final Map<int, DateTime?> out = <int, DateTime?>{};
    if (!response.hasData() || !response.data.hasConversations()) {
      return out;
    }
    for (final PrivateConversation conversation
        in response.data.conversations.privateConversations) {
      final int epoch = conversation.hasReadDate() ? conversation.readDate.toInt() : 0;
      out[conversation.targetId.toInt()] = epoch <= 0
          ? null
          : DateTime.fromMillisecondsSinceEpoch(epoch, isUtc: true);
    }
    return out;
  }

  @override
  Future<Map<String, DateTime?>> groupReadDates({
    required List<String> turmsGroupIds,
    required int selfAccountId,
  }) async {
    if (turmsGroupIds.isEmpty) {
      return const <String, DateTime?>{};
    }
    final TurmsNotification response = await _request(
      TurmsRequest.create()
        ..queryConversationsRequest = QueryConversationsRequest(
          groupIds: turmsGroupIds.map(Int64.parseInt),
        ),
    );
    _ensureSuccess(response, '查群读时间');
    final Map<String, DateTime?> out = <String, DateTime?>{};
    if (!response.hasData() || !response.data.hasConversations()) {
      return out;
    }
    for (final GroupConversation conversation
        in response.data.conversations.groupConversations) {
      final int? epoch =
          conversation.memberIdToReadDate[Int64(selfAccountId)]?.toInt();
      out[conversation.groupId.toString()] =
          epoch == null || epoch <= 0
              ? null
              : DateTime.fromMillisecondsSinceEpoch(epoch, isUtc: true);
    }
    return out;
  }

  @override
  Future<void> markRead({
    required String conversationType,
    required String targetId,
  }) async {
    final bool isGroup = conversationType == 'room';
    final TurmsNotification response = await _request(
      TurmsRequest.create()
        ..updateConversationRequest = UpdateConversationRequest(
          userId: isGroup ? null : Int64.parseInt(targetId),
          groupId: isGroup ? Int64.parseInt(targetId) : null,
        ),
    );
    _ensureSuccess(response, '更新已读');
  }

  @override
  Future<void> disconnect() async {
    _manualClose = true;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _generation++;
    _heartbeat?.cancel();
    _heartbeat = null;
    _up = false;
    final WebSocket? socket = _socket;
    _socket = null;
    final StateError closed = StateError('Turms 会话已断开');
    for (final Completer<TurmsNotification> pending in _pending.values) {
      if (!pending.isCompleted) {
        pending.completeError(closed);
      }
    }
    _pending.clear();
    if (socket != null) {
      try {
        await socket.close();
      } catch (_) {
        // 关闭失败不影响后续重连。
      }
    }
  }

  // 请求

  Future<TurmsNotification> _request(TurmsRequest request) {
    final int id = _nextRequestIdToUse();
    request.requestId = Int64(id);
    return _send(request, id);
  }

  Future<TurmsNotification> _sessionRequest(CreateSessionRequest request) =>
      _request(TurmsRequest.create()..createSessionRequest = request);

  Future<TurmsNotification> _queryRequest(QueryMessagesRequest request) =>
      _request(TurmsRequest.create()..queryMessagesRequest = request);

  int _nextRequestIdToUse() {
    // 正数、单连接内不重复即可；与 JS 客户端一样按请求关联响应。
    _nextRequestId = _nextRequestId % 9007199254740991 + 1;
    return _nextRequestId;
  }

  Future<TurmsNotification> _send(TurmsRequest request, int id) async {
    final WebSocket? socket = _socket;
    if (socket == null) {
      throw TurmsException(turmsCode: 1105, message: 'Turms 会话尚未连接');
    }
    final Completer<TurmsNotification> completer = Completer<TurmsNotification>();
    _pending[id] = completer;
    _lastRequestAt = DateTime.now().millisecondsSinceEpoch;
    socket.add(request.writeToBuffer());
    try {
      return await completer.future.timeout(_requestTimeout);
    } on TimeoutException {
      _pending.remove(id);
      throw TurmsException(turmsCode: 1105, message: 'Turms 请求超时');
    }
  }

  // 收帧

  void _handleFrame(int generation, Object? frame) {
    if (generation != _generation || frame is! List<int>) {
      return;
    }
    // 心跳回包也是空帧：先记存活，再看内容。
    _lastFrameAt = DateTime.now().millisecondsSinceEpoch;
    if (frame.isEmpty) {
      return;
    }
    final TurmsNotification notification;
    try {
      notification = TurmsNotification.fromBuffer(frame);
    } catch (_) {
      // 单帧坏了不等于连接坏了：丢掉这一帧，和 Web 端解析失败的处理一致。
      return;
    }
    if (notification.hasCloseStatus()) {
      _markDown(generation, StateError('Turms 终止了会话（${notification.closeStatus}）'));
      return;
    }
    if (!notification.hasRelayedRequest() && notification.hasRequestId()) {
      final Completer<TurmsNotification>? pending =
          _pending.remove(notification.requestId.toInt());
      if (pending != null) {
        pending.complete(notification);
        return;
      }
    }
    if (notification.hasRelayedRequest() &&
        notification.relayedRequest.hasUpdateMessageRequest()) {
      _deliverUpdate(notification);
      return;
    }
    if (notification.hasRelayedRequest() &&
        notification.relayedRequest.hasCreateMessageRequest()) {
      _deliver(notification);
    }
  }

  void _deliverUpdate(TurmsNotification notification) {
    final UpdateMessageRequest request =
        notification.relayedRequest.updateMessageRequest;
    if (!request.hasMessageId()) {
      return;
    }
    _onMessageUpdated?.call(
      MessageUpdate(
        id: request.messageId.toString(),
        senderId:
            notification.hasRequesterId() ? notification.requesterId.toInt() : 0,
        text: request.hasText() ? request.text : null,
        recallAt: request.hasRecallDate()
            ? DateTime.fromMillisecondsSinceEpoch(
                request.recallDate.toInt(),
                isUtc: true,
              )
            : null,
      ),
    );
  }

  void _deliver(TurmsNotification notification) {
    final CreateMessageRequest request =
        notification.relayedRequest.createMessageRequest;
    if (request.text.isEmpty) {
      // 与 Web 端一致：只推有正文的消息。
      return;
    }
    _onMessage?.call(
      IncomingMessage(
        id: request.hasMessageId() ? request.messageId.toString() : '',
        text: request.text,
        senderId:
            notification.hasRequesterId() ? notification.requesterId.toInt() : 0,
        sentAt: request.hasDeliveryDate()
            ? DateTime.fromMillisecondsSinceEpoch(
                request.deliveryDate.toInt(),
                isUtc: true,
              )
            : null,
        groupId: request.hasGroupId() ? request.groupId.toString() : null,
        recipientId:
            request.hasRecipientId() ? request.recipientId.toInt() : null,
      ),
    );
  }

  IncomingMessage _toIncoming(Message message) => IncomingMessage(
        id: message.id.toString(),
        text: message.text,
        senderId: message.senderId.toInt(),
        sentAt: message.hasDeliveryDate()
            ? DateTime.fromMillisecondsSinceEpoch(
                message.deliveryDate.toInt(),
                isUtc: true,
              )
            : null,
        groupId: message.hasGroupId() ? message.groupId.toString() : null,
        recipientId:
            message.hasRecipientId() ? message.recipientId.toInt() : null,
      );

  void _ensureSuccess(TurmsNotification notification, String what) {
    final int code = notification.hasCode() ? notification.code : 0;
    if (code >= 1000 && code < 2000) {
      return;
    }
    throw TurmsException(
      turmsCode: code,
      message: notification.hasReason() ? notification.reason : what,
    );
  }

  void _markDown(int generation, [Object? error]) {
    if (generation != _generation) {
      return;
    }
    _generation++;
    _heartbeat?.cancel();
    _heartbeat = null;
    _up = false;
    final WebSocket? socket = _socket;
    _socket = null;
    if (socket != null) {
      unawaited(socket.close());
    }
    final StateError closed = StateError('Turms 会话已断开');
    for (final Completer<TurmsNotification> pending in _pending.values) {
      if (!pending.isCompleted) {
        pending.completeError(closed);
      }
    }
    _pending.clear();
    _onConnected?.call(false);
    if (error != null) {
      _onError?.call(error);
    }
    _scheduleReconnect();
  }

  /// 断线自愈：半开连接不会触发 onDone，心跳回包超时也要把连接判死；
  /// 断开后指数退避重连，直到显式 disconnect（登出/切号）。
  void _scheduleReconnect() {
    if (_manualClose || _reconnectArgs == null) {
      return;
    }
    _reconnectTimer?.cancel();
    final int seconds =
        (_reconnectBase.inSeconds << _reconnectAttempt.clamp(0, 4))
            .clamp(_reconnectBase.inSeconds, _reconnectMaxSeconds);
    _reconnectAttempt++;
    _reconnectTimer = Timer(Duration(seconds: seconds), () {
      final _ReconnectArgs? args = _reconnectArgs;
      if (_manualClose || args == null) {
        return;
      }
      unawaited(
        connect(
          credential: args.credential,
          myAccountId: args.myAccountId,
          onMessage: args.onMessage,
          onMessageUpdated: args.onMessageUpdated,
          onConnected: args.onConnected,
          onError: args.onError,
        ),
      );
    });
  }

  void _startHeartbeat() {
    _heartbeat?.cancel();
    final int now = DateTime.now().millisecondsSinceEpoch;
    _lastRequestAt = now;
    _lastFrameAt = now;
    _heartbeat = Timer.periodic(_heartbeatCheck, (Timer _) {
      final WebSocket? socket = _socket;
      if (socket == null) {
        return;
      }
      final int current = DateTime.now().millisecondsSinceEpoch;
      if (current - _lastFrameAt > _heartbeatTimeout.inMilliseconds) {
        _markDown(_generation, StateError('Turms 心跳超时'));
        return;
      }
      if (current - _lastRequestAt < _heartbeatIdle.inMilliseconds) {
        return;
      }
      _lastRequestAt = current;
      socket.add(Uint8List(0));
    });
  }

  static String _wsUrl(String gatewayUrl) {
    if (gatewayUrl.startsWith('ws://') || gatewayUrl.startsWith('wss://')) {
      return gatewayUrl;
    }
    if (gatewayUrl.startsWith('https://')) {
      return 'wss://${gatewayUrl.substring('https://'.length)}';
    }
    if (gatewayUrl.startsWith('http://')) {
      return 'ws://${gatewayUrl.substring('http://'.length)}';
    }
    return gatewayUrl;
  }
}

class _ReconnectArgs {
  const _ReconnectArgs({
    required this.credential,
    required this.myAccountId,
    required this.onMessage,
    required this.onMessageUpdated,
    required this.onConnected,
    required this.onError,
  });

  final TurmsCredential credential;
  final int myAccountId;
  final void Function(IncomingMessage message) onMessage;
  final void Function(MessageUpdate update)? onMessageUpdated;
  final void Function(bool connected)? onConnected;
  final void Function(Object error)? onError;
}
