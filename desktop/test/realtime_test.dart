import 'dart:async';
import 'dart:io';

import 'package:fixnum/fixnum.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mondchat/api/models.dart';
import 'package:mondchat/turms/realtime.dart';
import 'package:mondchat_desktop/realtime.dart';
import 'package:turms_client_dart/turms_client.dart';

/// 用本地 WebSocket 冒充 Turms 网关，只校验线上契约：一帧一个 protobuf、
/// 请求/响应按 requestId 配对、登录用 DESKTOP、推送映射成 IncomingMessage。
void main() {
  test('Turms WebSocket：登录、查历史、收推送', () async {
    final HttpServer server =
        await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));

    final Completer<CreateSessionRequest> sessionRequest =
        Completer<CreateSessionRequest>();
    final Completer<QueryMessagesRequest> queryRequest =
        Completer<QueryMessagesRequest>();
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

    final List<IncomingMessage> page =
        await client.history(conversationType: 'dm', targetId: '9');
    expect(page, hasLength(1));
    expect(page.single.text, '早');
    expect(page.single.senderId, 9);
    expect(page.single.conversationKeyFor(7), 'dm:9');
    final QueryMessagesRequest query = await queryRequest.future;
    expect(query.areGroupMessages, isFalse);
    expect(query.fromIds.single.toInt(), 9);

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

    final IncomingMessage message =
        await pushed.future.timeout(const Duration(seconds: 5));
    expect(message.text, '新消息');
    expect(message.senderId, 9);
    expect(message.conversationKeyFor(7), 'dm:9');
  });
}
