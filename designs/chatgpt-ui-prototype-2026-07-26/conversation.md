# ChatGPT 会话记录：iOS UI 设计参考

- 分享链接：https://chatgpt.com/share/6a682d87-2dac-83ea-8874-0785fb6e19f4
- 本地存档日期：2026-07-28
- 可见消息节点：8
- 最终原型索引：[README.md](./README.md)

> 本文件按分享页当前可见内容导出。页面只显示了“上传文件”入口，没有提供可独立导出的原始附件；图片生成回复的早期方案因此记录资源 ID，最后一轮成稿链接到本地 PNG。界面按钮、思考耗时和复制控件等页面噪声已移除。

## 1. 用户

你先理解一下我想做的这个产品

## 2. ChatGPT

（图片生成回复）

早期图稿资源 ID（未纳入最终原型目录）：

- `00000000-2cb4-81fd-bff9-ac67282046bc`
- `00000000-d288-81f5-958e-c180f46c8fbd`
- `00000000-11b0-81f5-a34b-e569f1b77bcc`
- `00000000-1824-81f5-94b8-433ec807fff2`
- `00000000-4354-81fd-8e3f-78c6979d837b`
- `00000000-606c-81f5-9422-0d741441f3f2`
- `00000000-7fb0-81f5-b26b-1023108398e8`
- `00000000-1ddc-81fd-8aa1-20bd835232ec`
- `00000000-5938-81fd-a677-874b36ac3650`

## 3. ChatGPT

（图片生成回复）

早期图稿资源 ID（未纳入最终原型目录）：

- `00000000-4e6c-81f8-bfd3-4d17c59f10db`
- `00000000-0730-81fd-bb16-448690656132`
- `00000000-6be4-81f5-b7c4-c63c073da6ba`
- `00000000-1598-81f8-8f84-0e4995343f6f`

## 4. ChatGPT

我重新检索了 Apple 设计团队、Nielsen Norman Group、Microsoft Research/HAX、Google PAIR、Marty Cagan、Teresa Torres 的公开资料。先给出一个明确纠正：

上一版的右侧竖向“洞察 / 原文”、F·001 档案编号和纵向档案线，可以作为视觉探索，但目前没有证据证明它们能改善 Folio 的核心任务，不应该直接进入正式方案。

专家资料不会直接告诉我们“Folio 首页应该画成什么样”。它们提供的是经过研究或实践验证的设计约束；下面具体的 Folio 页面方案，是把这些约束映射到你的 PRD 后得到的设计推导，最终仍需用户测试验证。

一、专家意见的核心共识
1. 品牌应该主要出现在内容层，而不是重新发明导航

Apple 在 2026 年的 iOS 品牌设计专题中，把 App 分成两个层次：

UI 层：Tab Bar、Toolbar、导航和常规操作；

内容层：真正体现产品差异和品牌的内容、文字、颜色、图像与过渡。

Apple 明确建议：导航和常规操作尽量利用用户已经熟悉的 iOS 模式；只有在真正影响产品价值、能让内容更突出的地方，才投入成本设计自定义组件。强行让品牌覆盖系统交互，反而会增加学习成本。
Apple Developer

这对 Folio 的直接含义是：

不应该独特的地方：
Tab Bar、返回、洞察/原文切换、筛选、设置、删除

应该独特的地方：
洞察怎样呈现
证据怎样被理解
答案怎样回到来源
保存状态怎样建立信任

因此，“原生外壳 + 独特内容体验” 比“所有控件都设计得与众不同”更符合 Apple 当前的官方建议。

2. 简约不等于隐藏功能或减少视觉元素

Apple 最新的设计原则明确区分了“简约”和“极简”：把所有功能藏在一个入口里，界面可能看起来更少，但不一定更简单。真正的简单是用户不用努力就能找到需要的内容，并且立即明白：

什么最重要；

什么可以点击；

点击后会发生什么。

有时增加必要的上下文，反而会让产品更简单。
Apple Developer
+1

NN/g 对所谓 Zen Mode 的研究也指出，隐藏界面虽然减少视觉元素，却可能增加交互成本、记忆负担和注意力切换。
Nielsen Norman Group

所以 Folio 的“简约、清爽”不应该理解成：

把原文入口藏起来
只显示抽象图标
用手势代替可见按钮
去掉所有状态和说明

而应该是：

只展示当前任务需要的信息
但需要的信息必须清楚、可见、容易理解
3. 熟悉性优先于视觉新奇

Apple 将 Familiarity 作为基础设计原则：用户会把现实经验和其他软件中的约定带入产品。一个好的隐喻应帮助用户预测操作结果，而不是要求用户先学习设计师的表达。过度抽象或过度字面化的隐喻，都会带来误解。
Apple Developer

NN/g 的记忆研究进一步说明：识别比回忆容易。界面应该让功能和信息可见，而不是要求用户记住某个手势、编号或不常见的导航形式；一次性的 onboarding 也无法弥补长期隐藏的交互，页面内的上下文提示通常更有效。
Nielsen Norman Group
+1

因此，右侧竖向页签的问题不是“不够符合审美”，而是：

用户未必识别它是切换控件；

它要求用户理解“档案索引”的隐喻；

中文勉强成立，英文和 Dynamic Type 更难适配；

没有解决标准控件不能解决的问题。

Apple 的 HIG 恰好把 Segmented Control 定义为切换密切相关的子视图的控件，并强调它能让分组关系和当前选择一目了然。“洞察 / 原文”正是这一模式的典型使用场景。
Apple Developer

所以正式方案应该回到顶部的标准分段切换，而不是右侧竖向页签。

4. 好看很重要，但会掩盖可用性问题

