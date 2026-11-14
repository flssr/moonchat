# 测试与验证

后端测试使用 Testcontainers 启动真 PostgreSQL 与 Redis，Turms Admin 由 JDK `HttpServer` 假服务替代。Turms 的真实运行时结论由 `infra/turms/smoke` 在真实部署上断言。

接口测试覆盖账号、好友、黑名单、群、投影重放、两级限流、发言校验顺序、503 映射和 PG 零写入。并发重复请求测试断言不会落到 5xx，并用唯一键断言覆盖错误翻译。

OpenAPI 端点 `/v3/api-docs` 由 controller 与 DTO 生成，测试只断言它能生成并包含当前接口，不再校验或提交 `docs/openapi.json`。

Flutter 使用 `flutter analyze`、`flutter test` 和 Web release build。真实 Turms 的 Node 冒烟覆盖 JWT 登录、QUERY-only 拦截、Admin 代发、建群、成员对齐与移出群后拒绝。

已知未验证项：浏览器内 `js_interop` 读取通道只对假 `TurmsClient` 验证过，尚未在真实 Turms 上跑通。
