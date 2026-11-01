---
id: moonchat-messaging
type: module-design
status: active
title: 消息与隧道（Turms / im-facade）
parent: moonchat-architecture
---

# 消息与隧道（Turms / im-facade）

**一句话**：Turms 是消息唯一的写入者与投递者；群与成员的真相在 PG，`im-facade` 是 Biz 把真相投影进 Turms 的唯一通道，并握着唯一一支代发消息的手。

## 职责

- **Turms 是传输引擎**：消息、会话、投递、在线状态都在它那儿（MongoDB / Redis），平台不 fork 它的存储层，也不往它塞业务字段。它同时是消息存储的**唯一写入者**。
- **群与成员的真相在 PG**（`room_info` / `room_member`），Turms 里的 group / member 只是一份投影：群的 id、名字、所有者、成员列表。字段多一个都不放，可见性与成员变更历史一律不投影。
- **好友不投影，且 Turms 被配置成不校验它**：`allowSendMessagesToStranger = true`。Turms 的私聊发送校验因此只看黑名单，好友关系由 Biz 的写入网关判定。若这项配置为 false，Turms 会去查它自己的 user relationship——而平台从不往那里投影好友，结果是所有私聊被拒。
- **消息的排序标识就是 Turms 消息 id**：客户端查历史时的游标用它，平台不另建每会话序号。它单调递增但不连续，不能拿差值算条数。
- **账号即 Turms 用户**：`account.id` 就是 Turms 用户 id（见 `moonchat-accounts`），所以群成员、私聊、消息都落在同一个主体上，没有第二套身份映射。
- `im-facade` 负责五件事：建群与改成员（投影）、签发 Turms 凭据、同步账号资料、**代发消息**。它是唯一允许调用 Turms 服务端 API 的模块。

| GroupType | 关键配置 | 产品语义 |
| --- | --- | --- |
| `member_only` | `joinStrategy = REQUIRE_INVITATION`、`guestSpeakable = false` | 成员可见、非成员不可见不可读也不可发言；成员只能由 Biz 经 `im-facade` 加入，客户端不能自行加入 |

`GroupType` 在 Turms 里是可配置实体，所以这是配置，不是代码分支。公开群需要第二个 `GroupType`，第一版不做。

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
- **客户端直连 Turms 写入是已知旁路**：客户端持 Turms 凭据，技术上可以直接对 Turms 发消息绕过网关。这不是接口，是缺口，见文末。
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
客户端用自己的 Turms 会话查，按 Turms 消息 id 做游标分页。Biz 完全不参与：既不做代理，也不做可见性判断——可见范围由 Turms 的会话与成员关系决定。

## 不变量

- **消息的唯一写入者是 Turms**；服务端的唯一写入口是写入网关经 `im-facade` 的那一支手，代发必须带已认证的 `senderId`。
- **Turms 的 `MESSAGE_CREATE` 权限只在 `im-facade` 一处持有**：不给业务侧开，也不在这一个模块之外备一份 admin 凭据。
- **群与成员的真相在 PG**：任何模块不得把 Turms 的 group / member 当业务真相，也不得为群再建第二张表。
- **投影只有一个方向**：PG → Turms。Turms 里没被 PG 记过的群，平台视为不存在：它没有成员授权、不进群列表、不被投递。
- **任何服务不得直写 Mongo 的消息集合**；服务端要读也只走 Turms 的查询接口。
- **私密群与私聊不进入任何公开读模型**，也不出现在公开查询路径上。
- **群主不能退群**：`room_info.owner_account_id` 必须常驻，V1 没有群主转让、也没有解散群；「移除成员只有群主能做」也不包含把自己移除。群主想离开，只能等 V2 定义转让或解散。

## 已知缺口

| 缺口 | 后果 | 处置 |
| --- | --- | --- |
| **客户端能直连 Turms 发消息，绕过写入网关** | 限流、来源标记与非好友私聊校验都只对守规矩的实现有效。群消息仍受 Turms 的成员校验保护 | 关掉的话要写一个拒绝客户端 `CreateMessageRequest` 的 Turms 插件；先改 spec 再做。见 `moonchat-agent-connection` |
| **Turms 不校验好友关系** | 好友校验只在写入网关；Turms 的私聊校验只剩黑名单（`allowSendMessagesToStranger = true`） | 上一条是它的补救；不投影好友是有意的（见「群与成员的投影」） |
| **客户端能自己建 Turms group** | 产生游离群——平台不认它（无授权、不投递、不进列表），所以无害，但「Turms 里有多少群」永远不等于「平台有多少群」 | 实测第 3 条：能否禁止客户端自建 group |

## Turms 打通阶段必须实测的 7 条

这些是 spec 已经假设了、但没在真实 Turms 上验证过的能力。没测之前不要按「已支持」写代码。

| # | 要去验证什么 | 成立则 | 不成立则 |
| --- | --- | --- | --- |
| 1 | Admin API 能否用**指定 id** 建用户 | 保持 `account.id` 由 Biz 生成 | 回退为 Turms 建用户后回填（见 `moonchat-accounts`） |
| 2 | Admin API 能否用**指定 id** 建 group | `room_info` 表存同一个 id | 让 Turms 生成后回填 `turms_group_id` |
| 3 | 服务端能否禁止客户端自建 group / 加成员 | 游离 group 根本不会出现 | 保留「平台不认」的口径（见缺口） |
| 4 | 能否禁止客户端侧的 `CreateMessageRequest` | 写入网关成为唯一写入路径，缺口消失 | 缺口保留（见文末） |
| 5 | **Admin API `POST /messages` 能否代发且带指定 `senderId` / `senderDeviceType`** | 写入网关成立，这是整套设计的前提 | 整条写入路径要改：退回 agent 自己当客户端直发 |
| 6 | 代发是否仍走 Turms 自己的成员与黑名单校验 | 群消息与黑名单有两道闸 | 网关必须自己补齐，且要写明 |
| 7 | 客户端历史查询能否按消息 id 范围分页 | 游标分页直接用 | 退回其它分页方式，并改客户端接口 |

## 已定的简化

- **不做消息搜索**：全站检索留到有真实检索需求时再说，避免一上手就引入索引管道与权限过滤。
- **只投影投递必需的字段**：群投影不含可见性、公告、成员变更历史；要这些字段时再说，现在一个都不加。
- **不做公开群与邀请链接**：一个 `GroupType` 覆盖第一版；公开群的「非成员可读」依赖未实测的 Turms 只读能力。
- **不做结构化 mentions**：Turms 的消息模型里没有自定义属性字段（只有 `text` 与 `records`），而上一版需要它只是为了 `mention_only` 档位。档位不存在后，`@` 只在客户端渲染层按正文识别，不落库、不传输。
- **写入经 Biz 多一跳**：Turms 不可用时发言失败，V1 不排队重试——重试由客户端决定。
