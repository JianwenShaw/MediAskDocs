# MediAsk AI 服务 - Python 模块设计与落地清单

> 定位：`mediask-ai` 是 Java 主系统的内部 AI 执行服务。
>
> 当前口径：本文件为重写基线；Python 负责 RAG 检索、LLM 调用、护栏执行、流式输出，以及检索投影/引用追溯写库，不维护业务主事实。
>
> 浏览器经 Java 访问的外部 AI 契约，见 [10A-JAVA_AI_API_CONTRACT.md](./10A-JAVA_AI_API_CONTRACT.md)。

## 1. 定位与边界

`mediask-ai` 只提供 AI 能力，不处理业务事务，不持有患者/挂号/病历等业务主事实。

- 上游：Java 后端 `mediask-be`
- 下游：DeepSeek / OpenAI 兼容 LLM API、阿里百炼 Embedding API、PostgreSQL + pgvector
- 交互：内部 HTTP JSON + SSE

边界冻结如下：

- Java 负责：`ai_session`、`ai_turn`、`ai_turn_content`、`ai_model_run`、`knowledge_base`、`knowledge_document`、`knowledge_chunk`
- Python 负责：原始文档解析、文本清洗、chunk 切分算法、`knowledge_chunk_index`、`ai_run_citation`
- Python 不直接维护业务会话主事实
- AI 输出定位为“辅助问诊、风险提示、建议就医/推荐科室”，不输出诊断结论与处方建议

## 2. 目录结构建议

```text
app/
    api/
        v1/
            chat.py              # /api/v1/chat, /api/v1/chat/stream
            knowledge.py         # /api/v1/knowledge/prepare, /api/v1/knowledge/index, /api/v1/knowledge/search
    core/
        settings.py              # Pydantic Settings
        logging.py               # 结构化日志
        errors.py                # 错误码与异常映射
    middleware/
        auth.py                  # X-API-Key 校验
        request_context.py       # X-Request-Id 透传与日志上下文
    services/
        llm/
            client.py            # OpenAI-compatible LLM client
        rag/
            indexer.py           # knowledge_chunk_index upsert
            retriever.py         # 混合检索 + citations
            pipeline.py          # chat/chat_stream 主流程
            normalize.py         # 术语归一/PII 预处理
    schemas/
        chat.py
        knowledge.py
        common.py
    main.py
```

## 3. 依赖与运行

使用 `uv` 管理依赖，保持与 [09-PYTHON_ENV.md](./09-PYTHON_ENV.md) 一致。

```toml
[project]
name = "mediask-ai"
version = "0.1.0"
description = "MediAsk AI Service"
requires-python = ">=3.11.14"
dependencies = [
    "fastapi[standard]>=0.128.1",
    "openai>=2.17.0",
    "httpx>=0.28.0",
    "pydantic-settings>=2.0.0",
    "psycopg[binary]>=3.2.0",
    "pgvector>=0.3.0",
]

[tool.uv]
dev-dependencies = [
    "pytest>=8.0.0",
    "pytest-asyncio>=0.23.0",
    "httpx>=0.26.0",
    "pytest-cov>=7.0.0",
    "ruff>=0.15.0",
]
```

说明：

- `P0` 不强依赖 LangChain/LangGraph；优先使用轻量、自控的 `Retriever + RagPipeline`
- 如果后续进入 `P1/P2` 需要多步 Agent 编排，再评估是否引入更重的框架

## 4. 配置项

### 4.1 多环境切换规则

加载优先级（从高到低）：

1. `ENV_FILE`
2. `APP_ENV`
3. `.env.dev` / `.env`

```bash
# .env.dev
APP_ENV=dev
API_KEY=mediask-ai-secret-key
LOG_LEVEL=INFO

LLM_MODEL=deepseek-chat
LLM_BASE_URL=https://api.deepseek.com/v1
LLM_API_KEY=sk-xxx

EMBEDDING_PROVIDER=openai_compatible
EMBEDDING_MODEL=text-embedding-v4
EMBEDDING_BASE_URL=<阿里百炼兼容端点>
EMBEDDING_API_KEY=<你的百炼API Key>
EMBEDDING_DIM=1536

PG_HOST=127.0.0.1
PG_PORT=5432
PG_DB=mediask_dev
PG_USER=mediask_ai
PG_PASSWORD=

RAG_TOP_K=5
RAG_VECTOR_TOP_K=30
RAG_KEYWORD_TOP_K=30
RAG_SCORE_THRESHOLD=0.20
READY_CACHE_TTL_SECONDS=15
```

