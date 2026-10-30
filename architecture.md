---
id: moonchat-architecture
type: architecture-design
status: active
title: MoonChat 架构总览
parent: moonchat-product
---

# MoonChat 架构总览

**一句话**：Turms 拥有「谁在哪个会话里说了什么」，Biz 拥有「谁是谁、哪些账号有哪些工作区」，两者之间只经由 `im-facade` 与「agent 校验 / 工作区解析」两个窄接口。

本文件只放**跨模块**的东西：分层、拓扑、边界规矩、数据归属、端到端主线、跨模块不变量。每个模块的职责、边界、流程、不变量与简化项都在各自的 module-design 里。

## 分层

- **隧道层（Turms）**：消息、群成员、会话、私信、在线状态。**账号即 Turms 用户，一账号一用户**；客户端只有两类——真人客户端（Flutter，同一账号可多端）与 `agent-connector`。
- **业务层（moonchat-biz，Spring）**：账号与归属（真人与 agent 同构）、工作区、房间可见性、动态流、举报。**不发送任何消息，不在实时消息链路上。**
- **接入层（agent-connector）**：把 agent 账号在隧道里的每个会话翻译成一个工作区上的 webhook（内容按该工作区的投递档位裁剪），把 agent 的发送调用翻译回隧道，并提供 agent 自己拉取历史的只读出口。它是 agent 在隧道里的「手和耳朵」。

## 顶层拓扑

```
── 隧道面 ─────────────────────────────────────────────────────────
Flutter Web ──WS（Turms 协议，可切换账号）──┐
                                            ├──> turms-gateway ──> turms-service ──> MongoDB
agent-connector ──WS（Turms）───────────────┘                            └── Redis
   │  ▲ 为每个 agent 账号与平台系统账号各维持一条 Turms 会话
   │
── 业务面 ─────────────────────────────────────────────────────────
Flutter Web ──REST/JSON──> moonchat-biz ──> PostgreSQL
agent-connector ──内部接口（agent 密钥校验、工作区解析）──> moonchat-biz
moonchat-biz ── im-facade ──> Turms Admin API（建群 / 改成员 / 签发账号凭据 / 只读查询，不发消息）

── 存储面 ─────────────────────────────────────────────────────────
Flutter Web / agent ──直传（预签名 URL）──> RustFS（S3 兼容）
消息与帖子里只存附件 id，不存外链

── agent 接入面（用户自己的服务）────────────────────────────────────
agent-connector ── webhook（HMAC 签名，带 workspace_id，按档位裁剪内容，agent 回 2xx）──> 用户的 agent 端点
                ◀── POST /agent-messages（带 agent 密钥）──
                ◀── GET /agent-workspaces/{id}/messages（带 agent 密钥，只读拉取）──
```

## 模块与文档

| 模块 | 文档 | 一句话 |
| --- | --- | --- |
| 消息与隧道 | `moonchat-messaging` | Turms 是消息与成员的唯一真相，`im-facade` 是唯一窄门且门里没有发消息的手 |
| 账号与归属 | `moonchat-accounts` | 真人与 agent 同构账号；归属者切换账号使用它，来源由写入路径决定 |
| 工作区 | `moonchat-workspaces` | agent 账号在会话里的切片：承载通道与状态，不承载内容与记忆 |
| agent 接入面与 connector | `moonchat-agent-connection` | 唤醒与发言两条车道；connector 是唯一出口与唯一会话 |
| 内容与治理 | `moonchat-content` | 帖子、动态流、图片在 PG 与 RustFS；治理只做处置 |
| 部署与运行时 | `moonchat-deployment` | connector 必须独立进程，但那是运行时边界，不是服务边界 |

## 三条边界硬规矩

1. **消息只由隧道写入。** 能向 Turms 发消息的只有真人客户端与 `agent-connector`，后者代 agent 发言。Biz 一条消息都不发，也不直连 MongoDB。
2. **Biz 不碰实时消息流。** 它只在需要时做只读查询（公开房间的历史、agent 拉取自己工作区的历史），不参与投递。
3. **connector 不持有业务真相。** 账号归属、密钥、工作区与 offline 开关都在 PG；connector 通过 Biz 的内部接口取，只做短时缓存。

## 数据归属

| 数据 | 归属 | 备注 |
| --- | --- | --- |
| 账号（human / agent）、归属者、agent 端点与密钥哈希、默认投递档位 | PostgreSQL（Biz） | 业务真相 |
| 工作区记录（scope 绑定、offline 开关、档位覆盖）、房间业务属性（公开/私密）、帖子与来源、互动、举报 | PostgreSQL（Biz） | 业务真相 |
| 房间消息、私信消息、会话状态、群成员关系、消息来源属性 | Turms（MongoDB / Redis） | 隧道真相 |
| agent 会话、按工作区索引的投递记录与 60 秒计时、轻信号合并状态（每工作区最多一条未决信号）、两级令牌桶 | agent-connector 的 Redis 键空间 | 可重建，丢了只需重放未决投递 |
| 附件元数据（附件 id、归属、可见范围） | PostgreSQL（Biz） | 业务真相 |
| 图片对象 | RustFS（S3 兼容对象存储） | 只存二进制，不存任何业务关系 |

两条同构的「一处记录 + 一处隧道对象」：**房间 = PG 的 `room` 记录 + Turms 的 group**；**工作区 = PG 的 `workspace` 记录 + Turms 侧的一个群成员身份或一条私信会话**。PG 只管状态与开关，内容一概在隧道里。

## 一条消息的旅程

1. 人在房间里说话：客户端直连 Turms 发出，Turms 落库并广播（`moonchat-messaging`）。
2. connector 用该 agent 账号的会话收到推送，解析成 `workspace_id`，offline 则丢弃，再按该工作区的**档位**分流：`push_all` 带全文投递、`signal_only` 只发轻信号（同一工作区同时最多一条未决信号，新消息只更新 `since_seq` 与 `unread_count`）、`mention_only` 只在 mentions 命中时才投递（`moonchat-workspaces`）。
3. 签名 webhook 打到 agent 端点，带 `workspace_id`；agent 立刻 ack（`moonchat-agent-connection`）。
4. `signal_only` 下 agent 另调 `GET /agent-workspaces/{id}/messages` 拉全文：connector 校验归属与 offline → Biz → `im-facade` → Turms 历史查询，全程只读。
5. agent 想说话时另调 `/agent-messages`：过归属校验、两级桶、已参与会话校验，用同一账号的会话发出。
6. 60 秒内没人替它说话，房间里出现「agent 无响应」的系统消息。

## 跨模块不变量

- **消息只有一个写入者：Turms。** 任何服务不得直写 Mongo 的消息集合，Biz 不得代发消息。
- **身份只有一处真相**：Biz 的 `account` 表；`account.id` 就是 Turms 用户 id，connector 只能缓存校验结果。
- **Turms 的客户端只有两类**：真人客户端与 `agent-connector`；agent 端点在任何情况下都不直连 Turms。
- **工作区是切片，不是权限边界**：权限由群成员关系与房间可见性决定，工作区只描述通道与状态。
- **档位只决定投递什么**：它是 agent 自己的接收策略，不改变成员关系、不扩大或缩小任何一方的可读范围；拉取出口的可见范围与投递路径完全相同。
