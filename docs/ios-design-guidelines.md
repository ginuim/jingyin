# 镜隐 iOS 设计规范

更新时间：2026-09-07

本文是 iOS 版（`ios/Jingyin`）的界面设计规范。目标：所有新界面按本文执行，旧界面按"问题清单"逐步收口。与 `ios-app-plan.md` / `ios-launch-todo.md` 冲突时以产品文档为准，本文只管视觉与交互表达。

## 1. 颜色

唯一来源是 `ios/Jingyin/App/AppPalette.swift`。禁止在视图里写 `Color(red:green:blue:)`、十六进制字面量或裸 `Color.black / .white`（媒体画布与覆盖层除外，见 1.3）。

### 1.1 语义色（自适应深浅色）

| 角色 | 令牌 | 用途 |
| --- | --- | --- |
| 页面底色 | `AppPalette.background` | 所有页面最底层 |
| 卡片底 | `AppPalette.surface` | 内容卡片、输入区 |
| 浮层底 | `AppPalette.elevatedSurface` | 进度浮层、未选中填充、按压态 |
| 主文本 | `AppPalette.primaryText` | 标题、正文 |
| 次文本 | `AppPalette.secondaryText` | 说明、副标题、脚注 |
| 禁用文本 | `AppPalette.disabledText` | 禁用态（不要再用 `opacity(0.45)` 之类魔法数） |
| 描边/分隔 | `AppPalette.divider` | 卡片描边、分隔线；需要弱化时统一 `divider.opacity(0.5)`，不再各处自造 0.34/0.38/0.45/0.7 |

### 1.2 品牌色与反馈色

- 品牌主色只有一组：`AppPalette.accent`（当前 `signalOrange`）。交互元素用 `accent.primary`，按下态用 `accent.pressed`，弱强调底用 `accent.softFill`，描边用 `accent.outline`，主色上的文字用 `accent.foreground`。
- 反馈色：`warning`（警告）、`destructive`（删除/取消/失败）、`success`（成功、完成状态）。`success` 必须用起来，不许再用 `accent.primary` 冒充完成态。
- 付费/权益相关不加第三种品牌色，继续用 accent 系。

### 1.3 媒体画布与覆盖层

- 视频/照片画布的底统一用 `AppPalette.mediaCanvas`（纯黑）。`UIViewRepresentable` 里的 `UIColor.black` 视同 `mediaCanvas`，注释标明即可。
- 画布上的蒙版/标注一律：`maskOutline`（白）、`maskOutlineShadow`（黑 85%）、`mediaScrim`（黑 62%）。覆盖层颜色不随品牌色变化。
- 绘制中预览、选中态可用 `accent.primary`，保证与白色蒙版线区分。

## 2. 字体

优先用系统动态字体（支持 Dynamic Type），禁止新代码使用 `.system(size:)` 固定字号，下表"例外"除外。

| 角色 | 样式 |
| --- | --- |
| 页面大标题（仅首页/结果页庆祝文案） | `.system(.title, design: .rounded, weight: .bold)` |
| 分区/卡片标题 | `.headline` |
| 强调副标题、按钮文字 | `.subheadline.weight(.semibold)` |
| 正文 | `.body` / `.subheadline` |
| 辅助说明、卡片脚注 | `.footnote` |
| 标签、徽章、chip 文字 | `.caption`（需要强调加 `.weight(.semibold)`） |
| 时间码、百分比、计数 | `.caption` / `.headline` + `.monospacedDigit()` |
| 最小说明文字 | `.caption2`（每屏最多一处，不承载关键信息） |

固定字号的合法例外（必须注释原因）：

- 播放/处理中的大号百分比数字、结果页大标题等"展示级"数字；
- 图标尺寸（`Image(systemName:)` 的 `.system(size:)`）；
- Paywall 等营销页的主标题可用 `.title`/`title2` 动态字体等价物替代现有 28pt/34pt 固定值。

图标尺寸分三档：工具图标 18、状态/徽章图标 16、场景大图标（处理中、空状态）56。新增时先复用档位。

## 3. 圆角

只允许四档，按语义选：

| 档位 | 值 | 用途 |
| --- | --- | --- |
| 小控件 | 10 | chip 内小图、缩略图、小型选择器 |
| 控件 | 12 | 选项按钮、工具图标底 |
| 卡片/按钮 | 16 | 内容卡片、所有全宽主/次按钮 |
| 媒体 | 20 | 视频/照片预览画布 |

