# mondchat-turms-plugin

自研 Turms 插件（统一发送限流）。**故意不进 `backend/pom.xml` 的 reactor**：它编译在
`vendor/turms` 的构件上，而 vendor 是上游子模块、不进我们的 CI。它只在「客户端直写路线」切换时启用，
本轮只落骨架。

## 构建

```bash
# 1. 让本地 Maven 仓库有 Turms 构件（只做一次，vendor 是子模块）
cd vendor/turms && mvn install -DskipUTs -DskipITs -DskipSTs
# 2. 打包（产物 target/mondchat-turms-plugin.jar，内含 plugin.yaml）
cd backend/mondchat-turms-plugin && mvn package
```

JDK 21+；Turms 版本对齐 `vendor/turms` 锁定提交（`d6ec799`）。升级 Turms 必须重新编译本插件，
并回归 `ClientRequestHandler` 签名。

## 部署

- 容器内插件目录是 **`/opt/turms/turms-service/plugins`**（容器家目录 `TURMS_SERVICE_HOME`，
  不是镜像根的 `/opt/turms/plugins`；镜像里没有 JS 引擎，只认 Java jar）。
- 生产挂载一行 volume：`<宿主机目录>:/opt/turms/turms-service/plugins:ro`，目录里只放这一个 jar。
- **上线前必须用同一个 pinned digest 起一次性容器验加载**：容器内 `8510/health` 返回 200 才算通过。
  实测（2026-11-22）：`plugin.yaml` 的 `class` 指向不存在类时，`PluginManager` 构造抛
  `InvalidPluginException`，Spring 上下文 refresh 中止，容器直接 `Exited(1)`——**插件坏了是整台
  turms-service 起不来**，不是限流不生效。

## 配置

```yaml
turms-plugin:
  mondchat-ratelimit:
    account:     { capacity: 60, initial-tokens: 60, tokens-per-period: 60, refill-interval-millis: 60000 }
    conversation:{ capacity: 20, initial-tokens: 20, tokens-per-period: 20, refill-interval-millis: 60000 }
```

命中时回 `CLIENT_REQUESTS_TOO_FREQUENT`（1101，HTTP 语义 429），两级用 `reason` 区分。

## 已知上限

- 计数**每进程一份**：单实例与今天 Biz 的 Redis 桶等价；扩到 N 个 turms-service 就是 N 倍额度。
  升级路径：用 `getContext().getBean(...)` 拿宿主 Redis 客户端换共享计数。
- 限流对**所有客户端**生效（不分 agent / 真人）；客户端断线重发的连发也会吃桶，容量要留余量。

## 回滚

清空挂载目录里的 jar + 重启 `turms-service`。这是「整机不可用」类故障的唯一恢复路径，
staging 必须演练一次才能挂到生产（见 `docs/truth/deployment.md`）。
