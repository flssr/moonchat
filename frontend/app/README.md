# moonchat 客户端（Flutter Web）

V1 只发 Web 构建。界面以 `frontend/preview/index.html` 为唯一视觉源，实现依据是
`frontend/docs/DESIGN-SPEC.md`、`SCREEN-MAP.md`、`API-MAPPING.md`；接口契约以
`docs/api-contracts.md` 为准，本工程不新增路由与字段。

## 跑起来

```powershell
# 后端默认同源（nginx 反代 /api）。本地直连 Biz 时用 dart-define 指过去：
flutter pub get
flutter run -d chrome --dart-define=MOONCHAT_API_BASE=http://localhost:8080

# 产物
flutter build web --release --dart-define=MOONCHAT_API_BASE=
```

`MOONCHAT_API_BASE` 为空表示同源：客户端假定 `/api` 与页面同域，这是 `docs/deployment.md`
里 nginx 的部署形态。

## 结构

```
lib/
├─ main.dart              主题状态 + 登录/外壳切换
├─ theme.dart             设计 token（DESIGN-SPEC §2–§6 的唯一出处）
├─ api/
│  ├─ models.dart         与 api-contracts.md 一一对应的传输模型
│  └─ api_client.dart     20 条 /api/* 的唯一调用点；错误码 → 界面文案
├─ state/app_state.dart   身份、账号、好友、群、发言；登录 JWT 与 Turms 凭据续期
├─ ui/                    登录、消息、联系人、账号、资料页、通用组件
└─ turms/                 （待接）Turms 会话：收消息与历史分页
```

## 现状

- 已完成：注册 / 登录、切账号、建 agent（一次性密钥）、好友四条、资料页、群七条、
  发言（唯一写入口）、发送中 / 失败 / 重试、明暗主题、按容器宽度收栏。
- 未完成：**读取通道**。会话列表现在由「好友 + 我加入的群」拼出，历史消息与实时推送
  必须来自客户端自己的 Turms 会话（`docs/messaging-and-tunnel.md`）。这一层没接上之前，
  界面只能看到本机发出的消息，看不到对方与历史。
- 界面规则只从 `docs/friends.md`（私聊入口只有好友列表与资料页）与
  `docs/account-and-ownership.md`（主页字段）里读；需要新规则时先补 spec。

## 测试

```powershell
flutter analyze
flutter test
```
