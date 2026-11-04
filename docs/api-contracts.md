---
id: moonchat-api
type: module-design
status: active
title: Biz 业务接口契约（REST）
parent: moonchat-architecture
depends-on:
  - moonchat-biz-data
  - moonchat-accounts
  - moonchat-friends
  - moonchat-messaging
  - moonchat-agent-connection
---

# Biz 业务接口契约（REST）

**一句话**：Biz 对外只有 20 条 `/api/*` 路由——身份、好友、群与成员、发言；消息的读与投递一条都不在这里。

## 0. 这份文档管什么

| 本文管 | 本文不管 |
| --- | --- |
| 路径、方法、认证、请求与响应字段、错误码、每条接口读写哪张表 | 业务规则从哪来（各 module spec）、表与列的 DDL（`moonchat-biz-data`） |
| 「一个动作只有一条路由」这条纪律 | Turms 客户端 API（收消息、查历史，见 `moonchat-messaging`） |
| 接口面明确不提供什么 | 每个数字的依据（正文里逐个标了来源或「暂定」，汇总在 §10） |

三条纪律：

- **本文不新增业务规则**，只把已定稿的 spec 落成可实施的路由与字段。与 module spec 冲突时以 module spec 为准，并当场改本文。
- **接口里出现的每个字段都要能指回一列或一次投影**（§9 是这张对照表）；指不回去的字段，要么删掉，要么先在表结构或 module spec 里补上。
- **读消息不在 Biz**：消息历史、会话列表、未读数、在线状态一律走客户端自己的 Turms 会话。Biz 不代理、不做可见性判断（`moonchat-messaging` 的「读历史」）。

---

## 1. 总则

### 1.1 路径与命名

- 统一前缀 `/api`，资源用复数小写：`/api/accounts`、`/api/friendships`、`/api/rooms`、`/api/conversations`。
- 动作靠 HTTP 方法表达。只有两处例外，且都有理由：`POST /api/friendships/{peer_account_id}`（同意还是拒绝需要 `action`，见 §5.3）与 `DELETE /api/rooms/{room_id}/members/me`（「我自己」不是账号 id，写成路径尾段比 `?me=true` 直白）。
- **没有版本前缀**：V1 单客户端、单部署，客户端与 Biz 同仓推进。要引入 `/v2` 时先改本文。

### 1.2 认证：一个头，两种凭据

```
Authorization: Bearer <token>
```

| token 形态 | 谁用 | 网关判定 | 来源标记 |
| --- | --- | --- | --- |
| 登录 JWT（三段 base64url，Biz 自签自验，**7 天**） | 真人客户端（含归属者切进 agent 账号） | 验签 + 未过期 | `owner` |
| 账号密钥（agent 创建时拿到的那串明文） | agent 端点 | 算确定性 HMAC-SHA256 后按 `account_info.credential_hash` 反查账号 | `agent` |

- **来源由凭据形态决定，不看请求体自报的任何字段**；它只进结构化日志与限流判定，不作权限判定（`moonchat-accounts`、`moonchat-agent-connection`）。
- **两个不需要认证的路由**：`POST /api/auth/register`、`POST /api/auth/login`。
- **一个两者都接受的路由**：`POST /api/sessions`——不带 JWT 且带 `account_key` 是 agent 换凭据；带 JWT 且带 `account_id` 是归属者切账号（§3.3）。
- **登录 JWT ≠ Turms 凭据**：登录 JWT 只对 Biz 有效（认作 `owner` 来源）；Turms 凭据由 `POST /api/sessions` 单独签发，是一份 Turms 能验的 JWT，`statements` 只授 `QUERY`（§3.3）。两者都走同一个 `Authorization` 头。
- **无感续期由两半组成**：登录 JWT 在过期前调 `POST /api/auth/refresh` 滑动续（§3.4）；Turms 凭据（12 小时）在过期前重调 `POST /api/sessions` 换新的（§3.3，可重复调用）。客户端只需一个定时器，不靠“碰运气刚好没过期”。
- 冻结（`account_info.status = 'frozen'`）的账号：可登录、可读，**停写入与好友申请**（`account_frozen`）。

### 1.3 响应与错误

成功一律 2xx：`200` 查询与状态变更、`201` 新建成功、`204` 无 body（删除类）。

失败响应体固定为：

```json
{ "code": "not_friend", "message": "只有好友之间才能私聊" }
```

`message` 是给人看的，**客户端与 agent 只准按 `code` 分流**。`validation_failed` 额外带 `field`。

