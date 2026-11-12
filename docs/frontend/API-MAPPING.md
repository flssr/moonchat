# MoonChat 客户端接口映射 v1

- 日期：2026-11-11
- 依据：`docs/api-contracts.md`（20 条 `/api/*`）、`goal-and-requirements.md`
- 页面：`frontend/preview/index.html`
- 原则：读走 Turms，写走 Biz 网关；客户端没有 Turms 写权限。

## 1. 认证与凭据

```
Authorization: Bearer <token>
```

| 凭据 | 谁用 | 来源标记 | 有效期 |
| --- | --- | --- | --- |
| 登录 JWT | 真人客户端，含归属者切进 agent 账号 | `owner` | 7 天，滑动续期 |
| 账号密钥 | agent 端点 | `agent` | 不过期，创建时只发一次 |

- 注册与登录不需要认证；`POST /api/sessions` 两种形态恰好一种。
- 登录 JWT 只对 Biz 有效。连接 Turms 用的是 `POST /api/sessions` 返回的 `turms.credential`，它只授 `QUERY`。
- 客户端到期前自行续期：登录 JWT 走 `/api/auth/refresh`，Turms 凭据重调 `/api/sessions`。
- 来源只影响日志与限流，不下发到客户端，也不用于权限判断；界面不标注 agent。

## 2. 界面动作 → 接口

### 2.1 认证与账号

| 界面动作 | 接口 | 请求 | 用到的响应 | 错误处理 |
| --- | --- | --- | --- | --- |
| 注册 | `POST /api/auth/register` | `email`、`password`、`display_name` | `account_id`、`display_name`、`type` | `validation_failed` 贴字段；`conflict` 提示邮箱已用；`upstream_unavailable` 提示重试 |
| 登录 | `POST /api/auth/login` | `email`、`password` | `token`、`expires_at`、`account` | `unauthenticated` 统一提示，不区分账号不存在与密码错 |
| 登录后连 Turms | `POST /api/sessions` | 登录 JWT + `account_id` | `login_token`、`login_expires_at`、`turms.credential`、`turms.gateway_url`、`expires_at` | `forbidden` 说明账号不属于我；`account_frozen` 只读；`unauthenticated` 回登录 |
| 切到 agent 账号 | `POST /api/sessions` | 登录 JWT + `account_id` | 同上 | 同上 |
| agent 换凭据 | `POST /api/sessions` | 无 Authorization + `account_key` | `turms.*`、`expires_at` | 只用于 agent 端点，不在客户端界面出现 |
| 无感续期 | `POST /api/auth/refresh` | 当前登录 JWT | `token`、`expires_at` | `unauthenticated` 回登录；`account_frozen` 转只读 |
| 打开账号页 | `GET /api/accounts/mine` | — | `items[]`：`account_id`、`type`、`display_name` | 失败给空状态，不缓存旧列表 |
| 创建 agent | `POST /api/agent-accounts` | `display_name` | `account_id`、`display_name`、`account_key` | `validation_failed` 贴字段；`forbidden` 说明 agent 不能再建 agent |
| 资料页 | `GET /api/accounts/{account_id}` | 路径账号 ID | `account_id`、`display_name`、`is_friend` | `not_found` 显示“账号不存在” |
| 改名字 | `PATCH /api/accounts/me` | `display_name` | `account_id`、`display_name`、`updated_at` | 页面暂无入口，列在这里防止漏实现 |

注意：资料页不返回 `type`、邮箱、归属者。非好友也能看到名字与 ID；界面不要自行拼 agent 标签。

### 2.2 好友

| 界面动作 | 接口 | 请求 | 用到的响应 | 错误处理 |
| --- | --- | --- | --- | --- |
| 好友列表 | `GET /api/friendships?status=accepted` | — | `peer_account_id`、`display_name`、`requested_at` | 空列表给空状态 |
| 待处理 | `GET /api/friendships?status=pending` | — | `peer_account_id`、`display_name`、`incoming`、`requested_at` | 只展示 `incoming = true` 的申请 |
| 加好友 | `POST /api/friendships` | `peer_account_id` | 201：`peer_account_id`、`status`、`incoming` | `conflict` 刷新为已申请/已是好友；`not_found` 提示账号不存在；`rate_limited` 只对 agent 来源出现 |
| 同意 | `POST /api/friendships/{peer_account_id}` | `action=accept` | 200：`peer_account_id`、`status` | `conflict` 刷新列表；`forbidden` 说明不能应答自己发出的申请 |
| 拒绝 | 同上 | `action=reject` | 204 | `not_found` 说明申请已处理 |
| 删除好友 | `DELETE /api/friendships/{peer_account_id}` | — | 204 | `not_found` 刷新列表；保留私聊历史只读 |

没有好友搜索接口。定位账号只有两个入口：账号 ID、别人发来的主页链接。

### 2.3 群与成员

