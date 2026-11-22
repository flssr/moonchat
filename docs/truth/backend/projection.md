# 关系与群的 Turms 投影

PG 是业务真相；Turms 的 `user`、`userRelationship`、`group`、`groupMember` 是派生读模型，可以整份丢弃后从 PG 重建。投影失败不回滚业务写，由派发器与对账收敛。

**当前授权判定仍读 PG**：写入网关按 `friendship` / `blocklist` / `room_member` 判定，Turms 侧这些行还不参与授权。客户端切到直写 Turms 之后才由 Turms 用它们判定；切换前投影只产生读模型，不改变任何用户可见行为。

派发默认关闭：`mondchat.projection.enabled=false` 时事件照常在业务事务里写入 `domain_event`，只是不派发、不对账。这是 P2 之前的默认状态。

关系的创建、删除与拉黑从 `domain_event` 异步投影；建群、解散群与 Turms 群句柄的生成仍走 `RoomProjectionService` 的同步投影，规则见[群与成员投影](room.md)。

## 事件表与派发

`domain_event`（迁移 `V7__biz_domain_event.sql`）是唯一的事件通道：

- 业务变更与事件行在**同一个事务**里提交，PG 提交成功即事件必达，不再有「先写库再发消息」的两阶段。
- `payload` 是该聚合的**目标状态**（jsonb），不是差量；重放与重复投递都收敛到同一结果。
- 派发器单 worker，`where processed_at is null and next_attempt_at <= now() order by id limit 100`；不加 `SKIP LOCKED`（当前只有一个业务进程，见[架构不变量](../architecture.md)）。
- 失败按 `min(2^attempt, 300)` 秒退避，第 10 次失败后转日级重试并写 ERROR 日志，交给对账兜底。
- 已处理事件保留 7 天后按批清理。事件量与关系/群成员的变更频率同频，与消息量无关。
- **同一账号对的事件必须串行**：好友与拉黑在 Turms 里共用一行，交错执行会把 `blockDate` 弄丢；聚合键保证同一对按写入顺序派发。

配置在 `mondchat.projection.*`：`enabled` 默认 **`false`**——P1 阶段只累积事件、不派发；`enabled=true` 是 P2 打开派发与对账的开关，关掉同样只停派发与对账、事件继续累积（灰度回退用它，不删数据）。`dispatch-interval-ms` 默认 2000；`batch-size` 默认 100；`reconcile-cron` 默认每天 03:00。

P2 第一次打开时会一次性派发积压事件，等于一次天然增量回填。打开前先看 `select count(*) from domain_event where processed_at is null`；积压大就按 id 分批放（例如先处理一个范围、确认成功再放下一段），不要一次全推。

## 事件与投影形状

| 事件 | payload | Turms Admin 调用 |
| --- | --- | --- |
| `account.created` | `account_id`、`display_name` | 先 `GET /users?ids=`，不存在则 `POST /users`（幂等） |
| `friendship.changed`，`accepted=true` | `a`、`b`（小 id 在前）、`accepted`、`blocked` | 两个方向各一行：行不存在 → `POST /relationships`，存在 → `PUT` 只补 `establishmentDate`，不碰 `blockDate` |
| `friendship.changed`，`accepted=false` | 同上 | `DELETE /relationships?keys=[kAB,kBA]`；若 `blocked=true`，再 `POST` 两次只带 `blockDate` |
| `blocklist.changed`，`blocked_now=true` | `owner`、`blocked`、`blocked_now`、`friends` | 行不存在 → `POST /relationships`（`blockDate` 有值、`establishmentDate` 为 epoch-0）；存在 → `PUT` 只写 `blockDate` |
| `blocklist.changed`，`blocked_now=false`，`friends=true` | 同上 | `PUT /relationships` 带 `blockDate: "1970-01-01T00:00:00Z"` |
| `blocklist.changed`，`blocked_now=false`，`friends=false` | 同上 | `DELETE /relationships?keys=[k(owner→blocked)]` |
| `room_member.changed` | `room_id`、`account_id`、`turms_group_id`（可空）、`member` | 在册 → `POST /groups/members`；退出 → `DELETE /groups/members`；`turms_group_id` 为空时抛错让事件退避，等群投影回填 |

创建接口一律单条（`POST /users`、`POST /relationships`、`POST /groups/members`）；批量只出现在 `PUT/DELETE /relationships`、`PUT/DELETE /users`、`PUT /users/online-statuses`。回填与新增都逐条调用，没有「批量建关系」这个接口。

## 两条清空与判定规则

Turms 的语义决定了写法，不能想当然：

- **好友判定只看「行存在且 `blockDate` 为空」，不看 `establishmentDate`**。所以删好友必须**物理删行**，只清 `establishmentDate` 不够。
- **清 `blockDate` 只能传 epoch-0 日期**（`1970-01-01T00:00:00Z`）：`PUT /relationships` 的 `blockDate` 为 `null` 时是 no-op（服务层 `areAllNull` 先短路，仓储层 `setOrUnsetDate` 对 `null` 也不做事），只有 `getTime()==0` 才 unset。
- epoch-0 的 `blockDate` 只用于「PG 仍是好友」的对；非好友必须删行，否则 Turms 会凭空认为双方是好友。
- 拉黑陌生人时 `establishmentDate` 传 epoch-0，避免默认值把这一行当成好友行。

## 对账

期望集合三条，全部从 PG 算、只修 Turms、**永不反写 PG**：

1. 每对 `accepted` 好友期望 Turms 有两个方向的行且 `blockDate` 为空；
2. 每条 `blocklist` 期望对应方向 `blockDate` 非空，反向为空（除非反向也拉黑）；
3. 每群成员数与 `room_member` 在册数一致；Turms 的 `Group` 没有成员数字段，只能读 `GET /groups/members` 的分页 `total` 或逐页数。

差异动作两种：Turms 少行 → 补一条 `processed_at` 为空的事件，走正常派发；Turms 多行 → 批量 `DELETE /relationships` 或逐条 `DELETE /groups/members`。

## 已知上限

- 派发是单 worker、不加 `SKIP LOCKED`；多 worker 时必须先补行锁。
- 「删好友且仍在拉黑」要两次调用（`DELETE` 后 `POST`），中间有毫秒级窗口该对既非好友也无拉黑；当前 `allowSendMessagesToStranger = true`，窗口不产生用户可见后果。
- Turms 侧关系缓存上限 8096 条、过期 60 秒：投影对 Turms 判定的影响最坏滞后一分钟。切换授权前必须把这条写进切换验收。

## 已知风险

自研插件（例如切换后接管限流的 `ClientRequestHandler`）运行在 turms-service 进程内，发布与消息引擎耦合：插件加载失败会让**整个 turms-service 起不来**，不是「功能不生效」。上线前必须用同一 pinned digest 起一次性容器验证加载（`8510/health` 200），生产只挂一个版本，回滚靠清空插件目录重启。这是客户端直写 Turms 路线的固定代价，切换时要明确接受。

插件模块（`mondchat-turms-plugin`）当前**未编译验证**：`vendor/turms` 的 `pom.xml` 要求 JDK 25，而本机 JDK 只有 11/20/21，`target/classes` 与本地仓库里现成的 Turms 构件都是 class version 69，javac 21 读不了。P2 启用插件前必须先有一套 JDK 25 构建环境，建议用 `maven + JDK 25` 镜像在容器内编译 vendor 与插件、把产物拷出，不动本机工具链；跟 Turms 升级时同理，每次都要这条构建链。
