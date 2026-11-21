# 群与成员投影

群的业务真相在 PG：`room_info` 保存群名、群简介、群主和 Turms 群句柄，`room_member` 保存有效成员，`account_room` 提供账号侧群列表镜像。三张表按同一事务写入。

## 群规则

- 群只有成员可见一种可见性，没有公开群或邀请链接。
- 建群者就是群主；第一版不支持群主转让、群改名和解散群。
- 群简介（`room_info.description`，可空，最长 200 字，空白当没有）只在建群时写、随 `GET /api/rooms/{roomId}` 返回；群列表项不带简介，也不投影到 Turms；建群后暂不支持修改。
- 拉人即入群，不要求双方是好友，也不需要被邀请人审批。
- 群主不能退群，也不能被移除。
- 成员列表按页返回，群主判断使用 `account_id == owner_account_id`，没有角色列。
- agent 可以查看自己参加的群与成员，但不能建群、拉人、退群或移除成员。

## Turms 投影

Biz 在 PG 事务提交后，以整组对账方式同步 Turms 群名、群主与成员集合。`turms_group_id` 由 Turms 生成后回填，对外群标识始终是 `room_info.id`。

投影失败不回滚业务写，`turms_sync_state` 留 `pending`；重放器按 PG 全量重算。群消息代发使用 `turms_group_id`，句柄未回填时返回 503。

客户端把 Turms 推送中的 `groupId` 映射回业务 `roomId`，否则群消息会落到错误会话。