| code | HTTP | 含义 |
| --- | --- | --- |
| `validation_failed` | 400 | 字段缺失、类型错、枚举外取值、空白文本、page/size 非法 |
| `unauthenticated` | 401 | 没有凭据，或凭据验证失败（JWT 过期/签名错、账号密钥查不到账号） |
| `forbidden` | 403 | 动作本身不被允许：agent 来源调真人专属动作、非群主移除成员、切换不属于自己的账号 |
| `account_frozen` | 403 | 账号已冻结（V1 没有冻结入口，这个码只为 DDL 已有状态存在） |
| `not_friend` | 403 | `dm` 会话的对端不是已成立的好友 |
| `not_room_member` | 403 | 调用者不是该群的有效成员 |
| `not_found` | 404 | 账号、群、好友关系、待处理申请不存在（含已写 `deleted_at` 的） |
| `conflict` | 409 | 状态与请求冲突：已是好友、已在群里、申请已被处理、重复发起同类关系 |
| `owner_cannot_leave` | 409 | 群主退群或移除自己（V1 没有转让，也没有解散群） |
| `rate_limited` | 429 | agent 来源超过账号级（暂定 60 次/分钟）或会话级（暂定 20 次/分钟）桶；两个数字写进配置，不是硬编码 |
| `upstream_unavailable` | 503 | `im-facade` 没从 Turms 拿到确认（发言与注册建用户两处） |
| `internal_error` | 500 | 未分类的服务端错误，响应里不带堆栈 |

### 1.4 值约定

| 项 | 约定 |
| --- | --- |
| id | JSON number（`bigint`）。V1 的 identity 值域远小于 2^53，不做字符串包装 |
| 时间 | ISO-8601 UTC，形如 `2026-01-01T10:00:00Z`；全部来自 `timestamptz` 列 |
| 文本 | 服务端先 `trim` 再校验；空白视为缺失 |
| 列表 | `{"items": [...]}`；唯一分页的接口（群成员）另外带 `page` / `size` / `total` |
| 布尔 | `is_friend` 这类两态事实用布尔，不暴露 `status` 枚举给客户端拼 |

### 1.5 幂等与重试

- `GET` / `DELETE` 的**副作用**幂等，但响应用状态表达：删一个已经不存在的关系 → `404 not_found`，不是 `204`。
- **所有 `POST` 都不幂等，也不带请求号**。发言失败后是否重试由调用方决定；重试可能产生重复消息，这是已定的行为（`moonchat-messaging` 的「已定的简化」最后一条），网关不去重。

---

## 2. 接口总表

20 条，一条动作只有一个入口。`来源` 列里 `owner` 指登录 JWT，`agent` 指账号密钥，`任意` 指两种都行。

| # | 方法与路径 | 用途 | 来源 | 读写的表 |
| --- | --- | --- | --- | --- |
| 1 | `POST /api/auth/register` | 注册真人账号 | 无认证 | 写 `account`、`account_info` |
| 2 | `POST /api/auth/login` | 换登录 JWT | 无认证 | 读 `account`、`account_info` |
| 3 | `POST /api/sessions` | 换 Turms 凭据（agent 密钥 / 归属者切账号） | `agent` 或 `owner` | 读 `account`、`account_info` |
| 4 | `GET /api/accounts/mine` | 我的账号 + 我名下的 agent | 任意 | 读 `account`、`account_info` |
| 5 | `POST /api/agent-accounts` | 建 agent 账号（返回一次性密钥） | 仅 `owner` | 写 `account`、`account_info` |
| 6 | `PATCH /api/accounts/me` | 改本账号名字 | 任意 | 写 `account_info` + `account.turms_sync_state` |
| 7 | `GET /api/accounts/{account_id}` | 资料页 | 任意 | 读 `account`、`account_info`、`friendship` |
| 8 | `GET /api/friendships` | 好友列表 / 待处理申请 | 任意 | 读 `friendship` / `friendship_reverse` |
| 9 | `POST /api/friendships` | 发好友申请 | 任意 | 写 `friendship`、`friendship_reverse` |
| 10 | `POST /api/friendships/{peer_account_id}` | 同意 / 拒绝申请 | 任意 | 写 `friendship`、`friendship_reverse` |
| 11 | `DELETE /api/friendships/{peer_account_id}` | 删好友 | 任意 | 写 `friendship`、`friendship_reverse`（tombstone） |
| 12 | `POST /api/rooms` | 建群 | 仅 `owner` | 写 `room_info`、`room_member`、`account_room` + Turms 投影 |
| 13 | `GET /api/rooms` | 我加入的群 | 任意 | 读 `account_room`、`room_info` |
| 14 | `GET /api/rooms/{room_id}` | 群信息 | 任意（须成员） | 读 `room_info`、`room_member` |
| 15 | `GET /api/rooms/{room_id}/members` | 群成员列表（分页） | 任意（须成员） | 读 `room_member`、`account_info`、`friendship` |
| 16 | `POST /api/rooms/{room_id}/members` | 拉人进群 | 仅 `owner` | 写 `room_member`、`account_room` + 投影标记 |
| 17 | `DELETE /api/rooms/{room_id}/members/me` | 退群 | 仅 `owner` | 写 `room_member`、`account_room` + 投影标记 |
| 18 | `DELETE /api/rooms/{room_id}/members/{account_id}` | 移除成员（仅群主） | 仅 `owner` | 写 `room_member`、`account_room` + 投影标记 |
| 19 | `POST /api/conversations/{type}/{id}/messages` | 发言（唯一写入口） | 任意 | 不写 PG；读 `room_member` / `friendship`；经 `im-facade` 写 Turms |
| 20 | `POST /api/auth/refresh` | 登录 JWT 滑动续期（无感续期的那一半） | 登录 JWT | 不写 PG |

