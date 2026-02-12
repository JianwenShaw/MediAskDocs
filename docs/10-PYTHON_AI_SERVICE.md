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

### 4.1 多环境切换规则

加载优先级（从高到低）：
1. `ENV_FILE`：显式指定 env 文件路径（如 `.env.prod`）。
2. `APP_ENV`：自动选择 `.env.{APP_ENV}`，不存在则回退到 `.env`。
3. 默认：若存在 `.env.dev` 则使用 `.env.dev`，否则使用 `.env`。

常用示例：

```bash
# 本地开发（默认）
APP_ENV=dev

# 生产环境
APP_ENV=prod

# 或显式指定
ENV_FILE=.env.prod
```

```bash
# .env.dev (本地默认)
APP_ENV=dev
API_KEY=mediask-ai-secret-key
LOG_LEVEL=INFO

LLM_MODEL=deepseek-chat
LLM_BASE_URL=https://api.deepseek.com/v1
LLM_API_KEY=sk-xxx

EMBEDDING_PROVIDER=none
EMBEDDING_DIM=1536

REDIS_URL=
REDIS_HOST=127.0.0.1
REDIS_PORT=6379
REDIS_DB=0
REDIS_PASSWORD=
REDIS_SOCKET_TIMEOUT_SECONDS=2
REDIS_CONNECT_TIMEOUT_SECONDS=1
READY_CACHE_TTL_SECONDS=15

MILVUS_MODE=lite
MILVUS_LITE_PATH=.milvus/mediask.db
MILVUS_URI=http://localhost:19530
MILVUS_COLLECTION=mediask_knowledge
```

```bash
# .env.prod（生产）
APP_ENV=prod
LOG_LEVEL=INFO
DEBUG=false

MILVUS_MODE=milvus
MILVUS_URI=http://milvus:19530
MILVUS_COLLECTION=mediask_knowledge
```

> `/ready` 会将依赖检查结果缓存到 Redis（默认 TTL=15s），Redis 不可用时会回退到内存缓存；Redis key 采用 `mediask-ai:{业务}:{具体作用}` 命名空间（如 `mediask-ai:health:ready:lite`）。

### 4.2 本地启动与部署

本地开发：

```bash
uv sync
make dev
```

生产/演示环境（示例）：

```bash
# 方式一：环境变量切换
APP_ENV=prod make run

# 方式二：显式指定 env 文件
ENV_FILE=.env.prod make run
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

### 5.4 监控指标（Prometheus）

```
GET /metrics
```

响应: Prometheus text/plain 指标格式（包含 readiness 指标）。

### 5.4 Trace ID 规范

本服务支持链路追踪的 Trace ID 透传与生成规则：

- 若请求头包含 `X-Trace-Id`，直接透传并写入日志与响应头。
- 若无 `X-Trace-Id`，但包含 `X-Request-Id`，则使用 `X-Request-Id`。
- 两者都没有时，服务内部生成 UUID v4 作为 `trace_id`。

调用方式建议：

- **直接调用 AI 服务**：调用方可自行生成并传入 `X-Trace-Id`；否则服务会自动生成。
- **经 Spring Boot 服务转发**：Spring Boot 生成并透传 `X-Trace-Id`，保证全链路一致。

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
