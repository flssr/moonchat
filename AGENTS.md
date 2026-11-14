# AGENTS.md

给在本仓库工作的 AI agent 的入口。项目概览在 `README.md`；当前事实与决策历史在 `docs/`。

## 施工逻辑

1. 不为几乎不会发生的边界或并发问题提前膨胀代码；概率与代价不清楚时先停下确认。
2. 外部数据只在入口校验一次，内部靠类型系统与已验证状态流转。
3. 单次使用的逻辑就近内联，不提前抽无意义 helper。
4. 能由一个清晰函数完成的事不要拆层；非必要不引入 `try/catch`。

## 文档

- **`docs/truth/` 是当前事实**：只写现在生效的结论和关键依据，不写待办、备选或沿革。
- **`docs/history/` 是决策历史**：每次决策新增记录，带本地时间与 UTC，新记录在上。
- 文档按总体、后端、前端和功能模块分层；跨模块事实在总体文档只写一次，模块文档链接引用。
- 代码、迁移、测试和运行时 `/v3/api-docs` 是可执行事实。旧 spec、模块 `SPEC.md` 与 `docs/openapi.json` 均已退出仓库，不恢复。
- 施工中的临时计划与草稿不进入 `docs`，也不在仓库新增临时 markdown。
- 当前入口：[真相索引](docs/truth/README.md)；[历史索引](docs/history/README.md)。

## 硬边界

| 边界 | 含义 |
| --- | --- |
| 消息唯一写入者是 Turms | 服务端只经 Biz 写入网关与 `im-facade` 的 Admin `POST /messages` 代发；任何服务不得直写 Mongo |
| 客户端无 Turms 写权限 | 客户端 JWT 只授 `QUERY`；发言与建群都不能绕过 Biz |
| 业务真相在 PG | 账号、好友、群、成员与黑名单以 PG 为准；Turms 群成员是可重建投影 |
| 身份只有一处 | `account.id` 就是 Turms 用户 id；归属关系即授权，没有第二映射或授权表 |
| Biz 只校验不投递 | 不订阅消息事件，不做计数、通知或审计投递 |
| agent 与真人同构 | agent 用同一套 `/api`、同一签发路径和同一个 Turms `/im`，没有专用转发层 |

私聊授权只在写入网关检查 PG 好友关系；Turms 配置为不校验好友，且 `allowSendMessagesToStranger = true` 是部署前提。黑名单只单向拦截被拉黑方对拉黑方的私聊与好友申请，不投影 Turms。

## 当前范围

V1 已完成：身份、好友、私聊、群聊、agent 接入、Flutter Web 与六条验收。V2 只开始了黑名单后端，客户端入口仍待接入。

明确不做：内容流、评论点赞、图片附件、搜人、agent 目录、消息搜索、临时会话、公开群与邀请链接、音视频、多端同步、无响应提示、账号转让、平台托管 agent 记忆、agent 市场和应用商店上架。

## 代码形状

| 层 | 约定 |
| --- | --- |
| 分包 | `controller/<module>`、`service/<module>` + `impl`、`mapper/<module>`、`dto/<module>` |
| 持久层 | MyBatis-Plus：`@TableName` 实体 + `BaseMapper` + Wrapper |
| 实体 | `@Data @Builder @NoArgsConstructor @AllArgsConstructor`；凭据哈希不得进入日志 |
| 响应 | 只使用 DTO 白名单 record，实体不直接出接口 |
| 认证 | `HandlerMethodArgumentResolver` 解析当前账号；一个请求头按形状识别 JWT 或账号密钥 |
| 日志 | SLF4J + Logback，根级别 `info`；不得开启 MyBatis 参数明文日志 |
| 配置 | 自有配置使用 `moonchat.*`；密钥无默认值 |
| 测试 | 后端 Testcontainers 真 PG/Redis + 假 Turms Admin；Turms 运行时由真实 smoke 断言 |

## 提交与自检

- 提交主题用中文陈述句，一次提交只做一件事。
- 改动前确认是否触碰硬边界、当前范围或已定简化。
- 行为变化同步覆盖 `docs/truth` 对应章节，并向 `docs/history` 追加原因。
- 所有 Markdown 相对链接必须可解析；不得重新引入旧 spec、旧四份施工文档或提交 OpenAPI 文件。
- 后端至少跑相关测试；改动跨模块时跑 `.\backend\mvnw.cmd -f backend\pom.xml test`。客户端改动跑 analyze、test 与 Web build。
