# Folio iOS 体验规格：沉静的分量感（Quiet Gravity）

> 版本：1.0
> 日期：2026-03-19
> 状态：设计完成，待实现

---

## 一、设计哲学

**Folio 应该让你感觉在翻阅一本亲手装订的私人杂志，而不是在刷一个 App。**

四个核心原则：

| 原则 | 含义 | 反面 |
|------|------|------|
| **重力感（Gravity）** | 元素有重量，降落而非弹跳，抵达而非弹出 | 不做 bouncy spring、不做 pop-in |
| **墨迹感（Ink）** | 内容像被印上去的，庄重地呈现 | 不做淡入淡出、不做滑入 |
| **静默力量（Still Power）** | 90% 时间完全静止，运动即叙事 | 不做 idle 动画、不做脉冲闪烁 |
| **触感呼应（Touch Echo）** | 每次触碰以恰好对等的力度回应 | 不做过度 haptic、不做无意义震动 |

---

## 二、动画基础设施

### 2.1 动画常量

新建文件 `ios/Folio/Presentation/Components/Motion.swift`：

```
enum Motion {
    // 主曲线：沉稳降落感，几乎无回弹
    static let settle = Animation.spring(duration: 0.4, bounce: 0.05)

    // 快速响应：按钮反馈、状态切换
    static let quick = Animation.spring(duration: 0.25, bounce: 0.0)

    // 墨迹呈现：内容显现
    static let ink = Animation.easeOut(duration: 0.15)

    // 退场：元素离开
    static let exit = Animation.easeIn(duration: 0.2)

    // 缓慢推进：进度条、处理中状态
    static let slow = Animation.linear(duration: 2.0)

    // 时长常量
    enum Duration {
        static let instant: Double = 0.1     // 状态切换
        static let fast: Double = 0.2        // 按钮反馈
        static let normal: Double = 0.35     // 标准过渡
        static let slow: Double = 0.5        // 内容呈现
        static let glacial: Double = 2.0     // 进度推进
    }
}
```

### 2.2 使用规则

| 场景 | 动画 | 理由 |
|------|------|------|
| 元素进入画面 | `Motion.settle` | 有重量地降落到位 |
| 元素离开画面 | `Motion.exit` | 安静地退场 |
| 内容首次显现 | `Motion.ink` | 快速"着墨" |
| 按钮按下/释放 | `Motion.quick` | 即时物理反馈 |
| 状态数值变化 | `Motion.quick` | 数字/进度平滑过渡 |
| 处理中进度 | `Motion.slow` | 缓慢、持续、安静 |

---

## 三、触觉系统

### 3.1 触觉映射

新建文件 `ios/Folio/Presentation/Components/Haptics.swift`：

使用 SwiftUI 原生 `.sensoryFeedback()` 修饰符，不使用 UIKit。

| 操作 | 触觉类型 | 物理隐喻 |
|------|----------|----------|
| 收藏成功（URL/内容保存） | `.success` | 纸片放到桌上 |
| 切换收藏/取消收藏 | `.selection` | 精密开关拨动 |
| 删除确认按钮 | `.impact(.medium)` | 合上一本书 |
| 滑动到达删除阈值 | `.impact(.light)` | 指尖触到边缘 |
| 滑动到达收藏阈值 | `.impact(.light)` | 同上 |
| 长按触发菜单 | `.impact(.rigid)` | 按下实体按钮 |
| 下拉刷新触发 | `.impact(.light)` | 轻触 |
| 复制链接成功 | `.success` | 确认 |
| 操作失败/配额超限 | `.error` | 阻止 |
| Toast 出现 | 无 | 安静呈现，不打断 |

### 3.2 不使用触觉的场景

- 页面导航（push/pop）— 系统已处理
- 滚动 — 自然物理，不需要额外反馈
- 搜索输入 — 键盘已有触觉
- Toast 自动消失 — 离开应该是无声的

---

## 四、加载与状态系统

### 4.1 骨架屏组件

新建文件 `ios/Folio/Presentation/Components/ShimmerView.swift`：

骨架屏用于文章卡片的占位态。不是闪烁的 shimmer，是**静态的灰色块 + 极缓慢的明暗呼吸**。

视觉规格：
- 背景色：`Color.folio.separator`（极浅灰）
- 呼吸动画：透明度在 `0.4 ↔ 0.7` 之间，周期 `2.0 秒`，使用 `Animation.easeInOut(duration: 1.0).repeatForever(autoreverses: true)`
- 形状：与实际内容对应的圆角矩形
  - 标题占位：高 14pt，宽 70%，圆角 3pt
  - 摘要占位：高 12pt，宽 90%，圆角 3pt（标题下方 8pt）
  - 元信息占位：高 10pt，宽 40%，圆角 3pt（摘要下方 8pt）

