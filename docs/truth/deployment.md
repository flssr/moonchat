# 部署与运行

生产是单机 docker compose 加宿主机上的 1Panel OpenResty 反代。仓库只带编排 [`infra/prod/compose.yaml`](../../infra/prod/compose.yaml)，不带任何 nginx/Caddy 容器：反代是宿主机上 1Panel 管的 OpenResty，不在 compose 里。

- 真人与 agent 都从 `/api` 做业务读写，用各自账号凭据从 `/im` 收发与查询消息。
- Biz 无状态，会话不在进程内；限流状态在 Redis，可重建。
- 客户端与 agent 端点不在服务端部署单元里。
- Flutter Web 产物不在这台机器上部署，本机不放静态站目录。

## 部署单元与内存预算

2 核 4G 单机，PoC 个位数用户。八个常驻容器加两个一次性初始化容器：

| 容器 | 镜像 | 宿主端口 | `mem_limit` | JVM / 缓存 |
| --- | --- | --- | --- | --- |
| `postgres` | `postgres:17-alpine` | 无 | 320m | — |
| `redis` | `redis:8.0.3-alpine` | 无 | 96m | — |
| `mongo-config` | `mongo:8.0.12-noble` | 无 | 224m | config 副本集 `rs-config`，WiredTiger 缓存 0.12G |
| `mongo-shard` | `mongo:8.0.12-noble` | 无 | 384m | shard 副本集 `rs0`，WiredTiger 缓存 0.2G |
| `mongos` | `mongo:8.0.12-noble` | 无 | 128m | 路由，无缓存 |
| `mongo-rs-init` | `mongo:8.0.12-noble` | 无 | 96m | 一次性，发起两个副本集 |
| `mongo-shard-init` | `mongo:8.0.12-noble` | 无 | 96m | 一次性，`sh.addShard` |
| `turms-service` | 钉 digest `2be538a0…` | 无 | 800m | `-Xmx448m` + metaspace 160m |
| `turms-gateway` | 钉 digest `99f51a29…` | `127.0.0.1:10510` | 576m | `-Xmx320m` + metaspace 128m |
| `mondchat-biz` | GHCR `mondchat-biz` | `127.0.0.1:8080` | 480m | `-Xmx256m` + metaspace 128m |

常驻 `mem_limit` 合计 3008m ≈ 2.94G，加上一次性初始化容器的 96m 也不到 3.1G；宿主给 1Panel、OpenResty、dockerd 留约 1G，另配 **2G swap** 兜 JVM 启动尖峰。容器只设 `mem_limit`、不设 `memswap_limit`，所以单个容器到顶时先被压进等量 swap 而不是立刻被 OOM kill，表现出来是变慢而不是崩。

- 只有 `mondchat-biz` 的 8080 与 `turms-gateway` 的 10510 绑回环，给宿主上的 OpenResty 用；PostgreSQL、Redis、MongoDB 三件套、`turms-service` 的端口都不出容器网络。
- 不开 turms-admin。
- MongoDB 必须是分片集群，不是副本集：Turms 的 Mongo 客户端只接受 `SHARDED` / `LOAD_BALANCED`，把单节点副本集 URI（`?replicaSet=rs0`）交给它会抛 `IncompatibleMongoException` 并在启动约 4 秒后退出，没有配置项能绕过——判定来自驱动读 `hello` 得到的集群类型。所以用最小分片：config 副本集 + 单个 shard 副本集 + mongos，数据全落一个 shard，不用分片键、不用 balancer，URI 统一 `mongodb://mongos:27017/turms`。
- 启动顺序由依赖锁住：两个 `mongod` 健康 → `mongo-rs-init` 发起两个副本集并等到各自 primary → `mongos` 才能起（config 副本集没 primary 时 mongos 会直接退出）→ `mongo-shard-init` 把 shard 接进集群 → Turms 两个进程。两个初始化容器都可重跑：副本集已发起、shard 已接上就直接退出。
- 不在初始化里做 `enableSharding` / `shardCollection`：Turms 首次启动自己 `enableSharding` 并按实体上的 `@Sharded` 建分片键与索引，重复做会撞索引未就绪。
- Redis 分库：Turms 用 DB0，Biz 的限流桶用 DB1。
- Turms 的集群与数据源配置走 `TURMS_SERVICE_JVM_OPTS` / `TURMS_GATEWAY_JVM_OPTS` 里的 `-D`（与 `vendor/turms/docker-compose.standalone.yml` 同源），身份模式与密钥路径用环境变量。
- 日志收敛到每容器 3 × 10MB 的 json-file，不占满 4G 机器的盘。