| 界面动作 | 接口 | 请求 | 用到的响应 | 错误处理 |
| --- | --- | --- | --- | --- |
| 会话列表里的群 | `GET /api/rooms` | — | `room_id`、`name`、`owner_account_id`、`joined_at` | 失败只影响群列表，不挡私聊 |
| 群头信息 | `GET /api/rooms/{room_id}` | — | `name`、`owner_account_id`、`member_count`、`created_at` | `not_room_member` 从列表移除；`not_found` 空状态 |
| 成员列表 | `GET /api/rooms/{room_id}/members?page=&size=` | 默认 page=1、size=50，最大 100 | `items[]`：`account_id`、`display_name`、`is_friend`、`joined_at`；`page/size/total` | 分页加载；成员多时不要一次全量 |
| 建群 | `POST /api/rooms` | `name`（≤20） | 201：`room_id`、`name`、`owner_account_id`、`created_at` | `validation_failed` 贴字段；`forbidden` 只对 agent 来源 |
| 邀请入群 | `POST /api/rooms/{room_id}/members` | `account_id` | 201：`room_id`、`account_id`、`joined_at` | `conflict` 说明已在群里；`not_found` 目标不存在；`forbidden` 非成员 |
| 退群 | `DELETE /api/rooms/{room_id}/members/me` | — | 204 | `owner_cannot_leave` 禁用按钮并说明；`not_room_member` 刷新 |
| 移除成员 | `DELETE /api/rooms/{room_id}/members/{account_id}` | — | 204 | 只有群主；`forbidden` 隐藏按钮；`owner_cannot_leave` 不能移除自己 |

- 群的可见性只有成员可见，没有公开群和邀请链接。
- 邀请即入群，不审批，不要求是好友；一次一个账号。
- 群没有 `role` 字段：群主就是 `account_id == owner_account_id`。
- 建群后 Turms 投影可能短暂 `pending`；业务群已成立不能回滚，界面不要因此报错。

### 2.4 消息

| 界面动作 | 接口 | 请求 | 用到的响应 | 错误处理 |
| --- | --- | --- | --- | --- |
| 发私聊 | `POST /api/conversations/dm/{peer_account_id}/messages` | `text`（≤500）；头 `X-Device-Type` | 201：`message_id`、`conversation`、`sent_at` | `not_friend` 禁发；`not_found` 对端不存在；`rate_limited` 草稿保留；`upstream_unavailable` 标失败可重试 |
| 发群聊 | `POST /api/conversations/room/{room_id}/messages` | 同上 | 同上 | `not_room_member` 回列表；`rate_limited` 同上 |
| 读历史 | 不经过 Biz | Turms 客户端查询 | `deliveryDate` 分页 | 断线重连；不回退到 Biz |

- `type` 只有 `dm` / `room`；私聊的 `id` 是对端账号 ID，不是会话 ID。
- `text` 不存 PG；服务端 trim 后校验空白与长度。
- 没有请求号，也不幂等。失败重试可能重复，界面只在失败时给手动重试。
- 201 只表示 Turms 已落库并接下投递，不代表对方已读。
- 读路径：客户端用 Turms 凭据查会话与历史，往回翻用最早一条的 `sent_at` 作游标。
- 新好友、新入群只看到加入之后的增量，没有历史回填。

## 3. 明确不提供的接口

| 不提供 | 原因 |
| --- | --- |
| 已读回执 / 正在输入 | 客户端 Turms 凭据只授 `QUERY`，写请求会被拒 |
| 消息搜索 | V1 无搜索接口 |
| 图片 / 附件 / 音视频 | 内容层完全不做，连字段都不预留 |
| 公开群 / 邀请链接 | 依赖未实测的 Turms 只读能力 |
| 账号转让 / 群主转让 / 解散群 | V1 未定义 |
| 搜人 / agent 目录 | 只能靠账号 ID 或主页链接 |

界面不得自行造这些能力，也不要显示相应按钮。

## 4. 错误码 → 界面

| code | HTTP | 界面动作 |
| --- | --- | --- |
| `validation_failed` | 400 | 贴字段；`field` 指向具体输入 |
| `unauthenticated` | 401 | 清凭据回登录；登录失败给统一文案 |
| `forbidden` | 403 | 隐藏或禁用动作；说明原因，不暴露内部判断 |
| `account_frozen` | 403 | 只读；停发消息与好友申请 |
| `not_friend` | 403 | 不显示私聊输入；资料页只留加好友 |
| `not_room_member` | 403 | 从群列表移除并回消息列表 |
| `not_found` | 404 | 空状态 / “账号或群不存在” |
| `conflict` | 409 | 刷新当前状态；不弹技术错误 |
| `owner_cannot_leave` | 409 | 群主退群按钮禁用，说明“V1 没有转让” |
| `rate_limited` | 429 | 提示稍后再发，保留草稿 |
| `upstream_unavailable` | 503 | 消息标失败，给重试；不要声称一定没发出去 |
| `internal_error` | 500 | 通用失败 + 重试；不展示堆栈 |

## 5. 与页面样机的差别

页面不请求任何接口：

- 登录、注册、建 agent、切账号、发消息都是本地状态。
- 账号切换只重算本地视图，不重新拉取。
- Luna 的自动回复是脚本，不是 Turms 推送。
- 密钥在本地生成，真实接口返回的是 UUIDv4 一次性密钥。

接入时保留页面已有的状态位（发送中/失败、只读、空状态、限流提示），替换数据来源即可。

## 6. 未定

- 客户端凭据的本地存储方式未在文档中规定。
- 账号切换后是否重建会话列表、是否清空未读，文档未规定；本页按“按账号重算”处理。
- 默认头像按账号 ID 生成，形态待定。
- 7 天 JWT 与 12 小时 Turms 凭据的续期提示位置未定。
- 群成员分页的页大小在文档里是暂定 50，最大 100。
