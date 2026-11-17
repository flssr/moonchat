-- 账号头像：存平台内置头像的 key，null 表示用客户端按账号 id 生成的首字头像。
-- 真人 6 个、agent 3 个；「真人只能选真人那几张、agent 只能选 agent 那几张」跨表按 account.type 判，
-- 只能由应用层守，所以这里不加 check（issue #10）。头像不做上传，也不入库任何 URL。
alter table account_info add column avatar text;
