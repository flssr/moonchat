---
id: moonchat-deployment
type: module-design
status: active
title: 部署与运行时
parent: moonchat-architecture
---

# 部署与运行时

**一句话**：跑起来的业务只有 `moonchat-biz` 一个进程——它是无状态 REST，会话在客户端、限流桶在 Redis，所以再没有第二个业务进程要维护。

## 部署单元

`nginx`（Flutter Web 静态资源 + 反代 `/api`、`/im`）、`moonchat-biz`、`turms-gateway`、`turms-service`、`turms-admin`、`mongodb`、`redis`、`postgres`。

- `/api` 是 Biz 的 REST 入口，真人与 agent 都打这里。
- `/im` 是 `turms-gateway` 的 WS/HTTP 入口，真人与 agent 都用自己账号的 Turms 凭据连这里。
- `redis` 同时被 Turms 与 Biz 使用：Turms 用它做在线状态与缓存，Biz 用它放两级限流桶，键前缀隔离。
- **日志**：Logback 双输出——控制台（彩色，带 PID/线程/行号）与 `logs/moonchat-<日期>-<序号>.log`（单文件 10MB、按天滚动、保留 30 天）。容器里 `logs/` 要么挂卷、要么只依赖 stdout 采集；不挂卷就是容器重启即丢，V1 接受这一点（日志不是业务真相，也不是审计表）。

**当前只部署这一个子集**：Biz 与 Turms 同机多容器、单实例；公网入口靠内网穿透把一个域名指到 nginx，不做云上部署与域名运维。

**客户端不在仓库的部署单元里**：Flutter Web 构建由 nginx 托管，agent 端点跑在归属者自己的机器上。

## 为什么没有第二个业务进程

上一版有一个 `agent-connector`，它的独立性有三条论据。三条现在都不成立，因为它们描述的都是「平台侧替 agent 持会话并转发」这件事：

| 上一版的论据 | 现在为什么不成立 |
| --- | --- |
| 会话是有状态的，Biz 发布会让所有 agent 瞬断 | 会话在客户端（真人客户端与 agent 端点各自持自己的 Turms 会话），Biz 里没有任何连接 |
| `send` 能力必须被物理隔离，否则「`im-facade` 没有手」只能靠代码评审守 | 这道边界现在由凭据范围守：Turms Admin 的 `MESSAGE_CREATE` 权限只在 Biz 里持有，客户端根本不具备；隔离的对象从「进程」变成「哪个模块能拿这个凭据」 |
| 唤醒是 O(agent × 消息) 的外呼放大，慢端点会占线程 | 没有外呼：Turms 推给各客户端自己的会话，慢的是客户端自己 |

**Biz 是可水平扩容的无状态 REST**：会话不在这里，限流桶在 Redis 且丢失可从零重建，写入路径上唯一的跨进程调用是 Admin API。所以扩容就是加副本，不涉及会话分片。

## 什么时候才需要第二个进程

不是"以后可能"，而是满足下面任一条才值得付进程拆分与内部鉴权的成本：

| 触发条件 | 为什么那时才拆 |
| --- | --- |
| 写入网关与业务查询负载形态明显分叉（一个要低延迟短事务，一个要长查询） | 那时线程池与超时策略才会互相干扰 |
| 需要独立发布窗口（写入权限与业务查询的变更节奏不一致） | 分开发布才有意义，否则只制造兼容矩阵 |
| 需要独立故障域（写入网关成为业务查询的 SPOF 风险不可接受） | 那时才用进程边界换隔离 |

不满足就保持一个进程。提前拆出的「服务」在只有一个消费者时是净亏：多一套内部鉴权、一个 Dockerfile、一次部署，换不到任何东西。

## 本地与冒烟

- 本地起 Turms 用 `vendor/turms/docker-compose.standalone.yml` 叠加 `infra/turms/pinned-images.compose.yaml`；冒烟脚本与 10 条硬断言在 `infra/turms/smoke/`。
- Biz 的两个密钥没有默认值，必须由环境给出：`MOONCHAT_JWT_SECRET_FILE`（与 turms-gateway 共享）、`MOONCHAT_AUTH_JWT_SECRET`、`MOONCHAT_AGENT_KEY_PEPPER`。跑法见根 `README.md`。
- Turms 侧的三条配置前提（`identity-access-management.type = jwt`、`allowSendMessagesToStranger = true`、客户端凭据只从 `POST /api/sessions` 拿）是部署约束，不是代码可以“顺便”假设的东西；口径在 [`../docs/DDD.md`](../docs/DDD.md)「凭据与客户端权限」。

## 已定的简化

- **单实例起步**：一个 Biz 副本，扩容靠加副本，不预留分片与会话粘滞。
- **不引入外部消息队列**：写入是同步的 REST 调用，没有异步投递这一层。
- **不做多区域与蓝绿部署**：早期只有一套环境，靠内网穿透对外。
