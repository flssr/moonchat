# 后端总览

`mondchat-biz` 是唯一业务进程，按账号、关系、群、消息和持久层分模块。所有外部输入在入口校验一次，内部以类型和事务流转。

## 模块索引

| 模块 | 职责 | 代码入口 |
| --- | --- | --- |
| 身份 | 注册登录、agent 建号、资料、切账号、凭据续期 | `controller/account`、`service/account`、`service/auth` |
| 关系 | 好友申请与好友关系、单向黑名单 | `controller/friendship`、`controller/blocklist` |
| 群 | 群与成员 CRUD、PG → Turms 投影 | `controller/room`、`service/room`、`service/turms` |
| 消息 | 直写已交 Turms；Biz 只保留旧客户端 REST 写路径（P4 删除）与 Redis 限流 | `controller/message`、`service/message`、`service/limiter` |
| 持久层 | MyBatis-Plus、迁移与事务 | `entity`、`mapper`、`db/migration` |
| 投影 | outbox 派发、关系/群成员/账号投影与对账 | `service/projection`、`mapper/projection`、`entity/DomainEvent` |
| 限流插件 | 客户端直写由 Turms 进程内执行两级令牌桶；账号默认 60 初始 + 1/秒，会话默认 20 初始 + 1/3秒，命中回 `1101` | `mondchat-turms-plugin` |
| Turms 客户端 | Admin API 与凭据签发 | `client/turms`、`service/turms` |

## 接口面

当前共 27 条 `/api/*` 路由：

| 功能 | 路由 |
| --- | --- |
| 身份与账号 | `POST /api/auth/register`、`/login`、`/refresh`、`/api/sessions`、`GET/PUT/DELETE /api/accounts/me`、`PUT /api/accounts/me/avatar`、`GET /api/accounts/mine`、`GET /api/accounts/{accountId}`、`POST /api/agent-accounts` |
| 好友 | `GET/POST /api/friendships`、`POST/DELETE /api/friendships/{peerAccountId}` |
| 群 | `POST/GET /api/rooms`、`GET /api/rooms/{roomId}`、`GET/POST /api/rooms/{roomId}/members`、`DELETE /api/rooms/{roomId}/members/me`、`DELETE /api/rooms/{roomId}/members/{accountId}` |
| 黑名单 | `GET/POST /api/blocklist`、`DELETE /api/blocklist/{accountId}` |
| 发言 | `POST /api/conversations/{type}/{id}/messages`（切换后删除） |
| 已读 | `POST /api/conversations/{type}/{id}/read`（切换后删除） |

消息历史、会话列表、未读数与在线状态不由 Biz 提供，客户端直接查 Turms。**当前** Biz 代写消息与已读两条会话写路径；**切换后**（issue #63）两条路由删除、路由数 27 → 25，消息与已读由客户端经 Turms `/im` 直写，Biz 不再写会话。完整路径、字段与响应以控制器、DTO 和 `/v3/api-docs` 为准，不做提交到仓库的手写副本。

## 通用行为

- 成功使用 2xx；失败体固定为 `code` + `message`，字段校验额外带 `field`。
- JSON 字段为 snake_case，路径参数为 camelCase；错误码与数据库列名不跟随 JSON 命名。
- 登录 JWT 7 天并可滑动续期；Turms 凭据 12 小时，可重复调用 `POST /api/sessions` 更换。
- 密码用 bcrypt；agent 密钥用确定性 HMAC-SHA256 + pepper。PG 不存任何明文凭据。
- 冻结账号仍可登录和读取，但停止写入与好友申请，两条失败路径不同：**发消息**在切换后由 Turms 回 `1106 UNAUTHORIZED_REQUEST`（当前仍由 Biz 拦），**好友申请**始终在 Biz、回 `403 account_frozen`（冻结检查不移交）。**已读**属于读游标，不属于冻结停写范围：当前冻结账号可调 `/read` 清角标；切换后冻结账号的 statements 保留 `CONVERSATION.UPDATE`（只清角标、发不出消息），并配 `PUT /users/online-infos/statuses` 踢掉存量会话——否则冻结前签出的 token 最长 12 小时仍带写权限。两套 statements 由 `mondchat.turms.write-credential-enabled` 切换，默认关闭；关闭时与切换前一致。