- 胶囊（Capsule）只用于：横向滚动的 chip、浮在媒体上的提示条、徽标计数。
- 圆形（Circle）只用于：色板、浮在媒体上的小操作钮、完成状态标。
- 同一元素占位图与实际内容的圆角必须一致（现状：照片缩略图占位 10、裁剪 6，需修）。

## 4. 间距与布局

页面级统一：

- 页面水平边距 **20**。全屏媒体编辑页可用 0（画布贴边）+ 内容区 20。废止 28/32。
- 分区之间 spacing **24**；卡片内部元素 spacing **12**；紧凑控件组（chips、工具行）spacing **8**。
- 卡片内边距 **16**。
- 不要再出现 22/28/32 的页面边距和 42/30/22 之类的逐项 `.padding(.top:)` 堆叠；分区用 `VStack(spacing: 24)`。

点击目标：最小 44×44pt。视觉上小于 44 的按钮（媒体上的删除钮、缩放手柄）必须用负 inset 或透明扩展层把热区补足到 44。

## 5. 按钮体系

把 `ContentView.swift` 里 private 的 `PrimaryButtonStyle` / `SecondaryButtonStyle` 提升为 App 级组件（建议放 `AppPalette.swift` 旁新建 `AppButtonStyles.swift`），全 App 只允许这三种：

| 样式 | 规格 | 用途 |
| --- | --- | --- |
| 主按钮 | accent 底（pressed 用 `accent.pressed`）、`accent.foreground` 文字、headline、圆角 16、最小高度 52 | 每屏最多一个主行动（开始处理、保存、购买） |
| 次按钮 | `surface` 底 + `divider` 描边、primaryText、圆角 16、最小高度 52 | 与主按钮并列的第二行动 |
| 文字按钮 | 无底无框，destructive 操作用 `AppPalette.destructive`，其余用 accent 或 secondaryText | 取消、恢复购买、次要导航 |

规则：

- 禁止新代码使用 `.borderedProminent` / `.bordered` 系统样式出现在主流程页面（Menu 等系统控件除外）；现有 `ProcessingView` 重试按钮等逐步替换。
- 工具栏（toolbar）里的确认/取消用系统 `.confirmationAction` / `.cancellationAction` 文本样式，**不要**在导航栏里塞自绘胶囊按钮。
- 所有按钮必须有 pressed 反馈（ButtonStyle 内处理），`.plain` + 静态背景的写法禁止。
- 文字按钮也要有 44pt 最小高度。

## 6. 图标

- 统一 SF Symbols，默认 monochrome 渲染。
- 状态图标统一 fill 变体（`checkmark.circle.fill` 等）；分区/工具图标统一非 fill。
- 同一语义同一图标：添加蒙版统一 `plus.circle` 系（废弃 `circle.dashed`/`rectangle.dashed` 与 `plus.rectangle` 混用）；选中态统一 checkmark.circle.fill ↔ circle。
- 图标 + 文字的 Label，图标不再单独设与文字不协调的字号。

## 7. 导航与呈现

| 场景 | 方式 |
| --- | --- |
| 流程推进（首页→编辑→处理/结果） | push（`navigationDestination`） |
| 轻量配置（导出设置、人脸选择） | `.sheet`，导出设置保留 `.medium/.large` detents |
| 沉浸任务（全屏蒙版编辑） | `.fullScreenCover` + 强制深色 + `mediaCanvas` 底 |
| 付费墙 | 改为 `.sheet`（大 detent），或保留 fullScreenCover 但去掉伪 sheet 外观（顶部圆角+阴影），二选一后全 App 统一 |
| 分享 | 系统 ShareSheet |
| 错误/确认 | alert / confirmationDialog，见第 8 节 |

- 除全屏蒙版编辑外，页面不强制 `.preferredColorScheme(.dark)`；`FaceSelectionView` 的强制深色应移除。
- 处理中等长任务页面：`navigationBarBackButtonHidden` 期间，取消入口必须固定在可见位置（底部安全区上方），不能需要滚动才看到。

## 8. 反馈与确认

### 8.1 破坏性操作

以下操作必须二次确认（`confirmationDialog`）或提供撤销：删除整条蒙版轨道、删除关键帧、取消正在进行的导出/处理、批量导出前清空已编辑参数。alert 里纯确认的"好"按钮**不带** `role: .cancel`。