NN/g 的“审美—可用性效应”研究指出，漂亮的界面会让用户主观上认为产品更好用，并暂时容忍一些小问题；但这也可能掩盖真正的可用性缺陷。测试时不能只听用户说“好看”“高级”，而要观察他是否实际完成了任务。
Nielsen Norman Group
+1

所以我们不能再用这类问题评价 Folio：

你觉得哪一版更高级？
这个页面是否有惊艳感？
你喜欢档案风格吗？

至少要先观察：

能否找到原文？
能否分辨洞察和原文？
能否判断内容是否已经保存？
能否从结论找到证据？
能否理解为什么 Ask 拒绝回答？

用户完成任务后，再评价清爽、可信、安静、独特等视觉感受。

二、AI 产品专家对 Folio 最重要的启示
1. 信任目标不是“让用户更信 AI”，而是让信任与能力相匹配

Google PAIR 将其称为 calibrated trust：用户既不应该无条件相信系统，也不应该因为一次失败完全不信任。产品应明确说明：

系统能够做什么；

不能做什么；

使用了哪些数据；

当前答案基于什么；

哪些信息系统并不知道。

指出预测可能出错，可能降低用户对某一次输出的信任，却有助于建立更长期、更准确的信任。
PAIR

Microsoft HAX 同样建议在初次使用时说明能力范围和质量边界；系统不确定时，应收窄服务、请求澄清或优雅拒绝，而不是强行产生完整结果。解释还需谨慎，因为解释本身可能让用户产生过度信任。
Microsoft
+3
Microsoft
+3
Microsoft
+3

这与 Folio PRD 已经确认的原则高度一致：

Ask 只能根据用户资料回答；

资料不足时拒答；

每个确定性事实必须有实际使用的证据；

来源冲突时必须展示冲突。

folio-prd

因此 Folio 的可信感不应主要依赖：

高科技渐变
AI 头像
机器人语气
复杂置信度数字
“经过深度思考”等拟人化状态

而应依赖：

来源范围清楚
引用真实可点击
原文可以核对
不知道时明确拒答
AI 派生内容和原文明确区分
错误状态可以恢复
2. 不要通过 AI 人格化获得信任

Google 在一项 2,165 人的实验中发现，语音、第一人称等拟人化线索可能提高用户对系统准确性的主观评价。这里不能简单推导为“拟人化一定不好”，但它说明：人格化可能在没有提高实际质量的情况下改变用户的信任判断。
Google Research

因此，我建议 Folio 的 Ask：

不使用机器人或人物头像；

不用“我认为”“我读了你的资料后觉得”；

不把加载状态写成“我正在思考”；

采用中性的产品语气；

让证据承担信任，而不是人格承担信任。

例如：

不建议：
我认为，解释功能可能让低质量结论看起来更确定。

建议：
你的资料表明，解释可能让低质量结论显得更加确定。[1]
三、据此修正 Folio 的正式 UI 方向

新的原则应该是：

Native Foundation, Evidence-led Identity

即：

交互遵循原生习惯，品牌来自洞察与证据体验。

不是完全回到普通模板，也不是继续创造陌生控件。

1. App Store 1.0 使用两个顶层 Tab
资料库        提问

Apple 规定 Tab Bar 用于 App 的顶层区域，而不是执行操作；标签应清楚描述各区域，并保持可见以帮助用户理解自己所处的位置。
Apple Developer

基于 Folio PRD：

资料库对应回访；

提问对应知识调用；

保存主要发生在系统 Share Extension；

Echo 不属于 1.0；

搜索不属于 1.0；

设置是低频管理，不是核心顶层任务。

folio-prd



folio-prd

所以：

设置从资料库右上角头像进入；

不放独立设置 Tab；

不提前放 Echo Tab；

不出现搜索按钮；

不放没有明确需求的全局 +；

不增加 Ask 历史作为独立区域。

2. 资料库采用“标题识别优先，洞察价值增强”

上一版把核心洞察放在最前面、标题放在下面，视觉上更像杂志，但可能降低内容识别效率。

NN/g 的研究表明，保存列表和最近访问内容的价值就在于帮助用户通过上下文完成识别，而不是要求用户准确回忆名称。列表项的高优先级信息也应放在最容易扫描的位置。
Nielsen Norman Group
+1

因此正式列表建议是：

[网站图标]  如何设计可信的 AI 产品
            example.com · 2 小时前

            可信不是解释得更多，
            而是让能力边界可见。

信息顺序：

标题：帮助用户认出自己保存的内容；

来源和时间：补足上下文；

一句洞察：证明 Folio 提供了额外价值；

处理状态：仅在未完成或异常时出现。

不再使用：

F·001；

纵向档案时间轴；

“327 条洞察”；

未读数；

每条内容的固定大卡片；

没有实际作用的证据数量统计。

这也符合 PRD 对资料库的要求：不建立文件夹树、强制分类、未读压力和阅读任务。

folio-prd

视觉辨识度可以来自更好的字号、行距、留白和洞察排版，而不是新增编号系统。

3. 内容详情使用顶部“洞察 / 原文”分段切换

页面结构：

返回               更多

如何设计可信的 AI 产品
example.com · 2 小时前

┌──────────┬──────────┐
│   洞察   │   原文   │
└──────────┴──────────┘

默认进入洞察，但原文入口在首屏直接可见。

这同时满足：

用户容易发现；

当前状态一目了然；

中文和英文都能处理；

Dynamic Type 更容易适配；

VoiceOver 可表达选择状态；

不需要 onboarding；

原文与 AI 派生内容明确区分。

PRD 也明确要求原文和 AI 派生内容不能混为一体。

folio-prd

4. 品牌重点放在“核心洞察”内容上

顶部控件保持原生，洞察内容可以更加精致：

核心洞察

可信的 AI 产品，
不是解释得更多，

而是让用户清楚系统知道什么，
也清楚它不知道什么。

但这里也不建议首版直接使用一套复杂自定义中文字体。

