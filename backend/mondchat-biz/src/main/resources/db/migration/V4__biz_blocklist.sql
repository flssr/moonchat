-- 黑名单聚合：blocklist（有向、成对唯一，取消拉黑直接物理删行）。
-- DDL 与 docs/data-model.md §4.8 逐字一致。拦截只在 Biz 的写入网关与好友申请入口，不投影 Turms。

create table blocklist (
    owner_account_id   bigint      not null,
    blocked_account_id bigint      not null,
    created_at         timestamptz not null default now(),
    constraint blocklist_pk       primary key (owner_account_id, blocked_account_id),
    constraint blocklist_self_chk check (owner_account_id <> blocked_account_id)
);
