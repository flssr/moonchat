---
id: moonchat-dependencies
type: submodule-design
status: draft
title: biz 的依赖清单与版本依据
parent: moonchat-architecture
depends-on:
  - moonchat-deployment
  - moonchat-biz-data
  - moonchat-accounts
  - moonchat-messaging
---

# biz 的依赖清单与版本依据

**一句话**：`moonchat-biz` 的 pom 只服务四件事——PG、Redis、凭据的签与验、Turms Admin 的 HTTP 调用；每个包都能指回一份 spec，其余一律不加。

## 0. 这份文档管什么

| 本文管 | 本文不管 |
| --- | --- |
| pom 里有哪些依赖、版本从哪来、为什么加 | 表结构（`moonchat-biz-data`）、路由契约（`moonchat-api`） |
| 明确不加哪些包，以及理由 | 部署哪些单元、怎么编排（`moonchat-deployment`） |
| 测试期依赖与容器镜像 | 镜像站、代理这类机器级配置（不进仓库） |

- 判断标准只有一条：**每个依赖都要能指回某份 spec 的一句话**。指不回去的，要么删掉依赖，要么先补 spec。
- 版本只有两个来源：Spring Boot BOM，或者本文 §1 自钉的那两行。不允许出现第三种。

## 1. 版本来源

父 pom 的 `parent` 是 `spring-boot-starter-parent:4.1.2`，凡它管理的都不用写版本：

| 来源 | 具体版本 |
| --- | --- |
| Spring Boot 4.1.2 BOM | Flyway 12.4.0、PostgreSQL 驱动 42.7.14、Lettuce 7.5.2、Spring Security 7.1.2、Testcontainers 2.0.5、`com.redis:testcontainers-redis` 2.2.4 |

Boot 不管的两个，钉在父 pom 的 `<properties>` 里：

| 自钉 | 版本 | 依据 |
| --- | --- | --- |
| MyBatis-Plus | 3.5.18 | `mybatis-plus-spring-boot4-starter` 自身按 Boot 4.1.0 对齐，内含 `mybatis-spring` 4.1.0；Boot 4 要用它而不是 `-spring-boot3-starter` |
| nimbus-jose-jwt | 10.10 | Boot 不管；只有一个必选依赖（slf4j），BouncyCastle / tink / protobuf 全是 optional |

## 2. 生产依赖

| 依赖 | 用在哪 | 依据 |
| --- | --- | --- |
| `spring-boot-starter-webmvc` | 20 条 `/api/*` 路由；调 Turms Admin API 的 `RestClient` 也来自它的 spring-web | `moonchat-api` |
| `spring-boot-starter-validation` | 入口校验（密码 8..72 且不能纯数字、名字 ≤ 20、正文 ≤ 500） | `moonchat-api` §3.1 |
| `spring-boot-starter-actuator` | 健康检查，不进业务契约 | `moonchat-api` §9 |
| `spring-boot-starter-flyway` | `db/migration/V1__biz_schema.sql` 的执行者 | `moonchat-biz-data` §3 |
| `flyway-database-postgresql` | Flyway 10 起 PG 支持单独成模块，starter 不带它 | `moonchat-biz-data` §3 |
| `postgresql`（runtime） | 业务真相所在的唯一库 | `moonchat-biz-data` |
| `mybatis-plus-spring-boot4-starter` | 七张表的读写、聚合事务，以及唯一分页接口（群成员列表） | `moonchat-biz-data`、`moonchat-api` §6.4 |
| `spring-boot-starter-data-redis` | 「账号 → 会话」两级限流桶（键前缀与 Turms 隔离） | `moonchat-agent-connection` |
| `nimbus-jose-jwt` | 签登录 JWT（7 天）与 Turms 凭据（12 小时、`statements` 只授 `QUERY`），并验自己的登录 JWT | `moonchat-accounts`、`moonchat-api` §3.3 |
| `spring-security-crypto` | 只取 `BCryptPasswordEncoder`（cost 10 起，`bcrypt$` 前缀入 `credential_hash`） | `moonchat-biz-data` |

