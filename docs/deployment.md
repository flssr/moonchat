---
id: moonchat-deployment
type: module-design
status: active
title: 部署与运行时
parent: moonchat-architecture
depends-on:
  - moonchat-agent-connection
---

# 部署与运行时

**一句话**：connector 是一个必须独立的进程，但它与 Biz 之间不是服务边界——切的是运行时，不是契约。

## 部署单元

`nginx`（Flutter Web 静态资源 + 反代 `/api`、`/im`、`/agent-messages`、`/agent-workspaces`）、`moonchat-biz`、`agent-connector`、`turms-gateway`、`turms-service`、`turms-admin`、`mongodb`、`redis`、`postgres`、`rustfs`。connector 与 Biz 共用 Redis 实例，用不同键前缀隔离。

**M1 只部署子集**：内容层与 `rustfs` 不部署，connector 与 Biz 同机两容器单实例，Turms 的 WS 走同域名的 `/im` 反代；公网入口靠内网穿透把一个域名指到 nginx，不做云上部署与域名运维（见 `moonchat-product` 的 MVP 切片）。

connector **单实例**：会话不跨实例，重启会瞬断所有 agent 会话，几十秒内自动重连。

## connector 必须是一个独立进程

两条决定性理由，外加一条负载形态上的：

- **会话是有状态的。** connector 持有全部 agent 账号的长连 WS，而 Biz 是无状态 REST。合进一个进程，Biz 每次发布都等于所有 agent 瞬断（房间出现假的「无响应」），水平扩容也立刻撞上「一账号一条会话」。
- **`send` 能力必须被物理隔离。** `im-facade` 被规定不含发送消息的能力；与 Biz 同进程时这条不变量只能靠代码评审守，分进程后它是事实。
- **负载形态不同。** 唤醒是 O(每个 agent × 每条房间消息) 的外呼放大，一个慢端点会长时间占线程；与业务请求共用线程池等于把 agent 的故障度传到聊天以外的接口。

独立的只是**进程与入口**：一个代码库、两个启动模块（`biz` / `connector`），共享 Turms 客户端封装与模型；早期两者可以同机、同 Pod 两容器部署，但不得合回一个进程——除非会话先被外置成独立的会话网关，那只是把复杂度挪了位置，不叫简化。

## 切的是运行时，不是服务边界

进程边界给的是故障域、长连与线程资源、凭据范围；微服务边界额外要的是 API 契约、数据所有权、独立发布节奏。按判据对一遍：

| 判据 | 这里的情况 | 结论 |
| --- | --- | --- |
| 需要独立 API 契约与版本兼容 | 只有「agent 校验」「工作区解析」两个内部端点，总是同版本部署 | 否 |
| 需要独立的数据所有权 | connector 不应拥有任何业务数据，只有可重建缓存 | 否——服务化默认的「每服务一库」会诱使它长出投递库，凭空多一份真相 |
| 需要独立发布节奏 | 一个团队，一次改动同时改两侧 | 否，分开发布只制造兼容矩阵 |
| 需要独立故障域 | 慢端点不能拖垮业务请求 | 是 |
| 需要独立连接与线程资源 | 长连 WS 有状态 | 是 |
| 需要独立凭据范围 | `send` 能力不得进入 Biz 进程 | 是 |

微服务的治理成本随端点数摊销，为两个端点做服务化是净亏；进程拆分的成本几乎是常数（一个 Dockerfile、一次部署、一套内部鉴权）。升格为微服务的触发条件：出现第二个内部消费者、connector 需要独立团队或独立发布窗口、或需要按 agent 数量做会话分片。

## 已定的简化

- **connector 单实例**，不做会话分片：早期 agent 数量小，分片是能缓的复杂度。
