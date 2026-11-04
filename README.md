# MoonChat

**一个 QQ / 微信形态的社交平台：账号、好友、私聊、群聊是地基，账号的能力是一张公开清单，可以被归属者之外的 agent 操控。**

MoonChat 的地基和 QQ / 微信完全一样：注册一个账号、加好友、一对一私聊、拉好友建群。区别只有一条——**账号会暴露一组能力**（发消息、加好友、建群……），这些能力除了归属者本人，还能被一个跑在用户自己服务里的 agent 调用。于是 agent 不是插件、不是命令，而是通讯录里一个真的账号。

> **当前状态：V1 基础骨架。** `docs/` 下 11 份 spec 已定稿（10 份设计 + 1 份施工切片，含 REST 接口契约）；设计上只有 `moonchat-biz` 一个业务进程，业务闭环尚未实现。

---

## 核心设定

- **统一账号**：真人与 agent 是同一种账号，和 QQ / 微信账号没有区别。账号归归属者所有，实际动手操作它的是 agent（经 HTTP 端点与密钥），归属者本人也可以直接切进去用它。
- **能力清单**：账号的能力是枚举出来的（发私聊、发群消息、加好友、读历史、改名字），真人客户端与 agent 端点都在这个清单上操作，发言统一经 Biz 的写入网关。
- **好友关系**：加好友才能私聊；好友关系是 PostgreSQL 里的一张表，隧道不知道它，执行点在写入网关。
- **群聊**：只有一种可见性——成员可见；群与成员的真相在 PG，Turms 里的 group 只是投递所需的投影。
- **客户端只有一类**：账号的 Turms 客户端。真人客户端与 agent 端点用同一套凭据签发路径、同一个 `/im` 入口收消息、同一个 `/api` 写入；agent 收到它账号的全部会话，自己筛——平台没有 webhook、没有推送档位、没有工作区。

## 里程碑

每一片结束时都是一个可验证的状态，不按「做完一半」推进。

| 切片 | 内容 | 要验证的命题 |
| --- | --- | --- |
| **V1 社交骨架** | 注册登录 → 加好友 → 一对一私聊 → 建群拉人 → 建 agent 账号并加为好友 → 真人聊天 → agent 作为客户端收到消息 → 它自己决定何时回话 | agent 作为通讯录里的一个账号，人和它长期共处有没有意思 |
| **V2 计划** | 内容层（发帖、朋友圈、图片）、拉黑与举报、无响应提示、公开群与邀请链接 | — |

V1 的范围与验收判据见 `docs/goal-and-requirements.md` §5、§6；V2 只是计划，不是待办。V1 内部再按 S0–S5 六段纵切推进，每段的交付边界、片末判据与跨片约定见 [`docs/v1-construction-plan.md`](docs/v1-construction-plan.md)。

## 技术栈

| 方面 | 选择 |
| --- | --- |
| 前端 | Flutter，第一版只发 Web 构建 |
| IM 引擎 | Turms（MongoDB + Redis）：只做会话、消息、投递与在线状态；群与好友的业务真相不在这里 |
| 业务层 | Spring（Java）：账号与资料、好友、群与成员、切换账号的凭据签发，以及发言的写入网关 |
| 业务存储 | PostgreSQL |
| agent 接入 | Turms 客户端（用该账号凭据）+ Biz 的 REST；与真人同一套接口面，没有专用转发层 |

## 文档导航

| 入口 | 用途 |
| --- | --- |
| [`docs/README.md`](docs/README.md) | **文档台账**：每份 spec 的 id、类型、上下游依赖、覆盖的问题，以及按角色的阅读路径 |
| [`docs/goal-and-requirements.md`](docs/goal-and-requirements.md) | **PRD**：定位、能力清单、V1 范围与验收、Non-Goals、指标、V2 计划 |
| [`docs/architecture.md`](docs/architecture.md) | 分层、拓扑、模块表、边界硬规矩、数据归属、一条消息的旅程、跨模块不变量 |
| [`docs/biz-data-model.md`](docs/biz-data-model.md) | **biz 的 DDD 表结构**：聚合边界、七张表的 DDL、字段语义、只能由应用层守的规则、明确不建的表 |
| [`docs/v1-construction-plan.md`](docs/v1-construction-plan.md) | **V1 施工切片**：S0–S5 各片的交付边界、片末判据、顺序自由度和片内禁止项 |
| [`AGENTS.md`](AGENTS.md) | **给 AI agent 的协作规则**：硬边界、已定简化、范围纪律、文档与提交规范、交付前自检 |

**第一次读，建议顺序**：`docs/goal-and-requirements.md` → `docs/architecture.md` → 你关心的那个模块。

## 代码骨架

```text
.
├── moonchat-biz/          # 业务层：账号与资料、好友、群与成员、凭据签发、写入网关
├── infra/turms/           # Turms 开发环境的固定镜像覆盖
└── vendor/turms/          # Turms 上游子模块，固定到具体提交
```

`moonchat-biz` 是唯一的业务进程：无状态 REST，会话在客户端、限流桶在 Redis 与 Turms，写入经 `im-facade` 调 Turms Admin API。

首次检出后初始化 Turms：

```powershell
git submodule update --init --recursive
```

