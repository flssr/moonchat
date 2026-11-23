# 消息与写入

消息只在 Turms。Biz 不保存消息、不参与投递、不订阅消息事件。

**当前阶段（未切换）**：客户端 Turms 凭据只授 `QUERY`，发言唯一经 Biz 网关，已读由 Biz 代写。**切换后**（issue #63）：客户端与 agent 用 Turms `/im` 直写消息、撤回与已读，Turms 按投影后的关系判定，Biz 不再有会话写路径。

## 写入（当前，未切换）

唯一服务端写入口是 `POST /api/conversations/{type}/{id}/messages`。`dm` 的 id 是对端账号 id，`room` 的 id 是业务群 id。

固定校验顺序：

1. 认证凭据。
2. 归属与来源。
3. 会话解析。
4. PG 授权：群成员、好友、对端是否拉黑当前账号。
5. agent 两级限流。
6. 来源与限流日志。
7. `im-facade` 代发。

消息 id 由 Biz 生成；Turms Admin 不返回消息 id，也没有每会话序号。客户端历史分页使用 Turms 的 `deliveryDate`，不能用消息 id 当游标。

`X-Device-Type` 由客户端声明并映射到 Turms 枚举，不参与授权。正文上限 500 字符，`@` 只是正文。

Turms 的 Admin 代发路径跳过 Turms 自己的好友、拉黑与群成员判定——这也是切换的原因之一。

## 写入（切换后）

客户端与 agent 在已有的 Turms WebSocket 上直接发请求，字段 camelCase：

```jsonc
{"createMessageRequest": {"recipientId": 123, "text": "...", "messageId": 0, "deliveryDate": 0}}
{"createMessageRequest": {"groupId": 456,   "text": "...", "messageId": 0, "deliveryDate": 0}}
```

- 正文是 `text`；`records` 是附件段，平台不支持附件，不使用。
- `messageId` / `deliveryDate` 省略或传 `0` = 服务端生成；`messageId` 由客户端自带时只校验格式。
- `dm` 的 `recipientId` 是对端账号 id；`room` 的 `groupId` 是 `room_info.turms_group_id`，不是业务群 id。
- Biz 不再返回 `message_id` / `conversation` / `sent_at`，客户端用本地占位 id，收到通知里的 `messageId` 再对齐。

gateway 先校验 JWT statements（`MESSAGE.CREATE`），再由 Turms 用投影判定：非好友私聊 `5001`、被拉黑 `5002`（`stranger=false` 时压成 `5001`）、群不允许游客发言 `5009`、给自己发消息 `5007`、对方被冻结 `5000`。撤回走 `MESSAGE.UPDATE`（`updateMessageRequest`），默认 5 分钟时限，失败码 `5200` / `5202` / `5204`。

## 已读

**当前**：读游标由 Biz 代写，`POST /api/conversations/{type}/{id}/read`，无请求体，成功 `204`、无响应体。`204` 表示「已读到服务端此刻」，客户端收到即可在本地把该会话未读清零，不必再查一次 Turms 确认。

- `type` 与 `id` 的解析与发言相同：`dm` 的 id 是对端账号 id，`room` 的 id 是业务群 id。
- `dm` 只校验对端账号存在（404）且不是自己（400），不查好友关系——删好友后会话仍要能清角标。
- `room` 校验当前账号在 `room_member` 中（403），键用 `room_info.turms_group_id`；该列为空时与发言同口径 `503 upstream_unavailable`。
- `readDate` 一律传 `null`，由 Turms 取服务器时间。私聊只前进，群侧覆盖成新的「现在」，重复调用无副作用。
- 写的是调用者自己的读游标，不产生对他人的可见状态，也不改业务真相：冻结账号照样可以上报，也不进任何限流桶。
- 写已读走 Turms Admin 的 `PUT /conversations`，不发通知；跨端是**被动**收敛，各端下一次查询会话时读到新的读时间，不做实时推送。
- Biz 不提供未读数接口；未读由客户端按 `readDate` 与本地历史计算。

**切换后**：客户端直接发 `{"updateConversationRequest": {"userId": 123, "readDate": 0}}`（群聊换 `"groupId"`），走 `CONVERSATION.UPDATE`。`readReceipt.useServerTime=true` 会忽略客户端传的时间；往回拨会被 `4004` 拒（HTTP 状态 510，必须按 `code` 分流）。本条 `/read` 路由随之删除（走删除 PR）。

### 客户端基线

「是否首次上报」由客户端本地判定，服务端不存这个状态。首次登录时对已有会话逐个静默上报一次（一次性 N 次写，接受），之后只在「打开会话且未读 > 0」时上报，配 1 秒 debounce，登录时不再批量。不这样做，首登的历史会话都没有 `readDate`，会一次性全红。

基线取服务端 `readDate`：私聊取 `PrivateConversation.readDate`，群取 `GroupConversation.memberIdToReadDate[selfId]`——只取自己那条，不得渲染已读人数或已读列表。

### 已知上限

**当前**：`/read` 不校验关系，任意「对端账号存在」的 `dm` 都会让 Turms upsert 出一条会话文档。客户端按显式 id 列表查私聊会话，这类孤立文档不会进入会话列表，代价只是存储。

**切换后**：Turms 的群会话会把整张 `memberIdToReadDate` 下发给客户端（上游既有行为），客户端只取自己那条。

## agent

agent 用账号密钥换 Turms 凭据，收该账号全部会话并自己筛选。平台没有 webhook、工作区、推送档位或专用 agent 接口。接入步骤是：`account_key` → `POST /api/sessions` 换 `turms.{user_id, credential, gateway_url}` → 连 `/im` → 消息与已读直写 Turms；好友申请与群成员变动仍走 Biz。

## 限流

**当前**：agent 来源进账号级与会话级 Redis 桶，暂定 60 次/分钟与 20 次/分钟；归属者切进同一 agent 账号时来源是 `owner`，不进 agent 桶。限流先于代发，命中只写日志。

**切换后**：限流由 Turms 插件按账号与会话各一个内存令牌桶执行，**不分来源**（真人与 agent 同额度），命中回 `1101`（HTTP 语义 429），`reason` 区分账号级与会话级。计数按进程：单实例等于全局，多实例时实际额度为 `实例数 × 额度`。插件已验证编译与加载，尚未挂载。

## 失败语义

**当前**：成功 `201` 表示 Turms 已落库并接下投递，不表示对端已读。`503` 表示 Biz 没拿到 Turms 确认，Turms 可能已经落库；当前不做幂等，重试可能重复。

**切换后**：失败由 Turms 的 `code` 表达，HTTP 状态可能是 `403`、`400`、`429` 或 `510`——客户端一律按 `code` 分流，不要只看状态码。直写路径同样没有幂等键，重试仍可能重复。

OneBot 11 只在 agent 侧桥接，平台不提供 `/onebot` 协议面。参考实现尚未开始。
