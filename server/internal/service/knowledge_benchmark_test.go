package service

import (
	"context"
	"fmt"
	"math"
	"slices"
	"strings"
	"testing"
	"time"
)

type benchmarkKnowledgeRepo struct {
	docs []KnowledgeDocument
}

func (r *benchmarkKnowledgeRepo) ListKnowledgeDocuments(_ context.Context, userID string) ([]KnowledgeDocument, error) {
	if userID == "" {
		return nil, fmt.Errorf("missing user id")
	}
	return slices.Clone(r.docs), nil
}

type benchmarkAskCase struct {
	name            string
	question        string
	expectedSources []string
	crossSource     bool
}

type benchmarkSparkCase struct {
	name   string
	prompt string
}

type benchmarkLearnCase struct {
	name   string
	prompt string
}

func TestKnowledgeBenchmark_AskRecallAndCitations(t *testing.T) {
	svc := newBenchmarkKnowledgeService()

	cases := []benchmarkAskCase{
		{
			name:            "structured logs and slos",
			question:        "为什么结构化日志和 SLO 对可靠服务重要？",
			expectedSources: []string{"ds5"},
		},
		{
			name:            "reduce user choice",
			question:        "为什么 Folio 应该默认拒绝让用户手动选文章做上下文？",
			expectedSources: []string{"prod2", "prod3", "prod1"},
		},
		{
			name:            "grounded rag",
			question:        "提高 grounded AI answer 的关键机制是什么？",
			expectedSources: []string{"ai6", "ai8", "ai9", "ai10"},
		},
		{
			name:            "compensating reliability",
			question:        "为什么保存和同步要保持幂等和可补偿？",
			expectedSources: []string{"ds4"},
		},
		{
			name:            "active recall over summary",
			question:        "为什么学习功能不能只给摘要，还要有主动回忆题？",
			expectedSources: []string{"learn16", "learn17", "learn20"},
		},
		{
			name:            "provenance",
			question:        "个人知识库为什么必须保留来源追溯？",
			expectedSources: []string{"write23", "ai8", "learn20"},
		},
		{
			name:            "calm product in knowledge apps",
			question:        "怎样把 calm product 原则应用到知识收藏产品？",
			expectedSources: []string{"prod1", "prod2", "prod4"},
		},
		{
			name:            "say i dont know",
			question:        "为什么系统必须在证据不足时明确说不知道？",
			expectedSources: []string{"ai9"},
		},
		{
			name:            "from saving to understanding",
			question:        "什么机制能帮助用户从收藏走向真正理解？",
			expectedSources: []string{"learn17", "learn18", "write24"},
		},
		{
			name:            "simple and reliable",
			question:        "如何同时兼顾默认简单和系统可靠性？",
			expectedSources: []string{"prod1", "prod4", "prod5", "ds4"},
		},
		{
			name:            "ask folio shape",
			question:        "如果把 calm software 原则和 citation guardrails 结合，Ask Folio 应该长什么样？",
			expectedSources: []string{"prod1", "prod4", "ai8"},
			crossSource:     true,
		},
		{
			name:            "shared pattern",
			question:        "可靠性工程中的 idempotency 和 backpressure 与学习中的 spaced repetition 和 active recall 有什么共同模式？",
			expectedSources: []string{"ds4", "learn16", "learn17"},
			crossSource:     true,
		},
		{
			name:            "provenance and synthesis",
			question:        "为什么个人知识库需要既有 provenance 又能做 synthesis？",
			expectedSources: []string{"write23", "write25", "write22", "ai8"},
			crossSource:     true,
		},
		{
			name:            "two tap zero config",
			question:        "两步交互和零配置 AI 为什么能同时成立？",
			expectedSources: []string{"prod3", "prod4", "ai7"},
			crossSource:     true,
		},
		{
			name:            "knowledge loop",
			question:        "如何把相关文章、Spark 和 Learn 串成一个更强的知识闭环？",
			expectedSources: []string{"write21", "write24", "learn20"},
			crossSource:     true,
		},
	}

	totalRecall := 0.0
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			ctx, err := svc.Retrieve(context.Background(), "user-1", tc.question, KnowledgeRetrieveOptions{
				Mode:       KnowledgeModeAsk,
				MaxSources: 5,
			})
			if err != nil {
				t.Fatalf("Retrieve() error = %v", err)
			}

			recall := recallAtK(ctx.Sources, tc.expectedSources, 5)
			totalRecall += recall
			t.Logf("recall=%.2f sources=%v expected=%v", recall, sourceIDs(ctx.Sources), tc.expectedSources)

			answer, err := svc.Ask(context.Background(), "user-1", tc.question)
			if err != nil {
				t.Fatalf("Ask() error = %v", err)
			}
			if answer.Status != KnowledgeStatusAnswered {
				t.Fatalf("Ask() status = %q, want %q", answer.Status, KnowledgeStatusAnswered)
			}
			if len(answer.Answer) == 0 {
				t.Fatalf("Ask() returned empty answer")
			}
			if len(answer.Sources) == 0 {
				t.Fatalf("Ask() returned no sources")
			}
			for _, source := range answer.Sources {
				if source.EvidenceSnippet == nil || strings.TrimSpace(*source.EvidenceSnippet) == "" {
					t.Fatalf("Ask() source must include evidence snippet: %+v", source)
				}
			}
			if tc.crossSource {
				if uniqueSourceCount(answer.Sources) < 2 {
					t.Fatalf("cross-source answer must cite at least 2 sources, got %d", uniqueSourceCount(answer.Sources))
				}
			} else if uniqueSourceCount(answer.Sources) < 1 {
				t.Fatalf("single-source answer must cite at least 1 source")
			}
			assertCitationsAreBounded(t, answer.CitedIndices, answer.Sources)
		})
	}

	avgRecall := totalRecall / float64(len(cases))
	if avgRecall < 0.8 {
		t.Fatalf("average top-k recall = %.3f, want >= 0.8", avgRecall)
	}
}

