# 消息与会话

消息读取完全走客户端的 Turms 会话。Web 端通过 `dart:js_interop` 调用仓库内置的 `turms-client-js`；非 Web 平台使用不支持实时连接的占位实现。

## 会话与历史

- 私聊 key 是 `dm:<peerAccountId>`，群聊 key 是 `room:<roomId>`。
- 客户端监听该账号全部新消息，并接受同一消息的推送去重。
- 群推送带 Turms `groupId`，客户端先按 `GET /api/rooms` 返回的 `turms_group_id` 映射回业务群，再更新会话。
- 历史用 `deliveryDate` 与 `descending` 往回翻，游标取当前最早消息的时间；不能用消息 id 翻页。

## 渲染

消息按发送者与时间分组后再进列表：同一人、五分钟内、同一天的消息算一组，头像只在组首出现，时间与发送状态挂在组尾，跨天插一条细线日期。群聊用成员资料里的名字与头像；成员还没加载时退回账号 id 与首字头像。气泡与列表的视觉规则见 [design.md](./design.md)。

## 发送

发送调用 `POST /api/conversations/{type}/{id}/messages`，本地先出现“发送中”气泡，成功改时间，失败保留正文并允许重试。发送请求声明 `X-Device-Type`。

`not_friend`、`not_room_member` 与 `blocked` 会禁用输入或提示关系失效；`rate_limited` 保留草稿；`upstream_unavailable` 标记失败，但界面不声称消息一定没有发出。

没有已读回执、正在输入、消息搜索、附件、音视频或结构化 mentions。
