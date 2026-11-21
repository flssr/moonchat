# 后端总览

`mondchat-biz` 是唯一业务进程，按账号、关系、群、消息和持久层分模块。所有外部输入在入口校验一次，内部以类型和事务流转。

## 模块索引

| 模块 | 职责 | 代码入口 |
| --- | --- | --- |
| 身份 | 注册登录、agent 建号、资料、切账号、凭据续期 | `controller/account`、`service/account`、`service/auth` |
| 关系 | 好友申请与好友关系、单向黑名单 | `controller/friendship`、`controller/blocklist` |
| 群 | 群与成员 CRUD、PG → Turms 投影 | `controller/room`、`service/room`、`service/turms` |
| 消息 | 唯一写入网关、已读时间代写、限流、代发 | `controller/message`、`service/message`、`service/limiter` |
| 持久层 | MyBatis-Plus、迁移与事务 | `entity`、`mapper`、`db/migration` |
| Turms 客户端 | Admin API 与凭据签发 | `client/turms`、`service/turms` |

## 接口面

当前共 26 条 `/api/*` 路由：

| 功能 | 路由 |
| --- | --- |
| 身份与账号 | `POST /api/auth/register`、`/login`、`/refresh`、`/api/sessions`、`GET/PUT /api/accounts/me`、`PUT /api/accounts/me/avatar`、`GET /api/accounts/mine`、`GET /api/accounts/{accountId}`、`POST /api/agent-accounts` |
| 好友 | `GET/POST /api/friendships`、`POST/DELETE /api/friendships/{peerAccountId}` |
| 群 | `POST/GET /api/rooms`、`GET /api/rooms/{roomId}`、`GET/POST /api/rooms/{roomId}/members`、`DELETE /api/rooms/{roomId}/members/me`、`DELETE /api/rooms/{roomId}/members/{accountId}` |
| 黑名单 | `GET/POST /api/blocklist`、`DELETE /api/blocklist/{accountId}` |
| 发言 | `POST /api/conversations/{type}/{id}/messages` |
| 已读 | `POST /api/conversations/{type}/{id}/read` |

消息历史、会话列表、未读数与在线状态不由 Biz 提供，客户端直接查 Turms；Biz 只代写消息与已读时间两条会话写路径。完整路径、字段与响应以控制器、DTO 和 `/v3/api-docs` 为准，不做提交到仓库的手写副本。

## 通用行为

- 成功使用 2xx；失败体固定为 `code` + `message`，字段校验额外带 `field`。
- JSON 字段为 snake_case，路径参数为 camelCase；错误码与数据库列名不跟随 JSON 命名。
- 登录 JWT 7 天并可滑动续期；Turms 凭据 12 小时，可重复调用 `POST /api/sessions` 更换。
- 密码用 bcrypt；agent 密钥用确定性 HMAC-SHA256 + pepper。PG 不存任何明文凭据。
- 冻结账号仍可登录和读取，但停止写入与好友申请。已读上报（`POST /api/conversations/{type}/{id}/read`）属于读游标，不在冻结范围内——否则冻结期间角标永远清不掉。
