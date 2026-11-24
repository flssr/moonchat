# 消息与写入

消息只在 Turms。Biz 不保存消息、不参与投递、不订阅消息事件。

**当前阶段（客户端直写）**：`MONDCHAT_TURMS_WRITE_CREDENTIAL_ENABLED=true` 时客户端/agent 的 Turms 凭据含 `MESSAGE.CREATE/UPDATE` 与 `CONVERSATION.UPDATE`，消息、已读与撤回经各自的 `/im` 直写；Turms 按投影后的关系判定，生产 `allowSendMessagesToStranger=false` 已生效。Biz 的 REST 写路径只留给未升级的旧客户端，P4 删除（issue #63）。

## 旧写入路径（Biz 代发，P4 删除）

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

Turms 的 Admin 代发路径跳过 Turms 自己的好友、拉黑与群成员判定；所以只有未升级的旧客户端还走这里。

## 写入（当前，直写）

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

**当前**：客户端直接发 `{"updateConversationRequest": {"userId": 123, "readDate": 0}}`（群聊换 `"groupId"`），走 `CONVERSATION.UPDATE`。`readReceipt.useServerTime=true` 会忽略客户端传的时间；往回拨会被 `4004` 拒（HTTP 状态 510，必须按 `code` 分流）。触发时机：打开会话、窗口回到前台、正看着会话收到新消息，同一会话 1 秒去抖。

旧客户端的 `POST /api/conversations/{type}/{id}/read` 保留到 P4 删除，语义：

- `type` 与 `id` 的解析与发言相同：`dm` 的 id 是对端账号 id，`room` 的 id 是业务群 id。
- `dm` 只校验对端账号存在（404）且不是自己（400），不查好友关系——删好友后会话仍要能清角标。
- `room` 校验当前账号在 `room_member` 中（403），键用 `room_info.turms_group_id`；该列为空时与发言同口径 `503 upstream_unavailable`。
- `readDate` 一律传 `null`，由 Turms 取服务器时间。私聊只前进，群侧覆盖成新的「现在」，重复调用无副作用。
- 写的是调用者自己的读游标，不产生对他人的可见状态，也不改业务真相：冻结账号照样可以上报，也不进任何限流桶。
- 写已读走 Turms Admin 的 `PUT /conversations`，不发通知；跨端是**被动**收敛，各端下一次查询会话时读到新的读时间，不做实时推送。
- Biz 不提供未读数接口；未读由客户端按基线（私聊本机、群 Turms）与本地历史计算。

### 客户端基线

「是否首次上报」由客户端本地判定，服务端不存这个状态。首次登录时对已有会话逐个静默上报一次（一次性 N 次写，接受），之后只在「打开会话且未读 > 0」时上报，配 1 秒 debounce，登录时不再批量。不这样做，首登的历史会话都没有 `readDate`，会一次性全红。

基线：私聊用**本机已读时间**（随 `cache.json` 的 `read_dates` 落盘）——Turms 的 `QUERY_CONVERSATIONS_REQUEST` 只查得到「对方对我的会话」，`readDate` 是对方的，不能当自己的基线（#37）；群取 `GroupConversation.memberIdToReadDate[selfId]`，只取自己那条，不渲染已读人数或已读列表。

### 已知上限

旧 `/read` 路径（P4 删除）不校验关系，任意「对端账号存在」的 `dm` 都会让 Turms upsert 出一条会话文档；客户端按显式 id 列表查私聊会话，这类孤立文档不会进入会话列表，代价只是存储。

Turms 的群会话会把整张 `memberIdToReadDate` 下发给客户端（上游既有行为），客户端只取自己那条。

## agent

agent 用账号密钥换 Turms 凭据，收该账号全部会话并自己筛选。平台没有 webhook、工作区、推送档位或专用 agent 接口。接入步骤是：`account_key` → `POST /api/sessions` 换 `turms.{user_id, credential, gateway_url}` → 连 `/im` → 消息与已读直写 Turms；好友申请与群成员变动仍走 Biz。

## 限流

**当前**：客户端直写由 Turms 插件按账号与会话各一个内存令牌桶执行，**不分来源**（真人与 agent 同额度），命中回 `1101`（HTTP 语义 429），`reason` 区分账号级与会话级；插件已挂载并实测触发（实际阈值见 #79）。计数按进程：单实例等于全局，多实例时实际额度为 `实例数 × 额度`。

旧 REST 路径仍走 Biz 的 Redis 桶（账号 60 次/分钟、会话 20 次/分钟，只对 agent 来源计数），P4 随路由删除。

## 失败语义

**当前（直写）**：失败由 Turms 的 `code` 表达，HTTP 状态可能是 `403`、`400`、`429` 或 `510`——客户端一律按 `code` 分流，不要只看状态码。直写路径没有幂等键，重试可能重复。

旧 REST 路径（P4 删除）成功 `201` 表示 Turms 已落库并接下投递，不表示对端已读；`503` 表示 Biz 没拿到 Turms 确认，Turms 可能已经落库。

OneBot 11 只在 agent 侧桥接，平台不提供 `/onebot` 协议面。参考实现尚未开始。
