# dsh-onebot

把 MondChat 的私聊和群接成 DSH 会话：MondChat 里有人说话 → 唤醒对应会话 → agent 自己决定看不看、回不回。

它是 [OneBot 桥](../onebot) 的应用端，不直接连 Turms，也不碰 MondChat 的数据库。

```
MondChat ── 桥（integrations/onebot）── OneBot 12/WS ── 本插件 ── DSH 会话
```

## 界面

装在 DSH 里之后，**设置 → 插件 → MondChat** 多一个页签，显示：

- 桥有没有连上、连的哪个地址；
- 群聊开关、主动话题的闸门值、安静时段、工作目录与模型；
- 已接入的每个 MondChat 会话：名字、DSH 会话是否在线、还有几条待处理、最近一条消息的时间。

页面每 5 秒刷新一次，数据来自宿主的只读路由 `/api/mondchat/status`（走共享 `/api` 通道，和别的插件同一套会话鉴权）。它只读，改配置仍然写 profile 的 `cordis.patch.yml`。

## 行为

| 事 | 怎么做 |
| --- | --- |
| 一个 MondChat 私聊/群 | 一个 DSH 会话，映射存在 `$DSH_HOME/mondchat/state.json`，重启后接着用 |
| 来消息 | 进内存队列，3 秒去抖后给会话发一句唤醒语 |
| agent 看消息 | 调 `mondchat_unread`；读走即清空，不重复出现 |
| agent 发言 | 调 `mondchat_send`；不调就是不想说，没有哨兵文本、没有自动转发 |
| 权限 | 会话建好后按 `permissionPresets` 里 `sandbox === 'read-only'` 的档位压成只读 |
| 主动话题 | 只在群里：安静满 `idleMinutes`（默认 60）且不在安静时段，每小时最多 `maxPerHour`（默认 2）次 |
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
    bridge: ws://127.0.0.1:6700
    # accessToken: ''            # 桥设了 ONEBOT_ACCESS_TOKEN 时才要
    # workspace: /path/to/dir     # 默认 $DSH_HOME/mondchat/workspace
    # groups: true
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
