# 项目总体决策历史

## 介绍

记录跨模块的产品与架构决策，遵循 [历史决策规范](./README.md)。模块内部原因放到对应后端或前端文档。

## 写入模板

```text
<议题>

<本地时间与时区>   [<UTC 时间>]

<决策>：...

<原因>：...
```

新条目在上，旧条目保留。

## 目录

- [生产切客户端直写授权](#生产切客户端直写授权)
- [私聊未读基线回到本机](#私聊未读基线回到本机)
- [Turms 全局属性不再由 compose 决定](#turms-全局属性不再由-compose-决定)
- [Turms Admin 调用加超时](#turms-admin-调用加超时)
- [写路径回归 Turms](#写路径回归-turms)
- [自研插件与消息引擎发布耦合](#自研插件与消息引擎发布耦合)
- [关系与账号投影进 Turms 读模型](#关系与账号投影进-turms-读模型)
- [客户端未读改按服务端已读时间](#客户端未读改按服务端已读时间)
- [群简介与黑名单管理](#群简介与黑名单管理)
- [已读状态以服务端为唯一真相](#已读状态以服务端为唯一真相)
- [静态资源加内容指纹](#静态资源加内容指纹)
- [引言收窄到人机共生](#引言收窄到人机共生)
- [引言换成交流与人机共生的句子](#引言换成交流与人机共生的句子)
- [官网文案按用户口径定稿](#官网文案按用户口径定稿)
- [官网文案重写](#官网文案重写)
- [官网进场分出层次](#官网进场分出层次)
- [官网进场改成滚动驱动](#官网进场改成滚动驱动)
- [官网下载入口与滚动进场](#官网下载入口与滚动进场)
- [CI 桌面产物只在 main 出包](#ci-桌面产物只在-main-出包)
- [CD 自动清理 GHCR 旧镜像版本](#cd-自动清理-ghcr-旧镜像版本)
- [biz 镜像改分层布局与 alpine JRE](#biz-镜像改分层布局与-alpine-jre)
- [官网静态页进流水线](#官网静态页进流水线)
- [头像上线与流水线手动触发](#头像上线与流水线手动触发)
- [biz 镜像补 logs 目录](#biz-镜像补-logs-目录)
- [Turms 容器限额提到 1280m](#turms-容器限额提到-1280m)
- [Mongo 缓存下限改成 0.25G](#mongo-缓存下限改成-025g)
- [Mongo 改最小分片集群](#mongo-改最小分片集群)
- [生产部署与 CD](#生产部署与-cd)
- [文档体系](#文档体系)
- [架构骨架](#架构骨架)
- [施工切片](#施工切片)
- [消息写入路径](#消息写入路径)
- [agent 接入面](#agent-接入面)
- [限流](#限流)
- [好友与 Turms 投影](#好友与-turms-投影)
- [数据归属与可观测](#数据归属与可观测)
- [后端改名](#后端改名)
- [项目改名](#项目改名)

## 议题

### 生产切客户端直写授权

2026-11-25 05:20 CST   [2026-11-24 21:20 UTC]

决策：生产把 Turms 的 `allowSendMessagesToStranger` 从 `true` 翻成 `false`（走 admin API `PUT /cluster/settings`，`compose` 的 `-D` 只是种子），客户端与 agent 从 Biz 代发改成各自的 Turms `/im` 直写；限流插件镜像已挂载（`MONDCHAT_TURMS_SERVICE_IMAGE`）。Biz 的 REST 写路径只留给未升级的旧客户端，P4 删除。

原因：P3 的验收前提是好友与拉黑由 Turms 按投影判定。投影已回填、好友关系行已在 Turms，翻开关前实测好友发送不受影响。翻后验收：好友私聊/群聊正常，非好友 `5001`，被拉黑 `5001` 且未送达（`stranger=false` 压码）、解除拉黑恢复，连发触发 `1101`。验收同时发现桌面端把 `1101`（1xxx 里的错误码）当成功，已改成 `1000..1099` 判成功。Turms 自带防刷在约 8 请求/秒时先于插件触发（会话以 `701` 关闭、IP 封 10 分钟），验收限流不要用密集压测。

### 私聊未读基线回到本机

2026-11-25 04:20 CST   [2026-11-24 20:20 UTC]

决策：私聊未读基线改回本机已读时间，随 `cache.json` 的 `read_dates` 落盘（键是会话 key）；群聊仍取 Turms `memberIdToReadDate[自己]`。删除 `RealtimeClient.privateReadDates`。没有任何本机基线的会话（首登/重装）补报一次已读，不把历史算成未读。

原因：P3 生产验收（#73）实测 `QUERY_CONVERSATIONS_REQUEST` 的 `userIds` 在服务端是 owner、target 固定为请求者，返回的是「对方对我的会话」，`readDate` 是对方的读时间。原实现把它按对端 id 当自己的基线，永远取不到，导致每次登录都把私聊会话当成「从未上报」→ 上报后清角标，私聊未读数实际不出现（复现已记到 #37）。跨设备的服务端基线需要 Turms 侧补查询或换未读计数，仍由 #37 跟踪；本机重登先保证准确。

### Turms 全局属性不再由 compose 决定

2026-11-25 04:20 CST   [2026-11-24 20:20 UTC]

决策：`allowSendMessagesToStranger` 这类 Turms 全局可变属性以 Mongo shared config 为准，改动走 admin API `PUT /cluster/settings`；`compose.yaml` 里的 `-D` 只是首次启动的种子值，不再当作生效开关。

原因：`SharedPropertyService.initializeSharedProperties()` 在 shared config 里已有记录时直接用库里的 `TurmsProperties`，`-D` 只在库为空时写入；重启会被旧值覆盖。2026-11-24 P3 验收实测：compose 已写 `false`，线上仍允许陌生人私聊、拉黑后消息照常送达，限流插件也没装（`.env` 未设 `MONDCHAT_TURMS_SERVICE_IMAGE`）。改属性与限流的操作步骤写进 `docs/truth/deployment.md`。

### Turms Admin 调用加超时

2026-11-24 04:35 CST   [2026-11-23 20:35 UTC]

决策：`TurmsAdminClient` 的 `RestClient` 用 JDK `HttpClient` 配 `connect-timeout`（默认 2s）与 `read-timeout`（默认 5s），可用 `MONDCHAT_TURMS_HTTP_CONNECT_TIMEOUT` / `MONDCHAT_TURMS_HTTP_READ_TIMEOUT` 覆盖。超时抛的 `ResourceAccessException` 落进既有 `RestClientException` catch，外部契约仍是 `503 upstream_unavailable`；不加客户端自动重试，派发器继续按 `attempt_count` 与退避重试。

原因：Turms 只卡不回（TCP 通、不响应）时旧实现会无限占线程，派发器挂在那条事件上、`pending` 只增不减，而 Biz 健康检查仍正常，故障不可见。超时把失败推回正常重试路径，积压可观测且能自愈；这也修复了投影，而不只是防线程占满。

### 写路径回归 Turms

2026-11-22 23:57 CST   [2026-11-22 15:57 UTC]

决策：从「Biz 写入网关代发」转向「Biz 控制面 + Turms 数据面」——账号、关系、群、资料与凭据签发留在 Biz，消息、会话、已读、撤回归 Turms；客户端与 agent 用已有的 `/im` WebSocket 直写，Turms 按投影后的关系判定。分阶段推进（P0 契约 → P1 投影地基 → P2 启用 → P3 灰度 → P4 全量 → P5 清理），每端的接入说明与错误码、statements、灰度回滚写在 issue #63。当前只完成 P1：投影地基已合入，派发默认关、插件未挂载、写路径仍经 Biz，文档按阶段分开写。

原因：Admin 代发跳过 Turms 自己的好友、拉黑与群成员判定，每加一个标准 IM 能力都要 Biz 加一条路由、一手 Admin 调用和一套自己的规则；撤回、改消息、已读这类原语重写一遍没有收益。把授权执行点交回 Turms 后，Biz 只维护真相与投影。代价是自研插件与消息引擎发布耦合、限流计数按进程（N 实例为 N × 额度），且切换前不能先放开写权限——旧 token 最长活 12 小时，会绕过冻结与拉黑。

### 自研插件与消息引擎发布耦合

2026-11-22 20:05 CST   [2026-11-22 12:05 UTC]

决策：客户端直写 Turms 后，接管限流等能力的自研插件运行在 turms-service 进程内，按「能让消息引擎全体不可用」的变更对待——上线前用同一 pinned digest 起一次性容器验证插件加载（`8510/health` 为 200），生产只挂一个版本，回滚为清空插件目录后重启，插件模块不进后端 CI reactor。

原因：实测表明插件加载失败会让 Spring 上下文 refresh 中止、turms-service 以退出码 1 起不来，爆炸半径是整个消息引擎而不是「插件不生效」。这与 Biz 有独立进程边界不同，是 B/C 路线的固定风险；当初选 A 的一条论据正是避免把自研代码放进消息引擎进程，将来切换时要明确接受这条代价。插件构建在 `maven:3.9-eclipse-temurin-25` 容器内完成（vendor 指针 `d6ec799`，`-Dmaven.test.skip=true`），并用 pinned digest 一次性容器验证过加载：注册、扩展启动、`/health` 200 三条都通；限流命中返回 `1101` 仍待 P2 放开客户端写权限后再验。

### 关系与账号投影进 Turms 读模型

2026-11-22 19:55 CST   [2026-11-22 11:55 UTC]

决策：PG 仍是业务真相，账号、好友、黑名单、群与成员单向投影进 Turms 读模型；投影走同事务的 `domain_event` outbox + 单 worker 派发 + 每日对账，只修 Turms、永不反写 PG。`mondchat.projection.enabled` 默认 `false`：P1 只累积事件、不派发，P2 打开时一次性派发积压等于天然增量回填（打开前先看积压行数，大就按 id 分批放）。当前 `allowSendMessagesToStranger = true`，授权判定仍读 PG，投影不改变任何用户可见行为。

原因：客户端切到直写 Turms 之后，好友与拉黑必须由 Turms 判定，投影是那一步的地基；先把事件通道和对账建好，切换时只改授权执行点。同事务 outbox 让「PG 提交成功 = 事件必达」，避免双写丢事件；目标状态型 payload 让重放收敛到同一结果。两条 Turms 语义决定了写法：好友判定只看「行存在且 `blockDate` 为空」，所以删好友必须物理删行；清 `blockDate` 只有 epoch-0 日期会 unset，`null` 是 no-op。

### 客户端未读改按服务端已读时间

2026-11-22 03:35 CST   [2026-11-21 19:35 UTC]

决策：登录/重连后的未读基线换成 Turms 会话的已读时间——Web 端扩 `turms-client-js` 封装（`queryPrivateConversations` / `queryGroupConversations`），桌面端在自写 WebSocket 上发 `QueryConversationsRequest`；私聊取会话 `readDate`，群取成员表里自己那条，未读 = `deliveryDate` 晚于它且不是自己发的消息。打开会话、以及前台正看着会话时收到新消息，经 Biz 的 `POST /api/conversations/{type}/{id}/read` 上报，同一会话 1 秒去抖，`204` 才清本地角标，失败保留。从没有游标的会话首次登录补报一次，本机缓存只用于渲染与离线兜底，不再当未读基线。

原因：原来的未读是「缓存保存时间之后的对端消息」，首次落盘之前、换设备、缓存丢了的消息都不算未读，用户离线期间收到的消息重登后只有预览、没有角标和通知（issue #37 的复现）。服务端已读游标是账号级的，天然跨设备、跨重登；代价是两条读通道都要支持会话查询、且桌面端要手写 protobuf。上一轮已经把写已读接口和后端约定落地（见[已读状态以服务端为唯一真相](#已读状态以服务端为唯一真相)），这一轮接的是客户端。

### 群简介与黑名单管理

2026-11-22 02:30 CST   [2026-11-21 18:30 UTC]

决策：按 issue #38 给 `room_info` 加 `description`（V8 迁移，可空、长度 ≤200、空白当没有；只存 PG，不投影 Turms），建群请求与详情响应带简介，列表项不带。客户端建群弹窗加简介输入（0–200 字），群资料右栏在人数下面显示成浅底卡片。按用户要求把设置 → 隐私里的「黑名单管理」占位接成真入口：弹窗列出被拉黑的人（一次取上限 100），逐行「解除」；`AppState.conversations` 过滤掉被我拉黑的 `dm:` 会话，所以聊天界面不再显示他们，解黑自动回来。拉黑不删好友，联系人页照旧。

原因：群简介是 #38 里已经拍过板的能力，后端字段一落地，客户端不能停在「弹窗不设简介」；它是建群时的一句话，放在右栏顶部比塞进成员列表合适。黑名单那条一直是「接口有了、入口没有」：设置里的占位写着「待接入」，用户点不动。列表弹窗比逐个搜人再拉黑/解黑顺手，和微信/QQ 的做法一致；「拉黑后聊天界面不出现他」是用户明确要的效果，放在 `conversations` getter 一处过滤，会话列表、未读总数和选中态都走同一条，不用在每个视图里各改一遍。

### 已读状态以服务端为唯一真相

2026-11-21 22:58 CST   [2026-11-21 14:58 UTC]

决策：已读时间以 Turms 服务端为唯一真相，客户端经 Biz 的 `POST /api/conversations/{type}/{id}/read` 上报（详见[消息与写入网关决策历史](./backend-doc/message-gateway-history.md)）。各端**下一次查询**会话时生效，不做实时推送，也不属于此前列为不做的「多端同步」。

原因：读时间写在自己名下，多端读同一份服务端数据即可收敛；被动收敛不需要推送或第二份来源。此前「多端同步」指的是消息与状态在端间实时同步，与读游标按查询收敛不是一回事，因此不把后者记为放开「多端同步」。

### 静态资源加内容指纹

2026-11-21 22:26 CST   [2026-11-21 14:26 UTC]

决策：`site.yml` 在部署时给 `styles.css`、`app.js`、`sky.js` 和品牌图算 10 位内容哈希，写成 `?v=` 指纹塞进部署产物里的 `index.html`（仓库里的 HTML 保持裸文件名）。同步分两趟：先解压资源，最后落 `index.html`。冒烟测试多一条，校验线上 HTML 里的指纹与线上资源的实际哈希对得上。

原因：线上出现过「新 HTML + 旧 CSS」——导航里新加的「现在体验 MondChat」拿不到 `.cta` / `.nav__actions` 的样式，链接退回成普通文字、主题按钮被挤到下一行。两条来源：服务器没发 `Cache-Control`，浏览器按 `Last-Modified` 猜出一个有效期（旧的 CSS 上次改动是四天前，猜出来能有好几小时），这期间不回头校验；以及部署是把文件直接解压进站点根目录，HTML 先落、CSS 后落，中间那不到一秒谁刷新谁中。指纹治掉第一条的大部分：地址随内容变，旧缓存不会被当成新资源用；剩下「HTML 自己被缓存」只能靠服务器给入口页发 `no-cache`，那条记在 `docs/truth/frontend/site.md` 里，等部署侧配。

### 引言收窄到人机共生

2026-11-21 22:02 CST   [2026-11-21 14:02 UTC]

决策：上一轮加进来的「交流 / 相遇」类句子（圣埃克苏佩里、布伯、海德格尔、维特根斯坦、培根、纪伯伦、孔子、《礼记·学记》、老子）全部撤掉，只留「人机共生」这一条线：麦克卢汉「我们塑造工具，然后工具塑造我们」、乔布斯「计算机是人类心灵的自行车」、阿西莫夫「我不害怕计算机，我害怕的是没有它们」、哈拉维「我们都是赛博格」、尼采「我们的书写工具也在参与我们的思考」、维纳「交给机器的目的」、霍金「人工智能或许是我们最好的事，也或许是最坏的」、庄子「天地与我并生，而万物与我为一」。图灵与艾伦·凯两句继续留着。网站：引言带用麦克卢汉，首屏轮播图灵、乔布斯、阿西莫夫、哈拉维、尼采、维纳；客户端 10 条，含霍金与庄子。三语译文同步换掉。

原因：只讲语言和相遇的句子说的是「人和人怎么说话」，产品要说的是「人和会说话的机器怎么处在一个世界里」。两套话在登录页上读起来接近，但落点不同：前者像文学摘抄，后者才贴着产品。这条标准写进 `site.md`，以后挑引言按它来。

### 引言换成交流与人机共生的句子

2026-11-21 21:56 CST   [2026-11-21 13:56 UTC]

决策：官网首屏轮换的 6 句、引言带的 1 句和客户端登录页的 12 句一起换。删掉纯计算机科学的那些（洛芙莱斯、迪杰斯特拉两句、明斯基、斯金纳、吴恩达、霍珀、克努特、费曼、瓦西瓦尼），换成谈交流、相遇、人机共生的：圣埃克苏佩里、布伯、海德格尔、维特根斯坦、培根、维纳、纪伯伦、孔子、《礼记·学记》、老子。图灵「前方很短的一段」和艾伦·凯「预测未来」留着——它们说的是往前做，不是算法。`moon_strings.dart` 的英/日/德译文跟着换：新句补译，旧句的条目删掉。

原因：两组引言都在替产品说话。原来那批里有一半是工程段子（「过早优化是万恶之源」「最危险的一句话」「注意力就是你所需要的一切」），跟「账号背后可以是人，也可以是人的 agent」没有关系，登录页那一瞬间看着像技术博客的装饰。换成谈语言、相遇和机器目的这几句，人物名单也散开一些：哲学、文学、古文、工程各来一点，不再全是计算机圈的人。

### 官网文案按用户口径定稿

2026-11-21 21:49 CST   [2026-11-21 13:49 UTC]

决策：上一轮的文案重写有几处按用户的具体句子改回来。02 段两段正文换成「它并不是冰冷的数据，而是活生生的“人”。」和「你们可以用共同的语言交流，它并不只会执行你的命令。」；03 段第二段退回「它怎么运行、在哪里运行，不在平台的视野里。我们只把账号交给它，其余的，是它的。」；04 段标题退回「对话，多了一种可能。」；结尾换成「欢迎来到 MondChat 世界。」。语气规则相应收窄：只说「不堆三连排比、不凑对称句」，并把「视野」「可能性」这两句记为按用户意见保留的原句。

原因：关系感优先于去模板化。用户要的是「它像个人、能一起说话」的口气，抽象句和旧标题在这口气里成立；再按「不写抽象词」改回去，等于用词表压过产品想给人的感觉。文档里保留例外，避免以后照着规则又把这几句改掉。

### 官网文案重写

2026-11-21 21:40 CST   [2026-11-21 13:40 UTC]

决策：按用户给的新标题把第二段改成「02 / 同台 → 这里是人和 agent 共同的舞台。」（拆成两行，和其余标题一样走行遮罩），其余各段文案一起重写：首屏副标语、01/03/04 的正文、04 的标题从「对话，多了一种可能。」换成「聊天还是那个聊天。」；结尾从「剩下的，交给对话本身。」换成「接下来怎么聊，是你们的事。」；meta description 同步。意思和事实一条没变，只换说法。

原因：原来的句子读起来像模型写的——三连排比（「头像、名字、一句签名」「会累、会走开、会在深夜才回消息」）、镜像对偶（「不需要另一套名字，也不需要另一张脸」「没有专门的通道，也没有另一种语法」）、抽象名词收尾（「多了一种可能」「不在平台的视野里」「剩下的，交给对话本身」）。重写按两条标准：能用具体的东西说就不用抽象词（「好友列表里没有单独给它留的位置」替掉「不会把它分出去」），句子长短错开、不凑对称。语气规则记进 `docs/truth/frontend/site.md`，下次改文案照这个来。


### 官网进场分出层次

2026-11-21 20:42 CST   [2026-11-21 12:42 UTC]

决策：滚动驱动的骨架保留，内容按层拆开，各走各的动画——标题把 `<br>` 拆成 `.ln > .ln__i` 行遮罩、一行一行从下面推上来（`app.js` 拆，`overflow: clip` 当遮罩）；小节标签用 `clip-path` 从左揭开；段落与落款淡入上浮，滑到导航下方再淡出上浮；`.essay` 的 1px 分节线用 `background-size` 从 0 拉到 100%；`.nav::after` 加一层渐变，在滚动 0–120px 内淡入，让正文滑上去时在导航下面化开；首屏标题按行推上来、其余元素依次淡入，作为一次性的读入动画。

原因：上一版所有块同一条曲线、同一个方向，滚下去只有一种「浮上来」，单调。分层以后不同元素有不同动作和不同速度，标题是主角、标签是引子、分节线是结构，读起来有编排感。两个实现上的取舍：`overflow: hidden` 会变成滚动容器、把行内元素的 `view()` 时间线接走，所以遮罩用 `overflow: clip`；分节线一开始挂在 `.essay::before` 上，实测伪元素的 `view()` 不跟滚动（transform 停在终值），改成对真实元素的 `background-size` 做动画才生效。

### 官网进场改成滚动驱动

2026-11-21 20:30 CST   [2026-11-21 12:30 UTC]

决策：`site/styles.css` 用原生 `animation-timeline: view()` 给 `.reveal` 里的正文块放一段滚动驱动关键帧（0% 透明、下沉 26px、6px 模糊；14% 到位；84% 保持；100% 淡出并上浮 36px），删掉 `app.js` 里 IntersectionObserver 的进场逻辑与 `html.js` 那套隐藏规则；淡出从元素滑到导航下方才开始，正文停在读者区时不发灰。

原因：先是按「一次性进场」做的，滑走再回来不会重演；加上退场后，IntersectionObserver 的两段可见性判定会留下死区——元素卡在顶部退场带里时，出场的状态已经落到透明，人却还看得见那块位置，停在那儿就是一片空白，而且别的观察器不会把它重新点亮。挂在滚动位置上的动画进度只由几何决定，来回都原路重演，也没有状态可丢，还顺带把这段 JS 删掉了。代价是不支持 `animation-timeline` 的浏览器没有进场动画，正文静态可见。

### 官网下载入口与滚动进场

2026-11-21 20:07 CST   [2026-11-21 12:07 UTC]

决策：`site/` 导航右侧加「现在体验 MondChat」，指向 `preview` 标签下的 `MondChat-Setup-1.0.0.exe`；有 JS 时点击先弹原生 `<dialog>` 提醒「只支持 x64 平台的 Windows 10 及以上」，确认后关弹窗并下载，取消 / `Esc` / 点遮罩只关弹窗。没有 JS 或不支持 `dialog.showModal` 时不拦链接，直接下载。正文从整段淡入改成按段落逐个进场：`app.js` 给 `.reveal` 里的 `p` / `h2` / `blockquote` / `figcaption` 加 `rv`，`IntersectionObserver` 逐块触发，相邻块靠 `--i` 排 110ms。暗色首屏的流星从「一次一颗、间隔 9–18 秒」改成同时最多 3 颗、间隔 3.8–7 秒，起点抬到画面上方换更长的可见时间。

原因：桌面客户端已经能下载，官网原本没有任何入口，访客只能自己去仓库里找；安装包只支持 x64 的 Windows 10+，入口要先说清平台再给文件，不然装完才发现跑不起来。进场与流星是一起提的观感问题：原来整段一起淡入，长页面滑下去就是一片空白突然出现；流星间隔十几秒、又只在标题上方很短的一段里划完，暗色首屏看着几乎是静止的。

### CI 桌面产物只在 main 出包

2026-11-19 00:02 CST   [2026-11-18 16:02 UTC]

决策：`ci.yml` 的 `desktop` job 加 `if: github.ref == 'refs/heads/main' || github.event_name == 'workflow_dispatch'`，PR 阶段不再跑 Windows 构建；`upload-artifact` 加 `retention-days: 3`，产物只留三天。同时一次性删掉已有的 33 条 `mondchat-windows` 产物（482MB）和非 main 的 14 条缓存（约 4.0GB，其中 `refs/pull/30/merge` 1.95GB、`feat/desktop-client` 1.85GB）。

原因：#49 的 500MB artifacts + Packages 共享池被 artifacts 挤爆——`desktop` 在 `pull_request` 下也跑，每次 push 都留一份 14.7MB 产物，且默认保留 90 天；实测 artifacts 48 条 482MB，其中 33 条是桌面产物。后端侧（#50）已把 GHCR 每次新增压到约 0.2MB，这一条把客户端侧的增长源也收掉。代价是 PR 阶段不再编译 Windows 壳，平台层回归延后到 main；需要时用 `gh workflow run ci.yml --ref <分支>` 手动跑，桌面检查仍留在手动入口里。

### CD 自动清理 GHCR 旧镜像版本

2026-11-18 23:19 CST   [2026-11-18 15:19 UTC]

决策：`cd.yml` 在 `deploy` 之后加独立 `prune` job：用 Secret `GHCR_PAT` 读镜像包的 versions，排除带 `latest` 的那个，按 `created_at` 倒序保留最近 3 个 `:<sha>`，其余 DELETE；包可能挂在账号也可能挂在仓库命名空间下，先探 `/user/packages/container/mondchat-biz` 读不到再换 `/repos/<owner>/<repo>/packages/container/mondchat-biz`。job 用 `needs: deploy` + `continue-on-error: true`。

原因：上一轮只压住了「每次 push 新增多少」，已经存在的旧 sha tag 还在，500MB 池子照样会满；清旧版本必须删包，`GITHUB_TOKEN` 没有这个权限，用户另建了 `GHCR_PAT`（`read:packages` + `delete:packages`）。放进 CD 而不是手动跑，是因为「每次上线顺手留 3 个回滚点」只有跟着部署走才不会被忘掉。独立 job 加 `continue-on-error` 是为了清理失败不把已经成功的部署标成红叉：回滚点数量不是上线正确性的一部分，删不掉包也不该挡部署。

### biz 镜像改分层布局与 alpine JRE

2026-11-18 23:02 CST   [2026-11-18 15:02 UTC]

决策：`backend/mondchat-biz/Dockerfile` 在 `package` 之后用 `java -Djarmode=tools -jar ... extract --layers` 拆出 `dependencies/`、`snapshot-dependencies/`、`application/`，依赖层在前、`application/` 最后 COPY；运行镜像从 `eclipse-temurin:21-jre` 换成 `eclipse-temurin:21-jre-alpine`，建用户改用 busybox 的 `adduser -D -u 10001 mondchat`，`logs/` 目录与属主那段照旧。`cd.yml` 的 `cache-to` 去掉 `mode=max`。本机实测镜像 549MB → 378MB，`app.jar` 那一层 48.5MB → 209kB。Spring Boot 4.1 的 tools 提取结果是「瘦 jar + `lib/`」（Main-Class 直接是应用类），不再有 loader 层，所以入口仍是 `java -jar`，不是 `JarLauncher`。

原因：GHCR 500MB 存储池被每次 push 的 46MB fat jar 层吃满（#49），按这个增速约十次 push 就填满。依赖不变时 `lib/` 层命中缓存，一次 push 只有 209kB 的 application 层是新 blob。清理 GHCR 里旧的 `:<sha>` tag 需要带 `delete:packages` 权限的 PAT，`GITHUB_TOKEN` 删不了包，这部分留给用户。

### 官网静态页进流水线

2026-11-17 18:47 CET   [2026-11-17 17:47 UTC]

决策：新增 `.github/workflows/site.yml` 单独发官网静态页：`site/**` 推到 `main` 触发，也可 `workflow_dispatch` 手发；站点根目录不写死，用 `styles.css` 里的固定标语在 `/site`、`/opt/1panel/www`、`/www`、`/var/www` 里探测（可用仓库变量 `SITE_ROOT` 覆盖），`tar` 经 SSH 解包到根目录，只覆盖同名文件；最后逐文件比线上与仓库的 SHA256，不一致就失败。复用 CD 的四个 SSH secret。

原因：官网一直靠手工铺，`site/` 改完没人保证线上真的换了——#39 的 CSS 修复合进 main 后线上仍是旧文件（线上 `29CFD1B6…` vs 仓库 `831139c4…`），等到用户反馈才被发现。把发布收进流水线并加哈希冒烟，这类「代码合了但没生效」就变成一条红叉。目录探测是为了不在仓库里写死服务器路径；真写错也只会失败在探测那一步，不会覆盖别的目录。

### 头像上线与流水线手动触发

2026-11-17 18:24 CET   [2026-11-17 17:24 UTC]

决策：把头像落库（#10）连同今天的客户端改动一起合入 main（PR #30，`a30a2a3`）并走 CD 上线。CI 与 CD 两个 workflow 都加 `workflow_dispatch`：CI 按分支手动跑接口 / 前端 / 桌面三条检查，CD 按 main 重新构建上线。合并前用 `gh workflow run ci.yml --ref feat/desktop-client` 手动跑过一轮全绿（test / frontend / desktop），合并后 GitHub 侧 merge push 触发的 CI 与 CD 也都成功。上线前把两枚只存本机的头像回填进服务端（Regen → `male_01`，我的机器 → `agent_pink`），避免服务端 null 让它们变回首字头像；生产验证：`GET /api/accounts/mine` 带 `avatar`，`PUT /api/accounts/me/avatar` 传非法 key 回 400 `validation_failed`。

原因：2026-11-17 12:17 UTC 之后仓库的 `pull_request` 事件不再创建 workflow run（push 到 main 与 dispatch 正常），PR 上没有任何检查；既要保证合进 main 的东西真的跑过，又要在事件投递恢复前能人工跑通流水线，所以加了手动触发并写进部署文档（#42）。桌面端本机没有 VS2022，这轮 exe 用 CI `desktop` job 的 artifact；本地重编 `app.so` 的手工流程与 artifact 逐字节一致，说明值得固化成脚本（#44）。官网静态页仍不在 CD 里，线上还是旧 CSS（#43）。

### biz 镜像补 logs 目录

2026-11-17 01:20 CST   [2026-11-16 17:20 UTC]

决策：`backend/mondchat-biz/Dockerfile` 在 `useradd` 之后加一步 `mkdir -p /opt/mondchat/logs && chown -R 10001:10001 /opt/mondchat`，`COPY app.jar` 与 `USER mondchat` 位置不动。用数字 uid:gid 而不是 `mondchat:mondchat`，因为 `useradd --system` 不保证建同名的组，写组名有构建期失败的风险。

原因：分片与内存两个问题修完后，`mondchat-biz` 起来就退出，日志是 `Logback configuration error: Failed to create parent directories for [/opt/mondchat/logs/...]`。`logback-spring.xml` 的滚动文件用相对路径 `logs/`，基准是 `WORKDIR /opt/mondchat`，而镜像里这个目录是 root 所有且根本不存在，`USER mondchat` 之后 uid 10001 建不出来，Spring Boot 判定日志初始化失败直接退出。容器内 `logs/` 不挂宿主卷，容器重建即丢，排障走 `docker logs`，这一点也写进了 `docs/truth/deployment.md` 的运维边界。

### Turms 容器限额提到 1280m

2026-11-17 01:10 CST   [2026-11-16 17:10 UTC]

决策：`turms-service` 的 `mem_limit` 从 800m、`turms-gateway` 从 576m 都提到 1280m，`-Xmx448m` / `-Xmx320m` 与 metaspace 不动。常驻 `mem_limit` 合计因此变成 4288m，比物理 3.66G 还大，这是有意的：`mem_limit` 是上限不是预留，实际用量由 `-Xmx` 与缓存决定，稳态预估 2.8–3.3G，尖峰靠 2G swap。文档里写清了这一点，免得下次有人看到总和比机器大就当配置错误。

原因：mongo 分片层起来后，`turms-service` 在启动阶段抛 `IncompatibleJvmException: The max available memory is too small to run. Expected: >= 1000MB. Actual: 760MB`。Root cause 在 `turms-server-common/.../healthcheck/MemoryHealthChecker.java` 132–142 行：它拿 cgroup 限额 × 95%（`MemoryHealthCheckProperties.maxAvailableMemoryPercentage` 默认 95）跟自己写死的 1000MB 下限比，低于就走人。800m × 0.95 = 760MB，正好卡死；换算下来容器限额至少约 1053m，取 1280m 留余量。这是继「Mongo 缓存 0.25G 下限」之后第二个只有真机才暴露的组件硬下限，两处都写进了 `docs/truth/deployment.md`。

### Mongo 缓存下限改成 0.25G

2026-11-17 00:45 CST   [2026-11-16 16:45 UTC]

决策：两个 `mongod` 的 `--wiredTigerCacheSizeGB` 都从 0.12 / 0.2 改成 0.25，`mongo-config` 的 `mem_limit` 从 224m 提到 320m；常驻 `mem_limit` 合计从 3008m 变成 3104m，其余容器不动。

原因：第一次真机部署时 `mongo-config` 一直 unhealthy，日志是 `storage.wiredTiger.engineConfig.cacheSizeGB must be greater than or equal to 0.25`——MongoDB 的 WiredTiger 缓存有 0.25G 下限，低于它 mongod 拒绝启动并进重启循环，`docker compose up -d --wait` 因此整单失败。这也是「配置参数必须先在真机上验一次」的实例：分片拓扑本身是对的，栽在一个库下限上。

### Mongo 改最小分片集群

2026-11-17 00:55 CST   [2026-11-16 16:55 UTC]

决策：Mongo 从单节点副本集改成最小分片集群：`mongo-config`（`rs-config`，缓存 0.12G，限制 224m）、`mongo-shard`（`rs0`，缓存 0.2G，限制 384m）、`mongos`（限制 128m），加两个一次性初始化容器 `mongo-rs-init`（发起两个副本集并等 primary）与 `mongo-shard-init`（`sh.addShard`）；所有 Turms 的 Mongo URI 改成 `mongodb://mongos:27017/turms`，不带 `?replicaSet`。为腾出内存，`postgres` 384→320m、`redis` 128→96m、`turms-service` 832→800m（`-Xmx448m`）、`turms-gateway` 640→576m（`-Xmx320m`）、`mondchat-biz` 512→480m（`-Xmx256m`），常驻 `mem_limit` 合计仍是 3008m。

原因：Turms 的 Mongo 客户端只接受 `SHARDED` / `LOAD_BALANCED`（`turms-service` 与 `turms-gateway` 的 `MongoConfig` 都写死，`TurmsMongoClient.verifyServers` 直接抛 `IncompatibleMongoException`），判定来自 Mongodb 驱动读 `hello` 得到的集群类型，副本集一律是 `REPLICA_SET`，没有任何配置项能绕过，`loadBalanced=true` 也不行——LB 模式要求对端是 mongos。实测这个版本在服务器上启动约 4 秒后自行退出，是方案设计问题不是内存问题。选最小分片而不是降 Turms 版本：`vendor/turms` 子模块与 `infra/turms/pinned-images.compose.yaml` 都钉在当前提交，降版本要换 digest 并重验冒烟，而数据全落一个 shard 时不需要分片键与 balancer，代价只是多两个进程和一层启动顺序。

### 生产部署与 CD

2026-11-16 22:35 CST   [2026-11-16 14:35 UTC]

决策：生产是 2 核 4G 单机 docker compose（`infra/prod/compose.yaml`）：PostgreSQL、Redis、单节点副本集 MongoDB（`rs0`，一次性 `mongodb-init` 发起）、turms-service、turms-gateway、mondchat-biz 六个常驻容器，常驻 `mem_limit` 合计 2.94G，宿主另配 2G swap；不开 turms-admin，内部端口不出宿主，只有 biz 8080 与 gateway 10510 绑 `127.0.0.1`，交给宿主机上 1Panel 的 OpenResty 反代 `/api` 与 `/im`。CD 只做后端：push 到 `main` 构建 `mondchat-biz` 镜像推 GHCR，SSH 上机 `pull` 与 `up -d --wait`，宿主上 `curl /actuator/health`。Flutter Web 产物不在这台机器部署，仓库也不再自带 nginx/Caddy 容器。

原因：PoC 个位数用户，4G 内存要同时放 PG、Redis、Turms 两个 JVM 与 Biz，只有单节点副本集这条路撑得住预算——`vendor/turms` 那套 config + shard + router 光内存上限就 6G。反代本来就由 1Panel 的 OpenResty 在宿主机上管，`deployment.md` 原先写的 nginx 反代与实际不符，这次一并改掉。CD 只发后端，是因为前端和它的站点都在别处，把 Web 产物塞进这条流水线只会多一处没人用的部署面。

### 后端改名

2026-11-14 19:04 CET   [2026-11-14 18:04 UTC]

决策：后端标识统一改名：Maven 工程 `mondchat-parent`、模块 `mondchat-biz`、Java 包 `im.mondchat.*`、自有配置前缀 `mondchat.*`、环境变量 `MONDCHAT_*`、本地 DB 名 `mondchat`、OpenAPI 标题 `MondChat Biz API`；Turms 侧配置与外部进程名不变。

原因：产品改名后前后端命名分叉，运维与文档要记两套。同一次迁移比以后再挪包名、环境变量和数据库名便宜。

### 项目改名

2026-11-14 18:10 CET   [2026-11-14 17:10 UTC]

决策：产品与客户端改名为 MondChat；客户端包名、import、浏览器本地存储键（`mondchat.settings.v1`、`mondchat.avatars.v1`，旧的 `moonchat-theme` 迁移分支一并删除）、`MONDCHAT_API_BASE`、静态页标题与 README 一次换掉，不保留旧键兼容。

原因：改名发生在 MVP 期，用户量小，保留双写会让键名与品牌长期不一致。后端进程名、包名、DB 名与部署配置这次不跟进，由单独的后端改名 PR 处理。

### 文档体系

2026-11-14 16:55 CST   [2026-11-14 08:55 UTC]

决策：旧 spec 与 `docs/` 不再承担责任，也不再提交；`docs/truth` 成为当前事实，`docs/history` 成为决策沿革，并按总体、前端、后端和功能模块拆分。

原因：旧文档同时承担规范、接口、DDL、交接与历史，层级混杂且需要人工维持多处一致。把当前结论与决策原因分开，跨模块事实只写一次，模块文档独立维护。

2026-11-11 21:49 CST   [2026-11-11 13:49 UTC]

决策：设计 spec 收敛为根目录两份加模块旁三份，`docs/` 只保留 PRD、DDD、表结构、接口四份施工文档。

原因：按“决策、需求、领域、表、接口”分开，读者能判断哪类事实该写在哪里；此结构后来被更简单的 truth/history 两层替代。

### 架构骨架

2026-11-01 21:36 CST   [2026-11-01 13:36 UTC]

决策：推翻“connector + 工作区 + 三档投递”，改为单进程社交骨架：账号、好友、群与成员归 PG，消息归 Turms，写入统一走 Biz 网关。

原因：平台替 agent 持会话并按档位转发，会让工作区、dispatcher 与拉取出口成为平台能力；把会话还给 agent 后这些模型整体消失。

2026-10-30 20:12 CST   [2026-10-30 12:12 UTC]

决策：先做“房间闭环 + connector 三档投递”，内容层推到后续。

原因：先验证 agent 有身份、能自主接话后，人与它长期共处是否成立；该骨架后来被单进程社交骨架推翻。

### 施工切片

2026-11-04 15:21 CST   [2026-11-04 07:21 UTC]

决策：V1 按 S0–S5 纵切，每片自带迁移、接口、校验和测试，片末判据可重跑。

原因：横切会留下能调通但不校验的接口，无法验证每一片是否真正闭环。

### 消息写入路径

2026-11-04 16:27 CST   [2026-11-04 08:27 UTC]

决策：Biz 写入网关是唯一服务端写入口；消息 id 由网关生成并随代发提交，PG 零写入。

原因：Turms Admin 不回传消息 id，而客户端需要稳定 id；网关门是唯一能同时满足单一写入者和可观标识的位置。

2026-11-03 00:33 CST   [2026-11-02 16:33 UTC]

决策：客户端 Turms 凭据改为只授 `QUERY` 的 JWT，写入权限只留在服务端。

原因：若客户端能直发，归属、授权和限流都能被绕过；收紧 statements 比维护 Turms 插件便宜。

### agent 接入面

2026-11-01 21:36 CST   [2026-11-01 13:36 UTC]

决策：删除 connector、工作区、档位与 webhook。agent 是账号的 Turms 客户端，自己持会话、收全部会话消息并自行筛选。

原因：平台无法代替 agent 理解业务语义；平台负责身份、关系和写入校验，筛选权属于 agent。

### 限流

2026-11-04 20:43 CST   [2026-11-04 12:43 UTC]

决策：只做账号 → 会话两级桶，只对 `agent` 来源生效；授权校验先于限流。

原因：真人不太可能制造循环流量；先校验可避免用限流结果推断账号或关系是否存在。

### 好友与 Turms 投影

2026-11-01 21:36 CST   [2026-11-01 13:36 UTC]

决策：好友永不投影进 Turms，Turms 配置为不校验私聊双方关系，好友授权只在 Biz 写入网关执行。

原因：好友是 PG 业务真相；投影需要双向一致和重建，而 Turms 本不需要参与这项判断。

### 数据归属与可观测

2026-11-01 21:36 CST   [2026-11-01 13:36 UTC]

决策：消息只在 Turms，PG 不留副本；来源与限流命中只打结构化日志，不建审计表。

原因：消息副本要同步、清理和对齐顺序；早期没有查询审计的使用方。
