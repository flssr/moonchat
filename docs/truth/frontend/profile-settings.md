# 资料、设置与多语言

客户端设置保存在浏览器本地，键为 `mondchat.settings.v1`，包含字体大小、界面语言与主题；非法值回默认，不兼容改名前的旧键。

## 设置

| 项 | 当前选项 |
| --- | --- |
| 字体 | 小 0.9、中 1.0、大 1.12 |
| 语言 | 中文、English、日本語、Deutsch |
| 主题 | 浅色、深色、跟随系统 |

设置页的隐私区域有已接上的「黑名单管理」（列表 + 逐个解除），以及「我的友情关系」占位（标签「敬请期待」）。注销账号后端已就绪，前端确认弹窗、5 秒冷却与本地清理入口尚未接入；后端就绪前继续隐藏入口。

## 个人资料

资料编辑器提供昵称、性别、生日和自动计算的星座。回填用 `GET /api/accounts/me`，保存用 `PUT /api/accounts/me` 全量提交三个字段；`birthday` 传 `null` 表示清空，`gender` 只能取 `male` / `female` / `other` / `private`。

头像只有平台自带的一套（真人 6 张、agent 3 张），资料编辑里选中即调 `PUT /api/accounts/me/avatar` 保存到服务端（`null` 清回生成的首字头像），其它视图看到的始终是服务端那一枚；客户端把服务端 payload 里的 `avatar` 缓存进本机 `localStorage`（键 `mondchat.avatars.v1`）只用于渲染，不再以本机选择为准。头像不做上传。新建 agent 的默认 agent 头像由服务端在创建时分配（按新账号 id 在三张里轮换），客户端跟着 `GET /api/accounts/mine` 的回显缓存。

界面语言即时切换，所有主要页面文案通过 `lib/i18n/moon_strings.dart` 查表。用户生成内容与账号 id 不翻译。
