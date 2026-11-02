---
id: moonchat-messaging
type: module-design
status: active
title: 消息与隧道（Turms / im-facade）
parent: moonchat-architecture
---

# 消息与隧道（Turms / im-facade）

**一句话**：Turms 是消息唯一的写入者与投递者；群与成员的真相在 PG，`im-facade` 是 Biz 把真相投影进 Turms 的唯一通道，并握着唯一一支代发消息的手。

> 接口契约（路径、请求与响应字段、错误码）在 `moonchat-api` §6、§7；本文只写隧道行为与不变量。

## 职责

- **Turms 是传输引擎**：消息、会话、投递、在线状态都在它那儿（MongoDB / Redis），平台不 fork 它的存储层，也不往它塞业务字段。它同时是消息存储的**唯一写入者**。
- **群与成员的真相在 PG**（`room_info` / `room_member`），Turms 里的 group / member 只是一份投影：群的 id、名字、所有者、成员列表。字段多一个都不放，可见性与成员变更历史一律不投影。
- **好友不投影，且 Turms 被配置成不校验它**：`allowSendMessagesToStranger = true`。Turms 的私聊发送校验因此只看黑名单，好友关系由 Biz 的写入网关判定。若这项配置为 false，Turms 会去查它自己的 user relationship——而平台从不往那里投影好友，结果是所有私聊被拒。
- **消息的标识就是 Turms 消息 id**：它单调递增但不连续，不能拿差值算条数，平台不另建每会话序号。但它**不是分页游标**：Turms 的客户端查询只接受 `deliveryDateStart/End` + `maxCount` + `descending`，没有消息 id 范围参数（`QueryMessagesRequest`）。所以客户端往回翻历史用**最早一条的 `deliveryDate` 作游标**，消息 id 用于稳定标识与按 `ids` 精确查询。
- **账号即 Turms 用户**：`account.id` 就是 Turms 用户 id（见 `moonchat-accounts`），所以群成员、私聊、消息都落在同一个主体上，没有第二套身份映射。
- `im-facade` 负责五件事：建群与改成员（投影）、签发 Turms 凭据、同步账号资料、**代发消息**。它是唯一允许调用 Turms 服务端 API 的模块。

| GroupType | 关键配置 | 产品语义 |
| --- | --- | --- |
| `member_only` | `joinStrategy = REQUIRE_INVITATION`、`guestSpeakable = false` | 成员可见、非成员不可见不可读也不可发言；成员只能由 Biz 经 `im-facade` 加入，客户端不能自行加入 |

`GroupType` 在 Turms 里是可配置实体，所以这是配置，不是代码分支。公开群需要第二个 `GroupType`，第一版不做。

## 凭据与客户端权限

客户端的 Turms 凭据一律由 Biz 经 `im-facade` 签发，形态是 **JWT**：Turms 侧配 `identity-access-management.type = jwt`，用与 Biz 共享的 HMAC 密钥验签，要求 `sub` 等于登录的 userId。

JWT 里的 `statements` claim 决定**这个客户端能发哪些请求类型**：网关的 `ClientRequestDispatcher` 对 `!session.hasPermission(requestType)` 直接返回 `UNAUTHORIZED_REQUEST`（1106）。第一版只授查询：

```json
{ "effect": "ALLOW", "actions": ["QUERY"], "resources": ["*"] }
```

于是客户端**发不出消息**（`MESSAGE` 资源的 CREATE 就是 `CREATE_MESSAGE_REQUEST`），也**建不了 group**（`GROUP` 资源的 CREATE 是 `CREATE_GROUP_REQUEST`）。**发言只能走 Biz 的写入网关，由 `im-facade` 代发**——用户照样能从客户端发消息，只是不经过客户端自己的 Turms 会话。这不是靠客户端自觉，是 Turms 在会话权限上拦的。

三条前提，缺一条这条路就断：

