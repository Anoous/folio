# Folio AI Knowledge Partner Plan

更新时间：2026-04-16

## 产品目标

在不牺牲 Folio「简约、安静、默认好用」前提下，把产品从“AI 整理的收藏工具”升级为“无需手动选文的个人 AI 知识伙伴”。

本轮目标分两层：

1. 基础可信能力不退化：
   - 保存成功率
   - 同步一致性
   - 阅读页质量
   - 搜索找回能力
2. 差异化 AI 核心能力形成真实闭环：
   - Ask Folio：整库自动问答，自动选上下文，回答可追溯
   - Spark：自动发现跨文章连接，输出灵感与思维碰撞
   - Learn：自动生成学习摘要与带引用的学习卡片

## 当前现状

### 已有能力

- iOS 端已经具备本地优先保存、FTS5 搜索、Reader、后台同步与离线补偿链路。
- 服务端已有异步抓取、AI 分析、语义搜索、相关文章、Echo 复习卡和早期 RAG 问答能力。
- 近期 hardening 已经补上 SSRF、限流来源识别、auth refresh session、invalid UUID -> 400、E2E 稳定性、pipeline structured logs。

### 当前 AI 能力的真实状态

- `RAGService` 已存在，但主要基于标题/摘要拼 prompt，并不保证：
  - 自动检索质量可量化
  - 引用与证据一一对应
  - 证据不足时严格拒答
  - top-k recall、hallucinated citation 等 benchmark
- Echo 更偏“单篇文章回忆卡”，不是整库 Learn。
- 相关文章是后台关系计算，不是 Spark 的灵感生成。
- iOS 端当前只有“搜索或提问”的隐式入口，没有稳定承载 Spark / Learn 的默认入口。

## 当前与目标之间的关键差距

1. 缺少统一的“整库知识检索与证据层”。
2. Ask/Spark/Learn 没有共享检索与证据约束，能力分散且不可量化。
3. 问答仍偏“LLM 直接生成”，而不是“证据驱动生成”。
4. 没有最小但代表性的 benchmark 语料、问题集和验收门槛。
5. 产品入口不完整：Ask 有雏形，Spark/Learn 没有安静直接的入口。
6. 基础闭环虽然已做 hardening，但本轮缺少专门 guardrail 测试来证明 AI 升级没有伤到保存/搜索/删除/补偿。

## 用户体验问题

- 用户要靠“像问题一样的输入”才能触发问答，行为不可预期。
- 问答结果只展示来源列表，不保证回答中的每个论断都能追溯到真实证据。
- 没有“系统主动帮我提炼连接”和“基于我收藏直接帮我学”的低负担入口。
- AI 能力与搜索、阅读、收藏的关系还不够自然，像外挂功能而不是 Folio 默认能力。

## 技术根因

1. 现有 RAG 数据源过薄：
   - 只加载 `title/summary/site_name/created_at`
   - 没有充分利用 `key_points / semantic_keywords / markdown_content`
2. 缺少共享检索抽象：
   - semantic search、related、RAG 各自检索
   - 没有统一评分、召回、证据裁剪、证据不足判定
3. 缺少结构化 AI 输出契约：
   - Ask/Spark/Learn 没有统一 schema
   - 引用真实性无法自动审计
4. 测试面不完整：
   - 没有整库 benchmark 语料
   - 没有 citation hallucination / insufficient evidence / multi-source synthesis 的自动校验

## 范围

### 本轮范围

- 新增统一知识检索与证据层，供 Ask/Spark/Learn 共用。
- 升级 Ask Folio 为证据驱动问答：
  - 自动整库检索
  - 回答附来源
  - 证据不足拒答
  - 兼容现有 `/api/v1/rag/query` 与 `/api/v1/rag/query/stream`
- 新增 Spark API 与最小产品入口。
- 新增 Learn API 与最小产品入口。
- 建立 25 篇 benchmark 语料、问题集、评测与自动化测试。
- 补充基础闭环 guardrail 测试，防止 AI 改造伤到保存、搜索、删除、重试与 cleanup。

### 非目标

- 不做复杂 workspace / notebook / 手动项目化组织。
- 不做多轮 agent 规划、长任务编排、后台 AI 控制台。
- 不重做 Reader、Sync、Search 的整体架构。
- 不把所有输出都做成强 LLM 依赖；测试与默认回归必须可确定。

## 方案选择与权衡

### 方案 A：继续在现有 RAG 上堆 prompt

优点：

- 改动小
- 上线快

缺点：

- 引用真实性和证据不足难以证明
- Spark/Learn 会继续各做各的
- benchmark 很难稳定

结论：不选。

### 方案 B：建立共享“知识检索 + 证据合成”层

核心做法：

1. 统一读取 ready article 的：
   - title
   - summary
   - key_points
   - semantic_keywords
   - markdown_content（截断后的证据片段）
2. 用统一检索器做：
   - query normalization
   - keyword expansion（有 AI 时增强，无 AI 时规则退化）
   - broad recall
   - lexical + semantic keyword hybrid scoring
   - top-k evidence selection
   - insufficient evidence 判定
3. Ask/Spark/Learn 全部基于同一批 evidence 产出结构化结果。
4. 保留现有 RAG SSE 契约，避免 iOS 入口大改。

优点：

- 结构正确，可长期演进
- 引用、召回、拒答可以自动校验
- Ask/Spark/Learn 共用一套“理解整库”的核心能力

代价：

- 需要新增服务层与 benchmark
- 需要调整 iOS 入口承载 Spark/Learn

结论：本轮采用。

## 架构设计

### 1. 新增共享知识层

新增 `KnowledgeService`，内部包含：

