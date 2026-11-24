-- 群简介（issue #38）：只存在 PG，不投影到 Turms；空串当没有，长度上限 200（与建群校验一致）。
alter table room_info add column description text;

alter table room_info add constraint room_info_description_len_chk
    check (description is null or length(description) <= 200);
