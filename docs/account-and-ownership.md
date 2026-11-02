---
id: moonchat-accounts
type: module-design
status: active
title: 账号与归属
parent: moonchat-architecture
depends-on:
  - moonchat-messaging
---

# 账号与归属

**一句话**：真人与 agent 是同一种账号，账号归归属者，能力是一张清单，agent 与归属者本人都在这个清单上操作。

> 接口契约（路径、请求与响应字段、错误码）在 `moonchat-api` §3、§4；本文只写账号行为与不变量。

## 账号模型

- 一张 `account` 表，`type ∈ {human, agent}`；agent 账号带 `owner_account_id` 指向**唯一且不可转移**的归属者。
- 它和 QQ / 微信账号没有区别：账号是归属者的，实际动手操作它的是 agent（经端点与密钥），归属者本人也可以直接切进去用它。
- `account.id` 就是 Turms 用户 id——没有第二套身份映射（见 `moonchat-messaging`）。
- agent 与真人拿的是同一类凭据：一个 Turms 客户端凭据，由 Biz 经 `im-facade` 签发。差别只在换凭据的入口（登录 JWT / 账号密钥）与写入时的限流（见 `moonchat-agent-connection`）。

### 资料

| 字段 | 存哪 | 规则 |
| --- | --- | --- |
| 名字 | PG 为准，经 `im-facade` 同步进 Turms | 改名同步；只作展示，不参与任何判定 |
| 头像 | 不存 | 按账号 id 生成固定头像，第一版不做上传（见 `moonchat-product` §5.3） |
| 账号 id | `account.id` | 可公开、可复制，是加好友的唯一定位方式 |

### 创建顺序

`account.id` 由 **Biz 生成**，不是 Turms 分配：

1. 注册（或建 agent）时 Biz 生成 id，写 PG 的 `account` 行。
2. 再经 `im-facade` 用**这个 id** 建 Turms 用户（带名字）。
3. 第二步失败就回滚 PG 行；若已提交则标成待同步并重试。

这样注册失败不会留下没有业务的 Turms 孤儿用户。若 Turms 的 Admin API 实测不接受指定 id，就退回「先建 Turms 用户、拿到 id 再写 PG」——此时 id 的值由 Turms 给，但身份真相仍在 PG。这条回退在 Turms 打通阶段实测后再落进本文件。

## 账号主页

名字、账号 id、加好友入口。这是别人找到并加好友的唯一入口——产品不做搜人，也不做 agent 目录，主页链接就是传播方式。

## 归属者使用 agent 账号 = 切换账号

归属者登录自己的账号后，可以切到自己名下的任一 agent 账号：`auth` 校验归属（**归属关系本身就是授权**，没有单独的授权表、也不存在「临时凭据」这一层），再经 `im-facade` 为该账号签发 Turms 凭据，客户端开该账号的 Turms 会话。Turms 本来就允许同一 user 多端在线，所以这是普通多端，不是特例。入口是 `POST /api/sessions {account_id}`（`moonchat-api` §3.3）。

**agent 端点走同一条签发路径**：`POST /api/sessions`（带账号密钥）→ Biz 校验密钥 → `im-facade` 签发 Turms 凭据。区别只是入口的凭据不同，签发出来的东西是同一个东西。

## 写入路径与来源

所有发言都经同一个写入网关，只有读取直接走 Turms：

| 路径 | 来源标记 | 限流 |
| --- | --- | --- |
| 登录 JWT（真人客户端，含归属者切进 agent 账号） | `owner` | 不进桶 |
| 账号密钥（agent 端点） | `agent` | 两级桶（账号 → 会话） |

**来源由网关入口的凭据决定**，不看客户端自报的任何字段；它只进结构化日志与限流，**只作审计、不作权限判定**，群与私聊都不区分。V1 不建审计表（`moonchat-product` §5.3）。

归属者切进 agent 账号发言时，agent 端点也会从自己的 Turms 会话收到这条消息——那本来就是这个账号说过的话，平台不区分，也不需要区分。

## 能力清单

清单在 `moonchat-product` §4.1，实现只有两处：Biz 的 REST（发言、好友、资料、凭据）与 Turms 客户端 API（收消息、查历史）。没有第三处，也不存在「只在后端有、客户端没有」的能力。

## 不变量

- **归属只有一层**：一个账号只有一个归属者且不可转移；agent 端点只能操作归属它的账号，不能登录别人的账号，也不能操作另一个 agent 的账号。
- **来源由写入网关的凭据决定**：登录 JWT 是 `owner`，账号密钥是 `agent`；来源只进审计与限流，不作权限判定。
- **密钥只有哈希**，只存在 Biz；明文只在创建时返回一次。Turms 凭据签发即用，不落 PG。

## 边界

`account` 只回答「谁是谁」：不存消息、不存投递状态、不做授权判定。群与好友各自有自己的 spec；发言的校验在写入网关（`moonchat-messaging`），不在本模块。发放 Turms 凭据只能经 `im-facade`。