---

## 3. 认证与凭据

### 3.1 `POST /api/auth/register`

注册一个真人账号。**不签发 JWT**：注册与登录是两次独立请求，客户端注册成功后自己再调 §3.2 换凭据。

**请求**

| 字段 | 类型 | 必填 | 约束 |
| --- | --- | --- | --- |
| `email` | string | 是 | trim + 转小写后唯一；含 `@` 且位置 > 1；**≤ 254**（RFC 上限） |
| `password` | string | 是 | **8..72** 字符；**不能是纯数字**；只存 bcrypt 哈希。72 是 bcrypt 的硬上限，超过会被静默截断，必须在入口拦住 |
| `display_name` | string | 是 | trim 后非空；≤ 20（与 Turms `max-name-length` 默认值一致，超了会被 Turms 拒） |

**响应** `201`

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `account_id` | number | 新建账号的 id，也是它的 Turms 用户 id |
| `display_name` | string | 同请求值 |
| `type` | string | 固定 `human` |

响应里**没有 token**：注册不建立会话，登录（§3.2）才发 JWT。

**错误**：`validation_failed` 400、`conflict` 409（email 已存在）、`upstream_unavailable` 503（建 Turms 用户失败）。

**副作用与不变量**

- 同一事务写 `account`（`type = 'human'`）与 `account_info`（`credential_hash` 为 bcrypt，cost 10 起），并在**同一事务内**经 `im-facade` 用**这个 id** 建 Turms 用户；拿到确认才把 `account.turms_sync_state` 置 `synced`。
- 建 Turms 用户失败就整笔回滚（连同账号行），不留孤儿账号；不落 `pending`、也没有后台重试——重试是客户端重发一次注册（`moonchat-accounts` 的「创建顺序」）。
- 注册不做邮箱验证（已定的简化），所以没有验证令牌相关字段。

### 3.2 `POST /api/auth/login`

**请求**

| 字段 | 类型 | 必填 |
| --- | --- | --- |
| `email` | string | 是 |
| `password` | string | 是 |

**响应** `200`：`token`、`expires_at`、`account.account_id`、`account.type`、`account.display_name`。

**错误**：`validation_failed` 400、`unauthenticated` 401。冻结不拦登录（只拦写入与好友申请）。

- **账号不存在与密码错误返回同一个 `unauthenticated`**：不给账号枚举留信号。

### 3.3 `POST /api/sessions`

两种请求形态，**恰好一种**，混用或都给 → `validation_failed`。签出来的东西是同一个东西：一个该账号的 Turms 凭据。

| 形态 | 认证头 | 请求体 | 来源 |
| --- | --- | --- | --- |
| agent 换凭据 | **不带** | `{"account_key": "<明文密钥>"}` | `agent` |
| 归属者切账号 | 带登录 JWT | `{"account_id": 123}` | `owner` |

**响应** `200`

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `account_id` | number | 凭据归属的账号 |
| `display_name` | string | 该账号名字 |
| `type` | string | `human` / `agent` |
| `login_token` | string | **只在归属者切账号形态出现**：这个账号自己的登录 JWT（来源 `owner`）。没有它，切进去之后连 `/api` 都调不了 |
| `login_expires_at` | string | 上面那份登录 JWT 的过期时间（7 天） |
| `turms.user_id` | number | 等于 `account.id` |
| `turms.credential` | string | Biz 用与 Turms 共享的 HMAC 密钥签的 **JWT**；登录时当作 Turms 的 `password` 参数传给客户端 SDK |
| `turms.gateway_url` | string | Turms 网关地址（WS/WSS） |
| `expires_at` | string | 凭据有效期 |

**错误**：`validation_failed` 400、`unauthenticated` 401（密钥查不到账号 / JWT 无效）、`forbidden` 403（该 `account_id` 不在我的名下）、`account_frozen` 403、`not_found` 404（`account_id` 不存在）。

**副作用与不变量**

