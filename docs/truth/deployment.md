# 部署与运行

生产是单机 docker compose 加宿主机上的 1Panel OpenResty 反代。仓库只带编排 [`infra/prod/compose.yaml`](../../infra/prod/compose.yaml)，不带任何 nginx/Caddy 容器：反代是宿主机上 1Panel 管的 OpenResty，不在 compose 里。

- 真人与 agent 都从 `/api` 做业务读写，用各自账号凭据从 `/im` 收发与查询消息。
- Biz 无状态，会话不在进程内。**当前**限流状态在 Redis，可重建；**切换后**限流计数在 Turms 插件的进程内存里，按进程一份。
- 客户端与 agent 端点不在服务端部署单元里。
- Flutter Web 产物不在这台机器上部署，本机不放静态站目录。

## 部署单元与内存预算

2 核 4G 单机，PoC 个位数用户。八个常驻容器加两个一次性初始化容器：

| 容器 | 镜像 | 宿主端口 | `mem_limit` | JVM / 缓存 |
| --- | --- | --- | --- | --- |
| `postgres` | `postgres:17-alpine` | 无 | 320m | — |
| `redis` | `redis:8.0.3-alpine` | 无 | 96m | — |
| `mongo-config` | `mongo:8.0.12-noble` | 无 | 320m | config 副本集 `rs-config`，WiredTiger 缓存 0.25G |
| `mongo-shard` | `mongo:8.0.12-noble` | 无 | 384m | shard 副本集 `rs0`，WiredTiger 缓存 0.25G |
| `mongos` | `mongo:8.0.12-noble` | 无 | 128m | 路由，无缓存 |
| `mongo-rs-init` | `mongo:8.0.12-noble` | 无 | 96m | 一次性，发起两个副本集 |
| `mongo-shard-init` | `mongo:8.0.12-noble` | 无 | 96m | 一次性，`sh.addShard` |
| `turms-service` | 钉 digest `2be538a0…` | 无 | 1280m | `-Xmx448m` + metaspace 160m |
| `turms-gateway` | 钉 digest `99f51a29…` | `127.0.0.1:10510` | 1280m | `-Xmx320m` + metaspace 128m |
| `mondchat-biz` | GHCR `mondchat-biz` | `127.0.0.1:8080` | 480m | `-Xmx256m` + metaspace 128m |

常驻 `mem_limit` 合计 **4288m ≈ 4.19G，比物理 3.66G 还大**，这不是笔误：`mem_limit` 是上限不是预留，实际用量由各容器的 `-Xmx` 与缓存决定。之所以给两个 Turms 容器 1280m，是因为 Turms 启动时自己校验「容器限额 × 0.95 ≥ 1000MB」（`MemoryHealthChecker`），低于约 1053m 直接抛 `IncompatibleJvmException` 退出；1280m × 0.95 = 1216MB 才算过关。稳态预估 2.8–3.3G，宿主给 1Panel、OpenResty、dockerd 留约 1G，尖峰靠 **2G swap**。容器只设 `mem_limit`、不设 `memswap_limit`，所以单个容器到顶时先被压进等量 swap 而不是立刻被 OOM kill，表现出来是变慢而不是崩。

真觉得 swap 抖得太频繁时，第一个该调的旋钮是给两个 Turms 容器加 `-XX:MaxDirectMemorySize=128m`：`-XX:MaxDirectMemorySize` 不写时等于 `-Xmx`，Netty 的直连内存会再占一份和堆一样大的上限，PoC 的流量用不到那么多。

