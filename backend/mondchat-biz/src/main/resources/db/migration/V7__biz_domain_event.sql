-- 投影事件表：业务真相在 PG，Turms 侧是可重建读模型，两者之间的唯一通道就是这张表。
-- 事件与业务变更同事务提交（docs/truth/backend/projection.md）：PG 提交成功等于事件必达，
-- 不依赖「写库之后再发消息」这种会丢的两阶段。
create table domain_event (
    id              bigint      generated always as identity primary key,
    aggregate_type  text        not null,
    aggregate_id    text        not null,
    event_type      text        not null,
    -- 存「目标状态」而不是差量：重复投递必须收敛到同一结果，差量式的加减不幂等
    payload         jsonb       not null,
    created_at      timestamptz not null default now(),
    processed_at    timestamptz,
    attempt_count   integer     not null default 0,
    next_attempt_at timestamptz not null default now(),
    last_error      text,
    constraint domain_event_attempt_chk check (attempt_count >= 0)
);

-- 派发器只扫未处理行：已处理的再多也不进这条索引
create index domain_event_pending_idx
    on domain_event (next_attempt_at, id)
    where processed_at is null;

-- 同一聚合（账号对 / 群成员）按写入顺序重放，避免好友与拉黑的 DELETE/POST 交错
create index domain_event_aggregate_idx
    on domain_event (aggregate_type, aggregate_id, id);

-- 清理只按 processed_at 走
create index domain_event_cleanup_idx
    on domain_event (processed_at)
    where processed_at is not null;