func sourceIDs(sources []KnowledgeSource) []string {
	ids := make([]string, 0, len(sources))
	for _, source := range sources {
		ids = append(ids, source.ArticleID)
	}
	return ids
}

func TestKnowledgeBenchmark_AskInsufficientEvidence(t *testing.T) {
	svc := newBenchmarkKnowledgeService()

	questions := []string{
		"这些文章怎么评价量子纠错码的阈值定理？",
		"库里对地中海饮食和跑步训练有什么建议？",
		"用户收藏里有没有对中国宏观房地产周期的完整分析？",
		"这些资料如何比较 Kubernetes 和 Nomad 的调度器实现细节？",
		"文章库里有没有关于 CRISPR 临床试验的数据结论？",
	}

	for _, question := range questions {
		t.Run(question, func(t *testing.T) {
			answer, err := svc.Ask(context.Background(), "user-1", question)
			if err != nil {
				t.Fatalf("Ask() error = %v", err)
			}
			if answer.Status != KnowledgeStatusInsufficientEvidence {
				t.Fatalf("Ask() status = %q, want %q", answer.Status, KnowledgeStatusInsufficientEvidence)
			}
			if !strings.Contains(answer.Answer, "证据不足") && !strings.Contains(answer.Answer, "无法确认") {
				t.Fatalf("insufficient answer must be explicit, got %q", answer.Answer)
			}
			if len(answer.CitedIndices) != 0 {
				t.Fatalf("insufficient answer must not cite sources, got %v", answer.CitedIndices)
			}
			if len(answer.Sources) != 0 {
				t.Fatalf("insufficient answer must not return cited sources, got %d", len(answer.Sources))
			}
		})
	}
}

func TestKnowledgeBenchmark_SparkStructure(t *testing.T) {
	svc := newBenchmarkKnowledgeService()

	cases := []benchmarkSparkCase{
		{name: "default", prompt: ""},
		{name: "reliability and trust", prompt: "围绕可靠性与用户信任，提取几条值得继续思考的洞察"},
		{name: "learning and pkm", prompt: "从学习科学和知识管理之间提炼新的连接"},
		{name: "groundedness and simplicity", prompt: "找出 AI groundedness 和产品默认简单之间的张力"},
		{name: "design patterns", prompt: "发现这座知识库里反复出现的设计模式"},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			result, err := svc.Spark(context.Background(), "user-1", tc.prompt)
			if err != nil {
				t.Fatalf("Spark() error = %v", err)
			}
			if n := len(result.Insights); n < 3 || n > 5 {
				t.Fatalf("Spark() insight count = %d, want 3..5", n)
			}

			seen := map[string]bool{}
			for _, insight := range result.Insights {
				key := normalizeText(insight.Insight)
				if seen[key] {
					t.Fatalf("duplicate insight: %q", insight.Insight)
				}
				seen[key] = true

				if strings.TrimSpace(insight.Insight) == "" || strings.TrimSpace(insight.WhyItMatters) == "" || strings.TrimSpace(insight.FollowupQuestion) == "" {
					t.Fatalf("Spark() insight fields must be non-empty: %+v", insight)
				}
				if len(insight.SourceIDs) < 2 {
					t.Fatalf("Spark() each insight needs >= 2 sources, got %v", insight.SourceIDs)
				}
				assertSourceIDsExist(t, insight.SourceIDs)
				assertSourceIDsInResponseSources(t, insight.SourceIDs, result.Sources)
			}
		})
	}
}

