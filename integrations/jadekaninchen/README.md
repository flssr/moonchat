# Jadekaninchen

Jadekaninchen 是 [OneBot 桥](../onebot) 的 DSH 应用端：把 MondChat 的私聊和群接成 DSH 会话，MondChat 里有人说话 → 唤醒对应会话 → agent 自己决定看不看、回不回。

它不直接连 Turms，也不碰 MondChat 的数据库。桥与插件都在 agent 侧：消息经该 agent 同账号的 Turms `/im` 直写，好友申请、群成员等业务动作仍走 Biz。

```
MondChat ── 桥（integrations/onebot）── OneBot 12/WS ── 本插件 ── DSH 会话
```

启用直写的前提是写凭据开关已开、投影已回填并对账通过、`allowSendMessagesToStranger=false` 已生效；限流由 Turms 插件执行，不在插件或桥里写死阈值。

## 结构

```
index.js              装配：建服务、ctx.provide('mondchat')、挂路由
src/
  service.js          用例层：会话、桥、设置、定时器；面板/工具/路由都调它
  routes.js           HTTP 路由：只做协议转换，注册进宿主共享 /api 通道
  tools.js            工具注册：只决定把哪些工具挂到哪个 agent
  tools/              每个工具一个文件
    unread.js         mondchat_unread：取走积压消息
    send.js           mondchat_send：在当前会话发言
    recall.js         mondchat_recall：读本地长期记忆
    present.js        ContentBlock 与 OneBot 消息段的呈现辅助
  memory/
    store.js          原话层：JSONL 追加、按会话读、30 天保留期
    short.js          短期层：每会话滚动摘要
    core.js           长期层入口：SQLite 优先，JSON 回退
    core-sqlite.js    SQLite + FTS5 BM25
    core-json.js      JSON 回退与旧事实迁移
    compress.js       压缩提示词、模型输出解析与夹紧
    model.js          后台记忆任务的最小宿主模型调用
  persona/
    personas.js       人格卡：seed、frontmatter、当前正文
  bridge/client.js    OneBot 12 WS 客户端：连接、echo、退避
  model/              纯数据与纯函数，能脱离宿主单测
    conversation.js   ConversationId、Conversation、describe/titleOf
    message.js        InboundMessage、入站解析、队列上限
    settings.js       全局设置、每会话覆盖、gateFor、时区与安静时段
    prompt.js         结构化提示词（context/language/task/rules/example）
    wake.js           唤醒原因
    bridge.js         BridgeState（进程态 / 连接态分开）
personas/             自带人格卡，首次启动复制到数据目录
mock-onebot.mjs       简易 OneBot 12 mock 服务端：没有 IM 时冒充桥
mock-onebot.test.mjs  mock 服务的真实 WS 冒烟
ws-integration.test.mjs  mock WS + 插件 bridge/记忆/人格路由的端到端联调
selftest.mjs          假 ctx + 假 WebSocket，覆盖收/发/会话/设置/提示词/记忆
```

分层只有两条：**`model/` 不碰宿主**（可以单独 assert）；**`routes.js` 不写业务**（校验 + 调 service）。其余按 DSH 的插件习惯，`service.js` 之外没有框架。

## 开发规范

**分层**

| 文件 | 可以做什么 | 不可以做什么 |
| --- | --- | --- |
| `index.js` | 建服务、`ctx.provide`、挂路由 | 写业务逻辑 |
| `src/service.js` | 用例与状态、定时器、桥进程 | 认 HTTP、认槽位、拼提示词 |
| `src/routes.js` | 解析请求、调 service、包 JSON | 业务判定（该不该发、能不能改） |
| `src/tools.js` | 决定挂哪些工具 | 工具本体 |
| `src/tools/<name>.js` | 单个工具的 schema 与校验 | 跨工具共享状态 |
| `src/bridge/client.js` | OneBot 12 协议：连接、echo、退避 | 会话、设置、持久化 |
| `src/model/` | 纯数据与纯函数 | `import node:http`、读环境变量、起定时器 |

**实体**

- 会话标识用 `ConversationId` 的概念（`kind` + `id`），不要在任何地方手拼 `'private:100'` 字符串再拆；
- 会话的数据放在一个 `Conversation` 里，不要再开平行的 `Map` 存队列/丢弃/最近活动；
- 实体只存数据；推进状态用 `recordMessage` / `takeMessages` / `gateFor` 这类纯函数返回新对象。

