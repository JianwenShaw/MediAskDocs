# AI/RAG 核心模块实现计划（可演示、可追溯、可扩展）

> 目标：在现有 `mediask-ai`（FastAPI）骨架上，补齐“知识入库 → 向量化 → PostgreSQL + pgvector 检索 → 引用 → LLM 生成”的端到端链路，并与论文定案保持一致：Embedding 统一采用阿里云百炼 `text-embedding-v4`，向量存储与检索统一由 PostgreSQL + pgvector 承载（详见 [20-RAG_DATABASE_PGVECTOR_DESIGN.md](./20-RAG_DATABASE_PGVECTOR_DESIGN.md)）。

## 1. 背景与边界

- 本模块定位：`mediask-ai` 仅提供 AI 能力（RAG 问答、流式输出、知识库操作），不承载业务事务。
- 上游：Java 后端通过 HTTP 调用。
- 下游：LLM（DeepSeek / OpenAI 兼容 API）+ PostgreSQL + pgvector（向量检索与关系存储统一实例）。
- 约束：医疗场景必须“谨慎、可追溯、最小化采集”，并具备降级与审计能力。

## 2. 落地方式（以文档为准，避免被“目录结构”卡住）

本仓库的文档给出了一套推荐的 AI 服务目录结构（见 `docs/10-PYTHON_AI_SERVICE.md`）。实际代码若已存在不同目录组织方式，**只要能力与接口契约一致即可**，不要求完全同名同路径。

建议把需要实现的“能力缺口”拆成 2 类：
- **知识库入库**：文档解析/清洗 → 分块 → embedding → 写入 PostgreSQL `knowledge_chunk_index`（pgvector 向量 + tsvector 关键词索引）。
- **检索器**：query embedding → pgvector 向量检索 + tsvector 关键词检索 → RRF 融合 → 阈值过滤/重排 → 结构化返回（供 citations，结果写入 `ai_run_citation`）。

## 3. 核心目标（验收口径）

### 3.1 功能验收
- `/api/v1/knowledge/ingest`：支持 Markdown/PDF 入库（至少文本入库可用），完成分块、向量化、写入 PostgreSQL `knowledge_chunk_index`。
- `/api/v1/knowledge/search`：能检索返回 top_k chunks（含 score、metadata）。
- `/api/v1/chat`：`use_rag=true` 时返回 `answer + citations`（可追溯到 doc/page/section）。
- `/api/v1/chat/stream`：流式输出稳定；出现异常时输出 `error` 事件；结束输出 `end`。

### 3.2 质量验收
- 相关性：引入 `RAG_SCORE_THRESHOLD` 做基础过滤，避免硬塞无关上下文。
- 安全：输入侧 PII 脱敏、风险分级、拒答策略、强制免责声明；审计字段可追踪 `trace_id/session_id`。
- 可靠性：PostgreSQL 向量检索/LLM 任一不可用时可降级（例如检索失败则退化为无 RAG 的谨慎回答）。

## 4. 分阶段实施（从 MVP 到可用）

### 阶段 0：目标固化与验收样例（1 天）
- 输出 1 页 spec：输入/输出格式、边界与禁止项、引用字段、降级策略、审计字段。
- 建立最小“黄金问答集”（20 条）：用于后续对比检索与 prompt 调参效果。

### 阶段 1：RAG MVP（2–4 天，优先端到端跑通）

#### 1) 抽象能力边界（Embedding / Loader / VectorStore）
Embedding 供应商已确定为阿里云百炼，但仍建议保留清晰接口边界，避免与上层流程耦合：
- `EmbeddingClient.embed_texts(texts) -> vectors`
- `DocumentLoader.load_markdown/load_pdf -> (text, metadata)`
- `VectorStore.upsert/search`（封装 psycopg + pgvector）

建议默认方案（按你的约束取舍）：
- **远程 Embedding 固定为百炼**：统一使用 `text-embedding-v4`。
- **不再考虑本地部署**：移除本地小模型主线与切换策略，减少实现分叉。
- **调用前先脱敏与审计**：请求前做 PII 脱敏，调用后记录关键审计字段。

