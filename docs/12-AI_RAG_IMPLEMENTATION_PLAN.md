# AI/RAG 核心模块实现计划（P0 基线版）

> 目标：按重写基线补齐“Java 预创建运行记录 -> Python 检索与生成 -> citations 留痕 -> Java 回填业务落库”的端到端链路。

## 1. 背景与边界

- `mediask-ai` 只负责 AI 执行，不维护业务主事实
- Java 负责 `ai_session/ai_turn/ai_model_run/knowledge_document/knowledge_chunk`
- Python 负责 `knowledge_chunk_index/ai_run_citation`
- 输出定位为辅助问诊、风险提示、建议就医/推荐科室，不输出诊断与处方

## 2. 本轮只做两类能力

- **索引能力**：Java 已持久化 chunk -> Python 生成 embedding -> 写 `knowledge_chunk_index`
- **检索生成能力**：`model_run_id` 预分配 -> 检索 -> 写 `ai_run_citation` -> LLM 生成

## 3. 验收口径

### 3.1 功能验收

- `/api/v1/knowledge/index`：支持对 Java 已持久化的 chunk 批量建立索引
- `/api/v1/knowledge/search`：能返回 top_k chunks（含 `chunk_id/score/metadata`）
- `/api/v1/chat`：`use_rag=true` 时返回 `answer + citations + risk_level`
- `/api/v1/chat/stream`：稳定输出 `message/meta/end/error`

### 3.2 质量验收

- `model_run_id` 全链路透传
- `ai_run_citation` 可外键到 `ai_model_run`
- 引入 `RAG_SCORE_THRESHOLD`，避免硬塞无关上下文
- 检索失败时可降级为无 RAG 的保守辅助回答

## 4. 分阶段实施

### 阶段 0：冻结协议（0.5-1 天）

- 确认 `chat/chat_stream` 请求字段：`model_run_id/turn_id/session_uuid/trace_id`
- 确认 `ai_run_citation` 字段：`model_run_id/chunk_id/retrieval_rank/*score`
- 明确输出边界：不诊断、不处方

### 阶段 1：索引 MVP（1-2 天）

- 实现 `KnowledgeIndexer`
- 输入：`document_id + knowledge_base_id + chunks[]`
- 输出：`knowledge_chunk_index` upsert
- 幂等键：`chunk_id`

### 阶段 2：检索 MVP（1-2 天）

- 实现 `Retriever`
- pgvector 向量召回 + tsvector 关键词召回
- RRF 融合
- 写入 `ai_run_citation(model_run_id, chunk_id, retrieval_rank, ...)`

### 阶段 3：生成与护栏（1-2 天）

- 实现 `RagPipeline`
- 接入 LLM
- 接入基础护栏与免责声明
- 返回 `answer/summary/citations/risk_level/guardrail_action`

### 阶段 4：工程化补齐（1-2 天）

- SSE `meta/end/error`
- 检索/生成耗时拆分日志
- mock embedding / mock PostgreSQL 测试
- 黄金问答集回归

## 5. 配置建议

```bash
EMBEDDING_PROVIDER=openai_compatible
EMBEDDING_MODEL=text-embedding-v4
EMBEDDING_BASE_URL=<阿里百炼兼容端点>
EMBEDDING_API_KEY=<阿里百炼 API Key>

RAG_TOP_K=5
RAG_VECTOR_TOP_K=30
RAG_KEYWORD_TOP_K=30
RAG_SCORE_THRESHOLD=0.20
```

## 6. 交付顺序

1. `knowledge/index`
2. `knowledge/search`
3. `chat`
4. `chat/stream`
5. 黄金集与回归脚本