使用场景：
- 文章状态为 `.pending` 且 `markdownContent == nil` 时显示骨架屏替代正常卡片内容
- 不用于已有标题的文章（即使正在处理中）

### 4.2 处理中状态

文章状态为 `.processing` 时的卡片表现：

- 保留正常卡片布局（标题、来源等正常显示）
- 底部增加一条极细的进度线：
  - 高度：`1.5pt`
  - 颜色：`Color.folio.accent.opacity(0.4)`
  - 动画：宽度从 `0%` 到 `100%` 线性推进，周期 `3.0 秒`，循环
  - 圆角：`0.75pt`
- 移除当前的 `circle.dashed` + `symbolEffect` 处理中图标
- 不使用任何闪烁或脉动效果

### 4.3 状态转换动画

文章从 `processing → ready` 时：
- 进度线宽度快速推进到 100%（`Motion.quick`）
- 然后进度线透明度降为 0（`Motion.exit`）
- 同时触发 `.sensoryFeedback(.success)`
- 卡片内容（摘要、分类等新出现的信息）使用 `Motion.ink` 透明度从 0 到 1

文章从 `processing → failed` 时：
- 进度线变为 `Color.folio.error.opacity(0.4)`
- 然后淡出
- 触发 `.sensoryFeedback(.error)`

---

## 五、首页（HomeView）

### 5.1 文章卡片视觉层次

重新定义 ArticleCardView 的信息层级，拉开三级权重差：

**第一级：标题**
- 未读文章：`Typography.listTitle`（.headline, semibold）+ `Color.folio.textPrimary`
- 已读文章：`.fontWeight(.regular)` + `Color.folio.textSecondary`
- 这是最关键的改动——**用字重区分已读/未读**，比蓝色小点更有效
- 保留蓝色未读圆点作为辅助指示

**第二级：摘要**
- 字体：`Typography.body`（.subheadline）
- 颜色：`Color.folio.textTertiary`（比当前的 `textSecondary` 再退一级）
- 行数：最多 2 行
- 与标题间距：`Spacing.xxs`（4pt）

**第三级：元信息行**
- 字体：`Typography.caption`（.footnote）
- 颜色：`Color.folio.textTertiary.opacity(0.8)`（最安静的一层）
- 内容顺序：来源图标 → 来源名 → · → 分类 → · → 时间
- 右侧：状态指示 + 收藏心
- 与摘要间距：`Spacing.xs`（8pt）

**整体卡片：**
- 上下内边距：`Spacing.sm`（12pt）— 保持现有
- 列表行之间的分割线：保留 `Color.folio.separator`
- 不加阴影、不加卡片背景——保持列表的扁平纸面感

### 5.2 未读指示器增强

当前 8pt 蓝色圆点保留，但调整：
- 大小不变（8pt）
- 添加极微弱的光晕：`.shadow(color: Color.folio.unread.opacity(0.3), radius: 2, x: 0, y: 0)`
- 配合标题字重变化，未读文章在视觉上"更重"

### 5.3 列表项过渡

**新文章进入列表：**
- 初始状态：`opacity: 0`, `offset.y: 6pt`
- 最终状态：`opacity: 1`, `offset.y: 0`
- 动画：`Motion.settle`
- 仅对新增项生效，非首次加载

**文章被删除：**
- 使用 `.transition(.asymmetric(insertion: .identity, removal: .opacity.combined(with: .move(edge: .trailing))))`
- 动画：`Motion.exit`
- 删除后列表自然收拢（系统默认行为）

**文章状态变化（如 processing → ready）：**
- 使用 `withAnimation(Motion.ink)` 包裹状态更新
- 新出现的摘要文本从 `opacity: 0` 过渡到 `opacity: 1`

### 5.4 收藏切换动画

左滑收藏时的心形图标动画：
- 收藏（空心 → 实心）：
  - 图标 scale 从 `1.0 → 1.3 → 1.0`，使用 `Motion.settle`
  - 同时颜色从 `.gray` 过渡到 `.pink`
  - 触发 `.sensoryFeedback(.selection)`
- 取消收藏（实心 → 空心）：
  - 无 scale 动画，仅颜色过渡
  - 触发 `.sensoryFeedback(.selection)`

Context menu 中的收藏按钮：同样的触觉，无 scale 动画（菜单内不适合）。