**提示词**

- 只有一套英文模板，边界靠标签（`<context>` / `<task>` / `<rules>` / `<example>`）；
- 回复语言的唯一来源是 `<language>`，模板本身不能出现中文（群名、人名是数据，可以是中文）；
- 改模板必须同步 `selftest.mjs` 里的标签断言。

**配置**

- 声明式配置（桥地址、时区、语言、闸门默认值）进 profile patch，经 `configEditor` 写；
- 运行时数据（每会话覆盖、会话映射）进 `state.json`；两者互不覆盖；
- 记忆分三层：原话进 `$DSH_HOME/mondchat/memory.jsonl`，短期摘要进 `memory-short.json`，长期事实进 `memory-core.sqlite`（FTS5）；可用 `memoryFile` / `shortMemoryFile` / `coreDatabaseFile` 覆盖；旧的 `memory-core.json` 首次启动自动导入并改名留档；
- 原话只追加，不参与 `state.json` 的整体重写；摘要和事实单独原子替换；
- 密钥只从 `accountKey` 或 `accountKeyFile` 读，不进日志、不进 `state.json`、不写进 patch。

**测试**

- `npm test` 必须绿；新增分支或纯函数至少留一条 `assert`；
- 不引测试框架，不写 fixture 文件；假宿主在 `selftest.mjs` 的 `makeHost` 里，新服务方法/路由要在那里补用例；
- 涉及真机行为（桥连接、面板渲染）的改动，说明验到哪一步、哪些没验。

**提交与文档**

- 提交用中文陈述句，一次提交只做一件事；
- 行为变化同步本 README；若触及平台边界（Biz 的写入口、Turms 凭据、agent 收消息口径），同时改 `docs/truth` 并只在 `docs/history` 追加；
- 不提交密钥、`node_modules`、临时探针脚本。

**改完怎么验**

```powershell
cd integrations/jadekaninchen && npm test
# 真宿主里重载：plugin_manager set_bundle jadekaninchen(false) → 再 true
# 然后看 6700 上有没有连接（插件 ↔ 桥）
```

## 没有 IM 时怎么测

Turms/IM 在维护时，不需要等真桥：用仓库里的 `mock-onebot.mjs` 冒充 `integrations/onebot` 的 6700 端口，发私聊/群消息给插件，插件的记忆、唤醒和工具都照常跑。

```powershell
cd integrations/jadekaninchen
node mock-onebot.mjs --port 6700
# 另一个窗口：把插件配置的 bridge 指到 ws://127.0.0.1:6700
```

mock 起来后按提示在终端输入：`p <文本>` 发私聊，`g <文本>` 发群聊，`q` 退出。`--interval 5000` 可以每 5 秒自动发一条；`--text` 起来后先发一条。它只实现插件用到的动作和事件，不连 Turms，也不写数据库。

自动化联调：`node ws-integration.test.mjs` 会起 mock 桥、真实连上插件的 bridge 客户端，走一遍消息入队、人格注入、短期/长期记忆、压缩、`mondchat_recall`、发言和人格编辑路由；不需要 DSH 或 IM。

**不做**

- 不在插件里发明 OneBot 私有动作，协议面归 `integrations/onebot`；
- 不在客户端做业务判定，面板只呈现与提交。

## 界面

侧栏面板里和「便签」「自动化任务」并排，点图标在主栏整页打开，显示：

- 桥的进程态与连接态、连的哪个地址；
- 群聊开关、主动话题闸门、安静时段、模型、工作目录；
- 已接入的每个 MondChat 会话：名字、DSH 会话是否在线、还有几条待处理、最近一条消息的时间。

页面每 5 秒刷新一次，数据来自 `/api/mondchat/status`（走共享 `/api` 通道，和别的插件同一套会话鉴权）。

可操作的：

- **启动 / 停止 / 重启桥**：`POST /api/mondchat/bridge`，插件用 `subprocess.spawn` 托管桥进程，卸载时一起停；只允许操作自己托管的桥。端口上已有外部桥在应答时，面板禁用启动与重启，服务层和路由也会拒绝外部桥的启动、停止与重启，避免重复进程和撞端口；
- **桥地址（含端口）**：同一个 `global` 里的 `bridge`，只认 `ws://` / `wss://`；托管桥时子进程绑的就是这个地址的 host 与 port；
- **时区与回复语言**：`POST /api/mondchat/settings` 的 `global`，写回 profile patch（会触发一次插件重装，桥跟着重连）；
- **每个会话的主动话题闸门**：同一路由的 `gate`（安静分钟、每小时上限、免打扰时段、开关），写 `state.json`，立刻生效不重装；提交空 gate 表示回到全局。

