import 'dart:async';
import 'dart:io';

import 'package:fixnum/fixnum.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mondchat/api/models.dart';
import 'package:mondchat/turms/realtime.dart';
import 'package:mondchat_desktop/realtime.dart';
import 'package:turms_client_dart/turms_client.dart';

/// 用本地 WebSocket 冒充 Turms 网关，只校验线上契约：一帧一个 protobuf、
/// 请求/响应按 requestId 配对、登录用 DESKTOP、推送映射成 IncomingMessage，
/// 发送与已读按 Turms 的请求形状直写。
void main() {
  test('Turms WebSocket：登录、查历史、直写消息与已读、收推送', () async {
    final HttpServer server = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    addTearDown(() => server.close(force: true));

    final Completer<CreateSessionRequest> sessionRequest =
        Completer<CreateSessionRequest>();
    final Completer<QueryMessagesRequest> queryRequest =
        Completer<QueryMessagesRequest>();
    final List<CreateMessageRequest> createRequests = <CreateMessageRequest>[];
    final Completer<UpdateConversationRequest> dmReadRequest =
        Completer<UpdateConversationRequest>();
    final Completer<UpdateConversationRequest> groupReadRequest =
        Completer<UpdateConversationRequest>();
    final Completer<QueryConversationsRequest> privateConversationsRequest =
        Completer<QueryConversationsRequest>();
    final Completer<QueryConversationsRequest> groupConversationsRequest =
        Completer<QueryConversationsRequest>();
    final Completer<void> ready = Completer<void>();
    final Completer<IncomingMessage> pushed = Completer<IncomingMessage>();
    WebSocket? gateway;

    server.listen((HttpRequest request) async {
      final WebSocket socket = await WebSocketTransformer.upgrade(request);
      gateway = socket;
      socket.listen((dynamic data) {
        final TurmsRequest frame = TurmsRequest.fromBuffer(data as List<int>);
        if (frame.hasCreateSessionRequest()) {
          sessionRequest.complete(frame.createSessionRequest);
          socket.add(
            (TurmsNotification.create()
                  ..requestId = frame.requestId
                  ..code = 1000)
                .writeToBuffer(),
          );
          ready.complete();
          return;
        }
        if (frame.hasQueryMessagesRequest()) {
          queryRequest.complete(frame.queryMessagesRequest);
          final Messages messages = Messages();
          messages.messages.add(
            Message(
              id: Int64(42),
              text: '早',
              senderId: Int64(9),
              recipientId: Int64(7),
              deliveryDate: Int64(
                DateTime.utc(2026, 11, 16, 9).millisecondsSinceEpoch,
              ),
            ),
          );
          final TurmsNotification response = TurmsNotification.create()
            ..requestId = frame.requestId
            ..code = 1000;
          response.ensureData().messages = messages;
          socket.add(response.writeToBuffer());
          return;
        }
        if (frame.hasCreateMessageRequest()) {
          createRequests.add(frame.createMessageRequest);
          final TurmsNotification response = TurmsNotification.create()
            ..requestId = frame.requestId
            ..code = 1000;
          response.ensureData().long = Int64(99);
          socket.add(response.writeToBuffer());
          return;
        }
        if (frame.hasUpdateConversationRequest()) {
          final UpdateConversationRequest update =
              frame.updateConversationRequest;
          if (update.hasUserId()) {
            dmReadRequest.complete(update);
          } else {
            groupReadRequest.complete(update);
          }
          socket.add(
            (TurmsNotification.create()
                  ..requestId = frame.requestId
                  ..code = 1000)
                .writeToBuffer(),
          );
          return;
        }
        if (frame.hasQueryConversationsRequest()) {
          final QueryConversationsRequest query =
              frame.queryConversationsRequest;
          final Conversations conversations = Conversations();
          if (query.userIds.isNotEmpty) {
            privateConversationsRequest.complete(query);
            conversations.privateConversations.add(
              PrivateConversation(
                ownerId: Int64(7),
                targetId: query.userIds.first,
                readDate: Int64(
                  DateTime.utc(2026, 11, 16, 8).millisecondsSinceEpoch,
                ),
              ),
            );
          }
          if (query.groupIds.isNotEmpty) {
            groupConversationsRequest.complete(query);
            conversations.groupConversations.add(
              GroupConversation(
                groupId: query.groupIds.first,
                memberIdToReadDate: <Int64, Int64>{
                  Int64(7): Int64(
                    DateTime.utc(2026, 11, 16, 7).millisecondsSinceEpoch,
                  ),
                  Int64(8): Int64(
                    DateTime.utc(2026, 11, 16, 6).millisecondsSinceEpoch,
                  ),
                },
              ),
            );
          }
          final TurmsNotification response = TurmsNotification.create()
            ..requestId = frame.requestId
            ..code = 1000;
          response.ensureData().conversations = conversations;
          socket.add(response.writeToBuffer());
        }
      });
    });

    final DesktopRealtime client = DesktopRealtime();
    addTearDown(client.disconnect);
    await client.connect(
      credential: TurmsCredential(
        userId: 7,
        credential: 'token',
        gatewayUrl: 'ws://127.0.0.1:${server.port}/im',
        expiresAt: null,
      ),
      myAccountId: 7,
      onMessage: pushed.complete,
    );
    await ready.future;

    final CreateSessionRequest login = await sessionRequest.future;
    expect(login.version, 1);
    expect(login.userId.toInt(), 7);
    expect(login.password, 'token');
    expect(login.deviceType, DeviceType.DESKTOP);

    final List<IncomingMessage> page = await client.history(
      conversationType: 'dm',
      targetId: '9',
    );
    expect(page, hasLength(1));
    expect(page.single.text, '早');
    expect(page.single.senderId, 9);
    expect(page.single.conversationKeyFor(7), 'dm:9');
    final QueryMessagesRequest query = await queryRequest.future;
    expect(query.areGroupMessages, isFalse);
    expect(query.fromIds.single.toInt(), 9);

    final String messageId = await client.send(
      conversationType: 'dm',
      targetId: '9',
      text: '你好',
    );
    expect(messageId, '99');
    final CreateMessageRequest dm = createRequests.last;
    expect(dm.recipientId.toInt(), 9);
    expect(dm.hasGroupId(), isFalse);
    expect(dm.text, '你好');
    expect(dm.hasMessageId(), isFalse, reason: '消息 id 由服务端生成');
    expect(dm.hasDeliveryDate(), isFalse, reason: '投递时间由服务端生成');

    await client.send(conversationType: 'room', targetId: '456', text: '群里');
    final CreateMessageRequest group = createRequests.last;
    expect(group.groupId.toInt(), 456);
    expect(group.hasRecipientId(), isFalse);

    final Map<int, DateTime?> privateDates = await client.privateReadDates(
      <int>[9],
    );
    expect(privateDates[9], DateTime.utc(2026, 11, 16, 8));
    final QueryConversationsRequest privateQuery =
        await privateConversationsRequest.future;
    expect(privateQuery.userIds.single.toInt(), 9);
    expect(privateQuery.groupIds, isEmpty);

    final Map<String, DateTime?> groupDates = await client.groupReadDates(
      turmsGroupIds: <String>['456'],
      selfAccountId: 7,
    );
    expect(
      groupDates['456'],
      DateTime.utc(2026, 11, 16, 7),
      reason: '只取自己那条读时间，不渲染别人的',
    );
    final QueryConversationsRequest groupQuery =
        await groupConversationsRequest.future;
    expect(groupQuery.groupIds.single.toInt(), 456);
    expect(groupQuery.userIds, isEmpty);

    await client.markRead(conversationType: 'dm', targetId: '9');
    final UpdateConversationRequest dmRead = await dmReadRequest.future;
    expect(dmRead.userId.toInt(), 9);
    expect(dmRead.hasReadDate(), isFalse, reason: 'readDate 交给服务端时间');

    await client.markRead(conversationType: 'room', targetId: '456');
    final UpdateConversationRequest groupRead = await groupReadRequest.future;
    expect(groupRead.groupId.toInt(), 456);
    expect(groupRead.hasReadDate(), isFalse);

    final TurmsNotification push = TurmsNotification.create()
      ..requesterId = Int64(9)
      ..relayedRequest = (TurmsRequest.create()
        ..createMessageRequest = CreateMessageRequest(
          messageId: Int64(43),
          text: '新消息',
          recipientId: Int64(7),
          deliveryDate: Int64(
            DateTime.utc(2026, 11, 16, 10).millisecondsSinceEpoch,
          ),
        ));
    gateway!.add(push.writeToBuffer());

    final IncomingMessage message = await pushed.future.timeout(
      const Duration(seconds: 5),
    );
    expect(message.text, '新消息');
    expect(message.senderId, 9);
    expect(message.conversationKeyFor(7), 'dm:9');
  });
}