func TestKnowledgeBenchmark_LearnStructure(t *testing.T) {
	svc := newBenchmarkKnowledgeService()

	cases := []benchmarkLearnCase{
		{name: "grounded assistant", prompt: "帮我学会 grounded AI assistant 的关键原则"},
		{name: "calm product", prompt: "把 calm product 相关内容整理成复习包"},
		{name: "learning science", prompt: "围绕学习科学生成学习卡片"},
		{name: "provenance", prompt: "总结个人知识库中 provenance 的意义并出题"},
		{name: "reliability", prompt: "整理可靠性工程基础概念供复习"},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			result, err := svc.Learn(context.Background(), "user-1", tc.prompt)
			if err != nil {
				t.Fatalf("Learn() error = %v", err)
			}
			if strings.TrimSpace(result.Summary) == "" {
				t.Fatalf("Learn() summary must be non-empty")
			}
			if n := len(result.Items); n < 5 || n > 10 {
				t.Fatalf("Learn() item count = %d, want 5..10", n)
			}
			for _, item := range result.Items {
				if strings.TrimSpace(item.Type) == "" || strings.TrimSpace(item.Title) == "" || strings.TrimSpace(item.Content) == "" {
					t.Fatalf("Learn() item fields must be non-empty: %+v", item)
				}
				if len(item.SourceIDs) == 0 {
					t.Fatalf("Learn() every item must cite at least one source: %+v", item)
				}
				assertSourceIDsExist(t, item.SourceIDs)
				assertSourceIDsInResponseSources(t, item.SourceIDs, result.Sources)
			}
		})
	}
}

func newBenchmarkKnowledgeService() *KnowledgeService {
	return NewKnowledgeService(&benchmarkKnowledgeRepo{docs: benchmarkCorpus()})
}

func recallAtK(sources []KnowledgeSource, expected []string, k int) float64 {
	if len(expected) == 0 {
		return 1
	}
	expectedSet := map[string]bool{}
	for _, id := range expected {
		expectedSet[id] = true
	}
	found := 0
	for idx, source := range sources {
		if idx >= k {
			break
		}
		if expectedSet[source.ArticleID] {
			found++
		}
	}
	return float64(found) / float64(len(expected))
}

func uniqueSourceCount(sources []KnowledgeSource) int {
	seen := map[string]bool{}
	for _, source := range sources {
		seen[source.ArticleID] = true
	}
	return len(seen)
}

func assertCitationsAreBounded(t *testing.T, citedIndices []int, sources []KnowledgeSource) {
	t.Helper()
	for _, idx := range citedIndices {
		if idx < 1 || idx > len(sources) {
			t.Fatalf("hallucinated citation index %d for %d sources", idx, len(sources))
		}
	}
}

func assertSourceIDsExist(t *testing.T, ids []string) {
	t.Helper()
	all := map[string]bool{}
	for _, doc := range benchmarkCorpus() {
		all[doc.ArticleID] = true
	}
	for _, id := range ids {
		if !all[id] {
			t.Fatalf("source id %q does not exist in benchmark corpus", id)
		}
	}
}

func assertSourceIDsInResponseSources(t *testing.T, ids []string, sources []KnowledgeSource) {
	t.Helper()
	sourceSet := map[string]bool{}
	for _, source := range sources {
		sourceSet[source.ArticleID] = true
	}
	for _, id := range ids {
		if !sourceSet[id] {
			t.Fatalf("source id %q is not present in response sources %v", id, sourceIDs(sources))
		}
	}
}

func normalizeText(s string) string {
	s = strings.ToLower(strings.TrimSpace(s))
	replacer := strings.NewReplacer("，", "", "。", "", "：", "", " ", "")
	return replacer.Replace(s)
}

