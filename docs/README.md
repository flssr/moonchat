# 文档索引

本目录放**施工要用的四份文档**与一份机器可读副本，不放 spec：

| 文档 | 回答什么问题 |
| --- | --- |
| [`PRD.md`](PRD.md) | 为谁解决什么？核心场景、能力清单、第一版范围、验收步骤、技术栈与非功能要求 |
| [`DDD.md`](DDD.md) | 领域怎么切？账号、好友、消息与隧道、agent 接入、OneBot 桥接的规则、流程与不变量 |
| [`data-model.md`](data-model.md) | 表怎么建？聚合边界、八张表的 DDL、字段语义、只能由应用层守的规则、明确不建的表 |
| [`api-contracts.md`](api-contracts.md) | 接口长什么样？23 条 `/api/*` 路由、认证、字段、错误码、每条接口读写哪张表 |
| [`openapi.json`](openapi.json) | 上面那份契约的机器可读副本，由代码生成、给 Apifox 导入 |

客户端设计文档（`DESIGN-SPEC.md`、`SCREEN-MAP.md`、`API-MAPPING.md`、`HANDOFF.md`）在 [`frontend/`](frontend/)，它们是给实现者看的稿子，不是 spec、不进台账。

产品决策（Non-Goals、已定简化、V2 计划）在根目录的 [`../goal-and-requirements.md`](../goal-and-requirements.md)。

## spec 树在哪

ThinkRail 的 spec 索引以工作区根目录递归扫描：带 `id` + `type` frontmatter 的 `.md` 就是 spec，位置按默认形态放——入口文档在仓库根，模块 spec 贴在模块旁。

| 位置 | id | 类型 | 内容 |
| --- | --- | --- | --- |
| [`../goal-and-requirements.md`](../goal-and-requirements.md) | `moonchat-product` | goal-and-requirements | 定位、范围判据、已定简化、Non-Goals、V2 |
| [`../architecture.md`](../architecture.md) | `moonchat-architecture` | architecture-design | 分层、拓扑、四条边界、数据归属、跨模块不变量 |
| [`../backend/moonchat-biz/SPEC.md`](../backend/moonchat-biz/SPEC.md) | `moonchat-biz` | module-design | 业务进程的职责、边界、写入网关、数据与依赖 |
| [`../frontend/SPEC.md`](../frontend/SPEC.md) | `moonchat-client` | module-design | 客户端的职责与界面边界 |
| [`../infra/SPEC.md`](../infra/SPEC.md) | `moonchat-deployment` | module-design | 部署单元、单进程的理由、扩容触发条件 |

本目录的四份文档**没有 frontmatter，不是 spec**，不参与 spec-graph。它们写契约与表结构这类施工明细；spec 写决策与边界。冲突时：行为与边界以 spec 为准，契约与 DDL 以本目录为准，并在同一次改动里把两边修一致。

## 维护约定

1. **一份事实只写一次**：跨模块边界在 `architecture.md`，领域行为在 `DDD.md`，DDL 在 `data-model.md`，路由在 `api-contracts.md`。别在另一份里抄一遍。
2. **改行为 = 改 spec**：边界、契约、不变量变了，先改 `backend/moonchat-biz/SPEC.md`、`architecture.md`、`goal-and-requirements.md` 里对应的那份，再改这里的施工明细。
3. **改了代码就重新生成 `openapi.json`**（命令见根 `README.md`），构建会校验它与代码一致。
4. **临时文档不进仓库**：计划、草稿、任务记录写在 `.thinkrail/context/`（已 gitignore，spec 工具仍会索引它）；仓库里不新建 `NOTES.md` / `TODO.md` / `plan.md`。
5. **本目录不新增第五份文档**：确实需要新的一类内容时，先问它属于 PRD、DDD、表结构还是接口；都不属于，才考虑加一份并在本表登记。