- `KnowledgeRetriever`
- `EvidenceAssembler`
- `AskComposer`
- `SparkComposer`
- `LearnComposer`

统一输入：用户 ID + 可选 prompt

统一数据源：ready 且未删除文章

统一检索策略：

1. 首轮 broad recall：
   - `semantic_keywords`
   - title trigram
   - summary/key_points ILIKE
2. 统一打分：
   - title exact/prefix match
   - summary/key point hit
   - semantic keyword overlap
   - source diversity bonus
3. 统一证据裁剪：
   - 每篇最多保留 1-2 条 evidence excerpt
   - 全局 top-k 上限
4. 统一不足判定：
   - 低命中分数
   - 命中文章数过少且无法支撑问题类型
   - cross-source 问题检索不到至少 2 个来源

### 2. Ask Folio

输出契约：

- `answer`
- `status`：`answered | insufficient_evidence`
- `sources`
- `cited_indices`
- `followup_suggestions`

规则：

- 单源问题：至少 1 个来源
- 跨源综合问题：至少 2 个来源
- 所有 cited index 必须映射到实际检索上下文
- 证据不足必须显式拒答

实现策略：

- 非 streaming 路径：先检索、再合成最终回答
- streaming 路径：先发 sources，再按片段流式输出已合成回答
- 保留现有 conversation 存档逻辑

### 3. Spark

输出 3-5 条 insights，每条包含：

- `insight`
- `why_it_matters`
- `source_ids`
- `followup_question`

规则：

- 每条 insight 至少绑定 2 个不同来源
- 同轮去重，避免同义重复
- 可选 focus prompt；不提供时默认从整库主题分布里挑最有连接潜力的主题

### 4. Learn

输出：

- `summary`
- `items`（5-10 条）

每个 `item` 包含：

- `type`
- `title`
- `content`
- `source_ids`

规则：

- 每条 item 必须能追溯到真实来源
- 默认以用户整库中最聚焦、证据最密集的主题生成学习包
- 可选 prompt，用于按主题学习

### 5. iOS 最小产品入口

原则：不引入复杂新导航。

本轮最小交互：

- 保留首页 -> 搜索 的单入口
- 在搜索建议/AI 区增加三个安静动作：
  - Ask Folio
  - Spark
  - Learn
- Ask 继续复用现有 RAG 流式界面
- Spark / Learn 使用轻量结果视图，不要求用户建项目、选文章或配上下文

## 风险

1. 检索质量不足：
   - 用 benchmark 先锁最低 recall 门槛
   - 保留规则降级，避免 0 结果时硬答
2. LLM 不稳定或无 key：
   - 核心 benchmark 不依赖外部 LLM
   - 默认回归使用确定性合成路径
3. iOS UI 改动影响现有体验：
   - 只做轻量入口与结果承载，不改首页核心布局
4. E2E 时间变长：
   - 复用 client-provided markdown pipeline
   - 控制 benchmark fixture 长度与轮询次数

## 分阶段实施计划

### Phase 0：阅读与差距分析

- 完成文档与核心代码链路阅读
- 固化本设计文档

### Phase 1：基础可信能力 guardrail

- 新增 benchmark 基础夹具
- 补保存/搜索/删除/补偿 guardrail 测试
- 确认 SSRF、代理限流、refresh session、invalid UUID、E2E cleanup 约束不回退

### Phase 2：Ask Folio

- 先补 Ask benchmark 失败测试
- 实现共享检索与证据判定
- 升级 `/rag/query` 与 `/rag/query/stream`

### Phase 3：Spark

- 先补结构化输出 benchmark
- 实现 Spark 服务与 API
- 增加最小 iOS 入口

### Phase 4：Learn

- 先补 Learn benchmark
- 实现 Learn 服务与 API
- 增加最小 iOS 入口

### Phase 5：体验打磨与总回归

- 压缩交互步骤
- 清理命名与文案
- 全量回归与 cleanup 验证

## 可量化验收标准

### Benchmark 语料

- 25 篇种子文章
- 5 个主题簇
- 10 个整库问答问题
- 5 个跨文章综合问题
- 5 个证据不足问题
- 5 个 Spark 问题
- 5 个 Learn 问题

### 基础能力

- 新保存内容可立即进入本地可见路径
- 新保存内容可被搜索找回
- 删除后直接读取与搜索结果中均消失
- 失败存在自动补偿或可重试路径
- 现有 hardening 约束回归通过

### Ask Folio

- happy path 无需手动选文章
- 每个回答都带来源引用
- 单源问题至少 1 个来源
- 跨源问题至少 2 个不同来源
- 证据不足问题错误回答率 = 0
- hallucinated citation = 0
- benchmark top-k recall >= 0.8

### Spark

- 每次输出 3-5 条 insight
- 每条至少 2 个不同来源
- 同轮无重复 insight
- `insight / why_it_matters / source_ids / followup_question` 字段齐全

### Learn

- 每次输出压缩总结 + 5-10 个学习条目
- 每条学习条目附真实来源
- 无无来源支撑的知识点

### 工程

- `cd /Users/mac/github/folio/server && go test ./...`
- `cd /Users/mac/github/folio/server/reader-service && npm test`
- `cd /Users/mac/github/folio/server && ./scripts/run_e2e.sh`
- 如改 iOS：相关 `xcodebuild test` 通过
- cleanup 后无异常 Docker / 端口 / 进程残留

## 本轮执行策略

采用 TDD：

1. 先加 benchmark fixture 与失败测试
2. 再实现共享知识层
3. 再接 Ask/Spark/Learn API
4. 再补最小 iOS 入口
5. 最后全量回归和 cleanup 验证