- **归属者形态顺带发一份登录 JWT**：`login_token` 的 `sub` 就是切进去的那个账号，所以它接下来调 `/api` 时来源是 `owner` 而不是 `agent`——这正是「归属者切进 agent 账号能建群、能发言，且不进 agent 限流桶」的实现方式（§6 与 `moonchat-agent-connection`）。密钥形态**不发**登录 JWT：agent 端点不该有能力以 `owner` 来源写入。
- 凭据是一个 JWT，payload 至少有 `sub`（= `account_id`）、`exp`、`statements` 与 `authenticated: true`；由 `im-facade` 用共享 HMAC 密钥签，**不落 PG**（`moonchat-accounts`）。Turms 侧配 `identity-access-management.type = jwt`，按 `sub` 验证登录者就是 `user_id` 那一个人。
- **`statements` 只授查询**：`{"effect":"ALLOW","actions":["QUERY"],"resources":["*"]}`。客户端因此能登录、收推送、查历史与资料，但发不出消息（`CREATE_MESSAGE_REQUEST` → `UNAUTHORIZED_REQUEST`）、也建不了 group。写入只能走 §7 的写入网关。payload 还必须带 `authenticated: true`——Turms 默认期望这个 claim，缺了会以 `2011` 拒绝登录（实测）。依据与前提（`type = jwt`、Turms 用户的密码是平台不保存的随机值）在 `moonchat-messaging` 的「凭据与客户端权限」。
- **有效期 12 小时**，客户端在过期前重调本接口（幂等读取，不创建任何会话状态）；过期后 Turms 会拒登录，重调即可。
- `account_key` 形态只能换**密钥所属账号**的凭据，不存在「拿自己的密钥换别人账号」的路径；`account_id` 形态只能换**自己名下**的账号（归属关系本身就是授权）。
- Turms 允许同一 user 多端在线，所以 agent 端点与归属者的客户端可以同时持同一账号的凭据。

### 3.4 `POST /api/auth/refresh`

登录 JWT 的滑动续期。**它只换登录凭据，不签发 Turms 凭据**——那一步永远走 §3.3。

**请求**：无 body。凭据就是当前的登录 JWT。

**响应** `200`

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `token` | string | 新的登录 JWT，有效期从此刻起重算 7 天 |
| `expires_at` | string | 新凭据的过期时间 |
| `account.account_id` / `account.type` / `account.display_name` | number / string / string | 回显，省一次 `GET /api/accounts/mine` |

**错误**：`unauthenticated` 401（当前 JWT 已过期/无效，或来源是账号密钥）、`account_frozen` 403。

**副作用与不变量**

- **无状态**：不写 PG、不存凭据记录，签发只由现有凭据 + 服务器密钥决定。
- **滑动窗口**：每次续期都从“现在”重算 7 天，所以持续使用的客户端不会掉线；停用 7 天就要重新登录。
- **账号密钥不能续**：agent 的凭据是归属者创建时发放的账号密钥（本身不变），没有过期与续期概念；它换 Turms 凭据走 §3.3。

---

## 4. 账号与归属

### 4.1 `GET /api/accounts/mine`

切账号入口的数据源。

**响应** `200`：`items[]`，每项 `account_id`、`type`、`display_name`。自己排第一，其后的 agent 按 `account.created_at` 升序。

**读取**：`select ... from account where id = :me or owner_account_id = :me`（走 `account_owner_idx`），再按 `account_id` 取 `account_info.display_name`。

### 4.2 `POST /api/agent-accounts`

**请求**：`display_name`（string，必填，trim 后非空，≤ 20）。

**响应** `201`

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `account_id` | number | 新账号 id |
| `display_name` | string | 同请求值 |
| `account_key` | string | **明文密钥，只在这个响应里出现一次**；形态是 UUIDv4（36 字符），库里只有它的确定性 HMAC-SHA256 + pepper 哈希 |

**错误**：`validation_failed` 400、`forbidden` 403（来源是 agent：agent 不能再建 agent）。

**副作用与不变量**

- 同一事务写 `account`（`type = 'agent'`、`owner_account_id` = 调用者、`turms_sync_state = 'pending'`）与 `account_info`（`credential_hash` = HMAC-SHA256 + pepper（`moonchat.agent.key-pepper`），`email` 为空）。
- 之后建 Turms 用户，口径同 §3.1。
- 新账号**不入群、不加好友**：建完就是一个孤立的账号，关系由后续动作建立。

### 4.3 `PATCH /api/accounts/me`

**请求**：`display_name`（string，必填，trim 后非空，≤ 20）。

**响应** `200`：`account_id`、`display_name`、`updated_at`。

**错误**：`validation_failed` 400、`account_frozen` 403、`upstream_unavailable` 503（经 `im-facade` 同步名字失败）。

**副作用**：同一事务写 `account_info.display_name` 并写 `account.turms_sync_state = 'synced'`，事务内经 `im-facade` 同步名字进 Turms；同步失败**整笔回滚**——名字与同步状态都不变，回 `503`，与 §3.1 注册建用户同口径，不留永远挂 `pending` 的账号。

### 4.4 `GET /api/accounts/{account_id}`

