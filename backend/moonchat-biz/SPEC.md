---
id: moonchat-biz
type: module-design
status: active
title: 业务层 moonchat-biz
parent: moonchat-architecture
depends-on:
  - moonchat-architecture
---

# 业务层 moonchat-biz

**一句话**：Biz 是唯一的业务进程——账号、好友、群与成员的真相在它的 PG 里，发言只经它的写入网关代发；它同步校验，不做投递。

> 领域行为与流程在 [`../../docs/DDD.md`](../../docs/DDD.md)；表结构在 [`../../docs/data-model.md`](../../docs/data-model.md)；路由与字段在 [`../../docs/api-contracts.md`](../../docs/api-contracts.md)。本文只记模块边界与不可让渡的决定。

## 职责

- **账号与资料**：注册、登录、agent 账号、改名、资料页、登录 JWT 的签与续期。
- **好友**：申请、同意、拒绝、删除；好友关系是私聊授权的唯一事实。
- **群与成员**：建群、拉人、退群、移除；群主只有一位，不能转让或解散。
- **凭据签发**：两套入口（登录 JWT / 账号密钥）换同一份 Turms 凭据，经 `im-facade` 签发。
- **写入网关**：发言的归属校验、授权判定、限流与来源标记，再交给 `im-facade` 代发。
- **投影**：PG 写成功后经 `im-facade` 把群与成员投影进 Turms；失败留 `pending`，由 30 秒重放器收敛。

## 边界

- **只做同步校验，不做投递**：不参与消息投递，不订阅消息事件，不做计数 / 通知 / 审计。
- **唯一的写入口**：所有发言经 `POST /api/conversations/{type}/{id}/messages`；Biz 不提供第二条写入通道，也不直写 Mongo 的消息集合。
- **`im-facade` 只有一支发送的手**：只有写入网关能调它代发，且必须带 Biz 已认证的 `senderId`；`im-facade` 自己不做归属判断。
- **凭据的边界**：Turms Admin 的 `MESSAGE_CREATE` 权限只在 Biz 里持有；客户端凭据只授 `QUERY`。两者都由 Biz 签发，没有第三个签发点。
- **业务真相只在 PG**：Turms 的 group / member 只是投影，任何业务判断都回 PG 查。

## 账号与归属（决定）

- 一张 `account` 表，`type ∈ {human, agent}`；agent 账号的归属者唯一、不可转移。**归属关系本身就是授权**，没有授权表，也没有临时凭据。
- **`account.id` 由 Biz 生成，就是 Turms 用户 id**：先写 PG，再在同一事务内经 `im-facade` 用这个 id 建 Turms 用户；Turms 失败就整笔回滚，不留孤儿账号。起始 id 避开 Turms 已有号段，写在迁移里。
- **两种凭据**：登录 JWT 7 天（滑动续期）；Turms 凭据 12 小时（到期前重调 `POST /api/sessions`）。后者是 Biz 签的 JWT，`statements` 只授 `QUERY`。
- **账号密钥**：UUIDv4 明文只在创建时返回一次；PG 只存 `hmac-sha256$` + HMAC-SHA256(pepper, 明文)，pepper 来自 `moonchat.agent.key-pepper`（无默认值）。
- **来源由入口凭据决定**：登录 JWT → `owner`，账号密钥 → `agent`；只进日志与限流，不作权限判定。

## 好友（决定）

- 好友是私聊的充分必要条件，落在 PG 的 `friendship` + `friendship_reverse`（同事务双写）。**不投影进 Turms**，Turms 配成不校验好友（`allowSendMessagesToStranger = true`）。
- 无向关系用规范序（小 id 在前）+ 唯一键表达；接口只用 `peer_account_id` 寻址。
- **删除好友写 tombstone**：会话保留、历史只读、不能再发新消息；保留期后 purge，重新加好友复用原行。拒绝申请同样写 `deleted_at`，状态枚举不增加 `rejected`。
- **agent 只有好友申请一个关系动作**；建群、拉人、移除成员只有真人能触发（`owner` 来源）。
- **不做临时会话**：群里的非好友只能看资料页再申请好友；理由是两级桶按 `(账号, 会话)` 计，临时会话会让桶形同虚设。

## 群与投影（决定）

- 群与成员的真相在 PG（`room_info` / `room_member` / `account_room`）；Turms 只保留投递必需的投影：群 id、名字、所有者、成员集合。
- **投影在事务提交之后**，以 PG 为准做 full reconcile（集合对齐），不做事件流与增量补丁；失败不回滚业务写，`turms_sync_state` 留 `pending`，30 秒重放器按 PG 重算（间隔 `moonchat.turms.replay-interval`，**未确认**）。
- **`turms_group_id` 由 Turms 生成后回填**；对外标识始终是 `room_info.id`。
- **只有一种可见性**：`GroupType` 配成邀请制、成员可见、guest 不可发言。客户端建不了 group（JWT 不授 `GROUP` 的 CREATE）。
- **群主不能退群**，`owner_account_id` 必须常驻；V1 没有转让与解散。