- 只有 `mondchat-biz` 的 8080 与 `turms-gateway` 的 10510 绑回环，给宿主上的 OpenResty 用；PostgreSQL、Redis、MongoDB 三件套、`turms-service` 的端口都不出容器网络。
- 不开 turms-admin。
- MongoDB 必须是分片集群，不是副本集：Turms 的 Mongo 客户端只接受 `SHARDED` / `LOAD_BALANCED`，把单节点副本集 URI（`?replicaSet=rs0`）交给它会抛 `IncompatibleMongoException` 并在启动约 4 秒后退出，没有配置项能绕过——判定来自驱动读 `hello` 得到的集群类型。所以用最小分片：config 副本集 + 单个 shard 副本集 + mongos，数据全落一个 shard，不用分片键、不用 balancer，URI 统一 `mongodb://mongos:27017/turms`。
- 启动顺序由依赖锁住：两个 `mongod` 健康 → `mongo-rs-init` 发起两个副本集并等到各自 primary → `mongos` 才能起（config 副本集没 primary 时 mongos 会直接退出）→ `mongo-shard-init` 把 shard 接进集群 → Turms 两个进程。两个初始化容器都可重跑：副本集已发起、shard 已接上就直接退出。
- `--wiredTigerCacheSizeGB` 的下限是 0.25G，低于它 mongod 直接拒绝启动（`storage.wiredTiger.engineConfig.cacheSizeGB must be greater than or equal to 0.25`），容器会一直 unhealthy，`up -d --wait` 直接失败。两个 `mongod` 都钉 0.25G；`mongo-config` 的 `mem_limit` 因此是 320m 而不是 224m。
- 不在初始化里做 `enableSharding` / `shardCollection`：Turms 首次启动自己 `enableSharding` 并按实体上的 `@Sharded` 建分片键与索引，重复做会撞索引未就绪。
- Redis 分库：Turms 用 DB0；Biz 的限流桶用 DB1（切换后注销，限流进 Turms 插件）。
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
   | `MONDCHAT_TURMS_WRITE_CREDENTIAL_ENABLED` | 可选，默认 `false`。`true` = 签出带写权限的 Turms statements；必须与 `allowSendMessagesToStranger=false` 同一次开，单独提前开等于让持凭据客户端绕过好友与拉黑 |
   | `MONDCHAT_TURMS_HTTP_CONNECT_TIMEOUT` | 可选，默认 `2s`。Admin HTTP 连接超时 |
   | `MONDCHAT_TURMS_HTTP_READ_TIMEOUT` | 可选，默认 `5s`。Admin HTTP 读取超时；Turms 卡死时按既有 catch 回 `503 upstream_unavailable` |

2. `/opt/mondchat/secrets/jwt-hmac256.key`（`chmod 600`）：`openssl rand -hex 32` 生成，`mondchat-biz` 与 `turms-gateway` 挂同一份。
3. `docker login ghcr.io`，用带 `read:packages` 的 PAT，否则 `docker compose pull` 拿不到私有镜像。
4. 2G swap：`fallocate -l 2G /swapfile && chmod 600 /swapfile && mkswap /swapfile && swapon /swapfile`，并写进 `/etc/fstab`；`vm.swappiness=10`。
5. 宿主要有 `curl`（CD 的健康检查用它打本机 `8080/actuator/health`），以及 Compose 2.17+（用到 `up -d --wait`）。

`compose.yaml` 由 CD 每次覆盖，不在宿主上手改；`.env` 与密钥文件长期留在宿主，不进仓库。

## 持续交付

`push` 到 `main` 触发 [`.github/workflows/cd.yml`](../../.github/workflows/cd.yml)（即用户合完 PR 之后），只做后端：

1. 用 `backend/mondchat-biz/Dockerfile`、以仓库根为上下文构建镜像，推 `ghcr.io/<owner>/mondchat-biz:latest` 与 `:<sha>`。镜像是 Spring Boot 分层布局（第三方 jar 在 `lib/`，每次提交只变 `app.jar`），运行基础镜像 `eclipse-temurin:21-jre-alpine`；一次 push 新增的镜像存储是 application 层，约 0.2MB。
2. `scp` 最新 `compose.yaml` 到 `/opt/mondchat/compose.yaml`。
3. SSH 上机 `docker compose pull` 与 `docker compose up -d --wait --wait-timeout 300 --remove-orphans`。
4. 健康检查：宿主上轮询 `curl -fsS http://127.0.0.1:8080/actuator/health` 两分钟，起不来看 `docker compose ps` 并失败。
5. 部署成功后跑 `prune` job 清理 GHCR 里的旧镜像版本：只留 `latest` 与最近 3 个 `:<sha>`，更旧的删掉。它依赖 Secret `GHCR_PAT`（`read:packages` + `delete:packages`），是独立 job 且 `continue-on-error`，清理失败只红叉，不影响已经上线的部署。