资料页。**这是加好友的唯一入口**——V1 不做搜人、不做 agent 目录。

**响应** `200`

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `account_id` | number | |
| `display_name` | string | |
| `is_friend` | boolean | 调用者与该账号是否已是好友（查 `friendship`，规范序） |

**错误**：`not_found` 404。

- **只返回这三项**：不含 `email`、`owner_account_id`、`created_at`，也不含 `type`——PRD 的资料页就是名字 + id + 加好友入口。
- **非好友也返回名字与 id**：群里点开非好友时看到的就是这个页面，页面里没有「发消息」入口（`moonchat-friends` 的「私聊的入口只有两个」）。

---

## 5. 好友

好友是**无向的强关系**：一对账号之间只有一条关系，由两侧账号 id 唯一确定（落库时小 id 在前）。所以接口面只出现 `peer_account_id`，**`friendship.id` 不作为任何接口的入参或响应字段**——客户端没有理由保存一个不透明 id。

> 多对多关系的这种建模（规范序单表 + 反向表冗余、同事务双写）在后端是标准做法：单表 `friend(uid1, uid2)` 保证唯一，反向表让「按任一侧查询」都不必扫全表。我们落在 `friendship` / `friendship_reverse`（`moonchat-biz-data` §4.3、§4.4），但**不需要**那套「异步冗余 + 离线比对修复」的补偿机制：两张表在同一个 PG、同一个事务里提交，要么都成，要么都不成。

### 5.1 `GET /api/friendships?status=`

| 查询参数 | 取值 | 默认 | 语义 |
| --- | --- | --- | --- |
| `status` | `pending` / `accepted` | `accepted` | `pending`：**发给我的**待处理申请（`requested_by` 不是我）；`accepted`：已成立的好友 |

**响应** `200`：`items[]`，每项：

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `peer_account_id` | number | 对端账号 id |
| `display_name` | string | 对端名字 |
| `status` | string | `pending` / `accepted` |
| `incoming` | boolean | 是否对端发起的申请（`pending` 时有意义；`accepted` 恒为 `false`） |
| `requested_at` | string | 关系的 `created_at`，即申请发起时间 |

**错误**：`validation_failed` 400（`status` 不在枚举内）。

**读取**：按自己在规范序中的位置选表——较小的 id 查 `friendship`（`account_id = me`），较大的 id 查 `friendship_reverse`（`account_id = me`），两者都要求 `deleted_at is null`。反向表在这里只是查询镜像，不参与授权（授权一律读 `friendship`）。

### 5.2 `POST /api/friendships`

**请求**：`peer_account_id`（number，必填）。

**响应** `201`：`peer_account_id`、`status`（`"pending"`）、`incoming`（`false`）。

**错误**：`validation_failed` 400（`peer_account_id` 是自己）、`not_found` 404（对端账号不存在）、`account_frozen` 403（任一方冻结）、`conflict` 409（已是好友，或已有待处理申请）、`rate_limited` 429（`agent` 来源，账号级桶）。

**副作用与不变量**

- 同一事务写 `friendship` 与 `friendship_reverse`，一次写入使用同一个应用时间值。
- **被拒绝过之后重新申请复用原行**：清 `deleted_at`、`status = 'pending'`、`requested_by = 我`，不插入第二个同 pair 行（`moonchat-biz-data` §4.3）。
- **没有冷却期**，也不写 Turms 的任何东西——好友永不投影（`moonchat-messaging`）。

### 5.3 `POST /api/friendships/{peer_account_id}`

**请求**：`action`（string，必填，`accept` / `reject`）。

**响应**：`accept` → `200`，body `peer_account_id`、`status`（`"accepted"`）；`reject` → `204`，无 body。

**错误**：`validation_failed` 400（`action` 非法）、`not_found` 404（与对端没有待处理的申请）、`forbidden` 403（这条申请是我发出去的，不能自己应答）、`conflict` 409（关系已不是 `pending`）、`account_frozen` 403。

**副作用与不变量**

- 两张表同事务更新；`accept` 后私聊授权**立即**生效，因为写入网关是现查 PG 的 `friendship`，没有缓存也没有第二份真相。
- `reject` 写 `deleted_at`，`status` 枚举**不增加** rejected：拒绝就是 tombstone（`moonchat-biz-data` §4.3）。
- 应答时要校验操作方：只有 `requested_by` 的对端才能同意或拒绝。

### 5.4 `DELETE /api/friendships/{peer_account_id}`

**响应** `204`。

**错误**：`not_found` 404（没有有效好友关系）、`account_frozen` 403。

**副作用与不变量**

- 两张表同事务写 `deleted_at`；超过保留期（**未确认**）后由 Biz purge 物理删行。
- **Turms 侧什么都不发生**：会话保留、历史只读、不能再发新消息。删除好友不动任何设置，因为平台没有投递设置（`moonchat-friends` 的「删除好友之后」）。
- 重复调用返回 `404`，不返回 `204`：接口用状态表达事实（§1.5）。