### 5.5 下拉刷新

保持系统默认 `.refreshable` 行为，不自定义。原因：
- 系统控件与平台行为一致
- 用户已有肌肉记忆
- 自定义下拉刷新容易做出"不自然"的感觉

刷新触发时添加 `.sensoryFeedback(.impact(.light))`。

### 5.6 输入栏交互增强

**发送按钮按压反馈：**
- 按下时：scale 缩至 `0.85`，使用 `Motion.quick`
- 释放时：scale 回到 `1.0`，使用 `Motion.settle`
- 使用 `.buttonStyle` 自定义实现

**发送成功后：**
- 文本清空（瞬间，不需要动画）
- 键盘收起
- 底部 toast 浮起确认

**发送按钮出现/消失：**
- 保持当前 `.scale.combined(with: .opacity)` 过渡
- 动画改为 `Motion.settle`（当前是 `easeInOut(0.15)`，改为更有质感的 spring）

### 5.7 空状态

**进入动画：**
- 图标和文字作为整体：
  - 初始状态：`opacity: 0`, `offset.y: 12pt`
  - 最终状态：`opacity: 1`, `offset.y: 0`
  - 动画：`Motion.settle`，延迟 `0.1 秒`
- 不做逐元素入场，不做弹跳，一个整体安静地"沉"到位

**剪贴板检测到 URL 时：**
- "粘贴链接试试" 按钮出现：`Motion.ink`（快速着墨）
- 触发 `.sensoryFeedback(.selection)`

### 5.8 分组 Section Header

当前的日期分组标题（"今天"、"昨天"等）：
- 保持现有样式不变
- 不加入场动画——它们是背景信息，应该"一直在那里"

---

## 六、搜索交互

### 6.1 搜索结果出现

输入文字后搜索结果的呈现：
- 结果列表整体：`opacity: 0 → 1`，使用 `Motion.ink`
- 不做逐条入场动画——搜索结果应该"立刻在那里"，像翻到了书的索引页
- 搜索结果的关键词高亮保持现有实现

### 6.2 搜索空状态

- 进入动画同首页空状态：整体 `opacity + offset.y`，`Motion.settle`
- AI 问答按钮出现：`Motion.ink`
- AI 回答展开：使用 `Motion.settle`（替换当前的 `withAnimation`）

### 6.3 搜索 ↔ 列表切换

- 搜索激活时（`isSearching` 变为 true）：列表淡出 `Motion.exit`，搜索结果淡入 `Motion.ink`
- 搜索清空时：搜索结果淡出 `Motion.exit`，列表淡入 `Motion.ink`
- 使用 `.transition(.opacity)` + `withAnimation(Motion.quick)`

---

## 七、阅读页（ReaderView）

### 7.1 进入动画：墨迹呈现

标准 iOS NavigationStack push 动画保持不变（页面从右滑入）。在页面内容上叠加"着墨"效果：

**时间线：**
1. `0ms`：页面 push 开始，内容已在但 `opacity: 0`
2. `150ms`：标题"着墨"——`opacity: 0.3 → 1.0`，`Motion.ink`
3. `250ms`：元信息区域着墨——同上，延迟 100ms
4. `350ms`：正文内容着墨——同上，再延迟 100ms

实现方式：使用 `.task` 触发状态变量，三个独立的 opacity 状态，通过延迟控制序列。

总时长 350ms，push 动画本身约 300ms，所以着墨在 push 完成后几乎立刻结束。用户不会感觉"在等"，但会感觉内容被"庄重地呈现"。

### 7.2 排版呼吸感

调整阅读页排版参数，增加"空气"：

**标题区域：**
- 标题上方留白：从当前值增加到 `40pt`
- 标题下方到元信息：`24pt`（如果当前更小则调整）
- 标题字体保持不变（NotoSerifSC-Bold 或用户偏好字体）

**元信息区域：**
- 元信息块下方到正文分隔：`32pt`
- 分隔线颜色：`Color.folio.separator`
- 分隔线上下各 `16pt` 呼吸空间

**正文：**
- 段间距：增加到 `1.0em`（当前行高 1.7 保持，段落之间额外加空）
- 引用块左边距：从默认增加到 `20pt`
- 引用块左侧竖线：宽 `2.5pt`，颜色 `Color.folio.accent.opacity(0.3)`
- 代码块上下外边距：各 `16pt`
- 图片上下外边距：各 `20pt`

**整体：**
- 正文左右边距：保持 `screenPadding`（16pt）
- 底部留白：`80pt`（让最后一段不贴着屏幕底部）