Apple 建议字体可以承载品牌，但必须保持功能性并支持 Dynamic Type；系统字体本身支持大量语言，也可以通过字号、字重、宽度和层级形成辨识度。
Apple Developer

首版更稳妥的方案是：

导航和正文均使用系统字体；

通过字号、行宽、字重、段距形成编辑感；

核心洞察控制在两到四行；

不为所有内容使用超大标题；

中英文和最大 Dynamic Type 均先验证；

之后再测试局部 Serif 是否真的提升阅读体验和品牌识别。

真正的视觉高级感来自排版精度，而不是字体数量。

5. 保留证据 Sheet，但取消装饰性“证据线”

点击引用 [1] 后展示半高 Sheet：

证据 1

“原文中直接支持当前观点的段落……”

如何设计可信的 AI 产品
example.com · 2 小时前

[ 在原文中查看 ]

Apple 将 Sheet 定义为处理与当前上下文紧密相关、范围有限的内容或任务；它可以在保留父页面上下文的同时提供补充信息，不适合长流程。核对一段证据正好符合这种模式。
Apple Developer

因此保留：

结论
→ 点击引用
→ 查看证据 Sheet
→ 在原文中定位

删除：

页面右侧装饰性证据线；

从正文跨越到边缘的复杂连接；

为每个来源制作档案编号；

多层 Sheet 套 Sheet。

Folio 的品牌不是“看起来像档案”，而是任何结论都可以被顺畅核对。

证据区域可以使用一套稳定的浅暖色背景，因为颜色在这里具有明确语义：

这是原始证据，不是 AI 生成内容。

6. Ask 保持文档式，而不是聊天式或杂志式

建议页面：

提问

为什么许多 AI 产品的解释功能
反而降低可信度？

回答

解释可能让低质量结论显得更加确定。[1]

更可靠的设计是说明证据、能力范围
和未知边界，而不是用更长的语言
掩盖不确定性。[2][3]

来源
1  如何设计可信的 AI 产品
2  透明度与可解释性
3  建立长期 AI 信任

保持：

问题；

简洁答案；

行内引用；

来源列表；

证据展开；

原文定位；

资料不足拒答。

不使用：

左右聊天气泡；

AI 人物头像；

“Folio 正在思考”；

没有产品依据的无限追问；

模型选择器；

装饰性的第三方来源；

没有真实含义的置信度百分比。

Google PAIR 特别提醒，数字置信度对普通用户未必有清楚含义，是否展示及如何展示都应通过用户研究验证。
PAIR

7. 保存动效只表达状态变化

不再设计“网页折叠成纸张、进入档案页脊”的长动画。

NN/g 对动效的建议是：动效应该帮助用户理解状态变化、因果关系和空间连续性；重复出现、只为展示技术或制造惊喜的动画，会延长任务时间并很快变得烦人。
Nielsen Norman Group

Share Extension 只需要：

正在保存…
      ↓
✓ 已保存
Folio 会继续处理内容

可以有：

一次很短的进度到勾选过渡；

服务端确认后的轻触觉反馈；

自动关闭前足够看清结果的停留；

VoiceOver 下保证状态被朗读。

不能为了品牌动画推迟用户回到原 App。

这直接服务 PRD 定义的捕获目标：用户只想可靠提交，然后立即返回当前任务。只有服务端确认接收后，才可以显示“已保存”。

folio-prd



folio-prd

8. 谨慎使用 Liquid Glass 和材质

Apple 当前建议把 Liquid Glass 主要用于导航和控制层，不要把它铺进内容层，否则容易造成复杂和混乱的层级。
Apple Developer

NN/g 对 iOS 26 的独立评估则更加谨慎，指出过度透明、不断变化的控件、缩小的点击区域和无意义动效可能降低可读性、可预测性与发现性。
Nielsen Norman Group
+2
Nielsen Norman Group
+2

两者虽然立场不同，但对 Folio 可以得到一个保守而稳妥的决策：

让系统自动处理 Tab Bar、Toolbar 和 Sheet 的材质；

正文、洞察、证据和列表使用稳定、不透明、高对比的内容背景；

不手工给每条内容增加玻璃卡片；

不把文字叠在复杂图片或透明背景上；

不为了跟随视觉趋势牺牲阅读。

四、Folio 真正可持续的品牌辨识度

经过这次研究，我建议把 Folio 的品牌建立在四个体验信号上，而不是陌生控件上。

1. 洞察排版

每篇内容只突出一条真正有信息增量的核心洞察，文字层级和留白经过精细设计。

2. 证据语义

所有引用使用一致编号、证据底色和来源结构，用户逐渐形成：

看到这个样式，就知道可以核对原文。

3. 真实状态文案
正在保存
已保存
尚未保存
正文已保存，洞察暂不可用
资料不足，无法可靠回答

这些文案本身就是 Folio 的可信品牌。

4. 连续的核对路径
洞察 / 答案
→ 证据
→ 原文定位
→ 返回原位置

这条路径做得极其流畅，比任何档案编号或视觉纹理都更有产品辨识度。

Apple 也强调，精致感来自可靠、流畅、响应及时、经过反复迭代的细节；粗糙的软件会让用户进一步怀疑其输出质量。
Apple Developer

五、不能再直接让图像模型决定产品

Marty Cagan 将产品风险分为：

用户是否愿意使用；

用户是否能用明白；

工程是否可实现；

商业是否成立。

产品设计师主要负责的不是“把界面做漂亮”，而是降低完整体验中的可用性风险。
Silicon Valley Product Group

他也强调，原型的首要目的不是展示和沟通，而是测试风险；不同风险需要不同程度的视觉、交互和数据真实性。只做出一张漂亮高保真图而不测试，容易把视觉产物误认为已经找到正确方案。
Silicon Valley Product Group
+2
Silicon Valley Product Group
+2

