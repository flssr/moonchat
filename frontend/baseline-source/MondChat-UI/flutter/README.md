# MondChat · Flutter

把网页版的「月面登陆」整段体验搬到了 Flutter：星空、舱门、登录、点火、飞进月球、聊天主页。
纯 Flutter SDK，没有任何第三方包，也没有音频/字体等外部资源依赖。

> 三张火箭图与 logo 都来自 `../mondchat-web`（logo 是用户提供的 SVG，已转成 PNG）。
> 门板是用两张互补的 alpha 遮罩预先切好的：`rocket_body.png`（去掉门板的机体）+ `rocket_leaf.png`（单独的门板），
> 这样门板可以在 Flutter 里独立做 3D 旋转，而不会把机身裁掉一条。

---

## 运行

需要 Flutter 3.16+（Dart 3.2+）：

```bash
cd mondchat_flutter
flutter pub get
flutter run -d windows      # 或 chrome / macos / android
```

Web 也可以：

```bash
flutter run -d chrome
# 或
flutter build web --release
```

## 这一版做了什么

### 开场（LoginScreen）

1. **登录页**：Canvas 星空（230 颗星，缓慢闪烁）+ 月亮 + 立着的火箭（门开着）。
   左侧是 `WELCOME TO MONDCHAT` + **欢迎来到月读世界** + 玻璃质感的邮箱/密码框。
2. **提交**：两个输入框带着旋转、缩小、位移飞向舱门（用 `Transform` 驱动，两个框错开 120ms）。
   同时卡片和标题淡出，舱门里透出蓝光。
3. **关门**：
   - 门板绕左侧铰链做 `rotateY(-93°)`，转到侧对镜头时淡出；
   - 关闭状态的门用 `ClipRect` 从铰链侧扫进来；
   - 最后补一块机身边缘的补丁，消掉开门时被门板挡住的接缝。
4. **镜头**：火箭平移一半栏宽到画面正中（`AnimatedPositioned`，1.1s），红色「登录」按钮弹出来。
5. **发射**：
   - 原地抖动 0.46s（点火）；
   - 9 段关键帧的 **俯仰弧线**：先小幅后仰 −3°，再逐渐压弯到 +62°，同时位移、缩小；
   - 终点是世界坐标里的月亮中心，缩到 0.015 倍、透明度归零——**钻进月球、熄灭**；
   - 触月的一瞬间画一圈白色冲击波（`CustomPainter`）；
   - 白光一闪，根组件用 `ClipPath` 从月亮位置画一个圆扩到全屏，露出聊天主页。
6. 小屏（<940）自动改成上下布局：火箭在上、文案与表单在下，可滚动。

### 聊天主页（ChatScreen）

左栏图标 → 会话列表 → 消息区 → 右侧信息栏（宽度不足时自动收起）。
点会话切换、发消息后 0.9s 出现"正在输入"、1.4s 后自动回一句、搜索框可过滤。

## 文件

```
mondchat_flutter/
├── pubspec.yaml
├── lib/
│   ├── main.dart           # App、根组件、圆形揭幕裁剪
│   ├── theme.dart          # 配色
│   ├── sky.dart            # 渐变天空 + 星云
│   ├── starfield.dart      # 星空 CustomPainter + 月亮
│   ├── login_screen.dart   # 登录 / 关门 / 发射整套编排
│   └── chat_screen.dart    # 聊天主页
├── assets/                 # logo、机体、门板、关门、升空
└── tools/                  # 生成资源的脚本（非运行时依赖）
```

## 想改点什么

| 想改 | 改哪里 |
| --- | --- |
| 文案 | `lib/login_screen.dart` 的 `_eyebrow()` / `_headline()` / `_panel()` |
| 发射轨迹与倾角 | `lib/login_screen.dart` 顶部的 `_kFlight` 关键帧表 |
| 节奏 | 各 `AnimationController` 的 `duration` 与 `_submit` / `_launchRocket` 里的 `Future.delayed` |
| 配色 | `lib/theme.dart` |
| 聊天内容 | `lib/chat_screen.dart` 的 `_convs` |

> 说明：网页版里还有 WebAudio 合成音效；Flutter 版没有声音（避免引入音频包）。
> 另外这个项目是在没有 Flutter SDK 的环境里写的，没有现场编译过——如果 `flutter analyze` 报了哪一行，把报错发我，我直接改。