说明：

- Python 数据库账号只需要所有表 `SELECT` 权限，以及 `knowledge_chunk_index`、`ai_run_citation` 的写权限
- `model_run_id` 由 Java 预分配并通过请求显式传入，Python 不自行生成业务运行主键

### 4.2 本地启动与部署

```bash
uv sync
make dev
```

```bash
APP_ENV=prod make run
```

## 5. API 设计

> 这些接口是 **Java → Python 的内部服务契约**，不是浏览器直连接口。

### 5.1 健康检查

```http
GET /health
GET /ready
GET /metrics
```

### 5.2 Request ID 规范

- 若请求头包含 `X-Request-Id`，直接透传
- 若无 `X-Request-Id` 但有兼容旧头 `X-Trace-Id`，接受并规范化为 `request_id`
- 两者都没有时，内部生成 UUID v4
- `request_id` 通过 Header 传递，不作为 `/chat` 请求体必填字段

### 5.3 对话接口

```http
POST /api/v1/chat
```

请求：

Header：

```http
X-Request-Id: req_01hrx6m5q4x5v2f6k4w4x1c7pz
```

```json
{
  "model_run_id": 9001001,
  "turn_id": 8002001,
  "session_uuid": "ai-sess-001",
  "department_id": 101,
  "scene_type": "PRE_CONSULTATION",
  "message": "头痛三天，伴有低烧，应该先看什么科？",
  "context_summary": "患者女性，28岁，无已知慢病",
  "use_rag": true,
  "stream": false
}
```

响应：

```json
{
  "model_run_id": 9001001,
  "provider_run_id": "deepseek-run-abc",
  "answer": "建议尽快线下就医，优先考虑神经内科或发热门诊分诊。",
  "summary": "头痛三天伴低烧，建议线下就医并优先分诊。",
  "citations": [
    {
      "chunk_id": 7003001,
      "retrieval_rank": 1,
      "fusion_score": 0.82,
      "snippet": "持续头痛伴发热应结合感染风险进行线下评估。"
    }
  ],
  "risk_level": "medium",
  "guardrail_action": "caution",
  "matched_rule_codes": ["medical_triage_only"],
  "tokens_input": 502,
  "tokens_output": 168,
  "latency_ms": 1860,
  "is_degraded": false
}
```

说明：`request_id` 由响应头 `X-Request-Id` 回写，不要求重复放入业务响应体。

响应头：

```http
X-Request-Id: req_01hrx6m5q4x5v2f6k4w4x1c7pz
```

### 5.4 流式对话

```http
POST /api/v1/chat/stream
```

SSE 事件：

- `message`：流式文本片段
- `meta`：在结束前返回一次结构化元数据（`citations/risk_level`）；`request_id` 由 Header 串联
- `end`：正常结束
- `error`：异常结束

### 5.5 知识检索

```http
POST /api/v1/knowledge/search
```

请求：

```json
{
  "model_run_id": 9001001,
  "query": "高血压饮食注意事项",
  "top_k": 5,
  "knowledge_base_ids": [1001]
}
```

### 5.6 文档预处理与切块准备

```http
POST /api/v1/knowledge/prepare
```

请求：

```json
{
  "document_id": 6001001,
  "knowledge_base_id": 5001001,
  "source_type": "PDF",
  "source_uri": "oss://mediask/kb/htn-guide-v1.pdf"
}
```

响应：

```json
{
  "document_id": 6001001,
  "chunks": [
    {
      "content": "高血压患者应减少钠盐摄入。",
      "content_preview": "高血压患者应减少钠盐摄入。",
      "page_no": 3,
      "section_title": "生活方式管理",
      "char_start": 1200,
      "char_end": 1238,
      "token_count": 18,
      "citation_label": "高血压指南 / 生活方式管理 / P3"
    }
  ]
}
```

说明：

