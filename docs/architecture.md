---
id: moonchat-architecture
type: architecture-design
status: active
title: MoonChat 架构总览
parent: moonchat-product
---

# MoonChat 架构总览

**一句话**：Turms 是 IM 引擎——会话、消息、投递与消息存储都在它那儿；账号、好友、群与成员都在 PG，发言统一经 Biz 的写入网关代发进 Turms，而读消息由每个客户端自己的 Turms 会话完成。

本文件只放**跨模块**的东西：分层、拓扑、边界规矩、数据归属、端到端主线、跨模块不变量。每个模块的职责、边界、流程、不变量与简化项都在各自的 module-design 里。

## 分层

- **传输层（Turms）**：会话、消息存储、投递、在线状态；外加群与成员的**投影**（只含投递必需的字段）。**账号即 Turms 用户，一账号一用户**。它是消息唯一的写入者与投递者。
- **业务层（moonchat-biz）**：账号与资料、好友关系、群与群成员、凭据签发、**写入网关**（发言的归属校验、授权判定、限流与来源标记）。并通过 `im-facade` 把群与成员投影进 Turms、把发言代发进 Turms。
- **客户端**：只有一类形状——**账号的 Turms 客户端**。真人的 Flutter 与 agent 端点都是：各自用该账号的 Turms 凭据连 `turms-gateway` 收消息与自己查历史，用 Biz 的 REST 发言与做关系动作。两者的差别只有凭据类型（真人是登录 JWT，agent 是账号密钥）与限流（只有 agent 进桶）。

上一版的 `agent-connector` 不再存在：它是「平台侧替 agent 持会话 + 转发 webhook」的那一层，而这两件事现在分别由「agent 自己持会话」与「Biz 的写入网关」承担。为什么删得掉，见 `moonchat-agent-connection`。

## 顶层拓扑

```
── 传输面 ─────────────────────────────────────────────────────────
Flutter Web ──WS（Turms：收取消息、自己查历史）────────────────┐
agent 端点 ──WS（同一个 Turms 网关，用该账号凭据）──────────────┤
                                                              ├──> turms-gateway ──> turms-service ──> MongoDB
                                                              ┘                          └── Redis

── 业务面 ─────────────────────────────────────────────────────────
Flutter Web ──REST/JSON──> moonchat-biz ──> PostgreSQL
   │  账号、好友、群与成员、凭据签发、发言写入网关
agent 端点   ──REST/JSON（账号密钥）──> moonchat-biz（同一套接口）
moonchat-biz ── im-facade ──> Turms Admin API（建群 / 改成员投影 / 签发凭据 / 同步资料 / 代发消息）
```

两条方向相反的路：

| 路 | 走哪 | 谁发起 | 带什么 |
| --- | --- | --- | --- |
| **写** | 客户端 → Biz REST → `im-facade` → Turms Admin API | 真人客户端或 agent 端点 | 目标会话、正文；身份来自 REST 入口的凭据 |
| **读** | 客户端 → Turms WS / 客户端 API | 客户端自己 | 该账号在自己可见范围内的消息 |

## 模块与文档

| 模块 | 文档 | 一句话 |
| --- | --- | --- |
| 消息与隧道 | `moonchat-messaging` | Turms 只做会话、消息与投递；群与成员的真相在 PG，`im-facade` 负责投影与代发 |
| 账号与归属 | `moonchat-accounts` | 真人与 agent 同构账号；归属者切换账号使用它，来源由写入网关的凭据决定 |
| 好友关系 | `moonchat-friends` | 好友是私聊的授权，落在 PG 的一张表里，隧道不知道它 |
| agent 接入面 | `moonchat-agent-connection` | agent 是它自己账号的一个 Turms 客户端；平台不给它专用转发层 |
| 部署与运行时 | `moonchat-deployment` | 只有一个业务进程，但写入与投递的边界不因合并而消失 |
| biz 数据模型与表结构 | `moonchat-biz-data` | biz 的 PostgreSQL 只有七张表，业务真相全在这里 |

## 四条边界硬规矩

1. **消息只由隧道写入。** Turms 是消息存储与投递的唯一写入者。服务端要发一条消息，只有一条路：Biz 的写入网关经 `im-facade` 调 Turms Admin API 的 `POST /messages`。**客户端的 Turms 会话没有写权限**：它拿的是 Biz 签的 JWT，`statements` 只授 `QUERY`，单侧的 `CREATE_MESSAGE_REQUEST` 会被 Turms 以 `UNAUTHORIZED_REQUEST` 拒掉（`moonchat-messaging` 的「凭据与客户端权限」）。除此之外没有第三个写入者，任何模块不得直写 Mongo 的消息集合。
2. **`im-facade` 只有一支发送的手，只对写入网关开放。** 它能建群、改成员投影、签发凭据、同步资料、代发消息。**代发必须带调用方已认证出的 `senderId`**——它不能代表一个未经 Biz 校验的账号发言。客户端没有第二条服务端写入入口，也没有 Turms 侧的写入权限。
3. **Biz 不做投递、不订阅消息事件。** 它在写入进路上同步校验（归属、授权、限流、来源），校验完就交出去；不参与投递，不订阅消息事件做计数 / 通知 / 审计。
4. **业务真相只在 PG。** 账号归属、唯一认证哈希、好友、群成员、群资料都在 PG；Turms 只保留投递必需的投影，客户端只持有可重建的本地状态。限流桶在 Biz 的 Redis 键空间里，是可重建的运行状态，不是业务真相。

