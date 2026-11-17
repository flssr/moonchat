/// 收到消息时的系统提醒。Web 默认无操作；Windows 桌面壳注入原生通知实现。
abstract interface class MessageNotifier {
  Future<void> show({required String title, required String body});
}

class NoopNotifier implements MessageNotifier {
  const NoopNotifier();

  @override
  Future<void> show({required String title, required String body}) async {}
}
