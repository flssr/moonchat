# 产品官网

**一句话**：`site/` 是一页不需要构建的静态产品页，说明「账号背后可以是人，也可以是人的 agent」。

## 构成

| 文件 | 用途 |
| --- | --- |
| `site/index.html` | 单页结构，以及首帧前的主题内联脚本 |
| `site/styles.css` | 纸白 / 炭黑两套变量、排版与组件、滚动驱动的进出场 |
| `site/app.js` | 主题切换、引言轮换、下载确认弹窗 |
| `site/sky.js` | 首屏的月亮、星点与流星（canvas） |
| `site/assets/mondchat-logo.svg` | 品牌图标与 favicon |

没有构建、没有外部字体，也不发网络请求（下载入口除外）。直接打开 `site/index.html`，或用任意静态服务器托管都可以。

## 页面

导航 → 首屏（品牌图标、标语、引言）→ 三段散文（账号 / 同台 / 分寸）→ 引言带 → 结尾（于是）→ 页脚。

引言（首屏轮换 6 句、引言带 1 句）按「人机共生」挑：工具怎么塑造人、人怎么和会说话的机器相处；只讲语言、相遇、聊天的句子和纯计算机科学的句子都不取。同样的取舍也用在客户端登录页的引言行。文案只陈述产品本身，不承诺客户端之外的能力。语气以短句和具体的东西为主，不堆三连排比、不凑对称句；「不在平台的视野里」「对话，多了一种可能。」这两句是按用户意见保留的原句，不按这条规则改。

## 下载入口

- 导航右侧「现在体验 MondChat」本身是一个指向安装包的链接：`https://github.com/flssr/moonchat/releases/download/preview/MondChat-Setup-0.0.2.exe`（`preview` 标签下的产物，版本号随产物走，换包要同步改这一处）。
- 有 JS 时点它先弹原生 `<dialog>`，提示「只支持 x64 平台的 Windows 10 及以上」；「确认」关掉弹窗并跳下载，「取消」、`Esc`、点遮罩都只关弹窗。
- 没有 JS 或浏览器不支持 `dialog.showModal` 时不拦链接，直接下载；提醒只是告知，不是门禁。


## 主题与昼夜

- `<html data-theme>` 只有 `light` / `dark`；首帧前由 `index.html` 里的内联脚本决定：先读 `localStorage['mondchat-theme']`，没有就跟随 `prefers-color-scheme`。
- 主题按钮切换并写回同一个键；换键等于丢掉访客已存的偏好。
- **白天只留月亮**；星点与流星只画在暗色的首屏。`sky.js` 在切回亮色时停帧并清空画布，画布本身在亮色下 `display:none`。
- 流星同时最多 3 颗，间隔约 3.8–7 秒，只在标题上方的空天里划完，不穿过正文。

## 正文入场

进场和退场都挂在滚动位置上（`animation-timeline: view()` + `animation-range: cover 0% cover 100%`），滑过再滑回来会原路重演，也不存在「停在屏幕中间却是透明」的死区：透明度只由元素当时的位置决定。分了几层：

| 层 | 做法 |
| --- | --- |
| 标题行 | `app.js` 把 `.hero h1` / `.reveal h2` / `.band blockquote p` 里的 `<br>` 拆成 `.ln > .ln__i`，外层 `overflow: clip` 当遮罩，内层按自己的时间线从 118% 推到 0，一行一行出来 |
| 小节标签 | `.kicker` 用 `clip-path: inset(0 100% 0 0)` 从左往右揭开 |
| 段落 / 落款 | 淡入 + 上浮 22px + 5px 模糊，滑到导航下方再淡出并上浮 30px |
| 分节线 | `.essay` 的 1px 背景线随 `background-size` 从 0 拉到 100%，从左画到右 |
| 导航下沿 | `.nav::after` 的渐变在滚动 0–120px 内淡入，正文滑上来时在导航下面化开 |
| 首屏 | 标题按行推上来，图标 / 正文 / 引言 / 继续阅读依次淡入（一次性的读入动画，不跟滚动） |

- 标题行用 `overflow: clip` 而不是 `overflow: hidden`：后者是滚动容器，会接管行内元素的 `view()` 时间线。
- 有 `:has(.ln)` 的判断：标题被拆成行以后，整块的淡入让位给行遮罩，不叠两层。
- 没有 JS 时不拆行，标题退回整块淡入；`prefers-reduced-motion` 时全部不播，正文静态可见。

## 降级与可访问性

- **没有 JS**：主题保持首次解析时的默认值；「现在体验」退化成普通下载链接；标题不拆行、按整块淡入。
- `prefers-reduced-motion: reduce`：正文不播入场、直接可见；星图静止、不出流星、引言不轮换。
- 引言 `figure` 可以聚焦，悬停或聚焦时暂停轮换。
- 主题按钮有固定的 `aria-label`，不叠 `aria-pressed`；下载弹窗用 `<dialog>` 自带的焦点管理，标题由 `aria-labelledby` 关联。

## 本地预览

```powershell
python -m http.server 8130 --directory site
```

`file://` 下 `localStorage` 可能不可用，主题只跟随系统。

## 部署与缓存

- `site/` 推到 `main`（或手动触发）后由 [`.github/workflows/site.yml`](../../../.github/workflows/site.yml) 铺到 `mondchat.com` 根目录：先解压全部资源，最后落 `index.html`，中途刷新不会拿到「新 HTML 指向还没到的新资源」。
- 部署时把 `styles.css` / `app.js` / `sky.js` / 品牌图的内容哈希写成 `?v=` 指纹，只写在部署产物里；仓库里的 `index.html` 保持裸文件名，本地直接打开照常工作。资源一变地址就变，浏览器不会拿旧 CSS 配新 HTML。
- 站点服务器上给 `index.html` 发 `Cache-Control: no-cache`、给带指纹的资源发长缓存（`max-age` + `immutable`）是部署侧的事，不在仓库里；没配之前浏览器会按 `Last-Modified` 猜有效期，改样式后老访客可能短时间看到旧 CSS。

## 边界

- 不在客户端构建里，也不进 `frontend/app` 的产物；与 `frontend/preview`（客户端设计评审稿）是两回事。