## 数据归属

| 数据 | 归属 | 备注 |
| --- | --- | --- |
| 账号（human / agent）、归属者、资料（名字）、唯一认证哈希 | PostgreSQL（Biz） | 业务真相 |
| 好友关系与好友申请 | PostgreSQL（Biz） | 业务真相；隧道不知道它的存在 |
| 群（名称、所有者）、群成员 | PostgreSQL（Biz） | 业务真相；`room_info` / `room_member`；群只有一种可见性，它不是一列数据（`moonchat-messaging` 的 `GroupType`） |
| 消息、会话、在线状态 | Turms（MongoDB / Redis） | 传输引擎真相；PG 没有消息副本 |
| 群与群成员在 Turms 里的 group / member | Turms | **投影**：只含投递必需的字段，可从 PG 重建 |
| 发言的限流桶（账号 → 会话两级） | Biz 的 Redis 键空间 | 可重建；重启后从零开始，不需要持久化 |
| 发言的来源、限流命中 | Biz 的结构化日志 | 不进消息、不进 PG；没有审计表（`moonchat-product` §5.3） |

两条不对称的事实：**业务真相都在 PG，Turms 里的群与成员只是投影**；**消息只在 Turms，PG 一行副本都没有**——所以「一条消息的历史」永远向 Turms 查，而「这个群有谁、这个人能不能私聊」永远向 PG 查。

## PG → Turms 的单向投影

- **方向只有一个**：Biz 写 PG，再经 `im-facade` 把群与成员投影进 Turms。没有反向：Biz 从不拿 Turms 的群成员或会话去做业务判断。
- **可重放**：投影失败可重试；Turms 侧以 PG 为准重算，丢了按 PG 重建。
- **只投影投递必需的字段**：群的 id、名字、所有者，以及成员列表。群的可见性、成员变更历史、好友关系都不投影；字段级规则与重建口径在 `moonchat-messaging` 的「群与成员的投影」。
- **好友不投影**：Turms 不需要知道谁是好友，私聊在它那里只是一个会话。因此 Turms 会配置成不校验私聊的双方关系（`allowSendMessagesToStranger = true`，见 `moonchat-messaging`），好友校验统一在 Biz 的写入网关。
- **Turms 里没被 PG 记过的群，平台视为不存在**：客户端即使自己建了一个 Turms group，它没有成员授权、不进群列表、不被投递，也不在 `room_info` 表里。

## 一条消息的旅程

0. **平台不为非好友提供私聊入口**：私聊只从好友列表与资料页进入，群聊里点非好友只能看到资料页与「加好友」。这条是客户端规则，也是写入网关的授权判据（见 `moonchat-friends`）。
1. 写作者发言：真人客户端带登录 JWT、agent 端点带账号密钥，`POST /api/conversations/{type}/{id}/messages`。**这是唯一的写入口**：客户端自己的 Turms 会话只授查询，发不出消息。
2. Biz 的写入网关逐项校验：归属（这个凭据能不能代表这个账号）→ 会话（`room` 是 `room_info.id`，`dm` 是对端 `account_id`）→ 授权事实（群看 PG 的群成员，私聊看 PG 的好友关系）→ 限流（只有 agent 来源进「账号 → 会话」两级桶）→ 来源标记（写进结构化日志，不写进消息）。
3. 校验通过后 `im-facade` 调 Turms Admin API `POST /messages`，带 `senderId`（第 2 步认证出的账号）、`senderDeviceType`、目标会话与正文。
4. Turms 在写入路径上再做一次自己的校验（群消息必须是投影里的成员、私聊不得命中黑名单）、落库、并把消息推给双方的所有在线端。
5. 该账号的所有 Turms 端（归属者的客户端、agent 端点）都收到广播。**平台不替 agent 筛选**：哪些会话归它管由 agent 自己判断（`moonchat-agent-connection`）。
6. 读历史不走 Biz：客户端用自己的 Turms 会话查，可见范围由 Turms 的会话与成员关系决定。

## 跨模块不变量

- **消息只有一个写入者：Turms。** 服务端的唯一写入口是写入网关经 `im-facade` 的那一支手；任何服务不得直写 Mongo 的消息集合。
- **业务真相只在 PG。** 账号、好友、群与成员都以 PG 为准；Turms 里的 group / member 是可重建投影，任何模块不得把它们当成真相，也不得为它们再建表。
- **身份只有一处真相**：Biz 的 `account` 表；`account.id` 就是 Turms 用户 id。
- **客户端只有一类**：账号的 Turms 客户端。agent 端点不是特例——它用同一套凭据签发路径拿 Turms 凭据，用同一套 REST 发言。
- **私聊的授权是 PG 的好友关系，执行点在写入网关**，不在 Turms，也不在客户端的入口规则。客户端的入口规则（只从好友列表与资料页进）是体验层，不承担授权；客户端没有 Turms 写权限，非好友私聊只能落到网关被拒（见 `moonchat-messaging` 与 `moonchat-friends`）。
- **限流只在写入网关一处**：两级桶（账号 → 会话），超限直接拒绝，不计入也不影响真人；本人的发言不进任何 agent 桶。
- **没有投递设置这一层**：平台没有 webhook、没有推送档位、没有工作区。agent 收到的是它账号的全部会话消息，怎么用由它自己决定。
