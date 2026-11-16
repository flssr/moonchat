/// 本机会话缓存：退出时把各会话最后一段消息和当前会话存下来，重登先显示上次的内容。
///
/// Web 默认不落盘（刷新本来就重新拉历史）；Windows 桌面壳注入文件实现。
abstract interface class MessageCacheStore {
  Map<String, dynamic>? load(int accountId);
  void save(int accountId, Map<String, dynamic> data);
}

class NoopMessageCacheStore implements MessageCacheStore {
  const NoopMessageCacheStore();

  @override
  Map<String, dynamic>? load(int accountId) => null;

  @override
  void save(int accountId, Map<String, dynamic> data) {}
}