---

## 6. 群与成员

群只有一个可见性：成员可见。`room_info` 没有 `visibility` 列，可见性是 Turms `GroupType` 的配置（`moonchat-messaging`）。**成员操作只有真人能做**：`agent` 来源在这四条写接口上一律 `403 forbidden`——归属者切进 agent 账号时来源是 `owner`，所以那条路是通的。

### 6.1 `POST /api/rooms`

**请求**：`name`（string，必填，trim 后非空，≤ 20）。Turms 侧对群名没有长度配置，这个值是我们自己定的（与账号名字对齐）。

**响应** `201`：`room_id`、`name`、`owner_account_id`、`created_at`。

**错误**：`validation_failed` 400、`forbidden` 403（`agent` 来源）、`account_frozen` 403。

**副作用与不变量**

1. 一个 PG 事务写 `room_info` + 群主的 `room_member` + `account_room`（「群主一定是成员」是事务产物）。
2. 然后经 `im-facade` 在 Turms 建 group（名字与 ownerId 一并带过去），把返回的 group id 回填 `room_info.turms_group_id`。
3. **投影失败不回滚业务房间**：`turms_sync_state` 保持 `pending`，后台按 PG 重放（full reconcile）。所以 `201` 只表示「PG 里群已成立」，不表示 Turms 已能投递。

对外的群标识永远是这个 `room_id`，不是 Turms 的 group id。

### 6.2 `GET /api/rooms`

**响应** `200`：`items[]`，每项 `room_id`、`name`、`owner_account_id`、`joined_at`。

**读取**：`account_room`（`account_id = me` 且 `deleted_at is null`）联 `room_info`。**不读 Turms 的群列表**——客户端现在建不了新群，但 Turms 里仍可能有残留的游离群，它的群列表不等于业务列表（`moonchat-messaging` 的已知缺口）。

### 6.3 `GET /api/rooms/{room_id}`

**响应** `200`：`room_id`、`name`、`owner_account_id`、`member_count`、`created_at`。

**错误**：`not_found` 404（群不存在）、`not_room_member` 403。

**读取**：`room_info` + `room_member` 有效行计数。

### 6.4 `GET /api/rooms/{room_id}/members?page=&size=`

**这是唯一分页的接口**：群规模没有上限，其余列表（好友、待处理、我的群）V1 一次返回全量。

| 查询参数 | 类型 | 默认 | 约束 |
| --- | --- | --- | --- |
| `page` | number | `1` | ≥ 1；offset 分页（PageHelper / MyBatis-Plus 直接支持） |
| `size` | number | `50` | 1..100（两个数字暂定，等真实群规模） |

**响应** `200`

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `items[].account_id` | number | |
| `items[].display_name` | string | |
| `items[].is_friend` | boolean | 调用者与该成员是否好友（省掉每人一次资料页请求） |
| `items[].joined_at` | string | `room_member.joined_at` |
| `page` / `size` / `total` | number | `total` 为有效成员总数 |

**错误**：`validation_failed` 400（`page` / `size` 非法）、`not_found` 404、`not_room_member` 403。

- 成员列表**没有 `role` 字段**：群主就是 `owner_account_id`，是不是群主用 `account_id == owner_account_id` 判断（`moonchat-biz-data` §4.6）。

### 6.5 `POST /api/rooms/{room_id}/members`

**请求**：`account_id`（number，必填）。一次一个，不做批量。

**响应** `201`：`room_id`、`account_id`、`joined_at`。

**错误**：`validation_failed` 400、`forbidden` 403（`agent` 来源，或调用者不是该群成员）、`not_found` 404（群不存在，或目标账号不存在）、`conflict` 409（目标已在群里）。

**副作用与不变量**

- 同一事务写 `room_member` 与 `account_room`（在 purge 前重新进群时复用原行：清 `deleted_at`、`joined_at` 更新为本次时间）。
- **邀请即入群，不设审批**，也不要求目标是我的好友（已定的简化，PRD §5.3）。
- 写完把 `room_info.turms_sync_state` 置回 `pending` 并触发一次 full reconcile——成员集合是群聚合的一部分，投影读的是 `room_member` 全量。

### 6.6 `DELETE /api/rooms/{room_id}/members/me`

**响应** `204`。

**错误**：`owner_cannot_leave` 409（我是群主）、`not_room_member` 403、`not_found` 404（群不存在）、`forbidden` 403（`agent` 来源）。

**副作用**：两张成员表同事务写 `deleted_at` + 投影标记。V1 没有群主转让、也没有解散群，所以群主只能等 V2（`moonchat-messaging` 的不变量）。

### 6.7 `DELETE /api/rooms/{room_id}/members/{account_id}`

**响应** `204`。