- **`spring-boot-starter-jdbc` 不单独声明**：Flyway 与 MyBatis-Plus 的 starter 都会把它带进来，重复写只是噪音。
- **持久层是 MyBatis-Plus**，不是 JPA 也不是裸 `JdbcClient`；分页、事务与 SQL 都走它。

## 3. 明确不加

| 不加 | 理由 |
| --- | --- |
| `spring-boot-starter-security` | 认证是项目自己的两套凭据（登录 JWT / 账号密钥），不套 Spring Security 的过滤器链；只需要它的 crypto 模块 |
| `jjwt`（api / impl / jackson） | `jjwt-jackson` 依赖 Jackson 2，而 Boot 4 已换成 Jackson 3，会并存两套 JSON；nimbus 不依赖任何 JSON 库 |
| 任何 Turms 客户端（`turms-client-java` 等） | Biz 只打 Turms Admin REST（`POST /messages`，HTTP Basic），不连 `/im`；连 `/im` 的是真人客户端与 agent 端点 |
| MongoDB 驱动 / `spring-data-mongodb` | 消息在 Turms 的库里，Biz 不读不写 |
| `spring-boot-starter-restclient` | `RestClient` 已在 spring-web 里，JDK 的 HttpClient 够用；加它只是让 Boot 替你挑底层实现 |
| 消息队列、`spring-retry` | 写入是同步 REST 调用，设计里没有投递队列，也没有重试语义 |
| `springdoc` / swagger | 路由契约的唯一出处是 `moonchat-api`，不生成第二份文档 |

## 4. 测试期依赖

| 依赖 | 用途 |
| --- | --- |
| `spring-boot-starter-webmvc-test` | 上下文与 MVC 层测试 |
| `testcontainers-postgresql`、`testcontainers-junit-jupiter` | 真 PG：迁移、事务、唯一约束都按真库验 |
| `com.redis:testcontainers-redis` | 真 Redis：限流桶的计数与过期按真库验 |

- **容器替代本机环境**：`BizApplicationTests` 用 `@DynamicPropertySource` 把容器的 jdbc url 与 redis host/port 注入，本机装没装 PG / Redis 不影响 `./mvnw test`。
- **镜像固定**：`postgres:17-alpine` 与 `redis:8.0.3-alpine`。Redis 版本与 Turms 自带 compose 一致；PostgreSQL 的大版本没有 spec 依据（迁移里的语法迟早会依赖它），升级时改测试这一行即可，因为没有生产侧的镜像定义。

## 5. 加依赖的判断顺序

1. 它服务哪份 spec 的哪句话？指不出来就不加。
2. Boot BOM 管不管它？管就不写版本。
3. 能不能被一个已有的 starter 传递带入？（`starter-jdbc` 就是这样被省掉的）
4. 只为用一个类而引入整条框架的，降级到单模块——`spring-security-crypto` 而不是 `starter-security`，nimbus 而不是 Spring Security OAuth2。

## 6. 已知缺口

- **MyBatis-Plus 这个选择目前只记录在本文**：`moonchat-biz-data` §3 只写了 Flyway、PG 驱动与迁移路径，没写持久层。要么把它补进那份 spec，要么承认本文是它的唯一出处。
- **两级限流桶的速率未定**（`moonchat-agent-connection`）。实现只用 Redis 的原子自增与过期，不需要额外脚本或限流库。
- **agent 密钥的 pepper 未定**（`moonchat-biz-data` 的「只能由应用层守的规则」）：用 JCE 的 `HmacSHA256`，不引第三方包。
- **镜像站与代理是机器级配置**：Maven 走阿里云镜像、Docker 走国内 registry mirror，都写在开发者的 `settings.xml` / `daemon.json` / `.testcontainers.properties` 里，仓库不承担、也不记录这些值的唯一副本。
