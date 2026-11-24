import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter/foundation.dart';

import '../api/models.dart';
import 'realtime.dart';

/// `turms-client-js` 的 IIFE 构建（`vendor/turms/turms-client-js/dist/turms-client.iife.min.js`）
/// 由 `web/index.html` 以 `<script>` 引入，全局名就是 `TurmsClient`。
@JS('TurmsClient')
extension type _TurmsClient._(JSObject _) implements JSObject {
  external _TurmsClient(JSObject options);
  external _UserService get userService;
  external _MessageService get messageService;
  external _ConversationService get conversationService;
  external _NotificationService get notificationService;
  external _Driver get driver;
  external JSPromise<JSAny?> close();
}

@JS()
extension type _Driver._(JSObject _) implements JSObject {
  external void addOnDisconnectedListener(JSFunction listener);
  external JSPromise<JSObject> send(JSObject request);
}

@JS()
extension type _UserService._(JSObject _) implements JSObject {
  external JSPromise<JSAny?> login(JSObject options);
}

@JS()
extension type _MessageService._(JSObject _) implements JSObject {
  external void addMessageListener(JSFunction listener);
  external JSPromise<JSObject> queryMessages(JSObject options);
  external JSPromise<JSObject> sendMessage(JSObject options);
  external JSPromise<JSObject> recallMessage(JSObject options);
}

@JS()
extension type _NotificationService._(JSObject _) implements JSObject {
  external void addNotificationListener(JSFunction listener);
}

@JS()
extension type _ConversationService._(JSObject _) implements JSObject {
  external JSPromise<JSObject> queryPrivateConversations(JSObject options);
  external JSPromise<JSObject> queryGroupConversations(JSObject options);
  external JSPromise<JSObject> updatePrivateConversationReadDate(JSObject options);
  external JSPromise<JSObject> updateGroupConversationReadDate(JSObject options);
}

/// `turms-client-js` 的会话查询：私聊与群分开两个方法（issue #37 读已读时间）。
@JS('Date')
extension type _JSDate._(JSObject _) implements JSObject {
  external factory _JSDate(num milliseconds);
}

JSObject _object(Map<String, JSAny?> values) {
  final JSObject o = JSObject();
  values.forEach((String key, JSAny? value) {
    if (value != null) {
      o.setProperty(key.toJS, value);
    }
  });
  return o;
}

/// 统一把 JS 值转成 Dart 值：字符串、数字、布尔走这里，别在调用处做类型断言。
Object? _read(JSObject o, String key) {
  final JSAny? v = o.getProperty<JSAny?>(key.toJS);
  if (v == null || v.isUndefinedOrNull) {
    return null;
  }
  return v.dartify();
}

String? _readString(JSObject o, String key) {
  final Object? v = _read(o, key);
  return v is String ? v : v?.toString();
}

int? _readInt(JSObject o, String key) {
  final Object? v = _read(o, key);
  if (v is num) {
    return v.toInt();
  }
  if (v is String) {
    return int.tryParse(v);
  }
  return null;
}

/// `deliveryDate` / `readDate` 是 JS `Date`，`dartify` 不会替我们认，直接取毫秒。
DateTime? _dateFrom(JSAny? value) {
  if (value == null || value.isUndefinedOrNull) {
    return null;
  }
  final JSNumber ms = (value as JSObject).callMethod<JSNumber>('getTime'.toJS);
  final int epoch = ms.toDartInt;
  return epoch <= 0 ? null : DateTime.fromMillisecondsSinceEpoch(epoch, isUtc: true);
}

DateTime? _readDate(JSObject o, String key) =>
    _dateFrom(o.getProperty<JSAny?>(key.toJS));

List<JSObject> _dataItems(JSObject response) {
  final JSAny? data = response.getProperty<JSAny?>('data'.toJS);
  if (data == null || data.isUndefinedOrNull) {
    return const <JSObject>[];
  }
  return (data as JSArray<JSAny?>).toDart.whereType<JSObject>().toList(growable: false);
}

