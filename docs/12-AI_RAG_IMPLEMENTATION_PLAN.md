# AI/RAG 核心模块实现计划（P0 基线版）

> 目标：按重写基线补齐“Java 预创建运行记录 -> Python 检索与生成 -> citations 留痕 -> Java 回填业务落库”的端到端链路。

## 1. 背景与边界

- `mediask-ai` 只负责 AI 执行，不维护业务主事实
- Java 负责 `ai_session/ai_turn/ai_model_run/knowledge_document/knowledge_chunk`
- Python 负责 `knowledge_chunk_index/ai_run_citation`
- 输出定位为辅助问诊、风险提示、建议就医/推荐科室，不输出诊断与处方

## 2. 本轮 P0 聚焦三类能力

- **入库索引能力**：Python 解析原始文档并生成 chunk payload -> Java 持久化 chunk -> Python 生成 embedding -> 写 `knowledge_chunk_index`
- **检索生成能力**：`model_run_id` 预分配 -> 检索 -> 写 `ai_run_citation` -> LLM 生成
- **协议与收口能力**：统一 `request_id`、错误响应、Java 回填与知识入库状态流转

## 3. 验收口径

### 3.1 功能验收

- `/api/v1/knowledge/prepare`：支持原始文档解析、清洗和分块，返回可持久化的 chunk payload
- `/api/v1/knowledge/index`：支持对 Java 已持久化的 chunk 批量建立索引
- `/api/v1/knowledge/search`：能返回 top_k chunks（含 `chunk_id/score/metadata`）
- `/api/v1/chat`：`use_rag=true` 时返回 `answer + citations + risk_level`，并由 Java 回填 `ai_model_run/ai_turn_content/ai_guardrail_event`
- `/api/v1/chat/stream`：稳定输出 `message/meta/end/error`
- 索引成功后，只有 Java 显式确认后才能把 `knowledge_document` 更新为可用状态；索引失败必须保留重试入口

### 3.2 质量验收

- `model_run_id` 全链路透传
- `request_id` 通过 `X-Request-Id` 全链路透传；`X-Trace-Id` 仅兼容，不再作为新协议字段
- Python 失败响应统一为 `code/msg/requestId/timestamp`，Java Client 完成稳定映射
- `ai_run_citation` 可外键到 `ai_model_run`
- `ai_run_citation` 写入具备幂等性，避免流式重试产生重复引用
- 引入 `RAG_SCORE_THRESHOLD`，避免硬塞无关上下文
- 检索失败时可降级为无 RAG 的保守辅助回答
- 日志必须包含 `request_id/model_run_id/turn_id/latency_ms/is_degraded`，且不记录未脱敏原文

### 3.3 P0 联调验收

- 按同一 `request_id` 能在 Java、Python、审计记录中串起一次完整请求
- AI 原文、病历正文等高敏读取路径经过对象级授权，并写入 `data_access_log`
- AI 输出摘要/建议可进入挂号、接诊链路，不要求在本计划内扩展更多 AI 工作台功能

## 4. 分阶段实施

### 阶段 0：冻结协议（0.5-1 天）

- 确认 `chat/chat_stream` 请求体字段：`model_run_id/turn_id/session_uuid`，并通过 Header 透传 `X-Request-Id`
- 确认 `ai_run_citation` 字段：`model_run_id/chunk_id/retrieval_rank/*score`
- 冻结 Python 失败响应：`code/msg/requestId/timestamp`
- 明确知识入库 ownership：Java 维护 `knowledge_document/chunk`，Python 只维护 `knowledge_chunk_index/ai_run_citation`
- 明确解析边界：Python 负责解析与切块算法，Java 负责 chunk 业务落库
- 明确输出边界：不诊断、不处方

### 阶段 1：预处理与索引 MVP（1-2 天）

- 实现 `KnowledgePrepareService`
- 输入：`document_id + knowledge_base_id + source_uri/source_type`
- 输出：稳定 chunk payload
- Java 基于 payload 持久化 `knowledge_chunk`
- 实现 `KnowledgeIndexer`
- 输入：`document_id + knowledge_base_id`
- 输出：`knowledge_chunk_index` upsert
- 幂等键：`chunk_id`
- Python 根据 `document_id` 自行读取已持久化的 `knowledge_chunk`
- Java 在索引成功后更新 `knowledge_document` 可用状态；解析或索引失败均禁止误标为可用
- 预留失败重试与重建索引入口

### 阶段 2：检索 MVP（1-2 天）

- 实现 `Retriever`
- pgvector 向量召回 + tsvector 关键词召回
- RRF 融合
- 写入 `ai_run_citation(model_run_id, chunk_id, retrieval_rank, ...)`
- 加入阈值过滤与无结果降级路径

### 阶段 3：生成与护栏（1-2 天）

- 实现 `RagPipeline`
- 接入 LLM
- 接入基础护栏与免责声明
- 返回 `answer/summary/citations/risk_level/guardrail_action`
- Java 回填 `ai_model_run`、`ai_turn_content`、`ai_guardrail_event`
- 明确超时、模型不可用、检索失败三类降级分支

### 阶段 4：治理与可观测性（1-2 天）

- SSE `meta/end/error`
- Java -> Python `X-Request-Id` 透传与响应头回写
- 检索/生成耗时拆分日志
- Java Client 错误映射（成功/超时/异常/降级）
- AI 原文访问审计与对象级授权用例

### 阶段 5：质量与演示收口（1-2 天）

- mock embedding / mock PostgreSQL 测试
- 黄金问答集回归
- 随机抽样验证 `request_id` 跨服务串联
- 与 P0 主链路联调：AI 导诊/摘要结果可进入挂号与接诊演示

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

1. `knowledge/prepare` + `knowledge/index` + 文档状态流转
2. `knowledge/search` + `ai_run_citation`
3. `chat` + Java 回填
4. `chat/stream` + 错误契约 + `request_id`
5. 审计/观测补齐 + 黄金集与回归脚本