### 7.3 阅读进度条

顶部导航栏下方增加极细的阅读进度线：

- 高度：`1.5pt`
- 颜色：`Color.folio.accent.opacity(0.3)`
- 位置：紧贴导航栏底部，`zIndex` 在内容之上
- 宽度：随滚动进度从 `0%` 到 `100%`，绑定 `ScrollView` 的 `contentOffset`
- 动画：`Motion.quick`（跟随滚动平滑更新）
- 滚动停止后不消失，始终可见
- 到达底部时宽度 100%，颜色微微加深到 `opacity(0.5)`

### 7.4 AI 摘要展开

当前折叠/展开行为保持，动画替换：

- 展开：`Motion.settle`（有重力的展开，不是弹簧）
- chevron 旋转：`rotationEffect` 从 0° 到 180°，使用 `Motion.quick`
- 展开内容出现：`opacity: 0 → 1` + `offset.y: -4 → 0`，使用 `Motion.ink`
- 折叠：`Motion.exit`

### 7.5 返回手势

保持系统默认的边缘左滑返回，不自定义。

返回时触发阅读进度保存（已有逻辑），不增加额外动画。

---

## 八、Toast 系统重设计

### 8.1 位置变更

从顶部改为**底部浮起**，位于输入栏上方。理由：
- 操作在底部发生（输入栏、滑动），反馈应出现在操作附近
- 不遮挡导航栏标题
- 符合 iOS 系统趋势（系统 toast 越来越多在底部）

### 8.2 视觉样式

```
位置：距底部安全区 + 输入栏高度 + 8pt
宽度：自适应内容，最大不超过屏幕宽度 - 32pt
高度：自适应，内边距 horizontal 16pt, vertical 10pt
背景：.ultraThinMaterial（毛玻璃）
圆角：CornerRadius.large（12pt）
阴影：.shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 2)
图标：左侧，16pt，Color.folio.textPrimary
文字：Typography.body，Color.folio.textPrimary
```

### 8.3 动画

**入场：**
- 初始状态：`opacity: 0`, `offset.y: 8pt`, `scale: 0.96`
- 最终状态：`opacity: 1`, `offset.y: 0`, `scale: 1.0`
- 动画：`Motion.settle`
- 不触发 haptic（toast 是信息，不是操作反馈；haptic 在操作本身触发）

**停留：**
- 默认 2.5 秒（从当前 2 秒微增，给长文案更多阅读时间）
- 点击立即消失

**退场：**
- `opacity: 1 → 0`, `offset.y: 0 → 4pt`
- 动画：`Motion.exit`

---

## 九、导航过渡

### 9.1 页面 Push/Pop

保持系统默认 NavigationStack 动画，不自定义。原因：
- 系统动画已经过完美调优
- 自定义转场容易破坏手势返回
- 用户期望标准 iOS 行为

### 9.2 Sheet 呈现

当前的 ShareSheet 保持系统默认。

未来如果增加自定义 sheet（如标签编辑），使用：
- `.presentationDetents([.medium])` 半屏
- `.presentationDragIndicator(.visible)` 顶部拖拽条
- 不自定义 sheet 动画

### 9.3 Alert / ConfirmationDialog

保持系统默认，不自定义。

删除确认 alert 出现时触发 `.sensoryFeedback(.warning)`——提醒用户这是破坏性操作。

---

## 十、设置页

设置页是低频页面，不需要花哨交互。保持当前实现，仅添加：

- 退出登录按钮点击后增加 `.sensoryFeedback(.impact(.medium))` 确认感
- 订阅状态行的本月用量数字使用 `.contentTransition(.numericText)` — 刷新时数字平滑过渡

---

## 十一、Share Extension

Share Extension 受 120MB 内存限制，保持极简：

- 成功提示保持当前实现
- 添加 haptic：保存成功时 `.sensoryFeedback(.success)`
- 不增加额外动画（内存敏感）

---

## 十二、新增/修改文件清单

### 新建文件

| 文件 | 用途 |
|------|------|
| `ios/Folio/Presentation/Components/Motion.swift` | 动画常量 |
| `ios/Folio/Presentation/Components/Haptics.swift` | 触觉辅助修饰符（可选，如果 `.sensoryFeedback` 直接内联足够则不需要） |
| `ios/Folio/Presentation/Components/ShimmerView.swift` | 骨架屏组件 |
| `ios/Folio/Presentation/Components/ProcessingProgressBar.swift` | 处理中进度线组件 |
| `ios/Folio/Presentation/Components/ReadingProgressBar.swift` | 阅读进度条组件 |
| `ios/Folio/Presentation/Components/ScaleButtonStyle.swift` | 按压缩放按钮样式 |

