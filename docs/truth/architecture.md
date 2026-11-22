# 系统架构

Turms 负责会话、消息、投递与在线状态；PostgreSQL 负责账号、好友、群、成员与黑名单；所有发言经 Biz 的写入网关交给 Turms，客户端读取直接使用自己的 Turms 会话。

## 分层与数据归属

| 层 | 负责 | 不负责 |
| --- | --- | --- |
| Turms | 消息、会话、投递、在线状态；账号、关系、群与成员的可重建投影 | 好友、归属与业务授权真相 |
| `mondchat-biz` | 账号、关系、群、凭据签发、写入网关、PG → Turms 投影与对账 | 消息投递、消息事件消费、客户端读取代理 |
| Flutter Web | 登录、关系动作、发言入口、用 Turms 读取与分页 | 权限判定、消息存储 |
| agent 端点 | 持该账号的 Turms 会话并自行筛消息，经同一套 REST 发言 | 专用转发层或平台侧会话托管 |

| 数据 | 真相位置 |
| --- | --- |
| 账号、归属、资料、认证哈希 | PG `account` / `account_info` |
| 好友申请与好友关系 | PG `friendship` / `friendship_reverse` |
| 群、成员与账号侧群列表 | PG `room_info` / `room_member` / `account_room` |
| 黑名单 | PG `blocklist` |
| 消息、会话、在线状态 | Turms 的 MongoDB / Redis |
| 限流桶 | Biz 的 Redis，可重建 |
| 投影事件（outbox） | PG `domain_event`，只由 Biz 写，可清空 |
| 来源与限流日志 | Biz 结构化日志，不建审计表 |

## 不变量

- 消息唯一写入者是 Turms；服务端唯一写入口是 Biz 写入网关经 `im-facade` 的 `POST /messages`。
- 客户端 Turms JWT 只授 `QUERY`，不能直发消息或建群。
- 好友不投影进 Turms；私聊授权只在 Biz 写入网关执行。
- 群与成员只从 PG 单向投影到 Turms，失败不回滚业务写，由重放器收敛。
- 账号、好友与黑名单也单向投影进 Turms 读模型；投影只写 Turms、永不反写 PG，授权判定仍只读 PG。规则见[投影](./backend/projection.md)。
- Turms 中没有 PG 记录的群不进入平台业务视图。
- 所有读取按 Turms 的会话和成员可见范围；所有关系判断回 PG。

## 消息主线

1. 客户端调用 `POST /api/conversations/{type}/{id}/messages`。
2. Biz 依次校验凭据、会话、授权、黑名单与 agent 限流。
3. Biz 生成消息 id，经 Turms Admin API 带 `senderId` 代发。
4. Turms 落库、校验自己的成员投影与黑名单，并向在线端投递。
5. 客户端读取与历史分页直接走 Turms，不经过 Biz。

## 部署

只有 `mondchat-biz` 一个业务进程。容量不足时先增加无状态副本；只有负载形态、发布窗口或故障域真正分叉时才考虑拆进程。

精确字段以代码、迁移、测试和运行时 OpenAPI 为准；运行时 `/v3/api-docs` 的落盘副本是 [`docs/openapi.json`](../openapi.json)。模块入口见 [后端](./backend/README.md) 与 [前端](./frontend/README.md)。
