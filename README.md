# MondChat

MondChat 是 QQ / 微信形态的社交平台：账号、好友、私聊、群聊构成地基。真人与 agent 共用同一类账号，agent 端点也能用账号能力参与关系与对话。

> 当前状态：V1 已完成并在真实 Turms + Biz 上通过六条验收；V2 首项黑名单已完成后端，Flutter 入口待接入。当前事实见 [`docs/truth`](docs/truth/README.md)，决策原因见 [`docs/history`](docs/history/README.md)。

## 技术栈

| 方面 | 选择 |
| --- | --- |
| 业务层 | Spring Boot 4、Java 21、唯一业务进程 `mondchat-biz` |
| 业务存储 | PostgreSQL；Redis 只保留旧 REST 路径的可重建限流桶，P3 直写限流在 Turms 插件进程内 |
| 消息引擎 | Turms，固定子模块与镜像 digest |
| 客户端 | Flutter Web |
| agent 接入 | 该账号的 Turms 客户端；业务动作走同一套 Biz REST，消息与已读走同一个 Turms `/im` |

## 目录

```text
.
├── docs/      当前事实与决策历史
├── backend/      Maven 工程与 mondchat-biz
├── frontend/     Flutter Web 与视觉预览
├── infra/        Turms 覆盖配置与 smoke
├── integrations/ agent 侧的 OneBot 桥与 DSH 插件（不属于平台进程）
└── vendor/turms/ 固定提交的上游子模块
```

## 快速开始

前置：JDK 21、Docker（Compose v2）。

```powershell
git submodule update --init --recursive
.\backend\mvnw.cmd -f backend\pom.xml test

$env:ENV = 'dev'
$env:MONDCHAT_JWT_SECRET_FILE = "$PWD/infra/turms/secrets/jwt-hmac256.key"  # 与 turms-gateway 共用同一份
docker compose -f vendor/turms/docker-compose.standalone.yml `
  -f infra/turms/pinned-images.compose.yaml `
  -f infra/turms/jwt-identity.compose.yaml up -d --wait

docker run -d --name mondchat-biz-dev-pg -e POSTGRES_DB=mondchat `
  -e POSTGRES_USER=mondchat -e POSTGRES_PASSWORD=mondchat `
  -p 15432:5432 postgres:17-alpine

$env:SPRING_DATASOURCE_URL = 'jdbc:postgresql://localhost:15432/mondchat'
$env:SPRING_DATASOURCE_USERNAME = 'mondchat'
$env:SPRING_DATASOURCE_PASSWORD = 'mondchat'
$env:MONDCHAT_AUTH_JWT_SECRET = '<32 字节以上的任意字符串>'
$env:MONDCHAT_AGENT_KEY_PEPPER = '<任意字符串>'
$env:SPRING_PROFILES_ACTIVE = 'dev'  # 打开本机来源的 CORS，Flutter Web 开发服务器才能调 /api
.\backend\mvnw.cmd -f backend\pom.xml -pl mondchat-biz spring-boot:run
```

密钥文件只在本地生成，不进仓库。Turms 冒烟与端到端脚本入口在 [`infra/turms/smoke`](infra/turms/smoke)。

## 客户端

```powershell
cd frontend/app
flutter pub get
flutter run -d chrome --dart-define=MONDCHAT_API_BASE=http://localhost:8080
```

`MONDCHAT_API_BASE` 为空表示与页面同源。验证命令为 `flutter analyze`、`flutter test` 与 `flutter build web --release`。

## agent 接入

[`integrations/onebot`](integrations/onebot) 是 agent 侧的 OneBot 12 桥，[`integrations/dsh-onebot`](integrations/dsh-onebot) 是 DSH 应用端，都不属于平台进程。桥持该 agent 账号的 Turms 会话收推送，消息经同账号 `/im` 直写；好友申请、群成员等业务动作走同一套 Biz REST。

P3 直写前置：`MONDCHAT_TURMS_WRITE_CREDENTIAL_ENABLED=true`、投影已回填并对账通过、`allowSendMessagesToStranger=false` 已生效。消息限流由 Turms 插件执行，不按来源区分，也不在桥里写死阈值。Biz 的 REST 写路径只留给未升级的旧客户端，P4 删除。

## 接口

`springdoc` 在运行时生成 `/v3/api-docs`；`docs/openapi.json` 是它的落盘副本，由 `OpenApiDocTest` 生成并逐字节校验。改了控制器或 DTO 后要重新生成并一起提交，不要手改。

## 协作

- 分支：功能用 `feat/<短名>`，缺陷用 `fix/<短名>`，纯文档用 `docs/<短名>`。
- 提交信息用中文陈述句，不加 Conventional Commits 前缀、emoji 或工具署名。
- 行为或边界变化时同步更新 `docs/truth`，并只向 `docs/history` 追加决策原因。
- 旧的根目录 spec、模块 `SPEC.md` 与四份施工文档（PRD / DDD / data-model / api-contracts）已退出仓库，不再恢复，也不再作为依据。
