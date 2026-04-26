"""Knowledge partner benchmark E2E tests."""

from __future__ import annotations

import uuid

import pytest

from helpers.api_client import FolioAPIClient
from helpers.polling import poll_many_until_done
from helpers.test_auth import test_login

pytestmark = pytest.mark.timeout(240)

BENCHMARK_CORPUS = [
    ("Amazon's Two-Pizza Teams and Service Ownership", "Service ownership lowers coordination cost and makes reliability work visible because one team owns one service end to end."),
    ("Cell Architecture for Blast Radius Reduction", "Cell-based systems isolate failures so one broken partition does not take the whole product down."),
    ("Backpressure and Queue Discipline in High-Traffic APIs", "Reliable APIs need bounded concurrency, queue discipline, and backpressure so load spikes degrade gracefully instead of collapsing latency for everyone."),
    ("Idempotency Keys for Payment Reliability", "Idempotency and compensating workflows keep retries safe when mobile clients, queues, and payment providers deliver duplicates."),
    ("Observability First: Structured Logs and SLOs", "Structured logs, traces, and service level objectives turn incidents from guesswork into measurable feedback loops."),
    ("RAG Retrieval Recall vs Precision", "Grounded assistants fail when retrieval misses the right documents, so recall matters first and precision refines the shortlist later."),
    ("Hybrid Search: Dense + Lexical Retrieval", "Hybrid retrieval combines semantic similarity with lexical matching so exact names, acronyms, and concepts all remain discoverable."),
    ("Citation Guardrails for Grounded Answers", "A grounded assistant should only cite retrieved sources, bind every claim to evidence, and never invent citations that were not in context."),
    ("When to Say I Don't Know in AI Assistants", "A trustworthy assistant must explicitly say it lacks evidence instead of completing a plausible but unsupported answer."),
    ("Semantic Chunking for Long Knowledge Bases", "Long documents need chunking around ideas rather than arbitrary token windows so retrieval returns coherent evidence snippets."),
    ("Calm Software and Quiet Defaults", "Calm software removes spectacle and keeps the user in flow by making the right thing happen quietly in the background."),
    ("Reducing User Choice to Lower Cognitive Load", "Every extra choice taxes working memory, so tools should automate decisions that machines can make safely."),
    ("The Cost of Configuration in Consumer Tools", "Configuration is delayed work for users; products should expose policy only when the default can no longer serve most cases."),
    ("Designing Two-Tap Flows for Capture and Recall", "The most important action in a capture product should take at most two intentional taps from the home state."),
    ("Invisible Automation and Trust", "Automation earns trust when it is reversible, traceable, and silent by default rather than flashy or opaque."),
    ("Spaced Repetition Beats Cramming", "Spaced review strengthens long-term memory because effort is distributed over time instead of compressed into one session."),
    ("Active Recall Outperforms Rereading", "Learners understand more when they try to retrieve an idea from memory than when they passively reread the same page."),
    ("Interleaving Concepts Improves Transfer", "Mixing related ideas during practice helps learners notice boundaries and apply concepts in new settings."),
    ("Desirable Difficulties in Learning", "Learning sticks when practice is effortful enough to require reconstruction but not so hard that the learner gives up."),
    ("Flashcards Need Source-Linked Explanations", "Study cards are safer and more reusable when every card can point back to the original source passage that justified it."),
    ("Zettelkasten as Connection Engine", "A personal knowledge system creates value when notes connect across topics instead of staying trapped inside folders."),
    ("Writing to Think Across Sources", "Synthesis happens when you write through tension between multiple sources rather than copying one article at a time."),
    ("Personal Knowledge Bases Need Provenance", "Without provenance, a note may survive while the reason to trust it disappears."),
    ("From Highlights to Original Insight", "Highlights become useful only after they are compressed, compared, and turned into claims or questions worth revisiting."),
    ("Synthesis Requires Tension, Not Just Summaries", "Real synthesis comes from resolving disagreement, overlap, or contrast between sources, not from stacking summaries side by side."),
]


@pytest.fixture(scope="module")
def knowledge_api(base_url) -> FolioAPIClient:
    client = FolioAPIClient(base_url)
    test_login(client, alias=f"knowledge-{uuid.uuid4().hex}")
    yield client
    client.close()