Teresa Torres 的建议是同时比较多个方案，提前确定评价标准，并把脑中的假设显式写出来，而不是爱上第一个解决方案。
Product Talk

因此下一轮应该比较的不是：

普通版
vs
更夸张、更惊艳版

而是两个都符合 iOS 习惯、但内容表达不同的方案：

方案 A：内容识别优先

标题和来源最突出；

洞察作为第二层；

更适合快速浏览大量收藏。

方案 B：洞察价值优先

标题仍然可识别；

洞察字号和权重更强；

更突出 Folio 与普通收藏工具的差异。

二者都使用：

两个标准 Tab；

顶部分段控件；

标准 Sheet；

相同的状态和引用规则。

这样测试的是真正的产品问题：

用户回到资料库时，首先需要认出文章，还是首先需要看到洞察？

而不是测试用户是否喜欢一个奇特控件。

六、建议立即进行的用户验证

NN/g 在 2026 年 7 月重新审阅的可用性测试指南中强调：即使经验丰富的设计师，也无法脱离真实用户观察直接设计出足够好的体验。测试应让代表性用户完成真实任务，研究者观察行为，而不是让用户对设计发表抽象意见。单一用户群的一轮定性测试通常可先从约 5 人开始。
Nielsen Norman Group
+2
Nielsen Norman Group
+2

结合 PRD 已规划的 12—15 名核心用户，建议做两轮，每轮 5 人，保留剩余样本验证修改后的方案。

folio-prd

第一轮测试五项真实任务：

保存判断
从 Safari 分享文章后，让用户说明当前是否已经安全保存。

内容找回
给出“昨天从某网站保存的一篇 AI 文章”，让用户在资料库中找到它。

原文发现
打开洞察页，不提供提示，让用户找到完整原文。

证据核对
让用户判断某条观点来自哪里，并返回原文对应位置。

拒答理解
展示“资料不足，无法可靠回答”，询问用户发生了什么、下一步可以做什么。

记录：

是否完成；

第一次点击是否正确；

完成路径；

犹豫点和误点击；

完成时间；

用户对当前状态的复述；

是否能区分原文和 AI 内容。

任务完成后，再让用户评价：

清楚
可信
安静
清爽
有辨识度
愿意长期使用

不能把“很好看”当成任务成功的替代指标，因为漂亮界面可能让用户忽略自己刚刚遇到的问题。
Nielsen Norman Group
+1

最终修正后的设计判断

Folio 不应该在“普通”和“奇特”之间二选一。

正确方向是：

让导航、控件和操作保持熟悉；让洞察、证据、状态反馈和核对路径形成独有体验。

正式方案应当：

使用标准的双 Tab；

使用顶部“洞察 / 原文”分段控件；

资料库以标题和来源支持识别，以洞察体现价值；

Ask 采用文档式、有来源、会拒答的结构；

证据使用标准 Sheet，并能准确定位原文；

不使用人格化 AI、档案编号、陌生竖向导航和装饰性时间轴；

通过排版、文案、证据语义和精致交互建立品牌；

在下一轮高保真之前，先用可交互原型完成真实用户测试。

这套方案可能没有一张概念图那么“炫”，但更有机会让用户使用后产生真正有价值的感受：

它看起来很安静；每一步都容易理解；它不炫耀 AI，但我相信它保存了什么、依据了什么，也知道它什么时候不知道。

<details>
<summary>本轮外部链接（18）</summary>