## 写入网关

固定顺序，每一步都不能省：

1. **认证**：登录 JWT 或账号密钥；来源由凭据形态决定。
2. **归属**：凭据能不能代表这个账号。
3. **会话解析**：`room` 是 `room_info.id`，`dm` 是对端 `account_id`。
4. **授权事实**：群看 `room_member`，私聊看 `friendship`（`accepted` 且未删除）。
5. **限流**：只有 `agent` 来源进「账号 → 会话」两级桶；先校验再进桶，`429` 不盖住 `404` / `409`，被拒的请求不消耗配额。
6. **来源标记**：写结构化日志，不写进消息。
7. **代发**：`im-facade` 调 Turms Admin API `POST /messages`，带已认证的 `senderId`。

- **消息 id 由网关生成**后随代发提交：Admin 不回传 id；它单调递增但不连续，**不是分页游标**——客户端翻历史用 `deliveryDate`。
- **PG 零写入**；`503` 只表示没拿到 Turms 的确认，Turms 可能已落库，重试可能重复，不做幂等。
- **速率是暂定值**：账号级 `moonchat.limit.account-per-minute`（60）、会话级 `moonchat.limit.conversation-per-minute`（20），写配置不硬编码。

## 数据

七张表、聚合边界、DDL、只能由应用层守的规则、明确不建的表，全部在 [`../../docs/data-model.md`](../../docs/data-model.md)。本模块只记一条：**群、好友、账号都不为 Turms 的投影再建第二张表**。

## 接口面

20 条 `/api/*` 路由的路径、认证、字段、错误码与读写表在 [`../../docs/api-contracts.md`](../../docs/api-contracts.md)。**接口面不提供**：读消息与投递、消息搜索、头像上传、搜人与 agent 目录、拉黑举报封禁、临时会话、解散群与群主转让、删账号、agent 版的建设性动作（建群 / 拉人 / 移除）。

## 依赖

pom 只服务四件事：PG、Redis、凭据的签与验、Turms Admin 的 HTTP 调用。版本来源只有两处：Spring Boot BOM（4.1.2），或父 pom 里自钉的三个版本——MyBatis-Plus 3.5.18、springdoc 3.2.0、nimbus-jose-jwt 10.10。

| 依赖 | 用在哪 |
| --- | --- |
| `spring-boot-starter-webmvc`、`-validation`、`-actuator` | 20 条路由、入口校验、健康检查 |
| `spring-boot-starter-flyway` + `flyway-database-postgresql` + `postgresql` | 七张表的迁移与业务真相 |
| `mybatis-plus-spring-boot4-starter` | 七张表读写、聚合事务、群成员分页 |
| `spring-boot-starter-data-redis` | 两级限流桶（键前缀与 Turms 隔离） |
| `nimbus-jose-jwt` | 登录 JWT 与 Turms 凭据的签与验 |
| `spring-security-crypto` | 只取 `BCryptPasswordEncoder`，不引入过滤器链 |
| `springdoc-openapi-starter-webmvc-api` | `/v3/api-docs` → `docs/openapi.json`（给 Apifox 导入），不是第二份手写契约 |
| `lombok`（provided，产物里排除） | 只消模板代码；`credential_hash` 标 `@ToString.Exclude` |

**明确不加**：`spring-boot-starter-security`（认证自己实现）、`jjwt`（Jackson 2 与 Boot 4 的 Jackson 3 并存）、任何 Turms 客户端（Biz 只打 Admin REST，不连 `/im`）、MongoDB 驱动（消息在 Turms）、`spring-boot-starter-restclient`（`RestClient` 已在 spring-web）、消息队列与 `spring-retry`（没有投递队列与重试语义）。

**加依赖的判断顺序**：它服务哪份 spec 的哪句话 → Boot BOM 管不管版本 → 能否被已有 starter 传递带入 → 只为用一个类就降级到单模块。Lombok 是唯一例外（纯模板代码，provided、不进产物）。

## 已知缺口

- **两级限流桶的速率仍是暂定值**（60 / 20），等真实流量再调。
- **重放间隔 30 秒没有实测依据**（`moonchat.turms.replay-interval`）。
- **`turms-service` 默认缓存会话状态 60 秒**：登录后立即走写入网关的路径仍需在真实部署复测（[`../../docs/DDD.md`](../../docs/DDD.md)「要核对的 7 条」）。
- **客户端界面规则没有 spec**：`frontend/SPEC.md` 只记边界，页面与交互仍未描述。
