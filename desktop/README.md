# MondChat 桌面客户端（Windows）

`frontend/app` 是共享的 Flutter 客户端（Web 入口）；这个工程只加 Windows 侧的两件平台实现，
界面、状态、API 调用仍然只有一份：

| 能力 | Web（`frontend/app`） | 桌面（这里） |
| --- | --- | --- |
| 本地设置 / 登录态 | `localStorage` | `%APPDATA%\MondChat\*.json`（`lib/storage.dart`） |
| Turms 读通道 | 页面里的 `turms-client-js` | 原生 WebSocket + Dart proto（`lib/realtime.dart`） |
| 窗口 | 浏览器标签页 | 无边框窗口，自定义 32px 标题栏（`lib/title_bar.dart`） |

Turms 的 Dart 客户端只有 TCP 传输（11510），生产与本地编排暴露的只有 `/im` WebSocket（10510），
所以桌面端的读通道按 `turms-client-js` 的线上格式直接走 WebSocket：一帧一个 protobuf，
请求/响应按 `requestId` 配对。写入仍然只走 Biz，客户端不拿 Turms 写权限。

窗口由 `window_manager` 的 `TitleBarStyle.hidden` 去掉系统标题栏；`DesktopTitleBar` 负责
拖动、双击最大化、最小化/最大化/关闭。登录页传 `edgeToEdge: true`，表单与舞台铺满客户区，
不再保留 Web 的居中卡片边距。

## 构建

需要 Flutter SDK 与 **Visual Studio 2022「使用 C++ 的桌面开发」工作负载**（Windows 桌面构建的前置）。
工程带原生插件，Flutter 在 Windows 上构建插件需要符号链接支持（系统设置里打开“开发者模式”）。

```powershell
.\desktop\build.ps1                                  # 生产默认 https://api.mondchat.com
.\desktop\build.ps1 -ApiBase http://127.0.0.1:8080   # 本地 biz
```

产物：`desktop\build\windows\x64\runner\Release\MondChat.exe`。`assets/` 是构建前从
`frontend/app/assets` 复制出来的，不进 git。

CI 的 `desktop` job 在 `windows-latest` 上跑同一份构建并把整目录作为 `mondchat-windows`
artifact 上传；本机没有 Visual Studio 时，直接下载 artifact 即可。

## 本地开发

```powershell
cd desktop
flutter pub get
Copy-Item -Recurse ..\frontend\app\assets assets
flutter run -d windows --dart-define=MONDCHAT_API_BASE=http://127.0.0.1:8080
```

## 检查

```powershell
cd desktop
flutter analyze
flutter test
```

`test/realtime_test.dart` 用一个本地 WebSocket 冒充 Turms 网关，校验登录、查历史与推送映射；
`test/storage_test.dart` 校验本机文件里的设置、头像与登录态往返。