- [Apple Developer](https://developer.apple.com/videos/play/wwdc2026/251/?time=449)
- [Apple Developer +1](https://developer.apple.com/videos/play/wwdc2026/250/)
- [Nielsen Norman Group](https://www.nngroup.com/articles/zen-mode/?lm=checkboxes-design-guidelines&pt=article&utm_source=chatgpt.com)
- [Nielsen Norman Group +1](https://www.nngroup.com/articles/recognition-and-recall/)
- [Apple Developer](https://developer.apple.com/jp/design/human-interface-guidelines/segmented-controls?utm_source=chatgpt.com)
- [Nielsen Norman Group +1](https://www.nngroup.com/articles/aesthetic-usability-effect/)
- [PAIR](https://pair.withgoogle.com/guidebook-v2/chapter/explainability-trust/?utm_source=chatgpt.com)
- [Microsoft +3 Microsoft +3 Microsoft +3](https://www.microsoft.com/en-us/haxtoolkit/guideline/make-clear-what-the-system-can-do/?utm_source=chatgpt.com)
- [Google Research](https://research.google/pubs/believing-anthropomorphism-examining-the-role-of-anthropomorphic-cues-on-user-trust-in-large-language-models/?utm_source=chatgpt.com)
- [Apple Developer](https://developer.apple.com/cn/design/human-interface-guidelines/tab-bars?utm_source=chatgpt.com)
- [Apple Developer](https://developer.apple.com/jp/design/human-interface-guidelines/sheets?utm_source=chatgpt.com)
- [Nielsen Norman Group](https://www.nngroup.com/articles/animation-usability/?lm=animation-purpose-ux&pt=article&utm_source=chatgpt.com)
- [Apple Developer](https://developer.apple.com/design/human-interface-guidelines/materials?utm_source=chatgpt.com)
- [Nielsen Norman Group +2 Nielsen Norman Group +2](https://www.nngroup.com/articles/liquid-glass/)
- [Silicon Valley Product Group](https://www.svpg.com/four-big-risks/)
- [Silicon Valley Product Group +2 Silicon Valley Product Group +2](https://www.svpg.com/the-purpose-of-prototypes/)
- [Product Talk](https://www.producttalk.org/no-single-right-way-3/)
- [Nielsen Norman Group +2 Nielsen Norman Group +2](https://www.nngroup.com/articles/usability-testing-101/)

</details>

## 5. 用户

你这些是交互体验上的，我们的产品除了交互，还有视觉效果需要考虑，所以 UI 和配置等视觉上的设计应该怎么设计？也看看专家的意见？

## 6. ChatGPT

上面四组界面分别适合观察：

Apple Books：长文本阅读、排版和内容沉浸。

Things：间距、对齐、克制用色和细节完成度。

Bear：品牌色、主题和工具界面的平衡。

Matter：文章列表、阅读页和信息密度。

Folio 不应直接复制其中任何一个。更合适的组合是：

Apple Books 的阅读质感 + Things 的精确克制 + Bear 的品牌辨识度，再减少 Matter 的信息密度。

一、视觉效果不是交互完成后的“美化”

Apple 在 2026 年的设计原则中明确把 Craft 视为优秀产品的核心：字体、视觉、动画、文案、性能和细节完成度都会向用户传达产品质量。NN/g 的“审美—可用性效应”也表明，视觉上更有吸引力的界面，通常会被用户感知为更易用，用户也更愿意容忍轻微问题；但这种效应也可能掩盖真实的可用性缺陷。也就是说，视觉设计确实直接影响价值感、信任和使用意愿，但不能用来掩盖体验问题。
Apple Developer
+2
Apple Developer
+2

因此 Folio 需要同时达到两层目标：

用户一眼能看懂、能使用；

用户一眼能感受到这是一个认真、可信、有品质的产品。

二、专家对于品牌视觉的核心建议
1. 原生 UI 层，定制内容层

Apple 在 WWDC26 的品牌设计专题中，把 iOS App 分为：

UI Layer：Tab Bar、Toolbar、返回、菜单、Sheet、常规控件；

Content Layer：文字、内容、图像、数据表达、品牌色和内容过渡。

Apple 的建议是：常规操作尽量沿用用户熟悉的 iOS 组件，把真正的品牌表达放到内容层。高度定制导航和普通按钮，往往不会强化品牌，反而可能让产品显得不原生或过时。
Apple Developer
+1

这意味着 Folio 不需要通过这些方式获得特色：

特殊形状的 Tab Bar；

右侧竖排导航；

自创返回按钮；

每个按钮都做成独特形状；

所有页面都铺满品牌色。

Folio 应该在这些地方建立视觉辨识度：

核心洞察的排版；

引用编号的表现；

证据的视觉语义；

洞察与原文之间的关系；

Ask 答案的组织方式；

保存成功的状态反馈。

这也正好符合 Folio 的产品内核：价值单位不是文章数量，而是一条有出处、能被记住和再次调用的洞察。

folio-prd

2. 好视觉的基础不是装饰，而是网格、层级、用色和一致性

NN/g 对优秀视觉设计的总结是：

元素和字体对齐到网格；

建立清晰的视觉层级；

有目的地使用颜色；

所有设计决定保持一致。

对于列表页，NN/g 还建议先确定信息优先级，再通过位置、字号、字重、颜色和留白形成稳定的“微型信息架构”；不同列表项的相同信息应出现在相同位置，方便用户扫描和比较。
Nielsen Norman Group
+1

因此，Folio 的高级感不会来自“多画一些东西”，而会来自：

所有文字基线准确；

页面左右边距一致；

列表项内部结构稳定；

一级、二级、三级信息差异明显；

分割线、图标、间距和状态样式高度统一；

同一种颜色永远表达同一种含义。

三、我建议的最终视觉方向
Evidence Editorial｜可信编辑感

视觉关键词：

安静
清爽
准确
温暖
可信
内容优先

它不是：

复古纸张或档案馆拟物；

极简到什么都看不到；

蓝紫渐变的 AI 产品；

卡片化效率 Dashboard；

全部照搬系统设置页。

可以采用这样的视觉比例：

75% 原生 iOS 基础
20% 编辑式内容排版
5% Folio 证据视觉语言

Folio PRD 已经将产品气质定义为安静、克制、原生，通过层级和留白表达重点，不依赖卡片数量、红点和任务压力。

folio-prd

四、配色系统

Apple 建议颜色承担明确意义，例如操作、选择、状态、反馈、分组和层级；同一种颜色不要在不同位置表达互相冲突的含义。系统语义色还能自动适配深色模式、提高对比度等用户设置。
Apple Developer
+1

下面是适合 Folio 的第一版候选 Token，不是 Apple 规定值，后续需要在真机和无障碍测试中调整。

Token	浅色模式	深色模式	用途
canvas	#FAF9F6	#111210	洞察和阅读内容背景
surface	#FFFFFF	#1C1C1E	Sheet、输入框、有限分组
accent	#0F5C55	#78C8BC	主操作、引用、选中状态
accentSubtle	#E7F1EE	#17312E	极轻的选中背景
evidenceSurface	#F4F0E7	#29261F	原文证据区域
primaryText	label	label	标题与正文
secondaryText	secondaryLabel	secondaryLabel	来源、时间、辅助说明
separator	separator	separator	列表和章节分隔
成功 / 警告 / 错误	系统语义色	系统语义色	状态反馈

其中候选品牌色 #0F5C55 在暖白背景上的对比度约为 7:1，可以作为初步方向，但最终仍要通过 Accessibility Inspector 和真机环境验证。Apple 对普通小字号文本建议至少达到 4.5:1，并要求深色、浅色和高对比度模式都分别检查。
Apple Developer
+1

配色使用比例

建议大致控制为：

80% 中性背景和正文
15% 轻微层级背景
5% 品牌色和状态色

品牌色主要用于：

当前 Tab；

主按钮；

可点击引用；

当前分段选择；

处理进度；

成功后的轻量确认。

不要用于：

所有章节标题；

所有网站图标；

普通说明文字；

大面积页面背景；

非交互静态标签。

否则用户会无法判断绿色究竟表示“可以点击”“已成功”还是只是品牌装饰。

五、字体与排版

Apple 把字体定义为同时承担四个任务：

易读；

信息层级；

重要性表达；

品牌和风格。

Apple 建议减少字样数量；自定义字体可以用于标题和副标题，但正文和小字号信息通常更适合系统字体。系统字体还天然支持 Dynamic Type、粗体文本和多语言。
Apple Developer
+2
Apple Developer
+2

Folio 字体策略
功能 UI

统一使用系统字体：

中文：系统中文字体；

英文：SF Pro；

数字和代码式元数据：必要时使用 SF Mono。

适用范围：

Tab；

Toolbar；

按钮；

设置；

来源；

时间；

状态；

表单。

品牌 Wordmark

Folio 英文品牌字样可以使用 New York 或定制 Serif，仅用于：

登录页；

App Store 素材；

品牌介绍；

极少量空状态。

不要在每个导航栏反复出现 Logo。Apple 也建议品牌应让位于内容，不要浪费屏幕空间持续提醒用户正在使用哪个 App。
Apple Developer

核心洞察

首版建议仍使用系统字体，通过字号、字重、行距和段落宽度形成编辑感，而不是马上引入中文自定义字体。

推荐视觉层级：

内容	Text Style	建议表现
页面大标题	.largeTitle	Bold
文章标题	.title2	Semibold
核心洞察	.title2 / .title3	Semibold，宽松行距
Ask 答案结论	.title3	Medium / Semibold
正文	.body	Regular，宽松行距
来源和时间	.subheadline	Regular
标签与引用	.caption	Medium

一张页面尽量不要超过四种明显的文字层级，否则用户会感到每段内容都在争夺注意力。

中文排版原则

不人为增加过大的中文字符间距；

核心洞察行距比普通 UI 略宽；

每段尽量控制在三到五行；

长正文用清晰的段落间距代替大量分割线；

加粗只强调结论，不整段加粗；

不使用极细字重。

Apple 明确指出，细体在小字号下会降低可读性，常规、中等、中粗和粗体更适合界面文本。
Apple Developer

六、间距和布局系统

建议以 4pt 为最小单位，以 8pt 为主要节奏：

Token	数值	用途
space.1	4	图标内部、微小差距
space.2	8	图标与文字
space.3	12	相邻元信息
space.4	16	列表项内部
space.5	20	iPhone 页面左右边距
space.6	24	内容模块间距
space.8	32	大章节间距
space.10	40	Hero 与下一章节
关键原则
一个页面只有一条主要对齐轴

标题、正文、来源、观点和按钮应尽量共享左侧基线。不要让：

标题从 20pt 开始；

正文从 24pt 开始；

卡片从 16pt 开始；

引用又从 28pt 开始。

这种细微错位是很多 AI 设计稿显得廉价的原因。

用留白隔离重要内容

NN/g 建议通过字号、字重、颜色和周围留白共同强调高优先级信息，但也提醒不要让每个项目都拥有不同视觉处理，否则整个页面会失去扫描路径。
Nielsen Norman Group

因此核心洞察可以拥有更大留白，但普通关键观点不要每一条都做成 Card。

七、表面、圆角、阴影与材质

Apple 将 Material 定义为建立前景、背景和层级的工具，而不是装饰。Liquid Glass 更适合导航、控制和浮动前景；文本密集区域应优先保证稳定背景和可读性。
Apple Developer
+1

Folio 的使用规则
使用系统材质

用于：

Tab Bar；

Toolbar；

底部 Ask 输入栏；

Sheet；

浮动菜单。

这些部分尽量让系统自动适配当前 iOS 版本。

使用不透明内容背景

用于：

资料库列表；

核心洞察；

关键观点；

长正文；

来源列表；

证据文字。

不要把正文放在透明玻璃上。

圆角

建议：

元素	建议
普通按钮	系统默认或约 10–12pt
输入框	14–16pt
证据区域	12–14pt
Sheet	系统默认
列表项	不加容器圆角

避免所有元素统一使用 20–28pt 大圆角。圆角越多，内容越容易变成一堆相互竞争的卡片。

阴影

大部分内容区域不使用阴影。

只在以下场景允许非常轻的阴影：

悬浮 Ask 输入框；

临时浮层；

需要与滚动内容分离的控制层。

列表、洞察和证据主要通过背景层级、分割线和留白组织。

八、图标系统

Apple 建议界面图标简单、容易识别、与所表达的对象或操作直接相关，并保持尺寸、线宽、细节程度和视觉重量一致。SF Symbols 能自动适配字体粗细、字号、深色模式和本地化，是普通操作的优先选择。
Apple Developer
+1

Folio 建议

普通操作使用 SF Symbols：

资料库：books.vertical 或更轻量的集合图标；

提问：text.bubble；

筛选：line.3.horizontal.decrease；

来源：link；

原文：doc.text；

删除：trash；

重试：arrow.clockwise。

视觉样式：

默认单色；

选中状态使用 Fill；

不给每个图标加彩色圆形背景；

不用 Emoji；

不把 sparkles 作为所有 AI 功能的统一标志。

自定义图标只保留两个：

Folio App Icon；

必要时设计一个专属“证据”符号。

其他普通操作没有必要重新绘制。

九、图片和插画

NN/g 对移动端图片的建议是：图片应当带来信息价值，纯装饰图片会占用屏幕、增加加载和滚动成本。
Nielsen Norman Group

资料库不要默认展示大封面图

外部网页封面通常会出现：

视觉风格不统一；

清晰度不一致；

广告式文字；

不相关配图；

过强颜色；

大量人像和 Logo。

这会直接破坏 Folio 的安静感。

资料库建议只展示：

24–28pt 网站图标；

标题；

来源；

一句话洞察；

处理状态。

正文中的原始图片仍然保留。

品牌插画只出现在少数位置

可以设计一套非常轻的线性插画，主题是：

内容进入
→ 被提炼
→ 连接证据
→ 在需要时被调用

只用于：

首次登录；

空资料库；

第一次 Ask；

App Store 截图。

不在每个页面反复展示。

十、Folio 的三个视觉签名

视觉辨识度不应该平均撒在所有页面，而应该集中在三个核心时刻。

1. Insight Hero｜核心洞察

详情页顶部：

核心洞察

可信的 AI 产品，
不是解释得更多，

而是让用户清楚系统知道什么，
也清楚它不知道什么。

视觉规则：

不放进厚重卡片；

左侧可以有一条 2pt 深墨绿标识线；

使用比正文高一级的字号；

上下留白明显；

最多四到六行；

只突出一个结论。

这条细线不是导航，而是固定表达：

这是 Folio 提炼出的核心洞察。

原文和 AI 派生内容必须明确区分，这一点也是 PRD 的明确要求。

folio-prd

2. Evidence Surface｜证据底色

所有原文证据统一使用浅暖纸色：

证据 1

“这里显示原文中直接支持当前观点的段落……”

来源标题
作者 · 网站 · 发布时间

形成稳定语义：

白色或暖白：Folio 内容和界面；

浅纸色：原始证据；

深墨绿编号：可以打开和核对；

红色或橙色：异常状态。

久而久之，用户看到这一背景，就知道：

这不是 AI 的解释，而是原始依据。

3. Citation Mark｜引用标记

所有洞察和 Ask 统一使用同一种引用视觉：

……让能力边界变得可见。 [1]

建议：

13–14pt；

深墨绿；

轻微底色或描边；

至少 44pt 的实际点击区域；

不用细到看不清的上标；

点击后打开证据 Sheet。

这会比复杂的档案线、右侧编号和页面装饰更可持续，因为它直接连接了 Folio 最核心的产品价值：

结论 → 证据 → 原文

Ask 的每个确定性结论必须由实际参与回答的来源支撑，证据不足时拒答，来源冲突时展示冲突。

folio-prd

十一、关键页面的视觉设计
1. 登录页

建议：

暖白或系统背景；

顶部保留较多留白；

Folio Wordmark 可以使用 Serif；

中部是一句产品价值；

一张极轻的抽象插画；

底部 Apple 登录主按钮、邮箱登录次按钮；

隐私说明使用次级文字。

不要：

巨大 Logo 占半屏；

蓝紫渐变；

AI 发光球；

三到五页轮播；

十几个功能说明。

2. 资料库

每个条目建议：

[网站图标]  如何设计可信的 AI 产品
            example.com · 2 小时前
            可信不是解释得更多，而是让能力边界可见。

视觉规格候选：

网站图标：28×28pt；

标题：17pt Semibold，最多两行；

来源：13–15pt Secondary；

洞察：15–17pt Regular，最多两行；

行上下间距：14–18pt；

分割线从文字区域开始；

左右边距 20pt；

不使用外层 Card。

处理状态代替洞察所在位置：

正在提炼洞察…
正文已保存，洞察暂不可用
处理失败，可重新尝试

正常完成后不显示“已完成”徽章。

3. 洞察详情

结构：

文章标题
来源 · 时间

[ 洞察 | 原文 ]

核心洞察 Hero

关键观点
1  …………………… [1]
2  …………………… [2]
3  …………………… [3]

这条洞察有帮助吗？
有用    不准确

视觉焦点只有一个：核心洞察。

分段控件、返回、更多、反馈都保持原生和克制。

4. 原文阅读

推荐：

默认系统浅色 / 深色外观；

正文使用系统正文样式；

行距比普通 UI 宽；

页面左右 20–24pt；

顶部工具栏随滚动收起；

引用定位段落使用短暂暖色高亮；

不增加悬浮 AI 按钮；

不在正文插入推荐内容。

Apple Books 可以参考的是内容沉浸和阅读控制的克制，而不是照搬其书籍视觉。

5. Ask

视觉上采用“研究答案”，不是聊天：

你的问题

为什么许多 AI 产品的解释功能
反而降低可信度？

回答

解释可能让低质量结论显得更加确定。[1]

更可靠的设计是说明证据、能力范围和未知边界，
而不是用更长的语言掩盖不确定性。[2][3]

来源

1  如何设计可信的 AI 产品
2  透明度与可解释性
3  建立长期 AI 信任

推荐：

问题：普通正文层级；

答案结论：Title 3；

解释：Body；

引用：品牌色；

来源：紧凑列表；

输入框：底部系统材质 Capsule；

背景保持稳定，不铺渐变。

Ask 应该让“答案”成为视觉主角，不是输入框、AI Logo 或加载动画。

6. Share Extension

视觉只有三个阶段：

正在保存…
✓ 已保存
Folio 会继续处理内容
尚未保存
请联网后重试

成功时使用一个短促的 Symbol Replacement 或 Draw 动效，再配合轻触觉反馈。Apple 和 NN/g 都强调动画应表达状态变化、因果或关系，不应反复消耗用户注意力。
Apple Developer
+1

7. 设置与配置页

设置页不承担品牌展示任务，应使用系统 Form：

账号
云端空间
订阅
数据与隐私
帮助

视觉建议：

系统分组背景；

统一 SF Symbols；

品牌色只用于开关、链接和进度；

删除账号使用系统危险色；

容量进度条不要使用夸张渐变；

不在每个分组添加大卡片；

不加入装饰性插画。

设置页越熟悉，用户越容易信任涉及账号、容量和删除的操作。

十二、App Icon

Apple 将 App Icon 视为用户在主屏幕、搜索、通知、设置和分享面板中识别产品的核心品牌资产，要求它独特、容易记住，并能表达用途和个性。
Apple Developer

建议图形概念

不要使用：

普通书本；

普通书签；

AI 星星；

大写字母 F 直接放中央；

复杂文字；

多个细小元素。

推荐概念：

两张相互叠合的页面，中间负空间隐约形成 F，同时页面折叠方向形成一次“返回”或“回想”的循环。

配色：

主背景：深墨绿；

页面：暖白；

内部层：稍浅的青绿色；

极少量光泽或材质；

不使用复杂渐变。

它同时能够联想到：

Folio；

页面集合；

内容保存；

记忆返回；

不断积累。

需要分别测试：

浅色图标；

深色图标；

Tinted 图标；

通知和分享面板中的小尺寸；

主屏幕实际背景。

十三、视觉上的“惊艳感”应该放在哪里

Folio 不需要每个页面都惊艳。

需要让人记住的是四个瞬间：

第一次看到一条高质量核心洞察；

点击引用后看到原文证据；

Ask 给出简洁答案，并能逐条核对；

从证据精确定位回原文。

Apple 对 Delight 的解释也不是增加彩带，而是通过目的、清晰度、细节、动画和整体完成度，让产品自然产生令人愉悦的感觉。
Apple Developer

因此 Folio 的惊艳感应当是：

“这个排版真舒服”
“层级非常清楚”
“每个细节都很精确”
“这个证据链路很有质感”
“它看起来就值得信任”

而不是：

“这个控件以前没见过”
“这个动画很炫”
“页面里有很多设计元素”
十四、视觉验收标准

高保真稿完成后，不能只问用户“好不好看”，建议同时做以下检查：

视觉层级

把页面转为灰度后：

是否仍能第一眼看到主标题或核心洞察；

次级来源是否明显弱于正文；

可操作内容是否仍可识别；

页面是否只有一个主要焦点。

品牌感知

展示页面 5 秒后关闭，让用户自由描述产品。期望高频词是：

安静
可信
清晰
有品质
适合阅读

而不是：

像新闻 App
像笔记 App
像聊天机器人
像学习打卡 App
真机环境

必须检查：

阳光下；

暗光环境；

深色模式；

Increase Contrast；

Differentiate Without Color；

最大 Dynamic Type；

中文和英文；

低亮度 OLED。

Apple 明确建议颜色需要在浅色、深色、高对比度和不同照明环境中测试，而且不能只用颜色表达状态。
Apple Developer
+1

最终视觉结论

Folio 最合适的不是“纯原生工具风”，也不是之前的“档案馆概念风”，而是：

原生 iOS 框架之上的可信编辑感。

具体表现为：

暖白与深墨绿的克制配色；

系统字体为主、品牌 Serif 极少量使用；

精确的网格、间距和文字层级；

资料库保持平面，不堆卡片；

洞察成为强视觉焦点；

证据拥有稳定的暖色语义；

引用编号形成跨页面统一品牌符号；

Liquid Glass 只留给导航和控制；

图标使用 SF Symbols，App Icon 单独定制；

深色模式不是简单反色，而是单独调校；

惊艳感来自内容、排版、证据和完成度，而不是陌生控件。

这套方向既能满足“简约、清爽”，又不会重新退回毫无辨识度的系统模板。

<details>
<summary>本轮外部链接（12）</summary>

- [Apple Developer +2 Apple Developer +2](https://developer.apple.com/videos/play/wwdc2026/250/?utm_source=chatgpt.com)
- [Apple Developer +1](https://developer.apple.com/videos/play/wwdc2026/251/?time=449&utm_source=chatgpt.com)
- [Nielsen Norman Group +1](https://www.nngroup.com/videos/analyzing-figmas-shortcut/?lm=logo-placement-brand-recall&pt=article&utm_source=chatgpt.com)
- [Apple Developer +1](https://developer.apple.com/design/human-interface-guidelines/accessibility/?utm_source=chatgpt.com)
- [Apple Developer +2 Apple Developer +2](https://developer.apple.com/design/human-interface-guidelines/branding?utm_source=chatgpt.com)
- [Apple Developer](https://developer.apple.com/cn/design/human-interface-guidelines/typography?utm_source=chatgpt.com)
- [Nielsen Norman Group](https://www.nngroup.com/articles/list-entries/?lm=aesthetic-usability-effect&pt=youtubevideo&utm_source=chatgpt.com)
- [Apple Developer +1](https://developer.apple.com/design/human-interface-guidelines/materials?utm_source=chatgpt.com)
- [Apple Developer +1](https://developer.apple.com/jp/design/human-interface-guidelines/icons?utm_source=chatgpt.com)
- [Nielsen Norman Group](https://www.nngroup.com/videos/mobile-images/?lm=supporting-multiple-location-users&pt=article&utm_source=chatgpt.com)
- [Apple Developer +1](https://developer.apple.com/jp/design/human-interface-guidelines/sf-symbols?utm_source=chatgpt.com)
- [Apple Developer](https://developer.apple.com/cn/design/human-interface-guidelines/app-icons/?utm_source=chatgpt.com)

</details>

## 7. 用户

按这个标准，一张图一个 UI 页，完成所有 UI 也的设计我看看

## 8. ChatGPT

（图片生成回复）

最后一轮成稿（已保存到本地）：

- [欢迎与登录](./01-welcome-sign-in.png)
- [资料库与处理状态](./02-library.png)
- [原文阅读](./03-reader-original.png)
- [洞察详情](./04-insight-detail.png)
- [洞察证据浮层](./05-insight-evidence-sheet.png)
- [提问首页](./06-ask-home.png)
- [提问回答与引用](./07-ask-answer.png)
- [证据不足状态](./08-ask-insufficient-evidence.png)
- [分享扩展保存成功](./09-share-save-success.png)
- [设置](./10-settings.png)