- Python 负责原始文档解析、清洗、术语归一和 chunk 切分，但不直接写 `knowledge_chunk`
- Java 根据返回的 chunk payload 持久化 `knowledge_chunk`，再进入索引阶段

### 5.7 知识索引

```http
POST /api/v1/knowledge/index
```

请求：

```json
{
  "document_id": 6001001,
  "knowledge_base_id": 5001001,
  "chunks": [
    {
      "chunk_id": 7003001,
      "content": "高血压患者应减少钠盐摄入。",
      "page_no": 3,
      "section_title": "生活方式管理"
    }
  ]
}
```

说明：

- `knowledge_document` 与 `knowledge_chunk` 必须先由 Java 持久化
- Python 只负责为这些稳定 `chunk_id` 生成索引投影

## 6. 认证与安全

- Header：`X-API-Key: <API_KEY>`
- 未通过返回 `401`，失败体统一为 `{code, msg, requestId, timestamp}`，详见 [19-ERROR_EXCEPTION_RESPONSE_DESIGN.md](./19-ERROR_EXCEPTION_RESPONSE_DESIGN.md)
- 强制要求：输入/输出 PII 脱敏、风险分级、拒答策略、审计字段与 `request_id`

## 7. RAG 流程

### 7.1 索引流程

1. Java 创建 `knowledge_document(status=UPLOADED/INGESTING)`
2. Java 调用 Python `/api/v1/knowledge/prepare`
3. Python 完成原始文档解析、清洗与分块，返回 chunk payload
4. Java 写入 `knowledge_chunk`
5. Java 调用 Python `/api/v1/knowledge/index`
6. Python 调用百炼 Embedding
7. Python 写入 `knowledge_chunk_index`

### 7.2 查询流程

1. Java 预创建 `ai_model_run`
2. Java 传入 `model_run_id`
3. Python 做查询归一、PII 预处理
4. Query 向量化
5. pgvector 向量检索 + tsvector 关键词检索
6. RRF 融合与阈值过滤
7. Python 写入 `ai_run_citation(model_run_id, chunk_id, ...)`
8. 调用 LLM
9. 返回 answer + citations + guardrail + run metadata

### 7.3 输出边界

Python 输出应固定在以下范围：

- 症状整理
- 风险提示
- 建议就医
- 推荐科室/就诊方向
- 引用依据

不输出：

- 诊断结论
- 处方建议
- 具体药物剂量

## 8. 统一错误与日志

### 8.1 错误格式

成功响应保持端点自有载荷；失败响应统一返回错误封装：

```json
{"code": 6001, "msg": "AI service unavailable", "requestId": "req_01hrx6m5q4x5v2f6k4w4x1c7pz", "timestamp": 1761234567890}
```

### 8.2 日志要求

- 结构化 JSON 日志
- 必须包含：`request_id`、`model_run_id`、`turn_id`、`latency_ms`、`is_degraded`
- 不记录未脱敏的患者原文

## 9. 测试策略

- 单元测试：`Retriever`、`RagPipeline`、护栏规则、降级路径
- 接口测试：`httpx.AsyncClient`
- 关键覆盖：`model_run_id` 透传、`request_id` 透传、`ai_run_citation` 写入、SSE `meta/end/error`
- 联调覆盖：成功、超时、异常映射、无检索结果降级

## 10. Makefile 约定

```makefile
HOST ?= 127.0.0.1
PORT ?= 8000
APP ?= app.main:app

run:
	uv run uvicorn $(APP) --host $(HOST) --port $(PORT)

dev:
	uv run uvicorn $(APP) --reload --host $(HOST) --port $(PORT)

test:
	uv run pytest -v --cov=app

lint:
	uv run ruff check app/ tests/

clean:
	rm -rf .pytest_cache .coverage .ruff_cache __pycache__
```

## 11. 待办清单

- [ ] `model_run_id` 预创建与回传协议
- [ ] `knowledge/prepare` 返回稳定 chunk payload
- [ ] `knowledge/index` 批量 upsert
- [ ] `ai_run_citation` 写库与幂等
- [ ] `chat/stream` 的 `meta` 事件
- [ ] Java ↔ Python 统一错误响应与 `request_id` 透传
- [ ] 最小黄金问答集
