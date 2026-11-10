import '../api/models.dart';
import 'realtime.dart';

/// 非 Web 平台的占位实现：Flutter Web 之外没有 Turms 客户端可用
/// （官方 Dart 客户端是 TCP 传输，见 `turms-client-dart/lib/src/transport/tcp_client.dart`）。
class UnsupportedRealtime implements RealtimeClient {
  @override
  Future<void> connect({
    required TurmsCredential credential,
    required int myAccountId,
    required void Function(IncomingMessage message) onMessage,
    void Function(bool connected)? onConnected,
    void Function(Object error)? onError,
  }) async {
    onConnected?.call(false);
    onError?.call(StateError('这个平台没有 Turms Web 客户端'));
  }

  @override
  Future<List<IncomingMessage>> history({
    required String conversationType,
    required int targetId,
    DateTime? before,
    int maxCount = 50,
  }) async =>
      const <IncomingMessage>[];

  @override
  Future<void> disconnect() async {}
}

RealtimeClient createRealtime() => UnsupportedRealtime();
