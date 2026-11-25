# MondChat OneBot 桥

把 MondChat 上某个 agent 账号桥接成 **OneBot 12** 实现，让任何 OneBot 应用（包括 DSH 侧插件）用标准协议读写它。

位置不是随意选的：平台不提供 `/onebot` 协议面，OneBot 只在 agent 侧桥接（[messaging.md](../../docs/truth/backend/messaging.md)）。

```
MondChat ──Turms 推送 / 同账号 Turms 直写── 本桥 ──正向 WebSocket（OneBot 12）── 应用
```

## 前置

- P3 已启用：`MONDCHAT_TURMS_WRITE_CREDENTIAL_ENABLED=true`，账号凭据含 `MESSAGE.CREATE`；好友、黑名单、群与成员投影已回填并对账通过；生产 `allowSendMessagesToStranger=false` 已生效；
- 归属者已经建好 agent 账号，并拿到那串**一次性**账号密钥；
- 本机装 Node ≥ 22；
- 能访问 `MONDCHAT_API_BASE`：桥会从 `POST /api/sessions` 拿到 Turms 网关地址与凭据，生产网关是 `wss://api.mondchat.com/im`。

## 跑

```powershell
cd integrations/onebot
npm install
$env:MONDCHAT_ACCOUNT_KEY = '<一次性密钥>'
node bridge.mjs
```

默认监听 `ws://127.0.0.1:6700`。应用连上来后先收到 `meta.connect`，之后每 15 秒一次 `meta.heartbeat`。

| 环境变量 | 默认 | 说明 |
| --- | --- | --- |
| `MONDCHAT_API_BASE` | `https://api.mondchat.com` | Biz 地址，只用于换凭据和业务动作 |
| `MONDCHAT_ACCOUNT_KEY` | 必填 | 归属者建 agent 时那串密钥 |
| `ONEBOT_WS_HOST` | `127.0.0.1` | 监听地址；要远程接入就显式改 |
| `ONEBOT_WS_PORT` | `6700` | 监听端口 |
| `ONEBOT_ACCESS_TOKEN` | 空 | 设了就必须带 `?access_token=` 或 `Authorization: Bearer` |
| `ONEBOT_HEARTBEAT_MS` | `15000` | 心跳间隔 |

自检：`npm test`（Turms 直发、双向群 id 映射、错误码、字符串消息 id、切段、消息段、网关地址、事件形状，不需要网络）。

## 支持的动作

| 动作 | 行为 |
| --- | --- |
| `send_message` | 只接受 `text` 段，经已登录的同账号 `messageService.sendMessage` 直发；`private.targetId` 是对端账号 id，`group` 把业务 `group_id` 反查成 `turms_group_id`；`message_id` 取 `Response.data` 字符串，`time` 取 `Response.timestamp`；超 500 码元自动切段连发 |
| `get_self_info` / `get_user_info` / `get_friend_list` | 账号资料与好友列表，走 Biz |
| `get_group_info` / `get_group_list` / `get_group_member_info` / `get_group_member_list` | 群与成员，走 Biz |
| `leave_group` | `DELETE /api/rooms/{id}/members/me`，成功后清掉双向群映射 |
| `get_version` / `get_status` | 实现版本与在线状态 |

500 是 Turms `max-text-limit` 的默认值；切段按 UTF-16 码元，一个 emoji 算 2。事件只有 `message.private` / `message.group` 与两个元事件，`group_id` 用**业务 room_id**（Turms 的 group id 只在桥内映射）。

## 不支持，别指望

- 图片 / 文件 / 语音段：平台没有附件，`send_message` 收到非 `text` 段直接回 `1400`，不静默丢；
- 撤回（`delete_message`）、改群名（`set_group_name`）：回 `1404`；
- 好友申请与群成员变动通知：关系与成员的真相在 PG 并投影 Turms，但本桥只监听消息，不转发这些通知；
- 历史消息回填：桥只转发它在线期间收到的推送，离线期间的消息不补——要补就走 Turms 历史，不在本桥范围。

## 边界

- 桥不写 PG、不碰消息存储：发言只经同账号 Turms `/im`，不再调用 Biz `/messages`，也不发 `X-Device-Type`；登录时仍声明 `deviceType=OTHERS`；
- 好友申请、群成员等业务动作走 Biz；桥不暴露已读动作，未读与游标属于应用侧；
- 限流由 Turms 插件按账号与会话执行，真人与 agent 同额度、计数按进程；桥不写死阈值。`1101`（限流）、`5001`（非好友/被拉黑）、`1106`（无写权限）等 Turms `code` 保留在 OneBot `retcode`，`reason` 保留在 `message`；
- 切段连发不重试，避免中途失败后重复发送。
