# dsh-onebot

把 MondChat 的私聊和群接成 DSH 会话：MondChat 里有人说话 → 唤醒对应会话 → agent 自己决定看不看、回不回。

它是 [OneBot 桥](../onebot) 的应用端，不直接连 Turms，也不碰 MondChat 的数据库。

```
MondChat ── 桥（integrations/onebot）── OneBot 12/WS ── 本插件 ── DSH 会话
```

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
    present.js        ContentBlock 与 OneBot 消息段的呈现辅助
  bridge/client.js    OneBot 12 WS 客户端：连接、echo、退避
  model/              纯数据与纯函数，能脱离宿主单测
    conversation.js   ConversationId、Conversation、describe/titleOf
    message.js        InboundMessage、入站解析、队列上限
    settings.js       全局设置、每会话覆盖、gateFor、时区与安静时段
    prompt.js         结构化提示词（context/language/task/rules/example）
    wake.js           唤醒原因
    bridge.js         BridgeState（进程态 / 连接态分开）
selftest.mjs          假 ctx + 假 WebSocket，覆盖收/发/会话/设置/提示词/面板数据
```

分层只有两条：**`model/` 不碰宿主**（可以单独 assert）；**`routes.js` 不写业务**（校验 + 调 service）。其余按 DSH 的插件习惯，`service.js` 之外没有框架。

## 界面

侧栏面板里和「便签」「自动化任务」并排，点图标在主栏整页打开，显示：

- 桥的进程态与连接态、连的哪个地址；
- 群聊开关、主动话题闸门、安静时段、模型、工作目录；
- 已接入的每个 MondChat 会话：名字、DSH 会话是否在线、还有几条待处理、最近一条消息的时间。

页面每 5 秒刷新一次，数据来自 `/api/mondchat/status`（走共享 `/api` 通道，和别的插件同一套会话鉴权）。

可操作的：

- **启动 / 停止 / 重启桥**：`POST /api/mondchat/bridge`，插件用 `subprocess.spawn` 托管桥进程，卸载时一起停；端口上已有外部桥在应答时禁用启动，避免撞端口；
- **桥地址（含端口）**：同一个 `global` 里的 `bridge`，只认 `ws://` / `wss://`；托管桥时子进程绑的就是这个地址的 host 与 port；
- **时区与回复语言**：`POST /api/mondchat/settings` 的 `global`，写回 profile patch（会触发一次插件重装，桥跟着重连）；
- **每个会话的主动话题闸门**：同一路由的 `gate`（安静分钟、每小时上限、免打扰时段、开关），写 `state.json`，立刻生效不重装；提交空 gate 表示回到全局。

## 行为

| 事 | 怎么做 |
| --- | --- |
| 一个 MondChat 私聊/群 | 一个 DSH 会话，映射存在 `$DSH_HOME/mondchat/state.json`，重启后接着用 |
| 来消息 | 进内存队列，3 秒去抖后给会话发一句唤醒语 |
| agent 看消息 | 调 `mondchat_unread`；读走即清空，不重复出现 |
| agent 发言 | 调 `mondchat_send`；不调就是不想说，没有哨兵文本、没有自动转发 |
| 权限 | 会话建好后按 `permissionPresets` 里 `sandbox === 'read-only'` 的档位压成只读 |
| 主动话题 | 每个会话各自的闸门：安静满 `idleMinutes`、不在免打扰时段、每小时不超过 `maxPerHour` |
| 桥进程 | 可由面板托管（`subprocess.spawn`），也可自己在外面跑；插件只负责连 |
| 断线 | 桥不可达时指数退避重连（最长 30 秒），期间消息不补（桥本身也不回填历史） |
| 唤醒失败 | 排队被拒（比如 agent 正忙）时留着手里的消息，15 秒后补一次重试 |

## 挂载

**本地链接安装**（在 profile 目录，通常是 `%USERPROFILE%\.dsh\profiles\<名字>\`）：

```jsonc
// package.json
{
  "dependencies": { "dsh-onebot": "link:D:/CODE_SPACE/MoonChat/integrations/dsh-onebot" },
  "dsh": { "profile": { "bundles": ["@deepseek-ai/dsh-base", "@deepseek-ai/dsh-web-app", "dsh-onebot"] } }
}
```

```powershell
pnpm install    # profile 目录
# 重启 DSH
```

配置写在 profile 的 `cordis.patch.yml`：

```yaml
- id: mondchat-onebot
  config:
    bridge: ws://127.0.0.1:6700    # 桥地址即端口来源；托管桥时子进程绑这里的 host/port
    # accessToken: ''            # 桥设了 ONEBOT_ACCESS_TOKEN 时才要
    # workspace: /path/to/dir     # 默认 $DSH_HOME/mondchat/workspace
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

自检：`npm test`（假 ctx + 假 WebSocket，覆盖收/发/会话复用/只读预设/主动话题闸门/卸载回收，不连 DSH 也不连桥）。

## 不做什么

- 不读 MondChat 的未读角标、也不替 agent 上报已读——桥不暴露那条路径，agent 的“未读”就是它队列里没取走的；
- 不转发图片/文件（平台没有附件）；
- 不做白名单：能不能私聊由 MondChat 的好友关系决定，能不能在群里说话由群成员关系决定；
- 不把工具注册成全局：只在它自己建出来的会话里可见，你自己的 DSH 会话不会多出 `mondchat_*`。
