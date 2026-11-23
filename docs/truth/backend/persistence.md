# 持久层与数据

PostgreSQL 当前有九张表，Flyway 八个迁移文件，持久层统一使用 MyBatis-Plus。

| 迁移 | 表 |
| --- | --- |
| `V1__biz_account.sql` | `account`、`account_info` |
| `V2__biz_friendship.sql` | `friendship`、`friendship_reverse` |
| `V3__biz_room.sql` | `room_info`、`room_member`、`account_room` |
| `V4__biz_blocklist.sql` | `blocklist` |
| `V5__biz_account_profile.sql` | 不建表：`account_info` 增加 `gender`（`text not null default 'private'`，枚举 male/female/other/private）与 `birthday`（`date` 可空） |
| `V6__biz_account_avatar.sql` | 不建表：`account_info` 增加 `avatar`（`text` 可空，平台默认头像 key，null = 客户端生成首字头像） |
| `V7__biz_domain_event.sql` | `domain_event`（投影事件 outbox） |
| `V8__biz_room_description.sql` | 不建表：`room_info` 增加 `description`（`text` 可空，`check` 长度 ≤ 200，空白当没有） |

## 共同约定

- 表名与列名使用单数 snake_case；id 统一 `bigint`。
- 时间列为 `timestamptz`，由应用写入，不建更新时间触发器。
- 枚举用 `text + check`。
- 外键是逻辑外键，DDL 不写 `references` 或级联删除。
- 账号、群和认证信息不建第二套 Turms 映射表。
- 消息、会话、限流桶、来源日志都不进 PG。
- 投影事件表 `domain_event` 是业务事件的暂存，不是业务真相；它可清空、不参与授权，设计与派发规则见[投影](projection.md)。

`friendship_reverse` 与 `account_room` 是可重建查询镜像，主表才是授权真相。好友与成员删除写 tombstone，物理 purge 的保留期和频率尚未确定。

## 只能由应用守的规则

主从镜像同事务、群主始终是有效成员、真人账号必须属于真人归属者、软删查询排除、私聊好友授权与群成员授权，都必须由 Biz 事务和领域逻辑保证。数据库唯一键作为并发重复写的最后守卫。

黑名单每人最多 100 条：插入前按 `owner_account_id` 计数，达到上限回 409 `blocklist_full`。并发下 99→100 时最多多进 1 条，可容忍，不加锁、不加数据库约束。