func benchmarkCorpus() []KnowledgeDocument {
	base := time.Date(2026, time.April, 1, 9, 0, 0, 0, time.UTC)
	return []KnowledgeDocument{
		doc("ds1", base.Add(1*time.Hour), "Amazon's Two-Pizza Teams and Service Ownership", "Ownership shrinks coordination cost and makes reliability work visible because one team owns one service end to end.", []string{"service ownership lowers coordination cost", "clear ownership improves reliability decisions", "small teams move faster with less coupling"}, []string{"ownership", "service architecture", "coordination", "reliability"}, "Service ownership matters when teams need to move fast without dropping operational quality. Small end-to-end teams create accountability for uptime, incident response, and long-term maintenance."),
		doc("ds2", base.Add(2*time.Hour), "Cell Architecture for Blast Radius Reduction", "Cell-based systems isolate failures so one broken partition does not take the whole product down.", []string{"cells limit blast radius", "isolation improves recovery", "local failure should not become global failure"}, []string{"cell architecture", "blast radius", "isolation", "recovery"}, "A cell architecture treats the system as many small replicas. When a dependency fails, isolation keeps the incident local and preserves overall trust."),
		doc("ds3", base.Add(3*time.Hour), "Backpressure and Queue Discipline in High-Traffic APIs", "Reliable APIs need bounded concurrency, queue discipline, and backpressure so load spikes degrade gracefully instead of collapsing latency for everyone.", []string{"backpressure prevents latency collapse", "bounded concurrency protects shared resources", "queue discipline matters under spikes"}, []string{"backpressure", "queue", "latency", "bounded concurrency"}, "Backpressure is not optional in high-traffic systems. It converts overload into controlled shedding, preserving service quality and making behavior predictable under stress."),
		doc("ds4", base.Add(4*time.Hour), "Idempotency Keys for Payment Reliability", "Idempotency and compensating workflows keep retries safe when mobile clients, queues, and payment providers deliver duplicates.", []string{"idempotency makes retries safe", "compensating workflows repair partial failure", "duplicate delivery is normal in distributed systems"}, []string{"idempotency", "retries", "compensation", "distributed systems"}, "Network retries are normal, not exceptional. Idempotency keys and compensating actions let systems recover without double side effects or manual cleanup."),
		doc("ds5", base.Add(5*time.Hour), "Observability First: Structured Logs and SLOs", "Structured logs, traces, and service level objectives turn incidents from guesswork into measurable feedback loops.", []string{"structured logs speed up debugging", "slos align engineering with user experience", "observability enables fast diagnosis"}, []string{"structured logs", "slos", "observability", "incident response"}, "Reliable systems need observability before they need dashboards. Structured logs and SLOs reveal where user pain starts and which failure modes deserve engineering time."),

		doc("ai6", base.Add(24*time.Hour), "RAG Retrieval Recall vs Precision", "Grounded assistants fail when retrieval misses the right documents, so recall matters first and precision refines the shortlist later.", []string{"retrieval recall is a primary bottleneck", "precision matters after recall", "assistants need the right evidence before generation"}, []string{"rag", "retrieval recall", "precision", "grounded answers"}, "A grounded assistant cannot cite knowledge it never retrieved. Teams should optimize recall first, then use reranking and prompt discipline to control noise."),
		doc("ai7", base.Add(25*time.Hour), "Hybrid Search: Dense + Lexical Retrieval", "Hybrid retrieval combines semantic similarity with lexical matching so exact names, acronyms, and concepts all remain discoverable.", []string{"hybrid search balances semantics and exact match", "lexical retrieval catches exact terms", "semantic retrieval improves paraphrase recall"}, []string{"hybrid retrieval", "dense retrieval", "lexical search", "semantic search"}, "Dense retrieval alone can miss exact phrases, while lexical search alone misses paraphrases. Hybrid search raises top-k recall for real knowledge bases."),
		doc("ai8", base.Add(26*time.Hour), "Citation Guardrails for Grounded Answers", "A grounded assistant should only cite retrieved sources, bind every claim to evidence, and never invent citations that were not in context.", []string{"citations must bind to retrieved evidence", "hallucinated citations destroy trust", "grounded answers need source traceability"}, []string{"citation", "groundedness", "provenance", "evidence"}, "Citation guardrails are a product requirement, not just a model behavior. If the assistant cannot point back to retrieved evidence, it should not state the claim confidently."),
		doc("ai9", base.Add(27*time.Hour), "When to Say I Don't Know in AI Assistants", "A trustworthy assistant must explicitly say it lacks evidence instead of completing a plausible but unsupported answer.", []string{"evidence insufficiency should trigger refusal", "calibrated uncertainty builds trust", "plausible guessing is harmful"}, []string{"i don't know", "insufficient evidence", "trust", "refusal"}, "Trust grows when an assistant is willing to stop. Refusing unsupported questions is better than sounding smart while being wrong."),
		doc("ai10", base.Add(28*time.Hour), "Semantic Chunking for Long Knowledge Bases", "Long documents need chunking around ideas rather than arbitrary token windows so retrieval returns coherent evidence snippets.", []string{"chunk around ideas not raw token count", "retrieval needs coherent snippets", "long knowledge bases require evidence shaping"}, []string{"chunking", "long context", "knowledge base", "snippets"}, "Chunk quality influences retrieval quality. Coherent snippets make it easier to answer with evidence instead of noise."),

		doc("prod1", base.Add(48*time.Hour), "Calm Software and Quiet Defaults", "Calm software removes spectacle and keeps the user in flow by making the right thing happen quietly in the background.", []string{"quiet defaults reduce cognitive load", "software should stay out of the way", "background automation needs trust"}, []string{"calm software", "quiet defaults", "trust", "automation"}, "A calm product acts like infrastructure for thought. It does powerful work without demanding constant attention or configuration."),
		doc("prod2", base.Add(49*time.Hour), "Reducing User Choice to Lower Cognitive Load", "Every extra choice taxes working memory, so tools should automate decisions that machines can make safely.", []string{"too many choices create friction", "automation should remove low-value decisions", "user choice is a cost not a virtue"}, []string{"cognitive load", "user choice", "defaults", "automation"}, "A product can be powerful without asking the user to steer every step. Good defaults are a usability feature and a trust signal."),
		doc("prod3", base.Add(50*time.Hour), "The Cost of Configuration in Consumer Tools", "Configuration is delayed work for users; products should expose policy only when the default can no longer serve most cases.", []string{"configuration shifts system cost onto the user", "defaults should serve the median case", "power should not require setup"}, []string{"configuration", "consumer tools", "defaults", "setup"}, "Users experience configuration as work. A product that requires setup before delivering value leaks technical complexity into the product surface."),
		doc("prod4", base.Add(51*time.Hour), "Designing Two-Tap Flows for Capture and Recall", "The most important action in a capture product should take at most two intentional taps from the home state.", []string{"two-tap flows preserve momentum", "core actions should be near the surface", "capture must feel immediate"}, []string{"two tap flow", "capture", "recall", "interaction design"}, "If the product makes the user think before saving or asking, it loses the moment. Short paths are not polish; they are the product."),
		doc("prod5", base.Add(52*time.Hour), "Invisible Automation and Trust", "Automation earns trust when it is reversible, traceable, and silent by default rather than flashy or opaque.", []string{"traceability makes automation trustworthy", "silent defaults reduce interruption", "reversible automation lowers risk"}, []string{"automation", "trust", "traceability", "reversible"}, "Users accept background automation when they can inspect the result and recover from failure. Trust comes from legibility, not spectacle."),

		doc("learn16", base.Add(72*time.Hour), "Spaced Repetition Beats Cramming", "Spaced review strengthens long-term memory because effort is distributed over time instead of compressed into one session.", []string{"spacing improves long-term retention", "review over time beats cramming", "memory needs timed retrieval"}, []string{"spaced repetition", "memory", "retention", "review"}, "Spacing works because forgetting and effort interact. Revisiting material after delay strengthens recall more than massed repetition."),
		doc("learn17", base.Add(73*time.Hour), "Active Recall Outperforms Rereading", "Learners understand more when they try to retrieve an idea from memory than when they passively reread the same page.", []string{"active recall strengthens understanding", "questions beat passive rereading", "retrieval effort reveals knowledge gaps"}, []string{"active recall", "questions", "understanding", "retrieval practice"}, "Learning systems should create retrieval opportunities, not just compress text. Questions expose what the learner actually knows."),
		doc("learn18", base.Add(74*time.Hour), "Interleaving Concepts Improves Transfer", "Mixing related ideas during practice helps learners notice boundaries and apply concepts in new settings.", []string{"interleaving improves transfer", "mixing topics helps discrimination", "related ideas should be compared not isolated forever"}, []string{"interleaving", "transfer", "comparison", "learning science"}, "Interleaving feels harder than blocked study, but that difficulty improves flexible understanding and transfer."),
		doc("learn19", base.Add(75*time.Hour), "Desirable Difficulties in Learning", "Learning sticks when practice is effortful enough to require reconstruction but not so hard that the learner gives up.", []string{"difficulty should be useful not punishing", "effortful retrieval supports retention", "good friction can improve learning"}, []string{"desirable difficulties", "effort", "retention", "learning"}, "Not all friction is bad. The right amount of challenge makes learning durable instead of merely familiar."),
		doc("learn20", base.Add(76*time.Hour), "Flashcards Need Source-Linked Explanations", "Study cards are safer and more reusable when every card can point back to the original source passage that justified it.", []string{"cards need source linkage", "provenance protects against drift", "study items should remain inspectable"}, []string{"flashcards", "provenance", "source linked", "study cards"}, "A learning card without provenance drifts from the original material over time. Source-linked explanations keep review accurate and trustworthy."),

		doc("write21", base.Add(96*time.Hour), "Zettelkasten as Connection Engine", "A personal knowledge system creates value when notes connect across topics instead of staying trapped inside folders.", []string{"connections create value", "notes should link across topics", "knowledge systems need graph thinking"}, []string{"zettelkasten", "connections", "knowledge system", "links"}, "A knowledge base becomes generative when ideas collide. The goal is not storage alone but connection across contexts."),
		doc("write22", base.Add(97*time.Hour), "Writing to Think Across Sources", "Synthesis happens when you write through tension between multiple sources rather than copying one article at a time.", []string{"writing forces synthesis", "multiple sources create tension", "insight emerges from comparison"}, []string{"writing", "synthesis", "multiple sources", "comparison"}, "Writing is a thinking tool. It turns scattered reading into a point of view by forcing comparisons and decisions."),
		doc("write23", base.Add(98*time.Hour), "Personal Knowledge Bases Need Provenance", "Without provenance, a note may survive while the reason to trust it disappears.", []string{"provenance preserves trust", "notes need inspectable origin", "knowledge bases decay without traceability"}, []string{"provenance", "trust", "knowledge base", "traceability"}, "A durable knowledge base must keep the path back to origin. Provenance lets the user verify, reinterpret, and reuse ideas later."),
		doc("write24", base.Add(99*time.Hour), "From Highlights to Original Insight", "Highlights become useful only after they are compressed, compared, and turned into claims or questions worth revisiting.", []string{"highlights are raw material not finished knowledge", "compression and comparison create insight", "good questions unlock deeper reuse"}, []string{"highlights", "insight", "comparison", "questions"}, "Collection is only the first step. Insight appears when the system helps the user compress and recombine what was saved."),
		doc("write25", base.Add(100*time.Hour), "Synthesis Requires Tension, Not Just Summaries", "Real synthesis comes from resolving disagreement, overlap, or contrast between sources, not from stacking summaries side by side.", []string{"synthesis needs contrast or overlap", "summary alone is insufficient", "insight depends on tension"}, []string{"synthesis", "tension", "contrast", "overlap"}, "A personal knowledge assistant should look for friction between sources. Tension is what turns accumulation into thinking."),
	}
}

func doc(id string, createdAt time.Time, title, summary string, keyPoints, keywords []string, content string) KnowledgeDocument {
	siteName := "Benchmark Library"
	return KnowledgeDocument{
		ArticleID:        id,
		Title:            title,
		Summary:          summary,
		KeyPoints:        keyPoints,
		SemanticKeywords: keywords,
		MarkdownContent:  content,
		SiteName:         &siteName,
		CreatedAt:        createdAt,
	}
}

func TestKnowledgeBenchmarkCorpusShape(t *testing.T) {
	corpus := benchmarkCorpus()
	if len(corpus) != 25 {
		t.Fatalf("benchmark corpus size = %d, want 25", len(corpus))
	}

	clusters := map[string]int{}
	for _, doc := range corpus {
		prefix := strings.TrimRightFunc(doc.ArticleID, func(r rune) bool { return r >= '0' && r <= '9' })
		clusters[prefix]++
	}

	if len(clusters) != 5 {
		t.Fatalf("cluster count = %d, want 5", len(clusters))
	}
	for prefix, count := range clusters {
		if math.Abs(float64(count-5)) > 0 {
			t.Fatalf("cluster %s size = %d, want 5", prefix, count)
		}
	}
}
