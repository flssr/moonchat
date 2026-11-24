# 系统架构

PostgreSQL 是业务真相，Turms 是消息引擎。目标形态是 **Biz = 控制面**（账号、关系、群、资料、凭据签发、PG → Turms 投影与对账），**Turms = 数据面**（消息、会话、已读、撤回、投递）；客户端与 agent 用各自的 Turms 会话直写，授权由 Turms 按投影判定。

**当前阶段（P3 客户端直写已上线，P4 未做）**：投影已启用并回填，限流插件已挂载；`POST /api/sessions` 在 `MONDCHAT_TURMS_WRITE_CREDENTIAL_ENABLED=true` 下签发写权限，客户端与 agent 经各自 Turms `/im` 直写消息、已读与撤回；生产 `allowSendMessagesToStranger=false` 已生效，好友/拉黑由 Turms 按投影判定。Biz 的 REST 写路径只留给未升级的旧客户端，P4 再删（issue #63）。

## 分层与数据归属

| 层 | 负责 | 不负责 |
| --- | --- | --- |
| Turms | 消息、会话、已读、撤回、投递、在线状态；账号、关系、群与成员的可重建投影 | 业务授权真相 |
| `mondchat-biz` | 账号、关系、群、凭据签发、PG → Turms 投影与对账；P4 前保留 REST 写路径给旧客户端 | 消息投递、消息事件消费、客户端读取代理 |
| Flutter Web | 登录、关系动作、消息与已读（直写 Turms） | 权限判定、消息存储 |
| agent 端点 | 持该账号的 Turms 会话并自行筛消息；业务动作走同一套 REST，消息与已读走同一个 Turms `/im` | 专用转发层或平台侧会话托管 |

| 数据 | 真相位置 |
| --- | --- |
| 账号、归属、资料、认证哈希 | PG `account` / `account_info` |
| 好友申请与好友关系 | PG `friendship` / `friendship_reverse` |
| 群、成员与账号侧群列表 | PG `room_info` / `room_member` / `account_room` |
| 黑名单 | PG `blocklist` |
| 消息、会话、已读、在线状态 | Turms 的 MongoDB / Redis |
| 限流计数 | 客户端直写由 Turms 插件进程内计数；Biz 的 Redis 限流只管旧 REST 路径 |
| 投影事件（outbox） | PG `domain_event`，只由 Biz 写，可清空 |
| 来源与限流日志 | Biz 结构化日志，不建审计表 |

## 不变量

- **消息唯一写入者是 Turms**。当前入口是客户端的 Turms `/im`；Biz 的 `POST /api/conversations/.../messages` 只留给未升级的旧客户端，P4 删除。任何服务不得直写 Mongo。
- **授权真在 PG，执行在 Turms**。Turms 用投影后的好友、黑名单与群成员判定（`allowSendMessagesToStranger=false` 已在生产生效）；旧客户端的 Biz REST 路径仍按 PG 判定。
- **客户端 Turms 权限按阶段**：`mondchat.turms.write-credential-enabled=true` 时正常账号含 `MESSAGE.CREATE/UPDATE` 与 `CONVERSATION.UPDATE`，冻结账号只保留 `QUERY` 与 `CONVERSATION.UPDATE`（能清角标、发不出消息）。statements 写错不是静默降权，签发侧会直接抛错。翻 `allowSendMessagesToStranger=false` 不影响走 Biz 的旧客户端：Admin `POST /messages` 直接进 `saveMessage`，不经过好友校验那条 `authAndSaveMessage`。
- 群与成员只从 PG 单向投影到 Turms，失败不回滚业务写，由派发器与对账收敛。
- 账号、好友与黑名单也单向投影进 Turms 读模型；投影只写 Turms、永不反写 PG。规则见[投影](./backend/projection.md)。
- Turms 中没有 PG 记录的群不进入平台业务视图。
- 所有读取按 Turms 的会话和成员可见范围；关系判定读 Turms 投影（旧客户端走 Biz REST 时读 PG）。

## 消息主线

当前（客户端直写）：

1. 客户端经已有 WebSocket 发 `createMessageRequest`，gateway 校验 JWT statements。
2. Turms 按投影后的好友、黑名单与群成员判定，失败回 `5001`（非好友；被拉黑时 `stranger=false` 压成同码）或 `5009`（游客不能发言）等码。
3. service 落库并向在线端投递，Biz 不在链路上。
4. 已读与撤回同样走 `CONVERSATION.UPDATE` / `MESSAGE.UPDATE`，Biz 不在链路上。

旧客户端（Biz 代发，P4 删除）：

1. 客户端调用 `POST /api/conversations/{type}/{id}/messages`。
2. Biz 依次校验凭据、会话、授权、黑名单与限流。
3. Biz 生成消息 id，经 Turms Admin API 带 `senderId` 代发（跳过 Turms 的好友与拉黑判定）。
4. Turms 落库并向在线端投递。
5. 客户端读取与历史分页直接走 Turms，不经过 Biz。

## 部署

只有 `mondchat-biz` 一个业务进程。容量不足时先增加无状态副本；只有负载形态、发布窗口或故障域真正分叉时才考虑拆进程。Turms 侧限流插件已启用，计数按进程，多实例时实际额度为 `实例数 × 每分钟额度`。

精确字段以代码、迁移、测试和运行时 OpenAPI 为准；运行时 `/v3/api-docs` 的落盘副本是 [`docs/openapi.json`](../openapi.json)。模块入口见 [后端](./backend/README.md) 与 [前端](./frontend/README.md)。
