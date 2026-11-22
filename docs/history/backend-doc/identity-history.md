# 身份与认证决策历史

## 介绍

记录账号、归属、登录与 Turms 凭据的实现决策，遵循 [历史决策规范](../README.md)。

## 写入模板

```text
<议题>

<本地时间与时区>   [<UTC 时间>]

<决策>：...

<原因>：...
```

### 冻结 statements 保留清角标能力

2026-11-22 23:57 CST   [2026-11-22 15:57 UTC]

决策：修正上一条「冻结只签 `QUERY *`」——切换后冻结账号的 statements 是 `QUERY *` + `UPDATE CONVERSATION`，能清角标但发不出消息。放开写权限与「冻结时用 `PUT /users/online-statuses` 踢掉存量会话」必须在同一次上线里完成。

原因：`/read` 这条 Biz 路由在切换后删除，冻结账号不发消息时仍需要能清掉未读，否则角标永久挂着、看起来像数据坏了；把 `CONVERSATION.UPDATE` 留给冻结账号是用权限位表达「读游标不是业务写入」。踢会话这一步不能省：JWT 登录路径不查 `isActive`，冻结前签出的凭据最长 12 小时仍带写权限。另记一条运维事实：statements 写错不是静默降权，`PolicyDeserializer` 会直接抛 `IllegalPolicyException`，签发侧拼错一条就是全量登不上或发不出。

### Turms 凭据分两套 statements

2026-11-22 19:55 CST   [2026-11-22 11:55 UTC]

决策：Turms 凭据 JWT 的 statements 定为两套——正常账号 `QUERY *` + `CREATE MESSAGE` + `UPDATE MESSAGE` + `UPDATE CONVERSATION`；冻结账号只签 `QUERY *`。本轮不切换：当前仍只签 `QUERY`，随客户端接入直写时一起放开。

原因：客户端切到直写 Turms 后，发消息、撤回、直写已读都只能靠 Turms 侧的 statements 放行（`MESSAGE.CREATE` / `MESSAGE.UPDATE` / `CONVERSATION.UPDATE`）。冻结不依赖 Turms 的 `isActive`——JWT 登录路径不查它，所以「不能写」只能由签发侧不给写权限位来保证；踢掉存量会话是配套动作，客户端切换时一并落地。

### 头像落库

2026-11-17 17:19 CET   [2026-11-17 16:19 UTC]

决策：`account_info` 增加可空 `avatar text`（issue #10），存平台内置头像的固定 key：真人 `female_01..03` / `male_01..03`，agent `agent_blue` / `agent_pink` / `agent_gold`；`null` 表示客户端按 id 生成的首字头像。写入口是单独的 `PUT /api/accounts/me/avatar`（整枚替换，`null` 清空），按 `account.type` 校验 key 是否属于这一侧，非法回 400 `validation_failed` + `field=avatar`。登录、换凭据、`mine`、资料页、好友列表、群成员都带 `avatar`。创建 agent 时服务端按新账号 id 在三张里轮换分配默认头像。不做上传、不做缩略图、不投影 Turms。

原因：头像之前只存本机偏好，换设备或对方视角都看不到；服务端存 key 才能一致。没有把 `avatar` 塞进 `PUT /api/accounts/me`：那个接口是全量提交，选头像会顺带提交昵称并触发 Turms 改名，所以单独一条幂等替换的路由更安全。

### 资料字段与接口方法

2026-11-14 20:40 CST   [2026-11-14 12:40 UTC]

决策：`account_info` 增加 `gender`（`text not null default 'private'`，枚举 male/female/other/private）与 `birthday`（`date` 可空，null 即未设置）；资料写入改为 `PUT /api/accounts/me`，三字段全量提交；另加 `GET /api/accounts/me` 供前端回填。

原因：前端资料编辑器已经上线，需要后端有对应字段与读接口；三字段一起提交本来就是幂等的替换语义，用 `PATCH` 名不副实，也避免出现部分更新与“缺省 vs null”的三态判定。`gender` 默认 `private` 让老行在加列时自动回填，建号路径零改动；生日没有合理默认值，只能留 null。

### 前端资料字段

2026-11-12 21:43 CET   [2026-11-12 20:43 UTC]

决策：客户端先上线性别、生日与星座编辑，保存仍只发送现有资料接口。

原因：先把界面与本地交互收口；后端字段尚未实现，因此该能力当前是已知的前后端缺口，而不是已完成能力。

### 归属者切账号

2026-11-05 00:27 CST   [2026-11-04 16:27 UTC]

决策：归属者切进 agent 账号时，`POST /api/sessions` 同时签发该账号的登录 JWT 与 Turms 凭据。

原因：只发 Turms 凭据无法让切号后的客户端继续调用 Biz，来源 `owner` 也就不能成立。

### 账号 id

2026-11-04 08:50 CST   [2026-11-04 00:50 UTC]

决策：账号 id 序列从 `100000000` 起。

原因：Turms 开发档生成 `1..1000` 假用户，冒烟占用 `900000..1100000`；从 1 起会直接撞号。

### 认证解析与响应

2026-11-04 10:52 CST   [2026-11-04 02:52 UTC]

决策：使用 `HandlerMethodArgumentResolver` 解析当前账号，不写成过滤器；响应只走 DTO 白名单。

原因：过滤器异常到不了统一异常处理，401 会变 500；实体直出会泄漏邮箱和凭据哈希。
