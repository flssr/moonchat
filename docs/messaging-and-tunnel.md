---
id: moonchat-messaging
type: module-design
status: active
title: 消息与隧道（Turms / im-facade）
parent: moonchat-architecture
---

# 消息与隧道（Turms / im-facade）

**一句话**：Turms 是消息、成员关系、会话的唯一真相；`im-facade` 是 Biz 通往它的唯一窄门，而门里没有发送消息的手。

## 职责

- 消息、群成员、私信会话、在线状态全部落在 Turms（MongoDB / Redis），平台不 fork 它的存储层。
- **账号即 Turms 用户**：`account.id` 就是 Turms 用户 id（见 `moonchat-accounts`），所以关注、群成员、私信、帖子、举报都落在同一个主体上，没有第二套身份映射。
- **房间 = PG 的 `room` 记录 + Turms 的 group**：`room.id ↔ group.id` 一对一，由 Biz 发起创建与删除；可见性、归属、举报只在 PG，成员关系与消息只在 Turms。
- `im-facade` 负责：建群、成员变更、账号凭据签发、只读查询。它是唯一允许调用 Turms 服务端 API 的模块。

## 边界

- **不含发送消息的能力。** 往 Turms 写消息的只有真人客户端与 `agent-connector`，两者都不经过 Biz。
- 不直连 MongoDB 做写；只读查询优先走 Turms 的查询接口，能力不足时才在 `im-facade` 内开一条只读 Mongo 连接——连接与查询锁死在这一个模块里，仍然不允许任何写。

## 流程

**人在房间说话**
客户端直接经 Turms 发消息，Turms 落库并广播。Biz 不在链路上，connector 也不参与。

**公开房间的非成员只读**
非成员读历史：Biz → `im-facade` → Turms 侧查询接口（不直连 Mongo）。若查询能力不足，退化方案是在 `im-facade` 内开一条只读 Mongo 连接。

**agent 拉取工作区历史**
agent → connector（校验归属与 offline）→ Biz → `im-facade` → Turms 历史消息查询，按 seq 升序返回，带 `sender_account_id` / `sent_at` / 正文 / `mentions`。这是 `im-facade` 的只读窄门第一次被业务侧在实时链路附近调用，但**仍然只读，仍然不发消息**，“门里没有发送的手”不变（见 `moonchat-agent-connection`）。

## 不变量

- **`im-facade` 不含发送能力**：它只能建群、改成员、签发凭据、只读查询；往 Turms 写消息的只有客户端与 `agent-connector`。
- **只读出口有两个调用方，可见范围由调用方校验**：公开房非成员只读、agent 拉取自己的工作区。`im-facade` 不自己判定权限，它只接受已校验的查询；两路都不能被拼成“读任何会话”。
- **任何服务不得直写 Mongo 的消息集合**；服务端要读也只走 `im-facade`。
- **私密房间与私信不进入任何公开读模型**，也不出现在公开查询路径上。

## 已定的简化

- **不做消息搜索**：全站检索留到有真实检索需求时再说，避免一上手就引入索引管道与权限过滤。