**错误**：`forbidden` 403（调用者不是群主，或 `agent` 来源）、`owner_cannot_leave` 409（`account_id` 就是群主自己）、`not_found` 404（群不存在，或该账号不是有效成员）。

**副作用**：同 §6.6。移除不需要理由字段，也不记录成员变更历史（表里没有这类列）。

---

## 7. 发言：`POST /api/conversations/{type}/{id}/messages`

**唯一的写入口**（`moonchat-messaging`、`architecture` 的「一条消息的旅程」）。客户端自己的 Turms 会话只授查询，**发不出消息**，所以用户从客户端发信就是直接调用这个接口。

| 路径参数 | 取值 | 含义 |
| --- | --- | --- |
| `type` | `room` / `dm` | 会话类型 |
| `id` | number | `room` 下是 `room_info.id`；`dm` 下是对端 `account_id` |

没有第三个编号要给客户端记：私聊不是一对象 id，而是「我和他」。

**请求**：`text`（string，必填，trim 后非空；≤ 500 字符）。500 是 Turms `max-text-limit` 的默认上限，Biz 先拦一道，别让超长文本变成 Turms 的报错。`@` 只是正文字符，不做结构化 mentions。

**请求头**：`X-Device-Type`（可选，`desktop` / `browser` / `ios` / `android` / `others`，缺省 `desktop`）。它只映射成 Turms 的 `senderDeviceType`，不参与任何判定；枚举外取值回 `validation_failed`，`field` 就是这个头名。

**响应** `201`

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `message_id` | number | **写入网关生成**的消息 id（随代发提交，Admin 不回传 id）；单调递增但不连续，也不保存任何历史 id。**不是分页游标**：Turms 客户端查询只接受 `deliveryDateStart/End` + `maxCount` + `descending`，客户端往回翻用最早一条的 `sent_at` 做游标（`moonchat-messaging`） |
| `conversation.type` / `conversation.id` | string / number | 回显 |
| `sent_at` | string | 网关交出这一刻的时间；Turms 的 `deliveryDate` 与之差毫秒级 |

**错误**

| code | 何时 |
| --- | --- |
| `validation_failed` 400 | `text` 空白或超长；`type` 不是 `room`/`dm`；`dm` 的 `id` 是调用者自己 |
| `not_found` 404 | `dm` 的对端账号不存在；`room` 的 `room_id` 不存在 |
| `not_friend` 403 | `dm` 且双方不是已成立好友（`friendship.status = 'accepted'` 且未 tombstone） |
| `not_room_member` 403 | `room` 且调用者不是有效成员 |
| `account_frozen` 403 | 调用者账号冻结 |
| `rate_limited` 429 | `agent` 来源超账号级（60/分钟）或会话级（20/分钟）桶，两个数字暂定、可配置 |
| `upstream_unavailable` 503 | `im-facade` 没从 Turms 拿到确认 |

**校验顺序**（与架构旅程一致，不许调换）：认证凭据 → 归属（凭据能不能代表这个账号）→ 会话解析（`type` / `id` 合法且目标存在）→ 授权事实（群成员 / 好友，现查 PG）→ 限流（只有 `agent` 来源进桶）→ 来源标记写日志 → 交出去。

**副作用与不变量**

- 通过后 `im-facade` 调 Turms Admin API `POST /messages`，带 `id`（上一步生成的 message id）、`senderId`（上一步认证出的账号，**不接受请求体里自报的发送者**）、`senderDeviceType`（来自请求头）、`senderIp`（`X-Forwarded-For` 第一段，缺省 `remoteAddr`）、`isGroupMessage`、`targetId`。
- **PG 零写入**：消息只在 Turms，没有副本、没有发送记录表、没有审计表；来源与限流命中只进结构化日志。
- 成功（`201`）只保证「Turms 已落库并接下了投递」；是否真的到达对方在线端还取决于对方的会话在线状态（冒烟里观察到刚登录的会话有一段同步窗口，见 `moonchat-messaging` 的冒烟结果）。`503` 只表示 Biz 没拿到确认，**Turms 可能已经落库**——此时重试可能产生重复消息，这是已写的已知行为，不做幂等保证。
- Turms 侧还会用它自己的投影再校验一次（群成员、黑名单）；两道闸都在，但好友校验只有 Biz 这一道（`allowSendMessagesToStranger = true`）。

---

## 8. 明确不提供的接口