部署串行排队，不取消进行中的那一次。回滚：把 `/opt/mondchat/.env` 的 `MONDCHAT_BIZ_TAG` 改成要回退的 sha，再执行一次 `docker compose up -d`。

## 开关来源

三类来源，不要混淆：**服务器 `/opt/mondchat/.env`**（CD 不碰，改完 `up -d` 生效）、**仓库 compose 里写死**（跟着 CD 走，改它要过 PR）、**GitHub Secrets**（只给流水线用，不进容器）。

| 变量 | 来源 | 默认 / 说明 |
| --- | --- | --- |
| `POSTGRES_PASSWORD`、`MONDCHAT_TURMS_ADMIN_PASSWORD`、`MONDCHAT_BIZ_IMAGE`、`MONDCHAT_TURMS_GATEWAY_URL`、`MONDCHAT_AUTH_JWT_SECRET`、`MONDCHAT_AGENT_KEY_PEPPER` | 服务器 `.env` | 必填，缺失时 `docker compose config` 直接报错 |
| `MONDCHAT_BIZ_TAG` | 服务器 `.env` | 默认 `latest`；回滚填上一个提交的 sha |
| `MONDCHAT_JWT_SECRET_FILE` | 服务器 `.env` | 默认 `/opt/mondchat/secrets/jwt-hmac256.key` |
| `MONDCHAT_TURMS_SERVICE_IMAGE` | 服务器 `.env` | **默认空 = 上游 pinned digest（无插件）**；设成 `ghcr.io/<owner>/mondchat-turms-service:latest` 才加载限流插件 |
| `MONDCHAT_PROJECTION_ENABLED` | 服务器 `.env` | 默认 `true`（compose 写 `${MONDCHAT_PROJECTION_ENABLED:-true}`）；设 `false` 只停派发与对账，事件照常累积 |
| `MONDCHAT_PROJECTION_RECONCILE_CRON` | 服务器 `.env` | 默认 `0 0 3 * * *`（每天 03:00）；首次回填可临时调成分钟级 |
| `MONDCHAT_TURMS_WRITE_CREDENTIAL_ENABLED` | 服务器 `.env` | 默认 `false`；打开才有两套 statements 与冻结踢会话 |
| `allow-send-messages-to-stranger` | 仓库 compose 写死 `false` | 对仍走 Biz 代发的客户端无影响（Admin 进 `saveMessage`，不跑好友校验） |
| `SSH_HOST`、`SSH_USER`、`SSH_PRIVATE_KEY`、`SSH_KNOWN_HOSTS`、`GHCR_PAT` | GitHub Secrets | 只给 CD 与官网流水线用 |

`compose.yaml` 每次部署都被 CD 覆盖，**所以任何故障时要快速关掉的开关都必须走 `.env`**，不能写死在 compose 里。

## 插件镜像投放（一次性人工操作）

限流插件用自建镜像投放（`infra/turms/Dockerfile`，由 `.github/workflows/turms-plugin.yml` 按路径过滤构建并推 GHCR）——插件不进后端 CD 流水线，因为它要编 vendor，约 20 分钟。

启用步骤：

1. 确认 `ghcr.io/<owner>/mondchat-turms-service:latest` 已构建完成（Actions 里那次专用 workflow 绿）。
2. 服务器 `/opt/mondchat/.env` 加一行 `MONDCHAT_TURMS_SERVICE_IMAGE=ghcr.io/<owner>/mondchat-turms-service:latest`。
3. `docker compose pull turms-service && docker compose up -d --wait turms-service`。
4. 验插件：日志出现 `registered` 与 `extension ... has been started`，`curl 127.0.0.1:8510/health` 为 200。