| 前提 | 为什么 |
| --- | --- |
| `identity-access-management.type = jwt` | 配成 `noop` / `password` 时 JWT 与 statements 都不参与，客户端可以自证身份 |
| Turms 用户的密码是一段**平台不保存也不分发**的随机值 | Turms 的 `AddUserDTO` 要求 `password` 非空且 ≤ 16 字符（实测），所以做不到“用户没有密码”；但这段随机值只有 Biz 建号时见过，客户端拿不到它，PASSWORD 模式的会话照样登不进去 |
| 客户端凭据只能从 `POST /api/sessions` 拿 | 没有第二个签发点，也就没有第二种 statements |

代价：客户端做不了 Turms 侧的写请求（已读回执、正在输入）。第一版不使用这些能力。

## 群与成员的投影

投影是「把 PG 的群与成员，复制成 Turms 能用来投递的最小结构」。Turms 要广播一条群消息、要拒绝一个非成员的发言，必须自己知道这个 group 和它的成员——这是传输引擎的内部需要，不是业务真相。

| 项 | 规则 |
| --- | --- |
| 何时写 | Biz 对 PG 的写成功之后：建群、拉人、退群、移除成员、群改名 |
| 写什么 | Turms group 的 id（回填 `turms_group_id`）、名字、`ownerId`；成员集合 |
| 不写什么 | 可见性策略、加入审批、加入时间、成员角色、来源标记、好友关系、会话设置 |
| 怎么写 | 以 PG 为准做集合对齐（full reconcile），不做事件流、不做增量补丁 |
| 失败怎么办 | 重试；仍失败就把这条 PG 记录标成待同步，后台重放。Turms 侧丢了按 PG 重建 |
| 谁读它 | 只有 Turms 自己的投递与权限逻辑。Biz 与客户端都不拿 Turms 的群与成员做业务判断 |

**为什么好友一次都不投影**：Turms 用不到它。私聊的投递只需要「会话 + 参与者」，好友关系决定的是「能不能开始这段对话」，那是 Biz 的判断；把好友投影进去只会换来一份需要同步的副本、一个 Turms 侧也能改的状态，以及一次没有必要的一致性窗口，而 Turms 从头到尾没有一处会读它。代价是 Turms 的私聊校验必须配置成不查关系（见「职责」第二条），这条配置是这套设计成立的前提，不是可选项。

## 边界

- **发送只有一支手**：`im-facade.sendMessage` 是服务端唯一的发送路径，只对 Biz 的写入网关开放，不对外、不给其他模块调用。代发时必须带写入网关已认证出的 `senderId`，`im-facade` 自己不做归属判断，也不接受「任意 sender」。
- **客户端不握写入权限**：它的 Turms JWT 只授 `QUERY`，对 `CREATE_MESSAGE_REQUEST` 会被 Turms 拒（`UNAUTHORIZED_REQUEST`）。写入只有经 Biz 的写入网关这一条路，不需要额外的 Turms 插件。
- **不把 Turms 当业务真相。** 判断「这个群有谁」「这个人能不能私聊」一律查 PG；`im-facade` 不读 Turms 的成员关系回来做业务决定，Turms 的 group 只用于投递与它自己的校验。
- **不建业务表**：群与成员的表在 Biz 的迁移里，`im-facade` 只负责投影与代发，不持有任何业务判断。
- 不直连 MongoDB 做写；只读查询优先走 Turms 的查询接口，能力不足时才在 `im-facade` 内开一条只读 Mongo 连接——连接与查询锁死在这一个模块里，仍然不允许任何写。

## 流程

**建群**
客户端 `POST /api/rooms {name}` → Biz 写 PG（`room_info` + 一行 `room_member`：调用者为所有者）→ `im-facade` 在 Turms 建 group（名字与所有者一并带过去）→ `room_info` 表回填 `turms_group_id` 作为投递句柄 → 返回房间。**Turms 若不接受指定 id，就由它生成、Biz 回填**，对外标识始终是 PG 的 `room_info.id`。

**成员变更**
拉人、移除成员、退群都是 Biz 的写：先改 PG（`room_member`），再经 `im-facade` 把新成员列表投影进 Turms。投影失败可重试，以 PG 为准重算。

