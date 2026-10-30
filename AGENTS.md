# AGENTS.md

给在本仓库工作的 AI agent 的入口文档。人看的项目概览在 `README.md`，文档台账与阅读路径在 `docs/README.md`。

**这份文件只写约束与规矩，不写设计。** 设计内容一律在 8 份 spec 里；本文与 spec 冲突时以 spec 为准，并把冲突报告给用户。

---

## 0. 先认清这个仓库的状态

- **纯设计仓库**：`docs/` 下 8 份 markdown spec + 根目录两份导航文件，**没有任何代码**，没有 `package.json` / `pom.xml` / 构建脚本 / 测试。
- 因此：**不要凭空发明 `npm test`、`mvn verify`、`docker compose up` 之类的命令**；不要把「缺少脚手架」当缺陷去自动补全；不要为了「让仓库看起来完整」而新增 `src/`、CI 配置、lint 规则。
- 当前唯一有价值的产出是**文档的可信度**：一份自相矛盾的 spec 比没有 spec 更糟。
- 用户明确要求「开始实现」时，先确认落在哪个里程碑切片（见 [§6](#6-范围纪律按切片推进)），再动手。

---

## 1. 按任务决定读哪几份

| 你要做的事 | 必读 |
| --- | --- |
| 任何改动之前 | `docs/goal-and-requirements.md`（产品命题、Non-Goals、M1/M2/M3） |
| 判断某能力该不该做、属于哪一片 | `docs/goal-and-requirements.md` + `docs/architecture.md` |
| 动手改架构、跨模块行为、数据归属 | `docs/architecture.md`（硬规矩、数据归属表、一条消息的旅程、跨模块不变量） |
| 消息 / 群成员 / 会话 / 只读查询 | `docs/messaging-and-tunnel.md` |
| 账号、归属、切换账号、来源标记 | `docs/account-and-ownership.md` |
| 工作区、offline、投递档位、拉取范围 | `docs/workspace.md` |
| webhook、connector、限流、无响应 | `docs/agent-connection.md` |
| 帖子、动态流、图片、举报与处置 | `docs/content-and-moderation.md` |
| 进程拆分、部署单元、扩容 | `docs/deployment.md` |

依赖方向看 `docs/README.md` 台账里的 `depends-on` 列：**先读依赖，再读自己**。

---

## 2. spec 是唯一真相

spec 文件靠 frontmatter 里的 `id` / `type` 被 spec-graph 索引，因此：

- **frontmatter 不许删、不许改名**。schema 固定为 `id` / `type` / `status` / `title` / `parent` / `depends-on`。
- `id` 一旦发布不改（形如 `moonchat-product`、`moonchat-workspaces`），改 id 等于断开所有引用。
- `parent` / `depends-on` 只能指向**已存在的 id**。
- 每份 spec 的正文以一行 `**一句话**：…` 开头，这是它的定位句；改模块职责时这句必须同步改。

改动纪律：

- **改行为 = 改 spec**。任何影响边界、契约、不变量的改动，必须先落到对应 spec，再谈实现。反过来，实现暴露了 spec 没定的东西，先补 spec。
- **新增或删除 spec 文件，必须同步 `docs/README.md` 的台账表**，否则索引立刻开始骗人。
- **根目录只放 `README.md` 与 `AGENTS.md`**，设计内容一律在 `docs/`。
- **不要在仓库里新建临时 markdown**（`NOTES.md`、`TODO.md`、`plan.md`、`草稿.md` 之类）。计划用对话内的 TODO，草稿写在对话里。`docs/` 里每一份文件都必须是正式 spec，且已登记在 `docs/README.md` 台账。
- 已经写在 spec 里的「已定的简化」不是待办事项，是决定（见 §4）。

---

## 3. 硬边界：违反即错，不要「顺手」放松

这五条是整套设计成立的支点，代码里任何一处绕开它们，架构都不再是它描述的样子。

| 边界 | 含意 | 常见误犯 |
| --- | --- | --- |
| **消息只由隧道写入** | 能向 Turms 写消息的只有真人客户端与 `agent-connector`；`moonchat-biz` 一条消息都不发 | 在业务服务里加「发一条系统通知到房间」的便捷方法 |
| **`im-facade` 门里没有发送的手** | 它只能建群、改成员、签发凭据、只读查询 | 为了「少一次往返」把 send 加进 `im-facade` |
| **Biz 不碰实时消息流** | 只在需要时做只读查询，不参与投递 | 让 Biz 订阅消息事件做计数 / 通知 / 审计 |
| **身份只有一处真相** | `account.id` 就是 Turms 用户 id；归属关系本身就是授权，没有授权表、没有临时凭据、没有第二套映射 | 给 agent 单独建 `agent_user_mapping` 表 |
| **connector 不持有业务真相** | 归属、密钥、工作区、offline 全在 PG；connector 只做可重建的短时缓存 | 让 connector 持久化投递库并当成真相 |

另外三条容易踩的语义边界：

- **档位只裁剪投递内容**（`push_all` / `signal_only` / `mention_only`），**不改变成员关系、不改变可读范围**。拉取出口能看到的范围，与投递路径完全一致。档位的**写入口只有 Biz**，connector 只读解析结果。
- **一条消息只进它所在会话的那一个工作区**。跨工作区可共享的只有稳定 id（账号、群、工作区），**不共享内容**；档位改不了这条。
- **来源标记（`agent` / `owner`）只进审计与限流，不作权限判定**。房间与对外接口都不区分两者。

还有两条时间维度上的不变量：

- **没有历史回填**：新建工作区只从实时消息开始；`since_seq` 补的是「已在投递范围内的那一段」，不是进群之前的历史。
- **权限由群成员关系与房间可见性决定**，工作区只是切片，从来不是权限边界。

---

## 4. 「已定的简化」不是待办，别私自升级

下面每一条都是**有意不做**，并且都写明了重启条件。除非用户明确要求**且**你先改了对应 spec，否则一律保持现状：

| 简化 | 依据 |
| --- | --- |
| 不做消息搜索 | `docs/messaging-and-tunnel.md`（避免一上手就引入索引管道与权限过滤） |
| 不做打分排序，只有两条时间倒序的流 | `docs/content-and-moderation.md` |
| 不做 agent 目录 / 公开列表，靠主页链接与 @ 提及 | `docs/content-and-moderation.md`、`docs/goal-and-requirements.md` |
| 图片不做机器审核，只靠举报 | `docs/content-and-moderation.md` |
| agent 不能凭空发起新私信，只能回复已有会话 | `docs/agent-connection.md` |
| `offline` 只到工作区粒度，不做按消息类型的细粒度静音 | `docs/workspace.md` |
| `connector` 单实例，不做会话分片 | `docs/deployment.md` |
| 不做全局限流桶，只做「账号 → 工作区」两级桶 | `docs/agent-connection.md`、`docs/goal-and-requirements.md` |
| Biz 与 connector 是**一个代码库、两个启动模块**，不是微服务 | `docs/deployment.md` |

`docs/deployment.md` 里另有 connector 升格为微服务的**触发条件**（第二个内部消费者 / 独立团队与发布窗口 / 按 agent 数量分片）——没同时满足就不要提议拆分。

---

## 5. 三处已知缺口：动到相关代码前必须处理

1. **默认投递档位标着「（未确认）」**（`docs/workspace.md`）：默认是 `push_all`，但这是待确认的决定。不要把它当成定论去写死，也不要在别处复制这个默认值——默认值只在 `account.default_delivery_mode` 一处定义。
2. **轻信号合并窗口 5 秒标着「（未确认）」**（`docs/workspace.md`、`docs/agent-connection.md`）：实现前若仍是未确认状态，先问用户，并同步改两处。
3. **「无响应」判据在档位上线后不成立**（`docs/agent-connection.md`）：现有判据是「60 秒内没说话」，但 `mention_only` 的 agent 本不该说话、`signal_only` 的可能还在等合并窗口，直接沿用会制造大量假无响应。**M2 之前必须按档位重写为：只有该工作区确实发生过投递、且 agent 在 60 秒内没有任何动作时才提示。** 碰这段逻辑时不要沿用旧判据。

---

## 6. 范围纪律：按切片推进

产品按 M1 / M2 / M3 三个里程碑切片，**每一片结束时都是可验证状态，不按「做完一半」推进**（`docs/goal-and-requirements.md`）。

- 接到实现请求，先回答两个问题：它属于哪一片？该片的验收判据是什么？
- **M1 不包含**：私信、归属者切账号、无响应提示、举报与封禁、`offline` 开关、公开房非成员只读、图片、动态流与关注、多端同步、消息搜索、agent 主页。M1 里遇到这些需求 = 范围越界，报告给用户，不要「先做个简单的版本」。
- **Non-Goals 一律不动**：语音与视频通话、平台托管 agent 的记忆与上下文、账号转让与共同归属、agent 市场 / 付费订阅 / 平台代收模型费、应用商店上架（第一版只发 Flutter Web 构建）。这些不是延期项，是产品选择。
- 只做了「能跑」的一半功能而没满足该片验收判据，比没做更糟——它会让人误判命题成立。

---

## 7. 写文档的约定

- **语言**：中文，陈述式。术语表固定：**账号**（human / agent 同构）、**归属者**、**工作区**、**房间**、**会话**、**档位**、**隧道**（Turms 侧）、**业务层**（`moonchat-biz`）、**接入层**（`agent-connector`）、**端点**（用户自己的 agent 服务）、**connector**。
- **不发明同义词**：不要写「机器人 / bot / 助理」代指 agent，不要写「群组 / 频道」代指房间。
- **一句定位句**：每份 spec 开头保留 `**一句话**：…`。
- **数字必须带依据**：任何阈值（300ms、60 秒、5 秒、两级桶）要么给出理由，要么明确标「（未确认）」。凭空引入一个数字是最常见的 spec 污染。
- **表格优先**：边界、基数、判据、取舍对比一律用表格，别写成散文。
- **不写营销词**：不出现「无缝」「极致」「赋能」。这里的读者是下一个要改这段设计的人。

---

## 8. 提交规范

跟随仓库现有风格（`git log` 只有两条：`Initial commit` 与一条中文陈述句）：

- **中文、陈述式主题句**，说清「做了什么决定 / 改了什么」，例如：`落地 MoonChat MVP 决策：三档投递、拉取出口与 M1/M2/M3 切片`。
- **不加 Conventional Commits 前缀**（`feat:` / `docs:`），不加 emoji，不加工具署名。
- **一次提交一件事**：改 spec 与改受它约束的代码放在同一次提交里；无关的措辞润色单独提。
- 提交信息里不出现 TODO 编号、计划步骤名。

---

## 9. 交付前自检

- [ ] 改动是否触犯 §3 的任何一条硬边界？
- [ ] 是否把 §4 的某条「已定的简化」顺手升级了？
- [ ] 是否落进了 §6 里 M1 不包含的范围，或撞上 Non-Goals？
- [ ] 改了行为有没有同步改 spec？改了 spec 有没有同步改 `docs/README.md` 台账？
- [ ] frontmatter 完整、`id` 未改、`parent` / `depends-on` 指向存在的 id？
- [ ] 新引入的数字有没有依据或「（未确认）」标记？
- [ ] 有没有新建临时 markdown，或在根目录多出文件（只允许 `README.md` 与 `AGENTS.md`）？

无法自行判断时，**停下来问用户**，不要用「先做一个合理版本」代替决定。
