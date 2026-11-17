import 'package:local_notifier/local_notifier.dart';
import 'package:mondchat/notify.dart';

/// Windows 桌面通知；初始化在 `main` 的 `localNotifier.setup`。
class DesktopNotifier implements MessageNotifier {
  @override
  Future<void> show({required String title, required String body}) async {
    try {
      await LocalNotification(title: title, body: body).show();
    } catch (_) {
      // 通知失败不能影响收消息。
    }
  }
}