### 修改文件

| 文件 | 改动 |
|------|------|
| `ArticleCardView.swift` | 视觉层次重构（字重区分已读/未读、摘要降灰、未读圆点光晕、处理中进度线） |
| `HomeView.swift` | 列表项过渡动画、搜索切换动画 |
| `HomeArticleRow.swift` | 收藏切换动画、haptic 反馈、删除过渡 |
| `HomeSearchResultsView.swift` | 搜索结果着墨出现、空状态动画 |
| `UnifiedInputBar.swift` | 发送按钮 ScaleButtonStyle、发送动画改为 Motion.settle |
| `EmptyStateView.swift` | 进入动画改为 settle、剪贴板按钮着墨 |
| `ReaderView.swift` | 墨迹呈现序列、排版间距调整、阅读进度条 |
| `ReaderViewModel.swift` | 滚动进度计算（如果尚无） |
| `ToastView.swift` | 位置改底部、毛玻璃背景、新动画曲线 |
| `Color+Folio.swift` | 如需调整颜色（当前预计不需要） |

---

## 十三、不做的事

明确列出不在本次范围内的改动，避免范围蔓延：

- **不改配色方案** — 当前灰色系配色符合设计哲学
- **不改字体** — Typography 系统已经成熟
- **不改导航结构** — 单 NavigationStack 架构正确
- **不加自定义转场** — 系统 push/pop 已够好
- **不加手势冲突处理** — 当前手势系统工作正常
- **不加 idle 动画** — 违反"静默力量"原则
- **不加粒子/3D/视差效果** — 违反设计哲学
- **不改数据层** — 纯表现层改动
- **不改 API/网络层** — 纯 UI 层面

---

## 十四、验收标准

### 触觉

- [ ] 收藏 URL/内容：能感受到 `.success` haptic
- [ ] 切换收藏：能感受到 `.selection` haptic
- [ ] 删除确认：能感受到 `.impact(.medium)` haptic
- [ ] 操作失败：能感受到 `.error` haptic
- [ ] 长按菜单：能感受到 `.impact(.rigid)` haptic
- [ ] 静默场景（滚动、导航、Toast 出现）：无 haptic

### 动画

- [ ] 新文章进入列表：settle 曲线降落到位，无回弹
- [ ] 文章删除：向右滑出 + 淡出
- [ ] 处理中文章：底部细线缓慢推进
- [ ] processing → ready：进度线完成 + 淡出 + 新内容着墨
- [ ] 阅读页进入：标题 → 元信息 → 正文 依次着墨（总 350ms）
- [ ] Toast：从底部浮起、毛玻璃背景、2.5 秒后退场
- [ ] 搜索结果：整体着墨出现
- [ ] 空状态：整体 settle 降落
- [ ] 发送按钮：按压缩放 0.85 → 释放回弹

### 视觉

- [ ] 未读文章标题 semibold，已读 regular
- [ ] 未读圆点有微弱光晕
- [ ] 摘要文字比标题明显更淡
- [ ] 元信息行最安静
- [ ] 阅读页标题上方有充足留白
- [ ] 阅读页段间距宽松
- [ ] 阅读进度条在导航栏下方可见

### 性能

- [ ] 列表滚动 60fps，无卡顿
- [ ] 动画不阻塞主线程
- [ ] Toast 不干扰列表交互
- [ ] 骨架屏不增加内存负担

---

## 十五、实现顺序建议

虽然最终一次性交付，但实现时建议按依赖关系排序：

1. **基础设施**：Motion.swift、ShimmerView.swift、ProcessingProgressBar.swift、ReadingProgressBar.swift、ScaleButtonStyle.swift
2. **Toast 重设计**：位置 + 样式 + 动画
3. **ArticleCardView 视觉层次**：字重 + 颜色 + 光晕 + 进度线
4. **HomeArticleRow 交互**：haptic + 收藏动画 + 删除过渡
5. **HomeView 列表过渡**：新文章入场 + 搜索切换
6. **EmptyStateView + HomeSearchResultsView**：入场动画
7. **UnifiedInputBar**：ScaleButtonStyle
8. **ReaderView 排版**：间距调整 + 进度条
9. **ReaderView 墨迹呈现**：着墨序列动画
10. **全局 haptic 扫尾**：确认所有触点都已覆盖
11. **xcodegen + 构建验证**