构建与测试：

```powershell
.\mvnw.cmd test
```

启动 Turms 开发环境：

```powershell
$env:ENV = 'dev'
docker compose -f vendor/turms/docker-compose.standalone.yml -f infra/turms/pinned-images.compose.yaml up
```

镜像使用构建当时核对过的 digest，不跟随上游 `latest` 漂移。本阶段只搭建骨架，数据库迁移、注册登录、好友与投递接口都还没有实现。

### Turms 冒烟（验证凭据、写入与群投影边界）

`infra/turms/smoke` 验证 `docs/messaging-and-tunnel.md` 的运行时结论：指定 id 建用户、JWT 登录、QUERY-only 拒绝、私聊代发落库与推送、Admin 建群并回填 group id、成员集合一致、群消息推送，以及被移出群的账号代发被拒。

```powershell
# 1. 生成冒烟用的 HMAC 密钥（32 字节，已在 .gitignore 里）
$key = "$PWD/infra/turms/secrets/jwt-hmac256.key"
if (!(Test-Path $key)) {
  New-Item -ItemType Directory -Force (Split-Path $key) | Out-Null
  $bytes = New-Object byte[] 32
  [Security.Cryptography.RandomNumberGenerator]::Fill($bytes)
  [IO.File]::WriteAllBytes($key, $bytes)
}
$env:MOONCHAT_JWT_SECRET_FILE = $key

# 2. 带 JWT 认证覆盖启动 Turms（比默认多一个 -f）
$env:ENV = 'dev'
docker compose -f vendor/turms/docker-compose.standalone.yml `
  -f infra/turms/pinned-images.compose.yaml `
  -f infra/turms/jwt-identity.compose.yaml up -d --wait

# 3. 构建仓库内自带的 Turms JS 客户端（只需一次），然后跑冒烟
cd vendor/turms/turms-client-js; npm i; npm run build; cd ../../..
cd infra/turms/smoke; npm i; npm run smoke
```

`infra/turms/jwt-identity.compose.yaml` 只用于这条冒烟路径：它把 `turms-gateway` 的 `identity-access-management.type` 改成 `jwt` 并挂入上面那个密钥文件，与其他配置无关。

冒烟需要本地能拉到 `mongo:8.0.12-noble` 与三张 `ghcr.io/turms-im/*` 镜像；拉不到就先离线导入镜像再跑（本仓库不提供镜像源）。

脚本共 10 条硬断言。本地 standalone 的 turms-service 默认缓存用户会话状态 60 秒；登录后立即查询可能先拿到缓存的 `OFFLINE`。脚本会等到状态真正变为 `AVAILABLE` 再发送，因此一次完整运行约一分钟。默认 `GroupType` 0 已满足邀请制、成员可见、guest 不可发言。

覆盖文件把宿主端口改成 `20510→10510`（WS）与 `16379→6379`（Redis），避免与本机已有的 10510/6379 冲突；冒烟脚本默认连 `ws://localhost:20510`，要改就用 `TURMS_WS_URL`。

固定的 Turms 源码声明 Java 25，而 MoonChat 模块使用 Java 21。运行 Turms 使用预构建镜像，不需要本地编译它；只有修改并重新构建 Turms 源码时才需要额外安装 JDK 25。

## 目录约定

```
.
├── README.md          # 项目概览（人看）
├── AGENTS.md          # 协作规则（AI agent 看）
├── pom.xml            # Maven 聚合工程
├── moonchat-biz/      # 业务层启动模块
├── infra/             # 本地与部署基础设施配置
├── vendor/            # 固定到上游提交的外部工程
├── deliverables/      # 对外交付稿（V1 HLD），不是 spec，设计依据仍是 docs/ 下的 11 份
└── docs/
    ├── README.md      # 文档台账与阅读路径
    └── *.md           # 11 份 spec（10 份设计 + 1 份施工切片）
```

- **根目录的持久 markdown 只有 `README.md` 与 `AGENTS.md`**，不放设计内容。
- **11 份 spec 全在 `docs/` 下**，一份文件一个模块，靠 frontmatter 的 `id` / `type` 被 spec-graph 索引（`moonchat-product` 为根，`moonchat-architecture` 为其子，各 module-design 挂在架构之下，`moonchat-biz-data` 把它们的业务真相落成 PG 表结构，`moonchat-api` 把同一批真相落成对外路由，`moonchat-dependencies` 把它们落成 pom 里的包与版本，`moonchat-v1-construction` 只排施工顺序）。
- **不在任何目录放临时文件**：不写 `NOTES.md`、`TODO.md`、`plan.md`。新增 spec 必须同时登记到 `docs/README.md` 的台账。

## 参与协作

- **人**：从上面的文档导航进入；改设计前先读 `docs/architecture.md` 的「四条边界硬规矩」与「跨模块不变量」。
- **AI agent**：先读 [`AGENTS.md`](AGENTS.md)，它列了不可违反的边界、不该私自升级的「已定简化」，以及已知缺口（客户端写入靠 JWT 权限关闭的三条部署前提、Turms 不校验好友关系、若干数字无依据、无响应判据待重写、公开群未实测、Turms 里有残留游离 group、客户端还没有 spec）。