**摘除插件（回滚）= 删掉那一行再 `up -d`**，回到上游 pinned digest。

## P2 生产上线顺序

1. **先合并、再部署**：CD 会把新的 `compose.yaml` 推上服务器，此时 `stranger=false` 与投影开关一起生效。
2. **Biz 启动即跑迁移**：生产 PG 空白，Flyway 一次跑到 V7（`domain_event`），不需要手工执行 DDL。
3. **看积压再放派发**：`select count(*) from domain_event where processed_at is null;`。生产库为空，首次部署时 `pending = 0`。
4. **回填存量关系**：建号、好友、黑名单、群成员的存量没有事件（投影从 P1 之后才开始记事件），回填靠对账。默认每天 03:00（`0 0 3 * * *`，六段、秒在最前），要快就临时设 `MONDCHAT_PROJECTION_RECONCILE_CRON='0 */2 * * * *'` 跑一两轮再改回默认。对账只修 Turms、不反写 PG。
   派发器 2 秒一轮（`dispatch-interval-ms: 2000`）、一批 100 条，所以 `pending` 从 0 跳到几百属正常波动；判「卡住」要连续三次采样都只增不减，不能看单次快照。
5. **上线即变的一项**：`stranger=false` 在每次部署里都生效，对仍走 Biz 代发的客户端应当零影响；但这是唯一可能被误伤的地方——部署后用真实账号发一条私聊确认成功，一条就够。
6. **验三类差异为 0** 后，才允许客户端开始直写；`MONDCHAT_TURMS_WRITE_CREDENTIAL_ENABLED` 与 `stranger=false` 是同一次切换，不分开。
7. **插件最后才上**：限流对所有来源生效，但它与消息引擎同进程，按「插件镜像投放」单独一步做，出问题单独回滚。

## 生产回滚

| 目标 | 动作 |
| --- | --- |
| 摘掉限流插件 | `.env` 删 `MONDCHAT_TURMS_SERVICE_IMAGE` → `up -d` |
| 关投影派发 | `.env` 加 `MONDCHAT_PROJECTION_ENABLED=false` → `up -d`（事件继续累积，不丢数据） |
| 回退 Biz 版本 | `.env` 改 `MONDCHAT_BIZ_TAG=<上一个 sha>` → `up -d` |
| 关写权限 | `.env` 设 `MONDCHAT_TURMS_WRITE_CREDENTIAL_ENABLED=false` → `up -d`；已签出的旧凭据最长 12 小时失效，需要时同时踢会话 |

CI 与 CD 都支持手动触发：`gh workflow run ci.yml --ref <分支>` 跑接口 / 前端 / 桌面三条检查，`gh workflow run cd.yml --ref main` 重新构建并上线（等价于 push 一次 main）。

PR 合并前可以手动跑一次 CI 兜底：2026-11-17 12:17–17:26 UTC 之间 `pull_request` 事件整段不创建 workflow run（`workflow_dispatch` 与 push 到 main 正常），之后自行恢复；过程和证据见 #42。

## 官网静态页

[`.github/workflows/site.yml`](../../.github/workflows/site.yml) 单独发 80 端口的官网，不进后端 CD：`site/**` 推到 `main` 时触发，也可以 `gh workflow run site.yml --ref main` 手动发。

1. 站点根目录不写死：用 `styles.css` 里的固定标语在 `/site`、`/opt/1panel/www`、`/www`、`/var/www` 里找，找到的那一层就是根；要覆盖就配仓库变量 `SITE_ROOT`。
2. `tar` 打包 `site/` 经 SSH 解到站点根目录，只覆盖同名文件，不删站点目录里的其它东西。站点目录归 root、部署账号写不进去时用免密 `sudo` 覆盖；两者都不行就在这一步明确失败，不会动别的目录。
3. 冒烟：逐个 `curl -fsS "https://mondchat.com/<文件>?t=<时间戳>"` 与仓库文件比 SHA256，不一致就失败。

