# 镜隐移动端高保真 HTML Demo Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 `./jingyin-mobile-demo/` 交付可点击的 9 屏高保真移动端 HTML Demo（hash 路由 SPA），文案与动线对齐 `jingyin-mobile` 原型。

**Architecture:** 单页静态应用：`index.html` 放壳与 9 个 screen 的 DOM；`styles.css` 放 design tokens 与布局；`app.js` 做 hash 路由与演示态交互。无构建、无 npm。

**Tech Stack:** 原生 HTML / CSS / JS；Google Fonts（Fraunces + Manrope，失败时系统字体回退）。

**Spec:** `docs/superpowers/specs/2026-07-31-jingyin-mobile-html-demo-design.md`

## Global Constraints

- 输出目录仅限 `jingyin-mobile-demo/`（可引用但不修改 `jingyin-mobile/`）
- 9 屏 hash：`home` `upload` `editor` `settings` `exporting` `export-done` `scenarios` `how` `privacy`
- 色板：背景 `#E8ECF0`、页内 `#F4F6F8`、文字 `#0F1B24` / `#5A6A76`、强调 `#2A6F7A`、边框 `#D0D7DE`、徽章底 `#DCE8EA`
- 不做真实上传/编码；不做主体/高精子页；不做深色主题
- 用户未要求时不 `git commit`
- 用户可见文案用中文；无 emoji

## File Structure

| 文件 | 职责 |
|---|---|
| `jingyin-mobile-demo/index.html` | 桌面舞台、手机框、侧栏索引、9 个 `<section data-screen>` |
| `jingyin-mobile-demo/styles.css` | tokens、壳、通用组件、各屏样式、动效 |
| `jingyin-mobile-demo/app.js` | `navigate(hash)`、hashchange、设置选中态、导出演示跳转 |
| `jingyin-mobile-demo/README.md` | 打开方式与屏清单 |

---

### Task 1: 脚手架 + 视觉 tokens + 路由壳

**Files:**
- Create: `jingyin-mobile-demo/index.html`
- Create: `jingyin-mobile-demo/styles.css`
- Create: `jingyin-mobile-demo/app.js`
- Create: `jingyin-mobile-demo/README.md`

**Interfaces:**
- Produces: `navigate(id)` 全局函数；各屏 `id="screen-<id>"` + `data-screen="<id>"`；仅 `.is-active` 的屏可见
- Consumes: 无

- [ ] **Step 1: 创建目录与 README**

`README.md` 内容：

```markdown
# 镜隐 · 移动端高保真 Demo

双击 `index.html` 打开，或：

```bash
cd jingyin-mobile-demo && python3 -m http.server 8765
# 浏览器打开 http://localhost:8765
```

| # | 页面 | hash |
|---|---|---|
| 1 | 首页 | `#home` |
| 2 | 选择视频 | `#upload` |
| 3 | 编辑预览 | `#editor` |
| 4 | 效果设置 | `#settings` |
| 5 | 导出中 | `#exporting` |
| 6 | 导出完成 | `#export-done` |
| 7 | 适用场景 | `#scenarios` |
| 8 | 使用步骤 | `#how` |
| 9 | 隐私政策 | `#privacy` |

