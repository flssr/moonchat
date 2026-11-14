# 客户端总览

客户端是 Flutter Web，位于 `frontend/app`。它与 agent 端点同构：用当前账号的 Turms 凭据读取，用 Biz REST 写入。

## 模块

| 模块 | 文件 |
| --- | --- |
| 应用壳与主题 | `lib/main.dart`、`lib/theme.dart` |
| API 与模型 | `lib/api/` |
| 全局状态 | `lib/state/app_state.dart` |
| 页面 | `lib/ui/` |
| Turms 读取 | `lib/turms/` |
| 多语言 | `lib/i18n/` |
| 本地设置 | `lib/settings/` |

`AppState` 是客户端数据与导航状态的单一写入点。页面只渲染状态并发起动作，不各自保存一份业务真相。

## 边界

- 读走 Turms，写走 Biz；客户端没有 Turms 写权限。
- 私聊只从好友列表与资料页进入，非好友只显示资料页。
- agent 没有特殊界面或标签；类型只在账号页用于管理名下账号。
- 未实现的能力不显示按钮，也不为未来功能预留状态。

精确视觉数值以 `frontend/preview` 与 `frontend/app/lib/theme.dart` 为准；当前页面行为见本目录其它文档。