#### 2) 入库：Markdown / PDF → 分块 → Embedding → PostgreSQL
落地点：`app/services/knowledge_store.py`
- 文档清洗：统一空白、去噪、保留标题层级信息到 metadata。
- 分块策略：`chunk_size=800~1200`、`overlap=100~200`（以字符或 token 近似均可，MVP 先按字符）。
- 元数据：`doc_id/source/chunk_id/page/section/title/category/created_at`（用于引用与过滤）。
- 写入 PostgreSQL `knowledge_chunk_index`：每个 chunk 一条记录（chunk_id + embedding VECTOR(1536) + tsvector + metadata）。

#### 3) 检索：Query Embedding → pgvector Search → 过滤 → RetrievalResult
落地点：`app/services/retriever.py`
- `top_k`：默认 5（与 API 一致）。
- `score_threshold`：低于阈值的 chunk 过滤掉，防止上下文污染。
- 返回：`RetrievalResult(content, source, score, metadata)`（供 citations 使用）。
- 检索命中结果写入 `ai_run_citation`（run_id, chunk_id, rank, score, used_in_answer）。

#### 4) RAG Pipeline 串联与降级
落地点：`app/services/rag_pipeline.py`
- 检索失败或无结果：自动降级为无 RAG 的 LLM 回复（并打日志 + 审计字段体现“是否降级”）。
- citations：引用 snippet 建议按句子截断并携带 `page/section`，增强答辩“可追溯”观感。

### 阶段 2：演示增强与质量提升（3–6 天）
- Hybrid Retrieval：pgvector 向量检索 + tsvector 关键词检索 → RRF 融合（可先用简单权重公式，再逐步调优）。
- SSE 引用输出：为便于前端展示，建议在流式接口补充 `meta` 事件（携带 citations、session_id、trace_id），或在结束前追加一次结构化引用事件。
- Prompt 规范化：避免免责声明重复（当前既在系统提示里要求，也在输出末尾 append，需统一策略）。
- 输出侧基础脱敏：对模型输出再做一次 PII mask（防止意外泄露）。

### 阶段 3：工程化与可靠性（2–5 天，可并行）
- 可观测性：记录 retrieve/llm 耗时拆分、top score、命中数量、是否降级、模型名等。
- 韧性：PostgreSQL 向量查询超时、异常处理、重试/熔断（至少保证接口快速失败并降级）。
- 测试：mock embedding + mock PostgreSQL；覆盖 chunking、阈值过滤、引用字段（`ai_run_citation`）、拒答与降级路径；接口测试覆盖 SSE。

### 阶段 4：数据与评测闭环（长期）
- 扩充黄金集（50–200 条），每次调整分块/检索/prompt 都跑回归。
- 指标：引用正确率（引用是否支持回答）、拒答正确率、平均延迟、降级比例。

## 5. 配置建议（本地开发 → 线上演示平滑切换）

建议在 `app/config.py` 增补并统一管理（示例字段名，可根据现有命名风格调整）：
- Embedding：
  - `EMBEDDING_PROVIDER=openai_compatible`
  - `EMBEDDING_MODEL=text-embedding-v4`
  - `EMBEDDING_BASE_URL=<阿里百炼兼容端点>`
  - `EMBEDDING_API_KEY=<阿里百炼 API Key>`
- PostgreSQL（Python 直接写入）：
  - `PG_HOST=127.0.0.1`
  - `PG_PORT=5432`
  - `PG_DB=mediask_dev`
  - `PG_USER=postgres`、`PG_PASSWORD=...`
- RAG：
  - `RAG_TOP_K=5`
  - `RAG_SCORE_THRESHOLD=0.2`

环境切换方式：
- 本地：默认读取 `.env.dev`，连接本地 PostgreSQL（`PG_HOST=127.0.0.1`），pgvector 扩展已启用。
- 演示/生产：读取 `.env.prod` 或设置 `APP_ENV=prod` 指向生产 PostgreSQL；Embedding 仍统一走阿里百炼，不区分本地/线上供应商。

## 6. 交付清单（建议顺序）

1) 实现 `KnowledgeStore`：分块 + embedding + PostgreSQL `knowledge_chunk_index` upsert。
2) 实现 `Retriever`：pgvector 向量检索 + tsvector 关键词检索 + 阈值过滤 + 返回结构化结果 + 写入 `ai_run_citation`。
3) 在 `RagPipeline` 中补全降级、引用字段增强与审计字段补充。
4) 补齐 PDF/Markdown loader（先可用后优化）。
5) 增加最小测试与黄金集回归脚本（至少可在答辩前稳定复现效果）。
