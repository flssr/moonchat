# 消息与写入网关决策历史

## 介绍

记录消息标识、写入网关、限流与读取路径的决策，遵循 [历史决策规范](../README.md)。

## 写入模板

```text
<议题>

<本地时间与时区>   [<UTC 时间>]

<决策>：...

<原因>：...
```

### OneBot 桥跟随 P3 直写并修复托管边界

2026-11-25 23:25 CST   [2026-11-25 15:25 UTC]

决策：把 OneBot 12 桥与 DSH 插件适配到 P3：桥的 `send_message` 经已登录的同账号 Turms `messageService.sendMessage` 直发；私聊 `targetId` 是对端账号 id，群聊把 OneBot 的业务 `group_id` 反查成 `turms_group_id`；`message_id` 取 `Response.data` 的字符串，`time` 取 `Response.timestamp`，失败保留 Turms 的 `code` 与 `reason`。群映射刷新时整体重建，退群后同时清掉双向映射。DSH 托管的桥必须收到 `config.accessToken` 对应的 `ONEBOT_ACCESS_TOKEN`；外部桥不可由插件启动、停止或重启。启用前提是写凭据开关已开、投影已回填并对账通过、`allowSendMessagesToStranger=false` 已生效。

原因：Biz 的 `/messages` 与 `/read` 已降级为旧客户端路径，桥继续走 REST 会绕过 P3 的同账号 `/im` 链路；OneBot 12 的消息 id 必须是字符串，不能丢失 Turms 返回的精度。外部桥的停止按钮经重启路由会把状态从 `external` 改成 `stopped` 再触发启动，造成重复进程和端口冲突，因此启停权限必须由服务层判定，不能只靠面板禁用按钮。

### DSH 侧应用端

2026-11-21 23:35 CST   [2026-11-21 15:35 UTC]

决策：`integrations/dsh-onebot` 做桥的应用端，一个 MondChat 私聊/群对一个 DSH 会话；收发都做成会话内工具（`mondchat_unread` / `mondchat_send`），会话创建后按 `permissionPresets` 里 `sandbox = read-only` 的档位压成只读；主动话题只对群生效，默认安静 60 分钟、每小时最多 2 次、23:00–08:00 不发声；不注册全局工具。

原因：平台不替 agent 筛消息，所以“要不要看、要不要回”必须落在 agent 自己手里，工具比哨兵文本可靠（不回复就是不调工具，没有标记泄漏）。工具只挂在插件自己建的会话里，避免污染用户的普通 DSH 会话。只读而不是无工具，是主人选的折中：读得到工作区，改不动。

### OneBot 桥的落点

2026-11-21 23:19 CST   [2026-11-21 15:19 UTC]

决策：参考实现放 `integrations/onebot`，做 OneBot 12、正向 WebSocket、默认只绑 `127.0.0.1`；桥只持 agent 账号的 Turms 会话收推送、只走写入网关发言，不实现撤回/改群名/附件段，未读与游标留给应用侧，不上报已读。

原因：平台不提供 `/onebot` 协议面是既有裁决，桥必须留在 agent 侧；OneBot 12 的 id 一律字符串，正好避开 Biz 消息 id 超过 2^53 的精度问题，而 11 的整数 id 会丢位。不替应用上报已读，是因为读游标决定“谁来判断该不该回”，那属于 agent；桥一旦顺手把已读推上去，应用就看不到未读。
### `stranger=false` 不是断线开关，门槛在客户端直写

2026-11-23 00:40 CST   [2026-11-22 16:40 UTC]

决策：更正上一条里「statements 可以最早放开」与「`allowSendMessagesToStranger=false` 必须等投影回填与对账通过」的说法。翻 `stranger=false` 对今天走 Biz 的客户端**零影响**：Biz 代发走 Admin `POST /messages` → `MessageService.saveMessage`，不经过带好友判定的 `authAndSaveMessage`，好友与拉黑仍由 Biz 在 PG 里查。真正的门槛是投影回填与对账通过——那是**客户端开始直写**的前置，不是翻开关的前置。顺序收敛成一条硬约束：`allowSendMessagesToStranger=false` 生效前不得签发含 `MESSAGE.CREATE` 的 statements。