/// Turms 客户端把失败包成 `ResponseError`：`code` 是数值码，`reason` 只给人看。
/// 不要用 HTTP 状态分流；`fetch` 层甚至可能把非标准状态当异常抛。
TurmsException _turmsError(Object error) {
  if (error is TurmsException) {
    return error;
  }
  int? code;
  String reason = '';
  if (error is Map) {
    final Object? rawCode = error['code'];
    final Object? rawReason = error['reason'];
    if (rawCode is num) {
      code = rawCode.toInt();
    } else if (rawCode is String) {
      code = int.tryParse(rawCode);
    }
    if (rawReason is String) {
      reason = rawReason;
    }
  }
  try {
    // 显式 cast 而不是 `is`：Dart 值与 JS 互操作类型的 runtime `is` 在跨平台时不可靠。
    final JSObject jsError = error as JSObject;
    final JSAny? rawCode = jsError.getProperty<JSAny?>('code'.toJS);
    final Object? value =
        rawCode == null || rawCode.isUndefinedOrNull ? null : rawCode.dartify();
    if (value is num) {
      code = value.toInt();
    } else if (value is String) {
      code = int.tryParse(value);
    }
    final JSAny? rawReason = jsError.getProperty<JSAny?>('reason'.toJS);
    if (rawReason != null && !rawReason.isUndefinedOrNull) {
      reason = rawReason.dartify()?.toString() ?? '';
    }
  } catch (_) {
    // 不是 `ResponseError` 形状就退回字符串解析。
  }
  code ??= int.tryParse(
    RegExp(r'(?:^|[^0-9])(\d{4})(?:[^0-9]|$)').firstMatch(error.toString())?.group(1) ?? '',
  );
  return TurmsException(
    turmsCode: code ?? 0,
    message: reason.isEmpty ? error.toString() : reason,
  );
}

IncomingMessage _toMessage(JSObject raw) {
  return IncomingMessage(
    id: _readString(raw, 'id') ?? '',
    text: _readString(raw, 'text') ?? '',
    senderId: _readInt(raw, 'senderId') ?? 0,
    sentAt: _readDate(raw, 'deliveryDate'),
    // groupId / senderId 在 turms-client-js 里都是 int64→string；群句柄要保留原串。
    groupId: _readString(raw, 'groupId'),
    recipientId: _readInt(raw, 'recipientId'),
  );
}

/// 业务通知里只有 `updateMessageRequest` 需要处理：撤回带 `recallDate`，编辑带 `text`。
MessageUpdate? _toMessageUpdate(JSObject notification) {
  final JSAny? rawRequest = notification.getProperty<JSAny?>('relayedRequest'.toJS);
  if (rawRequest == null || rawRequest.isUndefinedOrNull) {
    return null;
  }
  final JSAny? rawUpdate =
      (rawRequest as JSObject).getProperty<JSAny?>('updateMessageRequest'.toJS);
  if (rawUpdate == null || rawUpdate.isUndefinedOrNull) {
    return null;
  }
  final JSObject update = rawUpdate as JSObject;
  final String? id = _readString(update, 'messageId');
  if (id == null || id.isEmpty) {
    return null;
  }
  return MessageUpdate(
    id: id,
    senderId: _readInt(notification, 'requesterId') ?? 0,
    text: _readString(update, 'text'),
    recallAt: _readDate(update, 'recallDate'),
  );
}

