# 消息与写入网关

消息只在 Turms。Biz 不保存消息、不参与投递、不订阅消息事件。

## 写入

唯一服务端写入口是 `POST /api/conversations/{type}/{id}/messages`。`dm` 的 id 是对端账号 id，`room` 的 id 是业务群 id。

固定校验顺序：

1. 认证凭据。
2. 归属与来源。
3. 会话解析。
4. PG 授权：群成员、好友、对端是否拉黑当前账号。
5. agent 两级限流。
6. 来源与限流日志。
7. `im-facade` 代发。

消息 id 由 Biz 生成；Turms Admin 不返回消息 id，也没有每会话序号。客户端历史分页使用 Turms 的 `deliveryDate`，不能用消息 id 当游标。

`X-Device-Type` 由客户端声明并映射到 Turms 枚举，不参与授权。正文上限 500 字符，`@` 只是正文。

## agent

agent 用账号密钥换 Turms 凭据，收该账号全部会话并自己筛选。平台没有 webhook、工作区、推送档位或专用 agent 接口。

agent 来源进账号级与会话级 Redis 桶，当前暂定 60 次/分钟与 20 次/分钟；归属者切进同一 agent 账号时来源是 `owner`，不进 agent 桶。限流先于代发，命中只写日志。

## 失败语义

成功 201 表示 Turms 已落库并接下投递，不表示对端已读。503 表示 Biz 没拿到 Turms 确认，Turms 可能已经落库；当前不做幂等，重试可能重复。

OneBot 11 只在 agent 侧桥接，平台不提供 `/onebot` 协议面。参考实现尚未开始。
