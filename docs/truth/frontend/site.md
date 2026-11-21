# 产品官网

**一句话**：`site/` 是一页不需要构建的静态产品页，说明「账号背后可以是人，也可以是人的 agent」。

## 构成

| 文件 | 用途 |
| --- | --- |
| `site/index.html` | 单页结构，以及首帧前的主题内联脚本 |
| `site/styles.css` | 纸白 / 炭黑两套变量、排版与组件 |
| `site/app.js` | 主题切换、引言轮换、下载确认弹窗、正文逐段进场 |
| `site/sky.js` | 首屏的月亮、星点与流星（canvas） |
| `site/assets/mondchat-logo.svg` | 品牌图标与 favicon |

没有构建、没有外部字体，也不发网络请求（下载入口除外）。直接打开 `site/index.html`，或用任意静态服务器托管都可以。

## 页面

导航 → 首屏（品牌图标、标语、引言）→ 三段散文（账号 / 同一处 / 分寸）→ 引言带 → 结尾 → 页脚。文案只陈述产品本身，不承诺客户端之外的能力。

## 下载入口

- 导航右侧「现在体验 MondChat」本身是一个指向安装包的链接：`https://github.com/flssr/moonchat/releases/download/preview/MondChat-Setup-1.0.0.exe`（`preview` 标签下的产物，版本号随产物走，换包要同步改这一处）。
- 有 JS 时点它先弹原生 `<dialog>`，提示「只支持 x64 平台的 Windows 10 及以上」；「确认」关掉弹窗并跳下载，「取消」、`Esc`、点遮罩都只关弹窗。
- 没有 JS 或浏览器不支持 `dialog.showModal` 时不拦链接，直接下载；提醒只是告知，不是门禁。


## 主题与昼夜

- `<html data-theme>` 只有 `light` / `dark`；首帧前由 `index.html` 里的内联脚本决定：先读 `localStorage['mondchat-theme']`，没有就跟随 `prefers-color-scheme`。
- 主题按钮切换并写回同一个键；换键等于丢掉访客已存的偏好。
- **白天只留月亮**；星点与流星只画在暗色的首屏。`sky.js` 在切回亮色时停帧并清空画布，画布本身在亮色下 `display:none`。
- 流星同时最多 3 颗，间隔约 3.8–7 秒，只在标题上方的空天里划完，不穿过正文。

## 降级与可访问性

- **没有 JS**：`<html>` 不会挂 `js` 类，正文不做进场、直接可见；主题保持首次解析时的默认值；「现在体验」退化成普通下载链接。
- 正文按段落进场：`app.js` 给每个 `.reveal` 里的 `p` / `h2` / `blockquote` / `figcaption` 加 `rv` 类，靠近视口才加 `is-in`；相邻元素靠 `--i` 排队 110ms。`rv` 的隐藏规则与 `is-in` 命中规则都带 `html.js` 前缀：命中规则少了它就会被压过，正文停在透明。
- `prefers-reduced-motion: reduce`：正文直接可见、星图静止、不出流星、引言不轮换。
- 引言 `figure` 可以聚焦，悬停或聚焦时暂停轮换。
- 主题按钮有固定的 `aria-label`，不叠 `aria-pressed`；下载弹窗用 `<dialog>` 自带的焦点管理，标题由 `aria-labelledby` 关联。

## 本地预览

```powershell
python -m http.server 8130 --directory site
```

`file://` 下 `localStorage` 可能不可用，主题只跟随系统。

## 边界

- 不在客户端构建里，也不进 `frontend/app` 的产物；与 `frontend/preview`（客户端设计评审稿）是两回事。
- 仓库里没有 `site/` 的部署编排与 CI 校验，托管方式由部署侧决定。