### 从单节点副本集编排升级

跑过旧编排的机器上留着 `mondchat_mongo-data` 卷，里面是按普通副本集初始化的 `rs0`，不能直接当 shard 用（没按 `--shardsvr` 建过），`mongo-shard` 会起不来。切到分片编排前删掉这一个卷即可，PG 与 Redis 的卷不动：

```bash
cd /opt/mondchat && docker compose down
docker volume rm mondchat_mongo-data
```

Turms 的数据是可重建投影，账号真相在 PG，所以这里不需要备份。

## 反向代理（1Panel OpenResty）

反代入口是独立子域名 `api.mondchat.com`：DNS 加一条 A 记录指向服务器，1Panel 建站点时 root 留空、只放下面的反代片段，并给这个子域名单独签证书。80 端口已绑定 `/site` 下的官网静态页，不复用这条链路。

在 1Panel 站点配置里加两个 location：

```nginx
server {
    listen 443 ssl;
    server_name api.mondchat.com;

    location /api/ {
        proxy_pass http://127.0.0.1:8080;
        proxy_set_header Host $host;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    # /im 是 WebSocket：Turms 网关只校验 Upgrade / Connection / Sec-WebSocket-Key，
    # 不校验路径，所以直转即可，超时要放大到小时级。
    location /im {
        proxy_pass http://127.0.0.1:10510;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_read_timeout 3600s;
        proxy_send_timeout 3600s;
    }
}
```

- `/api/` 必须保留前缀：控制器都挂在 `/api/**`，所以 `proxy_pass` 不带 URI 部分。
- 部署前提里 Biz 侧回给客户端的 WS 地址由 `.env` 的 `MONDCHAT_TURMS_GATEWAY_URL` 决定，形如 `wss://api.mondchat.com/im`。
- **生产不开 CORS**：`DevCorsConfig` 只在 `dev` profile 生效。放在别处的前端必须由那一侧把 `/api`、`/im` 反代到 `api.mondchat.com`（浏览器视角同源），直接从别的 origin 调本机入口会被浏览器拦掉。

## 服务器预置

`/opt/mondchat/` 下三样，加宿主侧两项：

1. `/opt/mondchat/.env`（`chmod 600`）。变量与用途：

   | 变量 | 用途 |
   | --- | --- |
   | `POSTGRES_PASSWORD` | PG 的 `mondchat` 用户密码，Biz 也用它连库 |
   | `MONDCHAT_TURMS_ADMIN_PASSWORD` | Turms 初始 root 密码，同时是 Biz 调 Admin API 的密码。**只用字母数字**：容器健康检查会把它拼进 `curl -u` |
   | `MONDCHAT_AUTH_JWT_SECRET` | Biz 登录 JWT 自签自验的密钥，32 字节以上 |
   | `MONDCHAT_AGENT_KEY_PEPPER` | agent 账号密钥的 HMAC pepper，无默认值 |
   | `MONDCHAT_BIZ_IMAGE` | 镜像全名，如 `ghcr.io/<owner>/mondchat-biz` |
   | `MONDCHAT_BIZ_TAG` | 镜像 tag，默认 `latest`；回滚时填提交 sha（不带冒号） |
   | `MONDCHAT_TURMS_GATEWAY_URL` | 客户端连的 WS 地址，如 `wss://api.mondchat.com/im` |
   | `MONDCHAT_JWT_SECRET_FILE` | 可选，默认 `/opt/mondchat/secrets/jwt-hmac256.key` |