原因：旧写法把两个不同事件的顺序写在一起，读者会以为翻开关本身有断线风险而不敢翻，或者反过来先给客户端写权限、Turms 又不校验好友，等于让持凭据客户端给任意账号发消息。实测依据：`vendor/turms` 的 `MessageService.java:1112`（`authAndSaveMessage`，客户端直写走这条）与 `:1165`（`saveMessage`，Admin 走这条）。

### 写入与限流执行点交给 Turms

2026-11-22 23:57 CST   [2026-11-22 15:57 UTC]

决策：客户端与 agent 改为在已有的 Turms WebSocket 上直发 `createMessageRequest` / `updateMessageRequest`（撤回）/ `updateConversationRequest`（已读），gateway 先校验 JWT statements，再由 Turms 按投影后的好友、拉黑与群成员判定；Biz 不再有会话写路径，`/messages` 与 `/read` 两条路由在切换后删除（26 → 24）。限流从 Biz 的 Redis 两级桶改为 Turms 插件内的账号级与会话级内存令牌桶，不分来源，命中回 `1101`，计数按进程。当前未切换：写路径与两个桶都还在 Biz，插件未挂载。

原因：Admin 代发跳过 Turms 的判定，撤回、改消息、已读这些原语只能由 Biz 自己重写；直写后这些能力由 Turms 提供，Biz 只保留真相与投影。两级限流放插件是为了在不改 vendor 的前提下复用 Turms 自己的请求分发流程，代价是计数按进程、自研代码进入消息引擎进程（加载失败会让整台 service 起不来）。切换顺序被拆成三个独立开关：statements 可以最早放开，`allowSendMessagesToStranger=false` 必须等投影回填与对账通过，插件与客户端流量同窗口启用。
### 已读上报代写

2026-11-21 22:58 CST   [2026-11-21 14:58 UTC]

决策：新增 `POST /api/conversations/{type}/{id}/read`，Biz 经 Turms Admin `PUT /conversations` 代写调用者读时间，`readDate` 传 `null` 由 Turms 取服务器时间；`dm` 只校验对端账号存在且不是自己、不查好友，`room` 校验成员且键用 `turms_group_id`（缺失回 503）；冻结账号放行，不进任何限流桶，不新增读接口或未读数接口，PG 零改动。

原因：客户端 Turms 凭据只授 `QUERY`，读时间不能由客户端直写。未读由客户端按读时间与本地历史计算，避开 Turms `withTotal` 在群会话里把本人消息和已删消息计入总数。`dm` 不查好友是为了删好友后仍然清得掉角标；放行冻结账号是因为读游标不产生对他人的可见状态，拒绝会让角标永久挂着。已知上限：任意合法账号对都会让 Turms 生成会话文档，客户端按显式 id 查私聊会话，孤立的文档不会进入列表。

### 消息标识与设备

2026-11-04 16:27 CST   [2026-11-04 08:27 UTC]

决策：消息 id 由网关生成；`sent_at` 取网关交出时刻；`X-Device-Type` 由客户端声明并入口校验。

原因：Turms Admin 不回传消息 id；设备类型只影响 Turms 的消息元数据，不参与权限判断。

### 单一写入口

2026-11-03 00:33 CST   [2026-11-02 16:33 UTC]

决策：客户端 Turms 凭据只授 `QUERY`；发言统一经 Biz 网关和 `im-facade` 代发。

原因：Turms 侧无法代表好友与来源等业务真相，若客户端能直发，所有业务校验都可绕过。

### 限流

2026-11-04 20:43 CST   [2026-11-04 12:43 UTC]

决策：只对 agent 做账号与会话两级桶，当前值 60/20 次每分钟，先校验后进桶。

原因：限制循环流量的同时不影响真人；暂定值等真实流量再调整。

### 读取与分页

2026-11-05 00:27 CST   [2026-11-04 16:27 UTC]

决策：历史由客户端直接查 Turms，以最早一条的 `deliveryDate` 为游标。

原因：Turms 不提供消息 id 范围分页，Biz 也不应代理消息读取。