**说话（唯一的写入路径）**
客户端 → `POST /api/conversations/{type}/{id}/messages` → Biz 的写入网关校验归属、会话、授权事实（群成员 / 好友）与限流 → `im-facade.sendMessage` → Turms Admin API `POST /messages`（`senderId` / `senderDeviceType` / `senderIp` / `isGroupMessage` / `targetId`）→ Turms 用自己的投影再校验一次（群成员、黑名单）、落库、广播给双方的所有在线端。

**读历史**
客户端用自己的 Turms 会话查，**用最早一条的 `deliveryDate` 做游标**往回翻（Turms 的客户端查询只接受时间范围 + `maxCount` + `descending`，没有消息 id 范围参数）。Biz 完全不参与：既不做代理，也不做可见性判断——可见范围由 Turms 的会话与成员关系决定。

## 不变量

- **消息的唯一写入者是 Turms**；服务端的唯一写入口是写入网关经 `im-facade` 的那一支手，代发必须带已认证的 `senderId`。客户端**没有 Turms 写权限**（JWT 只授 `QUERY`），所以不存在第二条写入路径。
- **Turms 的 `MESSAGE_CREATE` 权限只在 `im-facade` 一处持有**：不给业务侧开，也不在这一个模块之外备一份 admin 凭据。
- **群与成员的真相在 PG**：任何模块不得把 Turms 的 group / member 当业务真相，也不得为群再建第二张表。
- **投影只有一个方向**：PG → Turms。Turms 里没被 PG 记过的群，平台视为不存在：它没有成员授权、不进群列表、不被投递。
- **任何服务不得直写 Mongo 的消息集合**；服务端要读也只走 Turms 的查询接口。
- **私密群与私聊不进入任何公开读模型**，也不出现在公开查询路径上。
- **群主不能退群**：`room_info.owner_account_id` 必须常驻，V1 没有群主转让、也没有解散群；「移除成员只有群主能做」也不包含把自己移除。群主想离开，只能等 V2 定义转让或解散。

## 已知缺口

| 缺口 | 后果 | 处置 |
| --- | --- | --- |
| ~~客户端能直连 Turms 发消息~~ | — | **已关闭且已实测**（`infra/turms/smoke`）：JWT `statements` 只授 `QUERY`，Turms 对 `CREATE_MESSAGE_REQUEST` 回 `UNAUTHORIZED_REQUEST`（1106）；前提见「凭据与客户端权限」 |
| **Turms 不校验好友关系** | 好友校验只在写入网关；Turms 的私聊校验只剩黑名单（`allowSendMessagesToStranger = true`，Turms 默认值） | 客户端已无写入权限，非好友私聊只能经网关，由网关拒。不投影好友仍是有意的（见「群与成员的投影」） |
| ~~客户端能自己建 Turms group~~ | 已无法新建 | JWT 不授 `GROUP` 的 CREATE；Turms 里仍可能残留历史游离群，群列表依旧不等于 PG 的 `room_info` |

## Turms 打通阶段要核对的 7 条

前 6 条已在 `vendor/turms`（pinned commit）的源码里核对过，结论写进「已定结论」列——**设计按结论走，不再当假设**。但每一条都还要在真实部署上跑一遍，因为配置对不对、端到端通不通是运行时才看得见的。

