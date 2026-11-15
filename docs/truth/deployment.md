# 部署与运行

部署单元是 nginx、`mondchat-biz`、Turms Gateway/Service/Admin、MongoDB、Redis 与 PostgreSQL。

- nginx 托管 Flutter Web，并反代 `/api` 与 `/im`。
- 真人与 agent 都从 `/api` 做业务读写，用各自账号凭据从 `/im` 收发与查询消息。
- Biz 无状态，会话不在进程内；限流状态在 Redis，可重建。
- 客户端与 agent 端点不在服务端部署单元里。

## 必要部署前提

- Turms JWT 验签密钥与 Biz 使用同一份，`identity-access-management.type = jwt`。
- 建 Turms 用户时使用平台生成、不保存也不分发的随机密码。
- 客户端只能从 `POST /api/sessions` 获得 Turms 凭据。
- `allowSendMessagesToStranger = true`，因为好友关系不投影进 Turms。

任一前提被改都会破坏写入网关的唯一入口约束。

## 本地开发环境

- 清 dev 库必须连 Turms 用户一起清。账号 id 由 PG 序列从 1 亿起分配，同时也是 Turms 用户的 `_id`；只清 PG、留着 Turms 里的旧用户时，Biz 再分配到同一个 id 会被 Turms 回 `409 / 1103`（Mongo `E11000 duplicate key user _id`），Biz 侧表现为注册 `503 upstream_unavailable`——看起来像 Turms 故障，实际是撞号。
- 探 Turms 用 `http://localhost:8510/health`（basic `turms:turms`，`curl.exe` 实测 200 / 5ms）；不要探 `/actuator/*`（Turms 没有该端点），也不要探 `7510`（RPC 端口，HTTP 探测必然超时）。

## 运维边界

V1 单实例起步，不引入消息队列。日志使用控制台与滚动文件双输出；容器是否挂载 `logs/` 由部署决定，日志不是业务真相。健康检查由 Spring Boot Actuator 提供，不进入业务接口契约。