## 行为

| 事 | 怎么做 |
| --- | --- |
| 一个 MondChat 私聊/群 | 一个 DSH 会话，映射存在 `$DSH_HOME/mondchat/state.json`，重启后接着用 |
| 来消息 | 进内存队列，3 秒去抖后给会话发一句唤醒语 |
| agent 看消息 | 调 `mondchat_unread`；读走即清空，不重复出现 |
| agent 回忆 | 调 `mondchat_recall`；短期摘要 + 长期事实 + 原话兜底，取走队列或重启后仍在，可按关键词检索 |
| 记忆整理 | 原话攒到阈值或会话空闲时，后台调一次宿主模型：更早的段落压成短期摘要，重要事实进核心记忆；永远保留最后 `tailMessages` 条原话 |
| agent 发言 | 调 `mondchat_send`；不调就是不想说，没有哨兵文本、没有自动转发 |
| 权限 | 会话建好后按 `permissionPresets` 里 `sandbox === 'read-only'` 的档位压成只读 |
| 主动话题 | 每个会话各自的闸门：安静满 `idleMinutes`、不在免打扰时段、每小时不超过 `maxPerHour` |
| 桥进程 | 可由面板托管（`subprocess.spawn`），也可自己在外面跑；插件只负责连，不接管外部桥的启停 |
| 断线 | 桥不可达时指数退避重连（最长 30 秒），期间消息不补（桥本身也不回填历史） |
| 唤醒失败 | 排队被拒（比如 agent 正忙）时留着手里的消息，15 秒后补一次重试 |

## 记忆

三层，互不替代：

| 层 | 存什么 | 在哪 |
| --- | --- | --- |
| 原话 | 每条入站/出站消息，保留 30 天 | `memory.jsonl` |
| 短期 | 每个会话一段滚动摘要，覆盖更早的段落 | `memory-short.json` |
| 长期 | 结构化事实（文本、主体、重要度、是否过时） | `memory-core.sqlite` |

- 触发：原话攒到 `compressMessages` 条或 `compressChars` 字符，或会话空闲 `idleMinutes` 分钟后，后台调一次宿主模型；永远保留最后 `tailMessages` 条原话，压缩边界附近不会只剩摘要。
- 长期事实先和同会话、同主体的旧事实比对：能合并就合并，冲突（否定词/数字不同）把旧的标 `stale`，不直接删。检索用 SQLite FTS5 的中文二元切词 + BM25，再乘重要度和新近程度；`node:sqlite` 不可用时自动回退 JSON 后端。
- 作用域：事实只在原会话可见，不跨私聊也不进群；人物档案按账号持久化，但不会把别处的私聊内容带进来。短期摘要也按会话隔离。
- 失败：模型不可用、输出不是合法 JSON 或调用失败时，原话和旧摘要都不动，下次再试；摘要先落盘成功，原话仍按保留期管理。
- 成本：一次整理最多一次模型调用，只有在阈值/空闲触发时才发生；不做向量检索，不引 embedding。

## 人格

人格卡是 Markdown 文件，放在 `$DSH_HOME/mondchat/personas/`：

```markdown
---
name: Jadekaninchen
description: 一句话介绍这个人格
tags: [默认, 简洁]
---

## 身份
你是谁、在什么场景里聊天。

## 说话方式
句子长短、语气、常用词、要不要用 Markdown、要不要用表情。

## 性格与偏好
在意什么、不喜欢什么、遇到不同意见怎么处理。

## 边界
不能做什么、不能假装拥有什么、隐私和群聊里的规矩。
```

