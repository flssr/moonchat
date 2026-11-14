# MoonChat

**一个 QQ / 微信形态的社交平台：账号、好友、私聊、群聊是地基，账号的能力是一张公开清单，可以被归属者之外的 agent 操控。**

agent 不是插件、不是命令，而是通讯录里一个真的账号：它用自己账号的凭据连同一个 `/im` 入口、走同一个 `/api` 写入，收到它账号的全部会话，自己决定何时回话。

> **当前状态：V1 已完成，V2 首项（黑名单）开工。** S0–S5 已完成并合入 `main`（V1 的七张表迁移、20 条接口、群投影与重放器、两级限流桶、Flutter Web 客户端与 agent 示例端点），六条验收判据在真 Turms + 真 Biz 上跑通；V2 的 `blocklist` 表与 3 条接口按 `docs/api-contracts.md` §7 施工。设计与进度以根目录两份 spec（`goal-and-requirements.md`、`architecture.md`）、模块旁的 `SPEC.md` 与 `docs/` 四份文档为准，本文件只讲怎么上手。

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
├── README.md                    # 本文件：上手与协作
├── AGENTS.md                    # 给 AI agent 的硬边界与纪律（动代码前必读）
├── goal-and-requirements.md     # spec：产品决策（范围判据、已定简化、Non-Goals、V2）
├── architecture.md              # spec：分层、拓扑、四条边界、跨模块不变量
├── backend/                     # Maven 聚合工程（pom.xml、mvnw、.mvn/ 都在这层）
│   └── moonchat-biz/            # 唯一的业务进程（SPEC.md 在其根）
├── frontend/                    # 客户端（SPEC.md + Flutter 工程 + 网页预览）
├── infra/                       # 基础设施与冒烟脚本（SPEC.md 在部署与运行时的决定）
├── vendor/turms/                # Turms 上游子模块，固定在具体提交
└── docs/                        # 四份施工文档：PRD、DDD、表结构、接口契约 + openapi.json
    └── frontend/                # 客户端视觉与页面的交接稿（不是 spec）
```

## 快速开始

前置：JDK 21、Docker（Compose v2）。

```powershell
# 1. 取到 Turms 子模块（不初始化则 vendor/turms 为空）
git submodule update --init --recursive

# 2. 构建与测试（接口测试用 Testcontainers 起真 PG / Redis，需要 Docker 在跑）
.\backend\mvnw.cmd -f backend\pom.xml test

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
.\backend\mvnw.cmd -f backend\pom.xml -pl moonchat-biz spring-boot:run
```

密钥文件在本地生成、不进仓库（`infra/turms/secrets/` 只跟踪它自己的 `.gitignore`）。密钥生成、Turms 冒烟与身份链路两条端到端脚本的跑法见 `infra/SPEC.md` 与 `infra/turms/smoke/`。

## 接口文档

`docs/openapi.json` 是给 Apifox 导入的 OpenAPI 3.1 文件，由 biz 的 `/v3/api-docs` 落盘生成，不手写。
改了控制器或 DTO 之后重新生成并一起提交（文件不存在时也会自动生成）：

```powershell
.\backend\mvnw.cmd -f backend\pom.xml -pl moonchat-biz -Dtest=OpenApiDocTest -Dmoonchat.openapi.write=true test
```

`.\backend\mvnw.cmd -f backend\pom.xml test` 会顺带校验这份文件与代码一致，忘了重新生成会让构建失败。

## 协作

**分支与合并**：`main` 约定只收 PR、不直接推（免费版私有仓库开不了强制保护，靠约定 + CI 守住）。每件事开短分支，合完就删。

| 用途 | 分支名 |
| --- | --- |
| 功能 / 一片施工 | `feat/<短名>` |
| 修 bug | `fix/<短名>` |
| 只改文档 | `docs/<短名>` |

**PR 要求**：

1. CI（`.github/workflows/ci.yml`）在 `backend/` 里跑 `./mvnw -B test`，必须绿。
2. 改了行为必须同时改对应 spec（根目录两份或模块旁的 `SPEC.md`）；改了 spec 必须同时更新 `docs/README.md` 的索引。
3. 不夹带无关改动：一次 PR 一件事。

**提交信息**：中文陈述句，说清做了什么决定；不加 `feat:` 前缀、不加 emoji、不加工具署名。例：`按社交骨架重写 8 份 spec：好友归 Turms、私聊进 V1、内容层撤出`。

**动代码前先读** [`AGENTS.md`](AGENTS.md)：六条硬边界、已定的简化、V1 之外的范围都写在那里，踩了就是返工。

## 文档导航

| 入口 | 用途 |
| --- | --- |
| [`goal-and-requirements.md`](goal-and-requirements.md) | **产品决策**：定位、范围判据、已定简化、Non-Goals、V2 |
| [`architecture.md`](architecture.md) | 分层、数据归属、一条消息的旅程、跨模块不变量 |
| [`backend/moonchat-biz/SPEC.md`](backend/moonchat-biz/SPEC.md) | 业务进程的职责、边界、写入网关、数据与依赖 |
| [`frontend/SPEC.md`](frontend/SPEC.md) | 客户端的职责与界面边界 |
| [`infra/SPEC.md`](infra/SPEC.md) | 部署单元、单进程的理由、扩容触发条件 |
| [`docs/README.md`](docs/README.md) | **文档索引**：PRD / DDD / 表结构 / 接口契约四份施工文档 |
| [`docs/PRD.md`](docs/PRD.md) | 需求明细：场景、能力清单、V1 范围、验收、非功能要求 |
| [`AGENTS.md`](AGENTS.md) | 给 AI agent / 新人的协作规则与交付前自检 |

第一次读：`goal-and-requirements.md` → `architecture.md` → `docs/DDD.md` → 你关心的那份文档。