2. `/opt/mondchat/secrets/jwt-hmac256.key`（`chmod 600`）：`openssl rand -hex 32` 生成，`mondchat-biz` 与 `turms-gateway` 挂同一份。
3. `docker login ghcr.io`，用带 `read:packages` 的 PAT，否则 `docker compose pull` 拿不到私有镜像。
4. 2G swap：`fallocate -l 2G /swapfile && chmod 600 /swapfile && mkswap /swapfile && swapon /swapfile`，并写进 `/etc/fstab`；`vm.swappiness=10`。
5. 宿主要有 `curl`（CD 的健康检查用它打本机 `8080/actuator/health`），以及 Compose 2.17+（用到 `up -d --wait`）。

`compose.yaml` 由 CD 每次覆盖，不在宿主上手改；`.env` 与密钥文件长期留在宿主，不进仓库。

## 持续交付

`push` 到 `main` 触发 [`.github/workflows/cd.yml`](../../.github/workflows/cd.yml)（即用户合完 PR 之后），只做后端：

1. 用 `backend/mondchat-biz/Dockerfile`、以仓库根为上下文构建镜像，推 `ghcr.io/<owner>/mondchat-biz:latest` 与 `:<sha>`。
2. `scp` 最新 `compose.yaml` 到 `/opt/mondchat/compose.yaml`。
3. SSH 上机 `docker compose pull` 与 `docker compose up -d --wait --wait-timeout 300 --remove-orphans`。
4. 健康检查：宿主上轮询 `curl -fsS http://127.0.0.1:8080/actuator/health` 两分钟，起不来看 `docker compose ps` 并失败。

部署串行排队，不取消进行中的那一次。回滚：把 `/opt/mondchat/.env` 的 `MONDCHAT_BIZ_TAG` 改成要回退的 sha，再执行一次 `docker compose up -d`。

需要用户配的 GitHub Secrets：

| Secret | 用途 |
| --- | --- |
| `SSH_HOST` | 服务器地址 |
| `SSH_USER` | 部署用账号 |
| `SSH_PRIVATE_KEY` | 该账号的私钥 |
| `SSH_KNOWN_HOSTS` | 服务器主机指纹，严格校验用 |

推 GHCR 用仓库自带的 `GITHUB_TOKEN`（`packages: write`），不需要额外 PAT。

## 必要部署前提

- Turms 身份模式是 `jwt`，验签密钥与 Biz 使用同一份文件：`TURMS_GATEWAY_SESSION_IDENTITYACCESSMANAGEMENT_TYPE=jwt`，密钥文件挂到 gateway 的 `/opt/turms/secrets/jwt-hmac256.key` 与 Biz 的 `MONDCHAT_JWT_SECRET_FILE`。
- 建 Turms 用户时使用平台生成、不保存也不分发的随机密码。
- 客户端只能从 `POST /api/sessions` 获得 Turms 凭据。
- `allowSendMessagesToStranger = true`，因为好友关系不投影进 Turms；编排里显式传了 `-Dturms.service.message.allow-send-messages-to-stranger=true`，不吃上游默认值。

任一前提被改都会破坏写入网关的唯一入口约束。

## 本地开发环境

- 清 dev 库必须连 Turms 用户一起清。账号 id 由 PG 序列从 1 亿起分配，同时也是 Turms 用户的 `_id`；只清 PG、留着 Turms 里的旧用户时，Biz 再分配到同一个 id 会被 Turms 回 `409 / 1103`（Mongo `E11000 duplicate key user _id`），Biz 侧表现为注册 `503 upstream_unavailable`——看起来像 Turms 故障，实际是撞号。
- 探 Turms 用 `http://localhost:8510/health`（basic `turms:turms`，`curl.exe` 实测 200 / 5ms）；不要探 `/actuator/*`（Turms 没有该端点），也不要探 `7510`（RPC 端口，HTTP 探测必然超时）。
- 本地起依赖用 `vendor/turms/docker-compose.standalone.yml` 那套，与生产的 [`infra/prod/compose.yaml`](../../infra/prod/compose.yaml) 是两套编排，别混着用。

## 运维边界

V1 单实例起步，不引入消息队列。日志使用控制台与滚动文件双输出；容器是否挂载 `logs/` 由部署决定，日志不是业务真相。健康检查由 Spring Boot Actuator 提供，不进入业务接口契约。
