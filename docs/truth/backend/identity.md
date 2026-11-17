# 账号与认证

真人与 agent 共用 `account` 与 `account_info`。`account.id` 由 Biz 生成并同步作为 Turms 用户 id；agent 的 `owner_account_id` 唯一、不可转移。

## 建号

注册真人或创建 agent 时，Biz 先写 PG，再在同一事务内用同一个 id 建 Turms 用户。Turms 未确认就整笔回滚，不留下业务行或孤儿账号。账号 id 序列从 `100000000` 开始，避开 Turms 开发数据与冒烟脚本号段。

agent 明文的 UUIDv4 密钥只在创建响应出现一次；数据库存带算法前缀的 HMAC-SHA256 哈希，pepper 由部署配置提供且没有默认值。

创建 agent 时还会同时建立归属者与该 agent 的 accepted 好友关系，规则见 [`friendship.md`](friendship.md)。

## 登录与会话

| 入口 | 输入 | 结果 |
| --- | --- | --- |
| 登录 | 邮箱与密码 | 7 天登录 JWT 与当前账号资料 |
| 切账号 | 登录 JWT + `account_id` | 该 agent 的 Turms 凭据，并带新的登录 JWT |
| agent 接入 | `account_key` | 同一类 Turms 凭据与账号资料 |

当前账号由 `HandlerMethodArgumentResolver` 解析。请求头中的 JWT 产生 `owner` 来源，账号密钥产生 `agent` 来源。

Turms 凭据是 Biz 签发的 JWT，payload 带 `sub`、`exp`、`authenticated` 和只允许 `QUERY` 的 statements。客户端能收消息与查历史，不能直接写消息或建群。

## 资料

后端保存名字、状态、性别、生日、头像与认证哈希。资料页向其他账号返回名字、账号 id、头像与是否好友，不返回邮箱、类型、归属者、性别或生日。

- `GET /api/accounts/me` 返回本人完整资料：`account_id`、`display_name`、`gender`、`birthday`、`avatar`、`updated_at`。登录、切账号与 `GET /api/accounts/mine` 都只回鉴权与列表字段，不回资料；前端编辑页用这个接口回填。
- `PUT /api/accounts/me` 是**全量提交**：`display_name`、`gender`、`birthday` 三个字段都必传，不是部分更新。响应与 `GET` 同形。
- `gender` 取 `male` / `female` / `other` / `private`，默认 `private`。默认值由 `account_info.gender not null default 'private'` 提供，建号路径不写这一列；`private` 同时表示“没选”与“选了保密”，这是有意的，不另设标记。
- `birthday` 可空，`YYYY-MM-DD`；`null` 就是未设置，默认值也是 `null`，不捏造日期。传 `null` 会把已设置的生日清空。
- `avatar` 存在 `account_info.avatar`，可空；值是平台内置头像的固定 key，不是 URL：真人 `female_01..03` / `male_01..03`，agent `agent_blue` / `agent_pink` / `agent_gold`。`null` 表示客户端按账号 id 生成首字头像。不做上传、不做缩略图、不投影 Turms。
- 头像写入口是 `PUT /api/accounts/me/avatar`（整枚替换，`null` 清回生成的头像，响应回显 `avatar`）：真人只能用真人那 6 个 key、agent 只能用 agent 那 3 个，跨表按 `account.type` 在应用层判，非法 key 回 400 `validation_failed` 且 `field=avatar`。
- 创建 agent 时服务端按新账号 id 在三张 agent 头像里轮换分配一枚默认头像，所以新 agent 不会停在首字头像上。
- 带 `avatar` 的读接口：登录 #2、换 Turms 凭据 #3、`GET /api/accounts/mine` #4、资料页 #7、好友列表 #8、群成员 #15。
- 名字未变时不同步 Turms；变了才调 Admin 改名并写 `turms_sync_state = 'synced'`，未确认整笔回滚回 503。
- 校验失败一律 400 且带 `field`：名字空白或超过 20、枚举外性别、生日格式不对、日历上不存在或晚于今天、头像 key 不在平台这一套或跨类型。多个字段同时违规时只报其中一条，顺序不保证。