它复用 CD 的 `SSH_HOST` / `SSH_USER` / `SSH_PRIVATE_KEY` / `SSH_KNOWN_HOSTS`。1Panel 的站点根目录形如 `/opt/1panel/www/sites/<域名>/index`；部署账号要么能写它，要么有免密 sudo。

需要用户配的 GitHub Secrets：

| Secret | 用途 |
| --- | --- |
| `SSH_HOST` | 服务器地址 |
| `SSH_USER` | 部署用账号 |
| `SSH_PRIVATE_KEY` | 该账号的私钥 |
| `SSH_KNOWN_HOSTS` | 服务器主机指纹，严格校验用 |
| `GHCR_PAT` | 清理 GHCR 旧镜像版本用：`read:packages` + `delete:packages` |

推 GHCR 用仓库自带的 `GITHUB_TOKEN`（`packages: write`）；清理旧版本要删包，`GITHUB_TOKEN` 没有这个权限，所以另配 `GHCR_PAT`。

## 部署前静态卡口：JVM opts 里不能有 `#`

`TURMS_SERVICE_JVM_OPTS` 是 YAML 折叠块（`>-`），**块内的 `#` 是字符串内容而不是注释**：它会变成 JVM 参数的一部分，容器起来时报 `Unrecognized option` 直接退出。`docker compose config` 不会因此报错，所以要在部署前单独检查。

服务器上（用真实 `.env`）：

```bash
docker compose --env-file /opt/mondchat/.env -f infra/prod/compose.yaml config > /tmp/cfg.yml \
  || { echo "config 渲染失败，先修必填变量"; exit 1; }
val=$(sed -n 's/^ *TURMS_SERVICE_JVM_OPTS: //p' /tmp/cfg.yml)
[ "$(printf '%s' "$val" | wc -l)" -le 1 ] || { echo "JVM opts 不是单行，先看折叠块"; exit 1; }
case "$val" in *'#'*) echo "JVM opts 被注释污染，停"; exit 1;; esac
echo "clean: ${val: -120}"
```

断言只有两条：**`config` 能渲染**、**该变量的值里没有 `#`**。

- **不要拿长度做断言**：`stranger=true` 与 `false` 只差一个字符，长度会变，固定长度只会制造假红。
- 本地复现要给齐 6 个必填变量（compose 里 `${VAR:?...}` 会在渲染阶段校验），缺一个只会看到「config failed」，容易被误认为卡口在工作。
- `config` 只证明 YAML 能渲染，**不证明 JVM 能解析**；最终的真卡口仍是容器起来 + `8510/health` 为 200。
- 排障顺序：`turms-service` `Exited(1)` 且日志首行是 `Unrecognized option` → 先查 JVM opts。后面跟中文或 `P2` 是注释污染；跟合法参数名带 `[]`（如 `-D...uri-list[0]` 被 shell 拆开）是转义问题，两类成因分开查。

## 必要部署前提

- Turms 身份模式是 `jwt`，验签密钥与 Biz 使用同一份文件：`TURMS_GATEWAY_SESSION_IDENTITYACCESSMANAGEMENT_TYPE=jwt`，密钥文件挂到 gateway 的 `/opt/turms/secrets/jwt-hmac256.key` 与 Biz 的 `MONDCHAT_JWT_SECRET_FILE`。
- 建 Turms 用户时使用平台生成、不保存也不分发的随机密码。
- 客户端只能从 `POST /api/sessions` 获得 Turms 凭据。
- **当前** `allowSendMessagesToStranger = true`，因为写路径仍由 Biz 网关代发、且关系投影尚未派发；编排里显式传了 `-Dturms.service.message.allow-send-messages-to-stranger=true`，不吃上游默认值。**切换后**必须翻成 `false`，让 Turms 用投影后的好友与拉黑关系判定；前提是先完成投影回填并让对账三类差异为 0，否则全员私聊立刻回 `5001`。
- 已读只改写调用者自己的读游标，查询历史消息不得顺带把读时间推到最新（否则一登录就把角标清空）；编排里显式传了 `-Dturms.service.conversation.read-receipt.update-read-date-when-user-querying-message=false`，同样不吃上游默认值。**当前**读游标由 Biz 代写（`POST /api/conversations/{type}/{id}/read`），**切换后**由客户端直写 `CONVERSATION.UPDATE`，这条配置的口径不变。

