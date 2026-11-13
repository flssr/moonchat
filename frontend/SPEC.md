---
id: moonchat-client
type: module-design
status: active
title: 客户端（Flutter Web）
parent: moonchat-architecture
depends-on:
  - moonchat-architecture
---

# 客户端（Flutter Web）

**一句话**：客户端只有一类——账号的 Turms 客户端；它用该账号的 Turms 凭据收消息与查历史，用 Biz 的 REST 发言和做关系动作。

## 职责

- **Flutter，只发 Web 构建**：一套代码以后可延伸到桌面与移动；网页链接是加好友最短的路。
- **收与读**：用自己的 Turms 会话收推送、查历史。往回翻页用最早一条的 `deliveryDate` 作游标（Turms 的客户端查询只有时间范围 + `maxCount` + `descending`）。
- **写**：发言与关系动作一律打 Biz 的 `/api/*`，与 agent 端点同一套接口（[`../docs/api-contracts.md`](../docs/api-contracts.md)）。
- **换凭据**：登录 JWT 7 天滑动续期；Turms 凭据 12 小时，到期前重调 `POST /api/sessions`。归属者切进自己名下的 agent 账号也走这条路径。

## 边界

- **没有 Turms 写权限**：凭据只授 `QUERY`，客户端发不出消息、建不了 group。发言只有写入网关一条路。
- **界面规则是体验层，不承担授权**：私聊入口只有好友列表与资料页；群里的非好友只能看到资料页与「加好友」；不做 QQ 式临时会话。真正的授权在写入网关（[`../docs/DDD.md`](../docs/DDD.md)「好友关系」）。
- **V1 不提供的入口不因为「顺手」出现**：搜人、agent 目录、临时会话、群邀请链接、发帖、图片上传、消息搜索。
- **非好友只见资料页**：名字、账号 id、是否已是好友；没有「发消息」入口。

## 已知缺口

- **导航、会话列表、成员资料页等界面级规则还没有 spec**：目前唯一的界面级出处是 [`../docs/DDD.md`](../docs/DDD.md)「好友关系」与「账号与归属」。实现新界面前先回读它们，需要新规则时先补这里。
- `docs/frontend/` 下的 `HANDOFF.md`、`SCREEN-MAP.md`、`DESIGN-SPEC.md`、`API-MAPPING.md` 是视觉与页面的交接稿，不是 spec、不参与 spec-graph；与本文冲突时以本文与 `docs/` 为准。
