-- 账号资料：account_info 追加性别与生日（V2 首项的资料编辑接口）。
-- DDL 与 docs/truth/backend/persistence.md 逐字一致；gender 用 DDL 默认值兜底，创建路径不写这一列。

alter table account_info add column gender   text not null default 'private';
alter table account_info add column birthday date;

alter table account_info add constraint account_info_gender_chk
    check (gender in ('male', 'female', 'other', 'private'));
