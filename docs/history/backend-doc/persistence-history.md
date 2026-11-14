# 持久层决策历史

## 介绍

记录表结构、迁移与 MyBatis-Plus 使用的决策，遵循 [历史决策规范](../README.md)。

## 写入模板

```text
<议题>

<本地时间与时区>   [<UTC 时间>]

<决策>：...

<原因>：...
```

### 资料字段迁移

2026-11-14 20:41 CST   [2026-11-14 12:41 UTC]

决策：新增 `V5__biz_account_profile.sql`，只在 `account_info` 上加列：`gender text not null default 'private'` 带 `account_info_gender_chk`，`birthday date` 可空；不建新表、不加索引。

原因：资料字段天然属于 `account_info`，单独建表会把一账号一行的事实拆成两张表。`gender` 用 DDL 默认值让老行自动回填、建号路径不用改；生日没有合理默认值，留 null 表示未设置。

### 黑名单表

2026-11-14 15:02 CST   [2026-11-14 07:02 UTC]

决策：新增 `V4__biz_blocklist.sql`，主键为 `(owner_account_id, blocked_account_id)`，禁止拉黑自己，不建反向索引；取消拉黑物理删行。

原因：写入与好友申请只查“接收方是否拉黑发送方”，主键前导列足够；黑名单没有需要追溯的状态机。

### 并发重复写

2026-11-11 21:37 CST   [2026-11-11 13:37 UTC]

决策：好友申请与拉人的先查后写用唯一键冲突兜底，翻成 409，不改成单语句 upsert。

原因：唯一键提供原子守卫；常规路径仍用预查给出更准确的业务文案。

### 访问方式

2026-11-04 18:52 CST   [2026-11-04 10:52 UTC]

决策：持久层使用 MyBatis-Plus 的实体 + BaseMapper + Wrapper，不使用注解 SQL、JPA 或裸 JdbcClient。

原因：条件组合、分页与团队现有分层方式更一致。