| # | 要核对什么 | 已定结论（源码） | 运行时仍需确认 |
| --- | --- | --- | --- |
| 1 | Admin API 能否用**指定 id** 建用户 | **能**：`AddUserDTO.id` → `userService.addUser(id, ...)` | 建出来的 Turms 用户 id 就是 `account.id` |
| 2 | Admin API 能否用**指定 id** 建 group | **不能**：`AddGroupDTO` 没有 id 字段，`authAndCreateGroup` 也不收 id | 定案：由 Turms 生成 group id，回填 `room_info.turms_group_id` |
| 3 | 能否禁止客户端自建 group | **能**：JWT 不授 `GROUP` 的 CREATE，`ClientRequestDispatcher` 直接拒 | 真正发一个 `CREATE_GROUP_REQUEST`，确认回 `UNAUTHORIZED_REQUEST` |
| 4 | 能否禁止客户端侧的 `CreateMessageRequest` | **能**：同一机制，`MESSAGE` 的 CREATE 未授 | **已实测**：QUERY-only 凭据发消息回 1106，见下面的冒烟结果 |
| 5 | **Admin API `POST /messages` 能否代发且带指定 `senderId` / `senderDeviceType`** | **能**：`CreateMessageDTO` 带 `senderId` / `senderDeviceType` / `senderIp` / `isGroupMessage` / `targetId` / `text` / `records`，还能指定 `messageId` | 确认落库与广播给双方所有在线端 |
| 6 | 代发是否仍走 Turms 自己的成员与黑名单校验 | **是**：`MessageService.authAndSaveMessage` → `isAllowedToSendMessageToTarget`（群看投影成员，私聊看黑名单与目标状态） | 把某人移出群后，用他的 id 代发群消息应被拒 |
| 7 | 客户端历史查询能否按消息 id 范围分页 | **不能**：`QueryMessagesRequest` 只有 `ids` / `fromIds` / `deliveryDateStart/End` / `maxCount` / `descending` | 客户端分页游标改用 `deliveryDate`（见「职责」里的消息标识一条） |

三条配置项现在可以写定：`identity-access-management.type = jwt`（客户端凭据是 JWT）、`allowSendMessagesToStranger` 保持默认 `true`（好友校验只在网关）、`max-text-limit` 默认 500（与接口契约里的正文上限一致）。

**本地 standalone 冒烟结果（`infra/turms/smoke`：4 条硬断言全过，1 条 WARN）**：

| 验证项 | 结果 |
| --- | --- |
| Admin 用指定 id 建用户 | ✔ 通过；但 `password` 必填且 ≤ 16 字符，见上面前提表第 2 行 |
| Biz 签的 JWT 能登录 `/im` | ✔ 通过；**payload 必须带 `authenticated: true`**（Turms 默认 `jwt.authentication.expectation.custom-payload-claims`）＋ `sub` / `exp` / `statements`，少一个就 `2011 LOGIN_AUTHENTICATION_FAILED` |
| Admin 带 `senderId` 代发 | ✔ 落库通过，`senderDeviceType` 用枚举名（`DESKTOP`）即可 |
| 代发的消息**推送到目标客户端** | ⚠ 本地 standalone 下不稳定：消息落库正常，但 `GET /users/online-infos/sessions` 把刚登录的会话报成 `OFFLINE`、`sessions` 为空，推送因此被丢。这是本编排里 gateway → service 的在线会话同步问题，不是代发路径本身；真实环境要复测。冒烟脚本把它降级为 WARN，不计失败 |
| QUERY-only 凭据发 `CREATE_MESSAGE_REQUEST` | ✔ 被拒，`UNAUTHORIZED_REQUEST`（1106） |

**建群相关三条（指定 id、客户端自建群、代理成员校验）仍未实测**：本地没有建 `GroupType`，留给 Turms 打通阶段连同群投影一起跑。

## 已定的简化

- **不做消息搜索**：全站检索留到有真实检索需求时再说，避免一上手就引入索引管道与权限过滤。
- **只投影投递必需的字段**：群投影不含可见性、公告、成员变更历史；要这些字段时再说，现在一个都不加。
- **不做公开群与邀请链接**：一个 `GroupType` 覆盖第一版；公开群的「非成员可读」依赖未实测的 Turms 只读能力。
- **不做结构化 mentions**：Turms 的消息模型里没有自定义属性字段（只有 `text` 与 `records`），而上一版需要它只是为了 `mention_only` 档位。档位不存在后，`@` 只在客户端渲染层按正文识别，不落库、不传输。
- **写入经 Biz 多一跳**：Turms 不可用时发言失败，V1 不排队重试——重试由客户端决定。