### 8.2 进度反馈

- 凡耗时操作必须有进度：能算百分比就显示百分比 + ProgressView；批量任务显示"n/N"计数。照片批量导出目前只有缩略图徽章变色，需补整体进度。
- 处理页五要素保持：阶段标题、图标、百分比、进度条、预计剩余时间。

### 8.3 结果反馈

- 成功：页面内联状态或 Toast，统一用 `success` 色；保存成功的 Toast 模式（1.8s）可推广到视频流。
- 失败：内联错误卡（可操作场景，如重试）优先于 alert；alert 只用于"必须打断用户"的失败。错误文案必须本地化，禁止 `EntitlementStore` 里的硬编码英文串再出现。
- 触觉反馈：在导出完成、保存成功、蒙版删除、关键帧记录四处加 `.sensoryFeedback`（`.success` / `.warning` / `.impact`），并尊重系统设置。

### 8.4 无障碍

- 全屏动画（如彩带）必须响应 `Reduce Motion`（`@Environment(\.accessibilityReduceMotion)`），开启时降级为静态状态展示。
- 关键操作按钮都要有 `accessibilityLabel`（参照首页齿轮按钮的写法）。
- 文本与底色对比度按 WCAG AA：`warning` 色只用于图标和加粗文字，小字说明用 `secondaryText`。

## 9. 本地化

- 新增用户可见文本必须同步 `Localizable.xcstrings` 四语（简中/繁中/英文/日文），见 AGENTS.md。
- 语义化 key，禁止跨场景复用（现状：Paywall 取消按钮复用 `export.cancel`，应新建 `paywall.close`）。
- 动态拼接的 key（如 `ascii.theme.*`）在 xcstrings 里加注释说明，防止被当 stale 清理；真实废弃的 stale 条目定期删除。
- 文案里的价格、数量一律走 StoreKit 本地化价格或 `String(format:)`，不硬编码。

## 10. 落地优先级

按问题清单（见下方审查结论）执行顺序：

1. **高严重度交互**：删除蒙版/关键帧确认、处理中取消按钮可达性、Paywall 伪 sheet、人脸选择死代码确认。
2. **按钮与令牌收口**：共享 ButtonStyle、替换 borderedProminent、`success`/`pressed` 令牌启用、禁用态统一。
3. **圆角/间距/字号令牌化**：按第 2/3/4 节替换魔法数。
4. **反馈补全**：批量导出进度、触觉反馈、Reduce Motion、错误本地化。
5. **图标与同功能双实现统一**：主编辑器 vs 全屏编辑器、添加蒙版图标。

---

## 附：2026-09-07 审查发现的主要问题清单

详细行号见各文件；严重度标注在每条末尾。

### 交互

1. 删除蒙版、删除关键帧、取消导出均无二次确认且不可撤销；蒙版删除钮 28pt 与缩放手柄相邻，误触即删整条轨道。（高）
2. 处理页只隐藏返回键，取消按钮在页面底部且无确认，长视频误触代价高。（高）
3. Paywall 用 fullScreenCover 却画成 sheet 外观，下拉无反应，外观与行为不符。（高）
4. 人脸选择链路（`detectFacesAtCurrentFrame` / `FaceSelectionView`）当前不可达，状态机悬空，需确认是"有意隐藏"还是漏接。（高）
5. 照片批量导出无整体进度（无百分比、无 n/N），反馈弱于免费导入路径。（高）
6. 照片流无导出设置入口，免费"每次 1 张"除 crown 图标外无前置说明，点导出后才发现限制。（中）
7. 照片预览不支持左右滑动切换，只能点顶部缩略图。（中）
8. 内嵌视频预览强制 16:9，竖屏视频信箱化，蒙版编辑精度受损；全屏编辑器才用真实宽高比。（中）
9. 主编辑器与全屏编辑器的同组操作（添加蒙版图标、缩放按钮样式、可见性菜单）两套实现。（中）
10. 恢复购买反馈通道不一致：Paywall 内联、设置页 alert、成功一处 dismiss 一处弹窗。（中）
11. `refreshFromSystemIfNeeded` 无调用点，跟随系统语言时切换系统语言不生效。（中）
12. 全 App 无触觉反馈。（低）

### 视觉