任一前提被改都会破坏「客户端直写 + Turms 侧判定」这条链（未切换时则破坏写入网关的唯一入口）。

Turms 容器的家目录是 `/opt/turms/turms-service`，Java 插件加载目录是 `/opt/turms/turms-service/plugins`（不是镜像根目录）；pinned digest 镜像里没有 JS 引擎，插件只能是 Java jar。插件**当前未挂载、未启用**，限流仍在 Biz。启用方式是把插件打进自建镜像（`infra/turms/Dockerfile`，基础层仍是上游 pinned digest，只往插件目录多拷一个 jar），由服务器 `.env` 的 `MONDCHAT_TURMS_SERVICE_IMAGE` 指向它——投放与回滚步骤见[插件镜像投放](#插件镜像投放一次性人工操作)。

插件的故障半径是**整个 turms-service**：`plugin.yaml` 里的 `class` 不存在或加载失败会让 Spring 上下文 refresh 中止、容器以退出码 1 起不来，不是「插件不生效」。因此：

- 插件镜像上线前必须先用同一个 pinned digest 起一次性容器验证加载、`8510/health` 为 200，通过才把 `MONDCHAT_TURMS_SERVICE_IMAGE` 指过去；
- 生产只跑一个插件版本、不并行多版本；
- 回滚是删掉 `MONDCHAT_TURMS_SERVICE_IMAGE` 那一行再 `up -d`；**「换回上游镜像 + 重启即恢复」必须在 staging 演练通过，才算满足上生产的前置条件**；
- 插件模块不进后端 CI 的 reactor，避免 vendor 编译污染流水线；它由独立 workflow 按路径过滤构建。

插件崩在 Spring 上下文 refresh 阶段，此时 Flyway 与 Mongo 连接已经建立：不会留下半截数据，但连接池会随进程一起断掉，所以它属于「整机不可用」而不是「数据损坏」类故障。

## 本地开发环境

- 清 dev 库必须连 Turms 用户一起清。账号 id 由 PG 序列从 1 亿起分配，同时也是 Turms 用户的 `_id`；只清 PG、留着 Turms 里的旧用户时，Biz 再分配到同一个 id 会被 Turms 回 `409 / 1103`（Mongo `E11000 duplicate key user _id`），Biz 侧表现为注册 `503 upstream_unavailable`——看起来像 Turms 故障，实际是撞号。
- 探 Turms 用 `http://localhost:8510/health`（basic `turms:turms`，`curl.exe` 实测 200 / 5ms）；不要探 `/actuator/*`（Turms 没有该端点），也不要探 `7510`（RPC 端口，HTTP 探测必然超时）。
- 本地起依赖用 `vendor/turms/docker-compose.standalone.yml` 那套，与生产的 [`infra/prod/compose.yaml`](../../infra/prod/compose.yaml) 是两套编排，别混着用。

## 运维边界

V1 单实例起步，不引入消息队列。日志使用控制台与滚动文件双输出；滚动文件写在容器内 `/opt/mondchat/logs`，目录由镜像在 `useradd` 之后建好并交给 uid 10001，**不挂宿主卷**，容器重建即丢，日志不是业务真相——排障先看 `docker logs`。健康检查由 Spring Boot Actuator 提供，不进入业务接口契约。
