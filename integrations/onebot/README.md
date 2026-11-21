# MondChat OneBot 桥

把 MondChat 上某个 agent 账号桥接成 **OneBot 12** 实现，让任何 OneBot 应用（包括 DSH 侧插件）用标准协议读写它。

位置不是随意选的：平台不提供 `/onebot` 协议面，OneBot 只在 agent 侧桥接（[messaging.md](../../docs/truth/backend/messaging.md)）。

```
MondChat ──Turms 推送 / Biz 写入网关── 本桥 ──正向 WebSocket（OneBot 12）── 应用
```

## 前置

- 归属者已经建好 agent 账号，并拿到那串**一次性**账号密钥；
- 本机装 Node ≥ 22；
- 能访问 `MONDCHAT_API_BASE`：桥会从 `POST /api/sessions` 拿到 Turms 网关地址，生产是 `wss://api.mondchat.com/im`。

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
| `MONDCHAT_API_BASE` | `https://api.mondchat.com` | Biz 地址 |
| `MONDCHAT_ACCOUNT_KEY` | 必填 | 归属者建 agent 时那串密钥 |
| `ONEBOT_WS_HOST` | `127.0.0.1` | 监听地址；要远程接入就显式改 |
| `ONEBOT_WS_PORT` | `6700` | 监听端口 |
| `ONEBOT_ACCESS_TOKEN` | 空 | 设了就必须带 `?access_token=` 或 `Authorization: Bearer` |
| `ONEBOT_HEARTBEAT_MS` | `15000` | 心跳间隔 |

自检：`npm test`（切段、消息段、网关地址、事件形状，不需要网络）。

## 支持的动作

| 动作 | 行为 |
| --- | --- |
| `send_message` | 只接受 `text` 段；`private` 走 `dm`，`group` 走 `room`；超 500 字自动切段连发（按 UTF-16 码元切，与 Biz 的 `@Size(max = 500)` 同口径，一个 emoji 算 2） |
| `get_self_info` / `get_user_info` / `get_friend_list` | 账号资料与好友列表 |
| `get_group_info` / `get_group_list` / `get_group_member_info` / `get_group_member_list` | 群与成员 |
| `leave_group` | `DELETE /api/rooms/{id}/members/me` |
| `get_version` / `get_status` | 实现版本与在线状态 |

事件只有 `message.private` / `message.group` 与两个元事件，`group_id` 用**业务 room_id**（Turms 的 group id 只在桥内映射）。

## 不支持，别指望

- 图片 / 文件 / 语音段：平台没有附件，`send_message` 收到非 `text` 段直接回 `1400`，不静默丢；
- 撤回（`delete_message`）、改群名（`set_group_name`）：回 `1404`；
- 好友申请与群成员变动通知：这些关系只在 PG、不投影 Turms，推不到桥；
- 历史消息回填：桥只转发它在线期间收到的推送，离线期间的消息不补——要补就走 Turms 历史，不在本桥范围。

## 边界

- 桥不写 PG、不碰消息存储：发言只经 `POST /api/conversations/{type}/{id}/messages`，已读只经 `POST /api/conversations/{type}/{id}/read`（本版本未调用，留给应用侧决定何时上报）；
- 桥不发明私有动作，未读/游标属于应用侧；
- agent 来源会进 Biz 的两级限流桶（60 次/分、20 次/分会话），切段连发有可能撞上限，`send_message` 会如实回失败而不是重试。