基于 `jingyin-mobile` 线框；纯演示，无真实处理。
```

- [ ] **Step 2: 写 `styles.css` tokens 与壳**

至少包含：

```css
:root {
  --bg: #E8ECF0;
  --surface: #F4F6F8;
  --ink: #0F1B24;
  --muted: #5A6A76;
  --accent: #2A6F7A;
  --border: #D0D7DE;
  --badge: #DCE8EA;
  --radius-card: 16px;
  --radius-btn: 12px;
  --phone-w: 375px;
  --phone-h: 812px;
  --font-display: "Fraunces", "Times New Roman", serif;
  --font-ui: "Manrope", "PingFang SC", "Hiragino Sans GB", sans-serif;
}
```

以及：`.stage` 居中布局、`.phone` 375×812 圆角 36px 软影、`.screen` 默认 `display:none`、`.screen.is-active` 可见、`.nav-rail` 侧栏索引、通用 `.btn` / `.btn-ghost` / `.topbar` / `.badge` / `.card` / `.media-ph`。

切屏：

```css
.screen.is-active {
  display: flex;
  flex-direction: column;
  animation: screen-in 150ms ease-out;
}
@media (prefers-reduced-motion: reduce) {
  .screen.is-active { animation: none; }
}
```

- [ ] **Step 3: 写 `index.html` 壳（9 个空 section 占位）**

结构要点：

- `<link>` 引入 Google Fonts（Fraunces + Manrope）与 `styles.css`
- `.stage` > `.nav-rail`（9 个按钮 `data-nav`）+ `.phone` > `.phone-notch` + `.phone-screens`
- 每个屏：`<section class="screen" id="screen-home" data-screen="home">…</section>`（其余 8 个同理，内容先放标题占位即可）
- `<script src="./app.js" defer></script>`

- [ ] **Step 4: 写 `app.js` 路由**

```javascript
const SCREENS = [
  "home", "upload", "editor", "settings",
  "exporting", "export-done", "scenarios", "how", "privacy",
];

function navigate(id) {
  const next = SCREENS.includes(id) ? id : "home";
  if (location.hash !== "#" + next) {
    location.hash = next;
    return;
  }
  document.querySelectorAll(".screen").forEach((el) => {
    el.classList.toggle("is-active", el.dataset.screen === next);
  });
  document.querySelectorAll("[data-nav]").forEach((el) => {
    el.classList.toggle("is-active", el.dataset.nav === next);
  });
  const active = document.querySelector(".screen.is-active");
  if (active) active.scrollTop = 0;
}

