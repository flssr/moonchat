import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter/foundation.dart';

import '../api/models.dart';
import 'realtime.dart';

/// `turms-client-js` 的 IIFE 构建（`vendor/turms/turms-client-js/dist/turms-client.iife.min.js`）
/// 由 `web/index.html` 以 `<script>` 引入，全局名就是 `TurmsClient`。
@JS()
extension type _TurmsClient._(JSObject _) implements JSObject {
  external _TurmsClient(JSObject options);
  external _UserService get userService;
  external _MessageService get messageService;
  external _ConversationService get conversationService;
  external _Driver get driver;
  external JSPromise<JSAny?> close();
}

@JS()
extension type _Driver._(JSObject _) implements JSObject {
  external void addOnDisconnectedListener(JSFunction listener);
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

/// `turms-client-js` 的会话查询：私聊与群分开两个方法（issue #37 读已读时间）。
@JS()
extension type _ConversationService._(JSObject _) implements JSObject {
  external JSPromise<JSArray<JSAny?>> queryPrivateConversations(JSObject options);
  external JSPromise<JSArray<JSAny?>> queryGroupConversations(JSObject options);
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
  return _dateFromJs(v);
}

/// JS `Date` → UTC `DateTime`；null / undefined / 0 都当没上报过。
DateTime? _dateFromJs(JSAny? v) {
  if (v == null || v.isUndefinedOrNull) {
    return null;
  }
  final JSNumber ms = (v as JSObject).callMethod<JSNumber>('getTime'.toJS);
  final int millis = ms.toDartInt;
  if (millis <= 0) {
    return null;
  }
  return DateTime.fromMillisecondsSinceEpoch(millis, isUtc: true);
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

  /// 连接代次：disconnect 或新 connect 会自增；旧连接晚到的回调按代次丢弃。
  int _generation = 0;

  @override
  Future<void> connect({
    required TurmsCredential credential,
    required int myAccountId,
    required void Function(IncomingMessage message) onMessage,
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
    final _TurmsClient? client = _client;
    if (client == null) {
      // 抛而不是返回空数组：空数组会被 `AppState` 当成「这个会话到底了」，从此拉不到历史。
      throw StateError('Turms 会话尚未连接');
    }
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
  Future<Map<String, DateTime?>> readDates({
    required int myAccountId,
    required List<int> peerAccountIds,
    required List<String> turmsGroupIds,
  }) async {
    final _TurmsClient? client = _client;
    if (client == null) {
      throw StateError('Turms 会话尚未连接');
    }
    final Map<String, DateTime?> out = <String, DateTime?>{};

    if (peerAccountIds.isNotEmpty) {
      final JSArray<JSAny?> list = await client.conversationService
          .queryPrivateConversations(_object(<String, JSAny?>{
            'userIds': <JSAny>[for (final int id in peerAccountIds) '$id'.toJS].toJS,
          }))
          .toDart;
      for (final JSAny? item in list.toDart) {
        if (item == null) {
          continue;
        }
        final JSObject raw = item as JSObject;
        final String? target = _readString(raw, 'targetId');
        if (target != null) {
          // 对方从没打开过时是 null：调用方按「没有游标」处理。
          out['dm:$target'] = _readDate(raw, 'readDate');
        }
      }
    }

    if (turmsGroupIds.isNotEmpty) {
      final JSArray<JSAny?> list = await client.conversationService
          .queryGroupConversations(_object(<String, JSAny?>{
            'groupIds': <JSAny>[for (final String id in turmsGroupIds) id.toJS].toJS,
          }))
          .toDart;
      for (final JSAny? item in list.toDart) {
        if (item == null) {
          continue;
        }
        final JSObject raw = item as JSObject;
        final String? groupId = _readString(raw, 'groupId');
        if (groupId == null) {
          continue;
        }
        // 整张成员已读表只取自己那条，别人的阅读状态不展示也不使用。
        final JSAny? table = raw.getProperty<JSAny?>('memberIdToReadDate'.toJS);
        final JSAny? mine =
            table == null || table.isUndefinedOrNull ? null : (table as JSObject).getProperty<JSAny?>('$myAccountId'.toJS);
        out['room:$groupId'] = _dateFromJs(mine);
      }
    }
    return out;
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
