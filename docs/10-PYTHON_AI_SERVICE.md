# MediAsk AI 服务 - Python 模块设计与落地清单

## 1. 定位与边界

mediask-ai 是独立 AI 微服务，只提供 AI 能力，不直接处理业务事务。

- 上游: Java 后端 mediask-be 调用。
- 下游: DeepSeek/兼容 OpenAI API, Milvus 向量库。
- 交互: HTTP JSON + SSE 流式输出。

## 2. 目录结构建议

```
app/
    api/
        v1/
            chat.py              # /api/v1/chat
            knowledge.py         # /api/v1/knowledge
    core/
        settings.py            # Pydantic Settings
        logging.py             # 日志格式与trace_id
    middleware/
        auth.py                # API Key 校验
        trace.py               # 透传X-Trace-Id
    services/
        llm/
            base.py              # LLM 接口
            deepseek.py          # DeepSeek 实现
        rag/
            ingest.py            # 文档入库
            retrieve.py          # 检索
            prompt.py            # Prompt 构造
    schemas/
        chat.py
        knowledge.py
    main.py
```

## 3. 依赖与运行

使用 uv 管理依赖，保持与 [09-PYTHON_ENV.md](./09-PYTHON_ENV.md) 一致。

```toml
[project]
name = "mediask-ai"
version = "0.1.0"
description = "MediAsk AI Service"
requires-python = ">=3.11.14"
dependencies = [
    "fastapi[standard]>=0.128.1",
    "langchain>=1.2.8",
    "langgraph>=1.0.7",
    "openai>=2.17.0",
    "pydantic-settings>=2.0.0",
    "pymilvus>=2.6.8",
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

## 4. 配置项

```bash
# .env
API_KEY=mediask-ai-secret-key
LOG_LEVEL=INFO

LLM_PROVIDER=deepseek
DEEPSEEK_API_KEY=sk-xxx
DEEPSEEK_BASE_URL=https://api.deepseek.com
MODEL_NAME=deepseek-chat
EMBEDDING_MODEL=text-embedding-3-small

MILVUS_URI=http://localhost:19530
MILVUS_USER=
MILVUS_PASSWORD=
VECTOR_COLLECTION=mediask_knowledge
RAG_TOP_K=5
RAG_SCORE_THRESHOLD=0.2

REQUEST_TIMEOUT=30
MAX_TOKENS=1024
TEMPERATURE=0.2
```

## 5. API 设计

### 5.1 健康检查

```
GET /health
```

响应:

```json
{"status":"healthy"}
```

### 5.2 对话接口

```
POST /api/v1/chat
```

请求:

```json
{
    "session_id": "s-123",
    "message": "头痛三天，可能是什么原因？",
    "use_rag": true,
    "stream": false
}
```

响应:

```json
{
    "answer": "...",
    "citations": [
        {"doc_id": "kb-001", "score": 0.82, "snippet": "..."}
    ],
    "trace_id": "t-abc"
}
```

### 5.3 流式对话

```
POST /api/v1/chat/stream
```

返回 SSE, 事件名: message/end/error。使用 FastAPI 的 `StreamingResponse` 手写 SSE 格式，不依赖第三方库。

### 5.4 知识库检索

```
POST /api/v1/knowledge/search
```

请求:

```json
{"query": "高血压饮食注意事项", "top_k": 5}
```

### 5.5 知识库入库

```
POST /api/v1/knowledge/ingest
```

请求:

```json
{
    "source": "markdown",
    "content": "# 诊疗指南...",
    "metadata": {"doc_id": "kb-1001", "category": "guideline"}
}
```

## 6. 认证与安全

- Header: `X-API-Key: <API_KEY>`
- 未通过返回 401: `{"error":"Invalid API Key"}`
- 可选增强: 速率限制、PII 脱敏、敏感词过滤

```python
# app/middleware/auth.py
@app.middleware("http")
async def verify_api_key(request: Request, call_next):
        api_key = request.headers.get("X-API-Key")
        if api_key != settings.API_KEY:
                return JSONResponse(status_code=401, content={"error": "Invalid API Key"})
        return await call_next(request)
```

## 7. RAG 流程

### 7.1 入库流程

1. 文档加载 (Markdown/PDF)
2. 分块 (chunk_size 800-1200, overlap 100-200)
3. 生成向量 (Embedding)
4. 写入 Milvus

### 7.2 查询流程

1. Query 归一化
2. 混合检索 (向量 + 关键词)
3. 结果融合 (RRF)
4. 构造 Prompt
5. 调用 LLM
6. 返回答案 + 引用

## 8. 统一错误与日志

### 8.1 错误格式

```json
{"code": "AI_400", "message": "Bad request", "trace_id": "t-abc"}
```

### 8.2 Trace 透传

- 请求头优先使用 `X-Trace-Id`，若不存在则生成 UUID
- 日志字段包含 `trace_id` 便于链路追踪

## 9. 测试策略

- 单元测试: LLM/RAG 逻辑使用 Mock
- 接口测试: `httpx.AsyncClient` + FastAPI TestClient
- 覆盖率: 关键路径 80%+

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

- [ ] 完善 `pyproject.toml` 依赖
- [ ] 增补 `Makefile` 命令
- [ ] API Key 中间件与 Trace 中间件
- [ ] RAG pipeline 最小可用实现
- [ ] pytest + 基础用例
- [ ] SSE 流式输出与错误事件