13. 主按钮四种实现（首页 PrimaryButtonStyle private、视频结果页 18 圆角、照片结果页 20 圆角、Paywall 76 高/20 圆角、设置页 14 圆角），互不复用。（高）
14. Paywall 大量 `.system(size:)` 固定字号，不响应动态字体。（高）
15. 彩带 7 色硬编码且不响应 Reduce Motion；照片结果页多处 `.white/.black.opacity` 硬编码。（中）
16. 页面水平边距 16/20/28/32 并存；卡片圆角 14/18/20/24 并存；照片编辑页 6/7/10/11/18 自成一套。（中）
17. `AppPalette.success`、`accent.pressed` 令牌闲置；禁用态各处自造 opacity 0.45/0.55。（中）
18. 编辑页主按钮前景硬编码 `.white` 而非 `accent.foreground`；结果页描边按钮用 `primaryText` 当边框色且线宽不一。（中）
19. `mediaCanvas` 三处三个答案（令牌/裸 black/背景色）。（低）
20. `EntitlementStore` 硬编码英文错误串直接渲染给四语用户。（高）
21. xcstrings 21 个 stale 条目、4 个无翻译占位 key 待清理；`ascii.theme.*` 运行时依赖需加注释。（低）

## 11. 视频工作区规范（2026-09-08 实施依据）

本节取代上方旧附录中的视频布局建议；附录仅是 2026-09-07 历史快照，不能当作当前缺陷清单。删除确认、共享按钮和 Paywall sheet 已存在。

- 结构：导航 → 完整适配画布 → 播放与时间轴 → 四个文字工具 → 一个可滚动参数容器 → 安全区摘要与“下一步”。工具是会话状态，不能复制 ProcessingOptions、创建播放器或重置播放头。
- 尺寸：页面边距 20，紧凑间距 8，面板内边距 16，面板圆角 16，媒体圆角 20。工具图标 18，触摸至少 44。画布按实际可用高度分配，源视频始终 aspect-fit；常规字号工具切换时画布高度不变。无障碍字号需提供更大的参数区。
- 字体与色彩：复用动态字体和 AppPalette；橙色用于当前工具和主动作，工具同时提供 VoiceOver 选中语义。禁止用缩小文本适配整个页面。
- 参数：只展示当前工具，声音说明仅在变音时出现。对象/范围读写同一配置，猫狗、自定义组合、ASCII 颜色和条件贴纸必须可达。全画面隐藏编辑覆盖层但不删除轨道。
- 手动区域：默认固定位置、整段视频，不自动跟随；开启随时间调整后才产生运动记录，记录间线性移动。修改生效时段不生成位置记录。模式切换采用当前矩形并可撤销；一次手势只入栈一次，历史上限 40 次，仅会话内存。
- 全屏：复用主编辑器的区域工具、时间范围、位置模式与撤销源；编辑入口不依赖先打开手动面板。当前工程方向支持不扩展。
- 删除：工具面板垃圾桶删除，画布空白取消选中，角点双向箭头表示缩放；整轨删除须有确认或撤销。
- 背景模式：当前合成器先合并自动与手动区域再反转，因此手动框表示保留原画面的区域，必须明确说明。
- 导出：编辑页“下一步”，确认页“开始处理”；本次摘要用真实素材时长与权益上限的较小值，不把 10 秒视频说成处理 30 秒。

阶段验收以开发计划 A–F 为准。本节是设计契约，不能以规范写入代替代码、截图或真机验收。

### 2026-09-09：按用户反馈收紧视频编辑密度

本条覆盖第 11 节视频工作区的初始尺寸建议：编辑页水平边距 12，参数内边距 12，媒体与参数容器圆角 10，工具底圆角 8；工具仍有至少 44pt 热区。全宽主按钮沿用共享规格，不全局改变其他页面。

删除重复的人脸/人物预设行，范围选择与唯一一组人物/人脸/猫狗选择保留。画布高度取素材完整适配高度与可用高度 34% 的较小值，无障碍字号使用 25%；切换工具保持高度不变。播放区垂直间距 4，底部摘要和主操作间距 4。

拖动缩略时间轴或进度条必须在拖动过程中请求对应帧；连续请求采用单个在途 seek 与最新待处理目标，不不断取消尚未完成的请求。手动覆盖框跟随实际完成的寻帧时间，避免先移动框、后更新视频。预览每次请求帧重新检测，不能复用导出的隔帧缓存；导出采样策略保持原样。