function currentFromHash() {
  const raw = (location.hash || "#home").replace(/^#/, "");
  return SCREENS.includes(raw) ? raw : "home";
}

window.addEventListener("hashchange", () => navigate(currentFromHash()));
document.addEventListener("DOMContentLoaded", () => {
  document.body.addEventListener("click", (e) => {
    const t = e.target.closest("[data-go]");
    if (t) {
      e.preventDefault();
      navigate(t.dataset.go);
    }
    const n = e.target.closest("[data-nav]");
    if (n) {
      e.preventDefault();
      navigate(n.dataset.nav);
    }
  });
  navigate(currentFromHash());
});

window.navigate = navigate;
```

- [ ] **Step 5: 静态自检**

Run:

```bash
test -f jingyin-mobile-demo/index.html \
 && test -f jingyin-mobile-demo/styles.css \
 && test -f jingyin-mobile-demo/app.js \
 && test -f jingyin-mobile-demo/README.md \
 && rg -c 'data-screen="' jingyin-mobile-demo/index.html
```

Expected: 四个文件存在；`data-screen=` 至少 9 处。

---

### Task 2: 主路径六屏内容

**Files:**
- Modify: `jingyin-mobile-demo/index.html`
- Modify: `jingyin-mobile-demo/styles.css`（按需补屏级样式）

**Interfaces:**
- Consumes: `data-go="<screen-id>"` 点击跳转；`navigate`
- Produces: 完整主路径 DOM 与文案

文案来源：`jingyin-mobile/js/screens/{home,upload,editor,settings-general,exporting,export-done}.js`

- [ ] **Step 1: 实现 `#home`**

包含：顶栏「镜隐」+ 语言/主题徽章（静态）、eyebrow `ON-DEVICE · NO UPLOAD`、标题「想分享生活，先把隐私藏好。」、信任徽章三枚、主上传卡片（`data-go="upload"`）、Cell 列表进 scenarios/how/privacy、页脚 reaidea。

- [ ] **Step 2: 实现 `#upload`**

顶栏返回 home；居中大卡片「选择你的视频」；按钮 `data-go="editor"`；格式说明；边界文案提示。

- [ ] **Step 3: 实现 `#editor`**

顶栏返回 home、「已遮挡 2」；预览占位 + 播放条；遮盖范围三按钮（全画面/遮盖主体/主体之外 —— 后两者可都 `data-go="settings"`，全画面也进 settings）；设置列表；隐私说明卡；主 CTA「开始快速处理」→ `exporting`（或先到 settings，再从 settings 导出：主 CTA 用 `data-go="settings"` 与原型「通用设置」路径一致亦可；**规定：主 CTA → `settings`**，settings 内「开始快速处理」→ `exporting`）。

- [ ] **Step 4: 实现 `#settings`**

顶栏返回 editor；处理精度三档（快速/标准选中/高 —— 高档仅 UI，不跳高精页）；模糊强度滑条视觉；声音三档（变音选中）+ 音调条；水印说明卡；CTA → `exporting`。

选中态用 class `.is-selected`，由 Task 3 的 JS 切换；HTML 默认给「标准」「变音」加上 `.is-selected`。

- [ ] **Step 5: 实现 `#exporting` 与 `#export-done`**

exporting：进度 42%、预计 0:48、处理中占位、「停止处理」→ editor、「（演示）跳到完成」→ export-done。  
export-done：完成徽章、结果占位、「保存处理后的视频」（无真实下载）、隐私卡、「继续编辑」→ editor、「返回首页」→ home。

- [ ] **Step 6: 自检主路径链接**

Run:

```bash
rg -n 'data-go="(upload|editor|settings|exporting|export-done|home)"' jingyin-mobile-demo/index.html
```

Expected: home→upload、upload→editor、editor→settings、settings→exporting、exporting→export-done/editor、export-done→editor/home 均出现。

---

### Task 3: 旁路三屏 + 设置交互 + 收尾

**Files:**
- Modify: `jingyin-mobile-demo/index.html`
- Modify: `jingyin-mobile-demo/styles.css`
- Modify: `jingyin-mobile-demo/app.js`

**Interfaces:**
- Consumes: Task 1 `navigate`；settings 上 `.seg-btn` / `.choice-btn`
- Produces: scenarios/how/privacy 完整页；设置点选切换 `.is-selected`

- [ ] **Step 1: 实现 `#scenarios` `#how` `#privacy`**

文案分别对齐 `scenarios.js` / `how.js` / `privacy.js`。  
scenarios / how 底部 CTA → upload；privacy 返回 home。

- [ ] **Step 2: `app.js` 增加设置分段选中**

在 `DOMContentLoaded` 内：

```javascript
document.body.addEventListener("click", (e) => {
  const seg = e.target.closest("[data-seg]");
  if (!seg) return;
  const group = seg.parentElement;
  if (!group || !group.classList.contains("seg-group")) return;
  group.querySelectorAll("[data-seg]").forEach((b) => b.classList.remove("is-selected"));
  seg.classList.add("is-selected");
});
```

（与现有 `data-go` 监听可合并到同一 click 委托。）

- [ ] **Step 3: 视觉抛光检查清单（手工）**

打开页面后确认：

1. 默认落在 home，侧栏高亮正确  
2. 主路径点通一遍  
3. scenarios / how / privacy 可回 home  
4. settings 点选切换高亮  
5. `prefers-reduced-motion` 下无位移动画（可选）  
6. 无 emoji；触摸目标按钮高度 ≥ 44px

- [ ] **Step 4: 最终文件清单核对**

Run:

```bash
find jingyin-mobile-demo -type f | sort
rg -o 'data-screen="[^"]+"' jingyin-mobile-demo/index.html | sort -u
```

Expected: 仅 `index.html` `styles.css` `app.js` `README.md`（及可选 `.DS_Store` 忽略）；9 个唯一 `data-screen`。

---

## Spec Coverage Checklist

| Spec 项 | Task |
|---|---|
| 9 屏 + hash | Task 1–3 |
| 主路径 / 旁路 | Task 2–3 |
| 视觉 tokens | Task 1 |
| 不做真处理 / 无主体子页 | 全局约束 + Task 2 settings 合并 |
| 离线可开 | Task 1 静态三文件 |
| README | Task 1 |

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-07-31-jingyin-mobile-html-demo.md`.

**Two execution options:**

1. **Subagent-Driven（推荐）** — 每 Task 派一个子代理，Task 间复核  
2. **Inline Execution** — 本会话按 executing-plans 连续做完

选哪个？
