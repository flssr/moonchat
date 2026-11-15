# 好友与黑名单

好友是私聊授权的唯一来源。关系保存在 PG，不投影 Turms。

## 好友关系

`friendship` 是权威行，两个账号按小 id 在前存放；`friendship_reverse` 是同事务维护的查询镜像，不参与授权。申请与成立共用 `pending` / `accepted` 状态，拒绝写 `deleted_at`，不增加 `rejected`。

接口动作是申请、查看好友或待处理申请、同意/拒绝、删除。删除后会话保留但只能读；重新申请复用原行。并发申请由唯一键兜底并返回 `conflict`。

agent 可以申请好友、应答和删除好友，但必须对方同意才能成立。agent 不能建群、拉人、移除成员或操作黑名单。

**归属者与 agent 的关系在创建时建立**：`POST /api/agent-accounts` 在同一个事务内写一行 `accepted` 的 `friendship`（`requested_by` = 归属者）与对应的镜像行，所以新建的 agent 立刻能和归属者私聊。这条关系只建一次，被删除后不会自动重连；存量 agent **不回填**（有意），它们需要归属者手工加一次。写这一行**不是第二套授权**：好友仍是私聊授权的唯一来源，归属关系只决定谁有资格建立这层关系。

## 黑名单

黑名单是有向关系：只阻止“被拉黑方 → 拉黑方”的私聊和好友申请。拉黑方仍可主动联系，群聊两个方向都不受影响，拉黑也不解除好友关系。

黑名单只在 Biz 拦截，不投影 Turms。只有真人（`owner`）能操作，agent 不行。

| 接口 | 约束 |
| --- | --- |
| `GET /api/blocklist?page=&size=` | `page` 从 1 起，`size` 1..100、默认 50；响应带 `page` / `size` / `total`；按 `created_at` 倒序、`blocked_account_id` 兜底排序 |
| `POST /api/blocklist` `{account_id}` | 已在名单 → 409 `conflict`；每人上限 100 条，超出 → 409 `blocklist_full`，与 `conflict` 是两个 code，客户端按 `code` 分流 |
| `DELETE /api/blocklist/{accountId}` | 取消拉黑；不在名单 → 404 |

Flutter 设置页当前显示“待接入”。表结构与 100 上限的应用层规则见 [持久层](./persistence.md)。

## 私聊入口

私聊只从好友列表与资料页进入。群中的非好友只能看资料页并申请好友，没有临时会话。真正的授权在写入网关，客户端隐藏入口只是体验规则。