@pytest.fixture(scope="module")
def knowledge_library(knowledge_api) -> set[str]:
    article_ids: set[str] = set()
    task_ids: list[str] = []
    for index, (title, sentence) in enumerate(BENCHMARK_CORPUS):
        body = (
            f"# {title}\n\n"
            f"{sentence}\n\n"
            "This benchmark article is intentionally short and deterministic so the pipeline can exercise "
            "client-provided content, indexing, and knowledge retrieval without public-web variability.\n"
        )
        response = knowledge_api.submit_manual(body, title=f"{title} #{index}")
        assert response.status_code == 202, response.text
        payload = response.json()
        article_ids.add(payload["article_id"])
        task_ids.append(payload["task_id"])

    tasks = poll_many_until_done(knowledge_api, task_ids, timeout=180, interval=2)
    for task_id in task_ids:
        assert tasks[task_id]["status"] == "done", tasks[task_id]

    assert len(article_ids) == 25
    return article_ids


class TestKnowledgePartner:
    def test_ask_folio_queries_library_without_manual_selection(self, knowledge_api, knowledge_library):
        response = knowledge_api.rag_query("如果把 calm software 原则和 citation guardrails 结合，Ask Folio 应该长什么样？")
        assert response.status_code == 200, response.text
        body = response.json()

        assert body["answer"]
        assert len(body["sources"]) >= 2
        assert body["source_count"] >= 2
        assert "¹" in body["answer"] or "²" in body["answer"]
        for source in body["sources"]:
            assert source["article_id"] in knowledge_library
            assert source["evidence_snippet"]

    def test_ask_folio_refuses_when_evidence_is_missing(self, knowledge_api, knowledge_library):
        response = knowledge_api.rag_query("文章库里有没有关于 CRISPR 临床试验的数据结论？")
        assert response.status_code == 200, response.text
        body = response.json()

        assert "证据不足" in body["answer"] or "无法确认" in body["answer"]
        assert body["sources"] == []
        assert body["source_count"] == 0

    def test_spark_returns_structured_multi_source_insights(self, knowledge_api, knowledge_library):
        response = knowledge_api.knowledge_spark("围绕可靠性与用户信任，提取几条值得继续思考的洞察")
        assert response.status_code == 200, response.text
        body = response.json()

        insights = body["insights"]
        sources = {source["article_id"] for source in body["sources"]}
        assert 3 <= len(insights) <= 5
        assert sources

        seen = set()
        for insight in insights:
            assert insight["insight"]
            assert insight["why_it_matters"]
            assert insight["followup_question"]
            assert len(insight["source_ids"]) >= 2
            for source_id in insight["source_ids"]:
                assert source_id in knowledge_library
                assert source_id in sources
            normalized = "".join(insight["insight"].lower().split())
            assert normalized not in seen
            seen.add(normalized)

    def test_grounding_keeps_source_ids_unique_and_supported(self, knowledge_api, knowledge_library):
        response = knowledge_api.knowledge_spark("把 grounded AI 和 provenance 的关系整理成洞察")
        assert response.status_code == 200, response.text
        body = response.json()

        response_source_ids = {source["article_id"] for source in body["sources"]}
        assert response_source_ids

        for insight in body["insights"]:
            source_ids = insight["source_ids"]
            assert len(source_ids) == len(set(source_ids))
            for source_id in source_ids:
                assert source_id in knowledge_library
                assert source_id in response_source_ids

    def test_learn_returns_summary_and_cited_items(self, knowledge_api, knowledge_library):
        response = knowledge_api.knowledge_learn("围绕学习科学生成学习卡片")
        assert response.status_code == 200, response.text
        body = response.json()

        assert body["summary"]
        sources = {source["article_id"] for source in body["sources"]}
        assert sources
        assert 5 <= len(body["items"]) <= 10
        for item in body["items"]:
            assert item["type"]
            assert item["title"]
            assert item["content"]
            assert item["source_ids"]
            for source_id in item["source_ids"]:
                assert source_id in knowledge_library
                assert source_id in sources
