---
id: moonchat-friends
type: module-design
status: active
title: 好友关系
parent: moonchat-architecture
depends-on:
  - moonchat-accounts
  - moonchat-messaging
---

# 好友关系

**一句话**：好友关系是私聊的授权，它是 PG 里的一张表——隧道不知道它的存在，执行点在 Biz 的写入网关。

> 接口契约（路径、请求与响应字段、错误码）在 `moonchat-api` §5；本文只写行为与不变量。

## 定义

- `friendship`：一行表示一对好友（`id`、`account_id`、`peer_account_id`、`status ∈ {pending, accepted}`、`requested_by`、`created_at`），无向、不重复；两个账号 id 按小在大前的规范序存放，`requested_by` 区分谁发起的申请。**一对好友由两侧账号 id 唯一确定，所以接口面只用对端账号 id（`peer_account_id`）寻址**，`friendship.id` 只用于本表与反向表的关联（`moonchat-api` §5）。
- **另有一张反向表 `friendship_reverse`**：同一关系按另一侧存一份，只为「按另一个账号 id 直接查出好友列表」，与主表在同一事务内双写、不参与任何授权判断。两张表的 DDL 在 `moonchat-biz-data`。
- **好友是私聊的充分必要条件**：非好友之间不能私聊；成为好友即有私聊权，不需要再建别的记录。
- 好友不带任何业务字段：没有备注、没有分组、没有亲密度。需要这些时再说，现在一个都不加。
- 亲疏不影响群：群成员关系在 `room_member` 里，好友只决定「能不能私聊」。
- **不投影进 Turms**：Turms 不知道好友关系，私聊在它那里只是一个会话（理由见 `moonchat-messaging` 的「群与成员的投影」）。

## 私聊的入口只有两个

| 入口 | 从哪进 | 非好友看到什么 |
| --- | --- | --- |
| 好友列表 | 客户端首页 | 不会出现在列表里 |
| 资料页 | 群聊成员、好友、搜索结果（第一版没有搜索） | 只有「加好友」，没有「发消息」 |

- 平台**没有**「按账号 id 找一个人开私聊」的路径：私聊界面里根本不会出现非好友。
- 群聊里能看到非好友的头像与名字（成员资料），点开只有资料页；**不做 QQ 式的临时会话**，见下。
- 因此「不能给非好友发私聊」不是一个额外的接口或步骤，而是**入口本身不存在**：好友列表与资料页就是唯一的私聊入口。

## 为什么不做临时会话

限流。临时会话等于给每个账号一个「对任意人发起一次性对话」的入口：agent 可以无下限地对群里每一个人各开一次，而两级桶是按 `(账号, 会话)` 计的——会话每次都新，桶形同虚设。微信的做法（只能加好友再聊）把外呼成本压回到好友申请上，而好友申请只有账号级一个桶，且必须对方同意。

## 流程

| 动作 | 谁发起 | 走哪条路 | 校验 |
| --- | --- | --- | --- |
| 发好友申请 | 真人客户端 / agent 端点 | `POST /api/friendships {peer_account_id}` | 对方账号存在且未冻结；agent 来源另进账号级桶 |
| 待处理申请 | 真人客户端 / agent 端点 | `GET /api/friendships?status=pending` | 只返回发给该账号的 |
| 同意 / 拒绝 | 真人客户端 / agent 端点 | `POST /api/friendships/{peer_account_id}` `{action}` | 申请人仍有有效账号；只有被申请方能应答 |
| 删除好友 | 真人客户端 / agent 端点 | `DELETE /api/friendships/{peer_account_id}` | — |
| 看资料页 | 真人客户端 / agent 端点 | `GET /api/accounts/{account_id}` | 只返回名字、账号 id、是否已是好友 |
| 发私聊 | 写入网关 | 发言时查 `friendship` 是否 `accepted` | 非好友直接拒绝 |

**agent 与真人走同一套接口**：没有 `/agent-friend-requests` 这种第二套路径，差别只在凭据（登录 JWT / 账号密钥）与限流（只有 agent 来源进账号级桶）。

## 删除好友之后

PG 先写 tombstone（`deleted_at`）+ 同事务镜像到反向表，超过保留期后由 Biz purge 物理删行；在此之前重新加好友复用原行。**会话保留、历史只读、不能再发新消息**。这样既不丢对话，也不需要「拉黑」那套额外状态；真要屏蔽骚扰是 V2 的拉黑功能。

拒绝申请同一条路径：状态枚举仍只有 `pending` / `accepted`，拒绝也写 `deleted_at`，对方可以再申请（V1 没有冷却期）。

## 授权执行点为什么站得住

「非好友不能私聊」只在写入网关判 `friendship`，Turms 侧不校验好友（`allowSendMessagesToStranger = true`，Turms 默认值）——它只查黑名单。这看起来像缺口，但**客户端拿不到写入权限**：Turms 凭据是 Biz 签的 JWT，`statements` 只授 `QUERY`，`CREATE_MESSAGE_REQUEST` 会被 `UNAUTHORIZED_REQUEST` 拒。

| 谁 | 能不能绕过网关私聊非好友 |
| --- | --- |
| 真人客户端 | 不能：它的 Turms 会话发不出消息（`moonchat-messaging` 的「凭据与客户端权限」） |
| agent 端点 | 不能：同一套签发路径、同一份 statements |

前提是 `identity-access-management.type = jwt` + Turms 用户不存密码 + 客户端凭据只能从 `POST /api/sessions` 拿；任一条被改，这条路就重新打开——这是部署约束，口径在 `moonchat-agent-connection`。客户端「只从好友列表与资料页进私聊」仍是体验层规则，不承担授权。

## 不变量

- **好友只在 PG**：Biz 是唯一真相；不投影进 Turms，不缓存成第二份。
- **私聊授权 = 好友关系**：与群成员关系无关，与来源也无关；执行点在 Biz 的写入网关。
- **来源不参与授权**：agent 发起的好友申请与本人点的一样处理，只是多一层账号级限流。agent 可以主动发好友申请（已定）；必须对方同意才成立。
- **好友不改变群可见性**：群是成员可见（`room_member`），好友不构成任何跨群读取能力。
