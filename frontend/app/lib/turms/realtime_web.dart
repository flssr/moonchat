import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import '../api/models.dart';
import 'realtime.dart';

/// `turms-client-js` 的 IIFE 构建（`vendor/turms/turms-client-js/dist/turms-client.iife.min.js`）
/// 由 `web/index.html` 以 `<script>` 引入，全局名就是 `TurmsClient`。
@JS('TurmsClient')
extension type _TurmsClient._(JSObject _) implements JSObject {
  external _TurmsClient(JSObject options);
  external _UserService get userService;
  external _MessageService get messageService;
  external JSPromise<JSAny?> close();
}

@JS()
extension type _UserService._(JSObject _) implements JSObject {
  external JSPromise<JSAny?> login(JSObject options);
}

@JS()
extension type _MessageService._(JSObject _) implements JSObject {
  external void addMessageListener(JSFunction listener);
  external JSPromise<JSObject> queryMessages(JSObject options);
}

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

/// `deliveryDate` 是 JS `Date`，`dartify` 不会替我们认，直接取毫秒。
DateTime? _readDate(JSObject o, String key) {
  final JSAny? v = o.getProperty<JSAny?>(key.toJS);
  if (v == null || v.isUndefinedOrNull) {
    return null;
  }
  final JSNumber ms = (v as JSObject).callMethod<JSNumber>('getTime'.toJS);
  return DateTime.fromMillisecondsSinceEpoch(ms.toDartInt, isUtc: true);
}

IncomingMessage _toMessage(JSObject raw) {
  return IncomingMessage(
    id: _readString(raw, 'id') ?? '',
    text: _readString(raw, 'text') ?? '',
    senderId: _readInt(raw, 'senderId') ?? 0,
    sentAt: _readDate(raw, 'deliveryDate'),
    groupId: _readInt(raw, 'groupId'),
    recipientId: _readInt(raw, 'recipientId'),
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

  @override
  Future<void> connect({
    required TurmsCredential credential,
    required int myAccountId,
    required void Function(IncomingMessage message) onMessage,
    void Function(bool connected)? onConnected,
    void Function(Object error)? onError,
  }) async {
    await disconnect();
    try {
      final _TurmsClient client = _TurmsClient(_object(<String, JSAny?>{
        'wsUrl': _wsUrl(credential.gatewayUrl).toJS,
        'connectionTimeout': 15000.toJS,
      }));
      _client = client;

      void handler(JSObject message, JSObject addition) {
        try {
          final IncomingMessage parsed = _toMessage(message);
          if (parsed.text.isNotEmpty) {
            onMessage(parsed);
          }
        } catch (e) {
          onError?.call(e);
        }
      }

      client.messageService.addMessageListener(handler.toJS);

      await client.userService
          .login(_object(<String, JSAny?>{
            'userId': '$myAccountId'.toJS,
            'password': credential.credential.toJS,
            'deviceType': 'WEB'.toJS,
          }))
          .toDart;
      onConnected?.call(true);
    } catch (e) {
      onConnected?.call(false);
      onError?.call(e);
    }
  }

  @override
  Future<List<IncomingMessage>> history({
    required String conversationType,
    required int targetId,
    DateTime? before,
    int maxCount = 50,
  }) async {
    final _TurmsClient? client = _client;
    if (client == null) {
      return const <IncomingMessage>[];
    }
    final JSObject params = _object(<String, JSAny?>{
      'areGroupMessages': (conversationType == 'room').toJS,
      'areSystemMessages': false.toJS,
      'fromIds': <JSAny>['$targetId'.toJS].toJS,
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
  Future<void> disconnect() async {
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