/// 把 Turms 网关地址规整成 WebSocket 形式。
String _wsUrl(String gatewayUrl) {
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

class WebRealtime implements RealtimeClient {
  _TurmsClient? _client;

  /// Web 端没有内置重连：状态层在断开事件后按退避换凭据重连。
  @override
  bool get reconnectsByItself => false;

  /// 连接代次：disconnect 或新 connect 会自增；旧连接晚到的回调按代次丢弃。
  int _generation = 0;

  _TurmsClient _requireClient() {
    final _TurmsClient? client = _client;
    if (client == null) {
      // 抛 ApiException 的子类：界面能把「还没连上」显示成可读文案，而不是未捕获异常。
      throw TurmsException(turmsCode: 1105, message: 'Turms 会话尚未连接');
    }
    return client;
  }

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
    final int generation = ++_generation;
    _TurmsClient? connecting;
    try {
      final _TurmsClient client = _TurmsClient(_object(<String, JSAny?>{
        'wsUrl': _wsUrl(credential.gatewayUrl).toJS,
        'connectionTimeout': 15000.toJS,
      }));
      connecting = client;

      void handler(JSObject message, JSObject addition) {
        try {
          final IncomingMessage parsed = _toMessage(message);
          if (parsed.text.isNotEmpty) {
            onMessage(parsed);
          }
        } catch (e) {
          // 单条解析失败不等于会话断了：丢掉这一条，别把整个读通道标成不可用。
          debugPrint('解析 Turms 消息失败：$e');
        }
      }

      client.messageService.addMessageListener(handler.toJS);
      if (onMessageUpdated != null) {
        // `notificationService` 只回调非创建类业务通知，正好是撤回/编辑。
        client.notificationService.addNotificationListener(((JSObject notification) {
          try {
            final MessageUpdate? update = _toMessageUpdate(notification);
            if (update != null) {
              onMessageUpdated(update);
            }
          } catch (e) {
            debugPrint('解析 Turms 消息更新失败：$e');
          }
        }).toJS);
      }
      // 连接断了要让状态层知道：否则 UI 一直显示「实时」，推送静悄悄停掉。
      // 旧连接（切号/重连）的断开回调不能把新连接一起拆掉。
      client.driver.addOnDisconnectedListener(((JSObject info) {
        if (!identical(_client, client)) {
          return;
        }
        _client = null;
        _generation++;
        onConnected?.call(false);
      }).toJS);

      await client.userService
          .login(_object(<String, JSAny?>{
            'userId': '$myAccountId'.toJS,
            'password': credential.credential.toJS,
            // Turms 的 DeviceType 是 DESKTOP/BROWSER/IOS/ANDROID/OTHERS/UNKNOWN，没有 WEB。
            'deviceType': 'BROWSER'.toJS,
          }))
          .toDart;
      if (generation != _generation) {
        // 登录期间被 disconnect 或新的 connect 取代：关掉这条，别让它复活成当前连接。
        await client.close().toDart;
        return;
      }
      _client = client;
      onConnected?.call(true);
    } catch (e) {
      // 登录失败就别留着半开的连接：清掉再报，否则后续查询会撞 CLIENT_SESSION_HAS_BEEN_CLOSED。
      final _TurmsClient? failed = connecting;
      if (failed != null) {
        try {
          await failed.close().toDart;
        } catch (_) {
          // 关闭失败不影响向上报错。
        }
      }
      if (generation == _generation) {
        _client = null;
        onConnected?.call(false);
        onError?.call(e);
      }
    }
  }

  @override
  Future<List<IncomingMessage>> history({
    required String conversationType,
    required String targetId,
    DateTime? before,
    int maxCount = 50,
  }) async {
    final _TurmsClient client = _requireClient();
    final JSObject params = _object(<String, JSAny?>{
      'areGroupMessages': (conversationType == 'room').toJS,
      'areSystemMessages': false.toJS,
      'fromIds': <JSAny>[targetId.toJS].toJS,
      'maxCount': maxCount.toJS,
      'descending': true.toJS,
      if (before != null) 'deliveryDateEnd': _JSDate(before.millisecondsSinceEpoch),
    });

    final JSObject response = await client.messageService.queryMessages(params).toDart;
    final JSAny? data = response.getProperty<JSAny?>('data'.toJS);
    if (data == null || data.isUndefinedOrNull) {
      return const <IncomingMessage>[];
    }
    final List<IncomingMessage> out = <IncomingMessage>[];
    final JSArray<JSAny?> arr = data as JSArray<JSAny?>;
    for (final JSAny? item in arr.toDart) {
      if (item == null) {
        continue;
      }
      out.add(_toMessage(item as JSObject));
    }
    return out;
  }

  @override
  Future<String> send({
    required String conversationType,
    required String targetId,
    required String text,
  }) async {
    try {
      final _TurmsClient client = _requireClient();
      final JSObject response = await client.messageService
          .sendMessage(_object(<String, JSAny?>{
            'isGroupMessage': (conversationType == 'room').toJS,
            'targetId': targetId.toJS,
            'text': text.toJS,
          }))
          .toDart;
      return _readString(response, 'data') ?? '';
    } catch (e) {
      throw _turmsError(e);
    }
  }

  @override
  Future<void> recall({required String messageId}) async {
    try {
      final _TurmsClient client = _requireClient();
      // 不传 recallDate：`turms-client-js` 会补当前时间；服务端要求 pastOrPresent。
      await client.messageService
          .recallMessage(_object(<String, JSAny?>{'messageId': messageId.toJS}))
          .toDart;
    } catch (e) {
      throw _turmsError(e);
    }
  }

  @override
  Future<Map<String, DateTime?>> groupReadDates({
    required List<String> turmsGroupIds,
    required int selfAccountId,
  }) async {
    if (turmsGroupIds.isEmpty) {
      return const <String, DateTime?>{};
    }
    try {
      final _TurmsClient client = _requireClient();
      final JSObject response = await client.conversationService
          .queryGroupConversations(_object(<String, JSAny?>{
            'groupIds': turmsGroupIds.map((String id) => id.toJS).toList().toJS,
          }))
          .toDart;
      final Map<String, DateTime?> out = <String, DateTime?>{};
      for (final JSObject raw in _dataItems(response)) {
        final String? groupId = _readString(raw, 'groupId');
        if (groupId == null) {
          continue;
        }
        final JSAny? rawDates = raw.getProperty<JSAny?>('memberIdToReadDate'.toJS);
        final DateTime? readDate = rawDates == null || rawDates.isUndefinedOrNull
            ? null
            : _dateFrom((rawDates as JSObject).getProperty<JSAny?>('$selfAccountId'.toJS));
        out[groupId] = readDate;
      }
      return out;
    } catch (e) {
      throw _turmsError(e);
    }
  }

  @override
  Future<void> markRead({
    required String conversationType,
    required String targetId,
  }) async {
    try {
      final _TurmsClient client = _requireClient();
      // `turms-client-js` 的生成模型把 UpdateConversationRequest 私聊字段叫 `targetId`
      // （proto 的 target_id），而会话服务的封装还在写 `userId`——那个字段名会被编码器
      // 忽略，服务端只会回 `1102 userId/groupId both null`。所以这里直接按模型字段发，
      // 群聊一并走 driver，避免两个封装层再分叉。
      final JSObject update = _object(<String, JSAny?>{
        (conversationType == 'room' ? 'groupId' : 'targetId'): targetId.toJS,
        'readDate': '${DateTime.now().millisecondsSinceEpoch}'.toJS,
      });
      final JSObject request = _object(<String, JSAny?>{
        'updateConversationRequest': update,
        'customAttributes': (<JSAny?>[]).toJS,
      });
      await client.driver.send(request).toDart;
    } catch (e) {
      throw _turmsError(e);
    }
  }

  @override
  Future<void> disconnect() async {
    _generation++;
    final _TurmsClient? client = _client;
    _client = null;
    if (client == null) {
      return;
    }
    try {
      await client.close().toDart;
    } catch (_) {
      // 关闭失败不影响后续重连。
    }
  }
}

RealtimeClient createRealtime() => WebRealtime();
