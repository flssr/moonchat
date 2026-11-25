# 测试与验证

后端测试使用 Testcontainers 启动真 PostgreSQL 与 Redis，Turms Admin 由 JDK `HttpServer` 假服务替代。Turms 的真实运行时结论由 `infra/turms/smoke` 在真实部署上断言。

接口测试覆盖账号、好友、黑名单、群、投影重放、发言校验顺序、503 映射和 PG 零写入。注销测试覆盖密码确认、群主拒绝、agent 级联（含存量嵌套）、关系与群成员清理、邮箱重用、旧 Biz JWT/agent key 失效、限频、冻结账号、投影关闭拒绝、Turms outbox 重试与退群先失败后恢复；建 agent、换凭据与注销子树等待账号行锁的回归测试也已覆盖。两级限流当前在 Biz 由 `RateLimitApiTest` 覆盖；Turms 插件另有属性默认值单测，真实运行时仍以 smoke 验证 `1101`、无写权限 `1106`、冻结账号 `1106` 但能清角标。并发重复请求测试断言不会落到 5xx，并用唯一键断言覆盖错误翻译。

投影另有一组测试：业务变更与 `domain_event` 同事务落库、派发失败按退避重试、三类对账期望集合（好友双向、黑名单方向、群成员数）的差异只修 Turms，以及清拉黑的两种写法（仍是好友用 epoch-0、不是好友删行）。群成员测试覆盖空句柄退避后回填恢复、重复加成员的 `409/1103` 幂等收敛，以及其他 409/5xx 仍失败。

OpenAPI 端点 `/v3/api-docs` 由 controller 与 DTO 生成；`docs/openapi.json` 是它的落盘副本，由 `OpenApiDocTest` 生成并逐字节校验，改了控制器或 DTO 后用写开关重新生成并一起提交。

Flutter 使用 `flutter analyze`、`flutter test` 和 Web release build。真实 Turms 的 Node 冒烟当前覆盖 JWT 登录、QUERY-only 拦截、Admin 代发、建群、成员对齐与移出群后拒绝；切换后改为覆盖「有写权限可直发、冻结回 `1106`、`stranger=false` 下非好友回 `5001`、插件命中回 `1101`」。

已知未验证项：浏览器内 `js_interop` 读取通道只对假 `TurmsClient` 验证过，尚未在真实 Turms 上跑通。