- 字段：`name` 必填（最多 40 字）；`description` 可选（最多 120 字）；`tags` 可选（最多 8 个，每个最多 20 字）；正文必填（最多 20000 字）。
- 正文建议按「身份 / 说话方式 / 性格与偏好 / 边界」四段写；模板可以在面板里一键填入。
- 插件自带 `personas/jadekaninchen.md`；首次启动复制到数据目录，不覆盖用户已改的版本。
- 面板「人格编辑器」可以选已有的人格、新建、改名称/简介/标签/正文、删除非当前人格；保存写 Markdown 文件。
- 当前人格仍由配置 `persona` 指定：在设置卡的人格下拉里选中后点保存，插件重装一次生效。
- 人格正文放在每轮唤醒提示词最前面（`<persona>`），然后才是时间、会话、记忆和任务。
- 人格 id 只认英文字母、数字、`-`、`_`；文件坏了跳过，找不到就退回列表第一个/兜底文本。
- 现在记忆按会话存，不按人格隔离：换人格不会清空记忆，也不会自动复制一份新记忆。需要“一人格一记忆”时再按人格分目录。

## 挂载

**本地链接安装**（在 profile 目录，通常是 `%USERPROFILE%\.dsh\profiles\<名字>\`）：

```jsonc
// package.json
{
  "dependencies": { "jadekaninchen": "link:D:/CODE_SPACE/MoonChat/integrations/jadekaninchen" },
  "dsh": { "profile": { "bundles": ["@deepseek-ai/dsh-base", "@deepseek-ai/dsh-web-app", "jadekaninchen"] } }
}
```

```powershell
pnpm install    # profile 目录
# 重启 DSH
```

配置写在 profile 的 `cordis.patch.yml`：

```yaml
- id: jadekaninchen
  config:
    bridge: ws://127.0.0.1:6700    # 桥地址即端口来源；托管桥时子进程绑这里的 host/port
    # accessToken: ''            # 桥设了 ONEBOT_ACCESS_TOKEN 时才要；托管时原样传给子进程
    # workspace: /path/to/dir     # 默认 $DSH_HOME/mondchat/workspace
    # persona: jadekaninchen     # 数据目录 personas/<id>.md
    # memoryFile: /path/to/memory.jsonl   # 默认 $DSH_HOME/mondchat/memory.jsonl
    # shortMemoryFile: /path/to/memory-short.json
    # coreDatabaseFile: /path/to/memory-core.sqlite
    # coreMemoryFile: /path/to/memory-core.json   # 旧 JSON 首次启动自动导入
    # memory:
    #   auto: true                 # false = 只手动 compressNow
    #   compressMessages: 40      # 攒够多少条原话触发
    #   compressChars: 24000      # 或攒够多少字符触发
    #   tailMessages: 12          # 压缩时永远留多少条原话
    #   idleMinutes: 10           # 空闲多久后整理
    #   retainDays: 30            # 原话保留天数
    # groups: true
    # timezone: Asia/Shanghai     # 空 = 跟随宿主；提示词里的时间与免打扰都按它算
    # language: zh                # 回复语言，写进提示词的 <language>
    # accountKeyFile: ~/.mondchat.key   # 面板启停桥时读它；也可以直接给 accountKey
    # apiBase: https://api.mondchat.com
    # bridgeScript: /path/to/integrations/onebot/bridge.mjs   # 默认按插件位置推导
    # bridgeCommand: [node, /path/to/bridge.mjs]              # 给了就覆盖上面两行
    # model: { provider: deepseek, model: deepseek-chat }   # 不填就跟 DSH 默认
    # proactive:
    #   enabled: true
    #   idleMinutes: 60
    #   maxPerHour: 2
    #   quietHours: '23:00-08:00'
```

自检：`npm test`（假 ctx + 假 WebSocket，覆盖收/发/会话复用/只读预设/主动话题闸门/token 传递/托管桥重启/外部桥启停防护/卸载回收/人格 seed 与提示词、三层记忆写入、合并、检索、压缩解析与提示词注入；外加 mock-onebot 的真实 WS 冒烟和 mock WS + 插件 bridge/记忆/人格路由的端到端联调；不连 DSH 也不连真桥）。

## 不做什么

- 不读 MondChat 的未读角标、也不替 agent 上报已读——桥不暴露那条路径，agent 的“未读”就是它队列里没取走的；
- 不转发图片/文件（平台没有附件）；
- 不做白名单：能不能私聊由 MondChat 的好友关系决定，能不能在群里说话由群成员关系决定；
- 不把工具注册成全局：只在它自己建出来的会话里可见，你自己的 DSH 会话不会多出 `mondchat_*`；
- 记忆只在本机：原话 + 短期摘要 + 结构化事实，不做向量检索、不做平台托管记忆；需要语义召回时再在 `src/memory/` 上扩。