| 不提供 | 真相在哪 / 由谁做 | 依据 |
| --- | --- | --- |
| 消息历史、会话列表、未读数、在线状态 | 客户端用自己的 Turms 会话查 | `moonchat-messaging` 的「读历史」 |
| 客户端直接往 Turms 发消息 | 客户端 JWT 只授 `QUERY`，写入只能走 §7；Turms 对 `CREATE_MESSAGE_REQUEST` 返回 `UNAUTHORIZED_REQUEST` | `moonchat-messaging` 的「凭据与客户端权限」 |
| 消息搜索 | 不做 | `moonchat-messaging` 的「已定的简化」 |
| 头像上传或头像接口 | 客户端按 `account.id` 确定性生成 | `moonchat-product` §5.3 |
| 搜人 / agent 目录 | 加好友靠账号 id 与主页链接 | `moonchat-product` §5.3 |
| 拉黑、举报、封禁、备注、分组 | V2 或不做 | `moonchat-product` §8、§13 |
| 解散群、群主转让、批量拉人 | V1 没有这些动作 | `moonchat-messaging` 的不变量 |
| 临时会话（非好友私聊） | 入口本身不存在 | `moonchat-friends` 的「为什么不做临时会话」 |
| 建群 / 拉人 / 移除成员的 agent 版本 | agent 只有一个关系动作：发好友申请 | `moonchat-agent-connection` 的不变量 |
| 删账号 / 删 agent 账号 | V1 没有这个能力，账号行不删（`moonchat-biz-data` §2 的行生命周期） | `moonchat-product` §5.1 |
| 登出 / 注销 | 客户端丢掉手上的 JWT 即可；服务端无状态，没有登出接口 | §3.4 的续期也是同样无状态的 |
| 冻结账号、purge、对账 | 平台运维动作，不是产品能力 | `moonchat-biz-data` §4.1 |
| 健康检查 | 已有 `spring-boot-starter-actuator`，不进业务契约 | `moonchat-biz/pom.xml` |

---

## 9. 表 ↔ 接口对照

这张表就是「每列都要指回一句话」的落点：接口里能出现的数据，只能来自这里。

| 表 | 写入它的接口 | 读它的接口 | 从不出现在响应里的列 |
| --- | --- | --- | --- |
| `account` | #1 注册、#5 建 agent、#6 改名（只改 `turms_sync_state`） | #2、#3、#4、#7 | `turms_sync_state`、`created_at`、`updated_at`；`owner_account_id` 只在 #4 的「我名下的 agent」语义里间接体现 |
| `account_info` | #1、#5、#6 | #2、#3、#4、#7、#15 | `credential_hash`、`email`、`status`、时间列 |
| `friendship` | #9、#10、#11 | #7（`is_friend`）、#8、#15（`is_friend`）、#19（授权） | `id`、`requested_by`（对外是 `incoming`）、`deleted_at`、时间列（只暴露 `requested_at`） |
| `friendship_reverse` | #9、#10、#11（同事务镜像） | #8（按较大 id 查） | 全部列；它只是查询镜像 |
| `room_info` | #12、#16/#17/#18（只改 `turms_sync_state`） | #13、#14、#19 | `turms_group_id`、`turms_sync_state`、`updated_at` |
| `room_member` | #12、#16、#17、#18 | #14（计数）、#15、#19（授权） | `deleted_at`；不暴露角色（没有该列） |
| `account_room` | #12、#16、#17、#18（同事务镜像） | #13 | 全部列；`joined_at` 通过 `room_member` 语义暴露 |

Red 线两条：**消息表不存在**（没有它可对照），**授权判断只读主表**（`friendship` / `room_member`），反向表只服务查询。

---

## 10. 仍未定的事

已清掉的：Turms 凭据形态（JWT）、名字 20 / 正文 500（Turms 默认值）、客户端权限策略（`statements` 只授 `QUERY`）、邮箱 254 / 密码 8..72 且不能纯数字、登录 JWT 7 天 / Turms 12 小时、限流 60/20（暂定）、归属者切账号时附带登录 JWT、**消息 id 由网关生成**（Admin `POST /messages` 返回空 body，不回传 id）、`senderDeviceType` 由客户端声明（`X-Device-Type`）。剩下这些：

| 事项 | 现状 | 卡在哪 |
| --- | --- | --- |
| Turms 凭据端到端 | 已跑通（`infra/turms/smoke`）：JWT 登录 ✔、QUERY-only 发消息被拒 1106 ✔、代发落库 ✔ | `gateway_url` 的取值随部署定；**代发的推送到达**在本地 standalone 下未稳定（见 `moonchat-messaging` 的冒烟结果），真实环境复测 |
| 两个入口能否真正合并成一条 `POST /api/sessions` | 已按合并写 | 依赖 `im-facade` 两条签发路径共用同一个出口 |
| 群名称长度 20 | 自定（与账号名字对齐） | Turms 侧没有这个配置，没有外部依据 |
| 群成员分页的 `size` 默认 50 / 上限 100 | 暂用 | 没有实测依据；等真实群规模 |
| 两级限流速率 60/20 | 暂定值，写进配置 | 必须等真实流量才能定下；现在只为了能测 429 分支 |
| 403 是否要进一步细分 | 现在 5 个 403 码 | 客户端接入后按实际分支再收窄或合并 |
