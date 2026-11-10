# MoonChat

**一个 QQ / 微信形态的社交平台：账号、好友、私聊、群聊是地基，账号的能力是一张公开清单，可以被归属者之外的 agent 操控。**

agent 不是插件、不是命令，而是通讯录里一个真的账号：它用自己账号的凭据连同一个 `/im` 入口、走同一个 `/api` 写入，收到它账号的全部会话，自己决定何时回话。

> **当前状态：V1 施工中。** S0–S4 已完成并合入 `main`（七张表的迁移、20 条接口、群投影与重放器、两级限流桶）；下一步是 S5 客户端与 V1 验收。设计与进度以 `docs/` 为准，本文件只讲怎么上手。

## 技术栈

| 方面 | 选择 |
| --- | --- |
| 业务层 | Spring Boot 4（Java 21），唯一业务进程 `moonchat-biz` |
| 业务存储 | PostgreSQL；限流桶与缓存用 Redis |
| IM 引擎 | Turms（固定子模块 + 固定镜像 digest），只做会话、消息、投递 |
| 前端 | Flutter，第一版只发 Web 构建（`frontend/`） |
| agent 接入 | 该账号的 Turms 客户端 + Biz 的 REST，没有专用转发层 |

## 目录

```
.
├── README.md            # 本文件：上手与协作
├── AGENTS.md            # 给 AI agent 的硬边界与纪律（动代码前必读）
├── moonchat-biz/        # 唯一的业务进程
├── frontend/            # 客户端（Flutter 工程 + 网页预览）
├── infra/               # 本地与部署的基础设施配置（Turms 覆盖、冒烟脚本）
├── vendor/turms/        # Turms 上游子模块，固定在具体提交
├── deliverables/        # 对外交付稿（不是 spec，不作为设计依据）
└── docs/                # 12 份 spec，从 docs/README.md 的台账进
```

## 快速开始

前置：JDK 21、Docker（Compose v2）。

```powershell
# 1. 取到 Turms 子模块（不初始化则 vendor/turms 为空）
git submodule update --init --recursive

# 2. 构建与测试（接口测试用 Testcontainers 起真 PG / Redis，需要 Docker 在跑）
.\mvnw.cmd test

# 3. 起 Turms 开发环境
$env:ENV = 'dev'
docker compose -f vendor/turms/docker-compose.standalone.yml -f infra/turms/pinned-images.compose.yaml up -d --wait

# 4. 起开发用的 PG，然后跑 Biz（两个密钥没有默认值，必须由环境给出）
docker run -d --name moonchat-biz-dev-pg -e POSTGRES_DB=moonchat `
  -e POSTGRES_USER=moonchat -e POSTGRES_PASSWORD=moonchat `
  -p 15432:5432 postgres:17-alpine

$env:SPRING_DATASOURCE_URL = 'jdbc:postgresql://localhost:15432/moonchat'
$env:SPRING_DATASOURCE_USERNAME = 'moonchat'
$env:SPRING_DATASOURCE_PASSWORD = 'moonchat'
$env:MOONCHAT_JWT_SECRET_FILE = "$PWD/infra/turms/secrets/jwt-hmac256.key"  # 与 turms-gateway 共用同一份
$env:MOONCHAT_AUTH_JWT_SECRET = '<32 字节以上的任意字符串>'                   # 登录 JWT 自签自验
$env:MOONCHAT_AGENT_KEY_PEPPER = '<任意字符串>'
.\mvnw.cmd -pl moonchat-biz spring-boot:run
```

密钥文件在本地生成、不进仓库（`infra/turms/secrets/` 只跟踪它自己的 `.gitignore`）。密钥生成、Turms 冒烟与身份链路两条端到端脚本的跑法见 `docs/deployment.md` 与 `infra/turms/smoke/`。

## 协作

**分支与合并**：`main` 受保护，只收 PR，不能直接推。每件事开短分支，合完就删。

| 用途 | 分支名 |
| --- | --- |
| 功能 / 一片施工 | `feat/<短名>` |
| 修 bug | `fix/<短名>` |
| 只改文档 | `docs/<短名>` |

**PR 要求**：

1. CI（`.github/workflows/ci.yml`）跑 `mvnw test` 必须绿。
2. 改了行为必须同时改对应 spec；改了 spec 必须同时更新 `docs/README.md` 台账。
3. 不夹带无关改动：一次 PR 一件事。

**提交信息**：中文陈述句，说清做了什么决定；不加 `feat:` 前缀、不加 emoji、不加工具署名。例：`按社交骨架重写 8 份 spec：好友归 Turms、私聊进 V1、内容层撤出`。

**动代码前先读** [`AGENTS.md`](AGENTS.md)：六条硬边界、已定的简化、V1 之外的范围都写在那里，踩了就是返工。

## 文档导航

| 入口 | 用途 |
| --- | --- |
| [`docs/README.md`](docs/README.md) | **文档台账**：每份 spec 的 id、依赖、覆盖的问题、按角色的阅读路径 |
| [`docs/goal-and-requirements.md`](docs/goal-and-requirements.md) | PRD：定位、能力清单、V1 范围与验收、Non-Goals |
| [`docs/architecture.md`](docs/architecture.md) | 分层、数据归属、一条消息的旅程、跨模块不变量 |
| [`docs/v1-construction-plan.md`](docs/v1-construction-plan.md) | S0–S5 的交付边界与片末判据 |
| [`AGENTS.md`](AGENTS.md) | 给 AI agent / 新人的协作规则与交付前自检 |

第一次读：`docs/goal-and-requirements.md` → `docs/architecture.md` → 你关心的那个模块。
