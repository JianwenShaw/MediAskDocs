# Python AI 服务配置详解

> 本文档详述 MediAsk Python AI 服务（`mediask-ai`）的所有配置项。
>
> 当前口径：RAG Python 服务的最新接口与边界以 `docs/proposals/rag-python-service-design/` 为准。本文保留旧配置设计参考；涉及 `/health/ready`、`ai_run_citation`、`model_run_id`、降级返回等内容不再作为新的实现依据。
>
> **总纲**请参阅 [03-CONFIGURATION.md](./03-CONFIGURATION.md)。

---

## 1. 配置框架

### 1.1 Pydantic Settings

使用 `pydantic-settings` 实现类型安全的配置管理：

```python
from pydantic_settings import BaseSettings, SettingsConfigDict
from pydantic import Field, field_validator

class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        case_sensitive=True,          # 环境变量区分大小写
        extra="ignore",               # 忽略未定义的环境变量
    )

    # 服务基础
    APP_ENV: str = Field(default="dev", description="运行环境")
    DEBUG: bool = Field(default=False, description="调试模式")
    LOG_LEVEL: str = Field(default="INFO", description="日志级别")
    API_KEY: str = Field(..., description="服务间认证密钥")  # 必填

    # 数据库
    PG_HOST: str = Field(default="localhost")
    PG_PORT: int = Field(default=5432)
    PG_DB: str = Field(default="mediask")
    PG_USER: str = Field(default="mediask")
    PG_PASSWORD: str = Field(..., description="数据库密码")   # 必填

    # Redis
    REDIS_HOST: str = Field(default="localhost")
    REDIS_PORT: int = Field(default=6379)
    REDIS_PASSWORD: str = Field(default="")
    REDIS_DB: int = Field(default=0)
    REDIS_SOCKET_TIMEOUT_SECONDS: int = Field(default=5)
    REDIS_CONNECT_TIMEOUT_SECONDS: int = Field(default=5)
    READY_CACHE_TTL_SECONDS: int = Field(default=15)

    # LLM
    LLM_MODEL: str = Field(default="deepseek-chat")
    LLM_BASE_URL: str = Field(default="https://api.deepseek.com/v1")
    LLM_API_KEY: str = Field(..., description="LLM API 密钥")  # 必填

    # Embedding
    EMBEDDING_PROVIDER: str = Field(default="openai_compatible")
    EMBEDDING_MODEL: str = Field(default="text-embedding-v4")
    EMBEDDING_BASE_URL: str = Field(default="")
    EMBEDDING_API_KEY: str = Field(default="")
    EMBEDDING_DIM: int = Field(default=1536)

    # RAG
    RAG_TOP_K: int = Field(default=5)
    RAG_SCORE_THRESHOLD: float = Field(default=0.2)

    # AI 护栏
    GUARDRAIL_MODE: str = Field(default="normal")

    @field_validator("APP_ENV")
    @classmethod
    def validate_env(cls, v: str) -> str:
        if v not in ("dev", "test", "staging", "prod"):
            raise ValueError(f"APP_ENV must be one of: dev, test, staging, prod. Got: {v}")
        return v

    @field_validator("EMBEDDING_PROVIDER")
    @classmethod
    def validate_embedding_provider(cls, v: str) -> str:
        if v not in ("openai_compatible", "none"):
            raise ValueError(f"EMBEDDING_PROVIDER must be: openai_compatible | none. Got: {v}")
        return v

    @field_validator("GUARDRAIL_MODE")
    @classmethod
    def validate_guardrail_mode(cls, v: str) -> str:
        if v not in ("normal", "strict"):
            raise ValueError(f"GUARDRAIL_MODE must be: normal | strict. Got: {v}")
        return v
```

### 1.2 配置加载优先级

从高到低：

1. 操作系统环境变量
2. `ENV_FILE` 指定的文件
3. `.env.{APP_ENV}` 文件
4. `.env.dev` 文件（fallback）
5. `.env` 文件
6. 代码中的 `Field(default=...)` 默认值

```python
import os

def _resolve_env_file() -> str:
    """解析 .env 文件路径"""
    explicit = os.getenv("ENV_FILE")
    if explicit:
        return explicit

    app_env = os.getenv("APP_ENV", "dev")
    env_file = f".env.{app_env}"

    if os.path.exists(env_file):
        return env_file
    if os.path.exists(".env.dev"):
        return ".env.dev"
    return ".env"

settings = Settings(_env_file=_resolve_env_file())
```

---

## 2. 配置文件结构

```
mediask-ai/
├── .env.example          # 模板（提交到 Git）
├── .env                  # 本地 fallback（不提交）
├── .env.dev              # 开发环境（不提交）
├── .env.test             # 测试环境（不提交）
├── .env.staging          # 预发布环境（不提交）
├── .env.prod             # 生产环境（不提交）
├── .gitignore            # 排除 .env*（保留 .env.example）
└── app/
    └── core/
        └── settings.py   # Pydantic Settings 定义
```

### .gitignore 规则

```gitignore
# 环境配置文件
.env
.env.*
!.env.example
```

---

## 3. 服务基础配置

### 3.1 环境与调试

| 环境变量 | 类型 | 默认值 | 必填 | 说明 |
|----------|------|--------|------|------|
| `APP_ENV` | string | `dev` | — | 运行环境：`dev` / `test` / `staging` / `prod` |
| `DEBUG` | bool | `false` | — | 调试模式（开启详细日志、错误堆栈） |
| `LOG_LEVEL` | string | `INFO` | — | 日志级别：`DEBUG` / `INFO` / `WARNING` / `ERROR` |
| `API_KEY` | string | — | **是** | 服务间认证密钥（Java 通过 `X-API-Key` 传入） |
| `HOST` | string | `127.0.0.1` | — | 服务绑定地址 |
| `PORT` | int | `8000` | — | 服务绑定端口 |

### 3.2 启动命令

```bash
# 开发环境
APP_ENV=dev uvicorn app.main:app --host 127.0.0.1 --port 8000 --reload

# 生产环境
APP_ENV=prod uvicorn app.main:app --host 0.0.0.0 --port 8000 \
    --workers 4 --loop uvloop --http httptools \
    --access-log --log-level info
```

**Makefile 封装**：

```makefile
.PHONY: dev run test lint clean

dev:
	APP_ENV=dev uvicorn app.main:app --host 127.0.0.1 --port 8000 --reload

run:
	APP_ENV=prod uvicorn app.main:app --host 0.0.0.0 --port 8000 --workers 4

test:
	APP_ENV=test pytest tests/ -v --tb=short

lint:
	ruff check . && ruff format --check .

clean:
	find . -type d -name "__pycache__" -exec rm -rf {} +
	find . -type f -name "*.pyc" -delete
```

---

## 4. 数据库配置

### 4.1 PostgreSQL（psycopg 异步驱动）

| 环境变量 | 类型 | 默认值 | 必填 | 密钥级别 |
|----------|------|--------|------|---------|
| `PG_HOST` | string | `localhost` | prod 必填 | — |
| `PG_PORT` | int | `5432` | — | — |
| `PG_DB` | string | `mediask` | — | — |
| `PG_USER` | string | `mediask` | — | — |
| `PG_PASSWORD` | string | — | **是** | L1 |

### 4.2 连接池配置

```python
import psycopg_pool

pool = psycopg_pool.AsyncConnectionPool(
    conninfo=f"host={settings.PG_HOST} port={settings.PG_PORT} "
             f"dbname={settings.PG_DB} user={settings.PG_USER} "
             f"password={settings.PG_PASSWORD}",
    min_size=2,           # 最小连接数
    max_size=10,          # 最大连接数
    max_idle=300,         # 空闲连接最大存活秒数
    max_lifetime=3600,    # 连接最大存活秒数
    timeout=30,           # 获取连接超时秒数
)
```

### 4.3 数据写入权限

Python AI 服务的 DB 用户应配置以下权限：

```sql
-- 只读权限：所有业务表
GRANT SELECT ON ALL TABLES IN SCHEMA public TO mediask_ai;

-- 读写权限：仅 Python 管理的表
GRANT SELECT, INSERT, UPDATE, DELETE ON knowledge_chunk_index TO mediask_ai;
GRANT SELECT, INSERT, UPDATE, DELETE ON ai_run_citation TO mediask_ai;

-- Sequence 权限
GRANT USAGE ON ALL SEQUENCES IN SCHEMA public TO mediask_ai;
```

---

## 5. Redis 配置

| 环境变量 | 类型 | 默认值 | 必填 | 说明 |
|----------|------|--------|------|------|
| `REDIS_HOST` | string | `localhost` | prod 必填 | Redis 主机 |
| `REDIS_PORT` | int | `6379` | — | Redis 端口 |
| `REDIS_PASSWORD` | string | `""` | prod 必填 | Redis 密码 |
| `REDIS_DB` | int | `0` | — | Redis 数据库编号 |
| `REDIS_SOCKET_TIMEOUT_SECONDS` | int | `5` | — | Socket 超时 |
| `REDIS_CONNECT_TIMEOUT_SECONDS` | int | `5` | — | 连接超时 |
| `READY_CACHE_TTL_SECONDS` | int | `15` | — | 就绪缓存 TTL |

```python
import redis.asyncio as aioredis

redis_client = aioredis.Redis(
    host=settings.REDIS_HOST,
    port=settings.REDIS_PORT,
    password=settings.REDIS_PASSWORD or None,
    db=settings.REDIS_DB,
    socket_timeout=settings.REDIS_SOCKET_TIMEOUT_SECONDS,
    socket_connect_timeout=settings.REDIS_CONNECT_TIMEOUT_SECONDS,
    decode_responses=True,
)
```

---

## 6. LLM 配置

### 6.1 模型提供者

| 环境变量 | 类型 | 默认值 | 必填 | 密钥级别 |
|----------|------|--------|------|---------|
| `LLM_MODEL` | string | `deepseek-chat` | — | — |
| `LLM_BASE_URL` | string | `https://api.deepseek.com/v1` | — | — |
| `LLM_API_KEY` | string | — | **是** | L2 |

### 6.2 调用参数

| 参数 | 默认值 | 说明 |
|------|--------|------|
| `temperature` | `0.3` | 生成温度（医疗场景需要低随机性） |
| `max_tokens` | `2048` | 单次最大生成 token 数 |
| `timeout` | `60s` | 单次 LLM 调用超时 |
| `retry_attempts` | `2` | LLM 调用失败重试次数 |
| `retry_backoff` | `1s` | 重试退避时间 |

### 6.3 降级策略

当 LLM API 不可用时：
1. 重试 `retry_attempts` 次
2. 全部失败后返回固定降级响应："AI 服务暂时不可用，请稍后重试"
3. 在 `ai_model_run` 中标记 `is_degraded = true`
4. 触发告警（通过日志 + 指标）

---

## 7. Embedding 配置

### 7.1 Embedding 提供者

| 环境变量 | 类型 | 默认值 | 必填 | 密钥级别 |
|----------|------|--------|------|---------|
| `EMBEDDING_PROVIDER` | string | `openai_compatible` | — | — |
| `EMBEDDING_MODEL` | string | `text-embedding-v4` | — | — |
| `EMBEDDING_BASE_URL` | string | — | provider=openai_compatible 时必填 | — |
| `EMBEDDING_API_KEY` | string | — | provider=openai_compatible 时必填 | L2 |
| `EMBEDDING_DIM` | int | `1536` | — | — |

### 7.2 Provider 行为

| `EMBEDDING_PROVIDER` | 行为 |
|----------------------|------|
| `openai_compatible` | 使用 OpenAI 兼容 API 进行向量化（百炼 text-embedding-v4） |
| `none` | **禁用向量检索**，所有 RAG 相关功能退化为纯 LLM 对话 |

### 7.3 降级策略

当 Embedding API 不可用时：
1. 重试 2 次
2. 全部失败后跳过向量检索，使用纯 LLM 生成（无 RAG 上下文）
3. 在响应元数据中标记 `is_degraded = true`
4. 日志记录降级原因

---

## 8. RAG 配置

| 环境变量 | 类型 | 默认值 | 说明 |
|----------|------|--------|------|
| `RAG_TOP_K` | int | `5` | 向量检索返回的最相似 chunk 数量 |
| `RAG_SCORE_THRESHOLD` | float | `0.2` | 向量相似度阈值（低于此值的 chunk 被过滤） |

### RAG Pipeline 参数（代码内配置）

| 参数 | 默认值 | 说明 |
|------|--------|------|
| `chunk_size` | `512` tokens | 文档分块大小 |
| `chunk_overlap` | `64` tokens | 分块重叠 |
| `rerank_enabled` | `false` | 是否启用重排序（P2 特性） |
| `hybrid_search_weight` | `0.7` | 混合检索中向量权重（0.7 向量 + 0.3 关键词） |

---

## 9. AI 护栏配置

### 9.1 基础配置

| 环境变量 | 类型 | 默认值 | 说明 |
|----------|------|--------|------|
| `GUARDRAIL_MODE` | string | `normal` | 护栏模式：`normal` / `strict` |

### 9.2 模式差异

| 特性 | `normal` | `strict` |
|------|----------|----------|
| PII 检测 | 关键字段（身份证、手机号） | 全量字段（含地址、邮箱、银行卡） |
| 风险分类阈值 | 高风险才拒绝 | 中风险即拒绝 |
| 医疗免责声明 | 追加在回答末尾 | 追加在回答末尾 + 每段强调 |
| 输出 PII 回扫 | 开启 | 开启 + 更严格的模式匹配 |

### 9.3 护栏规则配置

护栏规则以 JSON 格式管理，存储在配置文件或数据库中：

```json
{
  "version": "1.0",
  "rules": [
    {
      "id": "RISK_001",
      "level": "high",
      "action": "refuse",
      "category": "suicide_self_harm",
      "keywords": ["自杀", "自残", "轻生"],
      "response_template": "您的问题涉及紧急情况，请立即拨打急救电话 120 或心理危机热线。"
    },
    {
      "id": "PII_001",
      "level": "medium",
      "action": "desensitize",
      "category": "pii_detection",
      "patterns": [
        {"type": "phone", "regex": "1[3-9]\\d{9}", "mask": "****"},
        {"type": "id_card", "regex": "\\d{17}[\\dXx]", "mask": "****"}
      ]
    }
  ]
}
```

---

## 10. 请求上下文与日志配置

### 10.1 Request Context 中间件

```python
from starlette.middleware.base import BaseHTTPMiddleware
from uuid import uuid4

class RequestContextMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request, call_next):
        # 从请求头读取或生成
        request_id = (
            request.headers.get("X-Request-Id")
            or request.headers.get("X-Trace-Id")  # deprecated alias
            or str(uuid4())
        )

        # 注入到请求 state（供下游使用）
        request.state.request_id = request_id

        # 注入到日志上下文
        # structlog.contextvars.bind_contextvars(request_id=request_id)

        response = await call_next(request)

        # 写入响应头
        response.headers["X-Request-Id"] = request_id
        return response
```

### 10.2 日志格式

```python
import structlog

structlog.configure(
    processors=[
        structlog.contextvars.merge_contextvars,
        structlog.processors.add_log_level,
        structlog.processors.TimeStamper(fmt="iso"),
        structlog.processors.JSONRenderer(),          # 生产环境 JSON
    ],
)
```

生产环境日志输出示例：

```json
{
  "timestamp": "2026-03-11T10:30:00.123+08:00",
  "level": "info",
  "event": "RAG 检索完成",
  "request_id": "req_01hrx6m5q4x5v2f6k4w4x1c7pz",
  "session_id": "sess-456",
  "top_k": 5,
  "results_count": 3,
  "latency_ms": 42
}
```

---

## 11. 健康检查

### 11.1 端点定义

```python
@app.get("/health")
async def health_check():
    """基础健康检查（无依赖检查）"""
    return {"status": "ok", "service": "mediask-ai", "env": settings.APP_ENV}

@app.get("/health/ready")
async def readiness_check():
    """就绪检查（含依赖项连通性验证）"""
    checks = {}

    # PostgreSQL
    try:
        async with pool.connection() as conn:
            await conn.execute("SELECT 1")
        checks["postgresql"] = "ok"
    except Exception as e:
        checks["postgresql"] = f"error: {str(e)}"

    # Redis
    try:
        await redis_client.ping()
        checks["redis"] = "ok"
    except Exception as e:
        checks["redis"] = f"error: {str(e)}"

    # Embedding API（仅在启用时检查）
    if settings.EMBEDDING_PROVIDER != "none":
        try:
            # 简单的 Embedding 调用测试
            checks["embedding"] = "ok"
        except Exception as e:
            checks["embedding"] = f"degraded: {str(e)}"

    all_ok = all(v == "ok" for k, v in checks.items() if k in ("postgresql", "redis"))
    status_code = 200 if all_ok else 503

    return JSONResponse(
        status_code=status_code,
        content={"status": "ready" if all_ok else "not_ready", "checks": checks},
    )
```

---

## 12. 配置项完整注册表

### 12.1 服务基础

| 环境变量 | 类型 | 默认值 | 必填 | 密钥级别 | 说明 |
|----------|------|--------|------|---------|------|
| `APP_ENV` | string | `dev` | — | — | 运行环境 |
| `DEBUG` | bool | `false` | — | — | 调试模式 |
| `LOG_LEVEL` | string | `INFO` | — | — | 日志级别 |
| `API_KEY` | string | — | **是** | L2 | 服务间认证密钥 |
| `HOST` | string | `127.0.0.1` | — | — | 绑定地址 |
| `PORT` | int | `8000` | — | — | 绑定端口 |

### 12.2 数据库

| 环境变量 | 类型 | 默认值 | 必填 | 密钥级别 |
|----------|------|--------|------|---------|
| `PG_HOST` | string | `localhost` | prod 必填 | — |
| `PG_PORT` | int | `5432` | — | — |
| `PG_DB` | string | `mediask` | — | — |
| `PG_USER` | string | `mediask` | — | — |
| `PG_PASSWORD` | string | — | **是** | L1 |

### 12.3 Redis

| 环境变量 | 类型 | 默认值 | 必填 | 密钥级别 |
|----------|------|--------|------|---------|
| `REDIS_HOST` | string | `localhost` | prod 必填 | — |
| `REDIS_PORT` | int | `6379` | — | — |
| `REDIS_PASSWORD` | string | `""` | prod 必填 | L3 |
| `REDIS_DB` | int | `0` | — | — |
| `REDIS_SOCKET_TIMEOUT_SECONDS` | int | `5` | — | — |
| `REDIS_CONNECT_TIMEOUT_SECONDS` | int | `5` | — | — |
| `READY_CACHE_TTL_SECONDS` | int | `15` | — | — |

### 12.4 LLM

| 环境变量 | 类型 | 默认值 | 必填 | 密钥级别 |
|----------|------|--------|------|---------|
| `LLM_MODEL` | string | `deepseek-chat` | — | — |
| `LLM_BASE_URL` | string | `https://api.deepseek.com/v1` | — | — |
| `LLM_API_KEY` | string | — | **是** | L2 |

### 12.5 Embedding

| 环境变量 | 类型 | 默认值 | 必填 | 密钥级别 |
|----------|------|--------|------|---------|
| `EMBEDDING_PROVIDER` | string | `openai_compatible` | — | — |
| `EMBEDDING_MODEL` | string | `text-embedding-v4` | — | — |
| `EMBEDDING_BASE_URL` | string | — | provider=openai_compatible 时 | — |
| `EMBEDDING_API_KEY` | string | — | provider=openai_compatible 时 | L2 |
| `EMBEDDING_DIM` | int | `1536` | — | — |

### 12.6 RAG

| 环境变量 | 类型 | 默认值 | 必填 | 说明 |
|----------|------|--------|------|------|
| `RAG_TOP_K` | int | `5` | — | 检索返回 top-k |
| `RAG_SCORE_THRESHOLD` | float | `0.2` | — | 相似度阈值 |

### 12.7 AI 护栏

| 环境变量 | 类型 | 默认值 | 必填 | 说明 |
|----------|------|--------|------|------|
| `GUARDRAIL_MODE` | string | `normal` | — | 护栏模式 |

---

## 13. .env.example 模板

```bash
# ============================================================
# MediAsk AI Service 配置模板
# 复制为 .env.dev / .env.prod 后填入实际值
# ============================================================

# ---- 服务基础 ----
APP_ENV=dev
DEBUG=false
LOG_LEVEL=INFO
API_KEY=                           # [L2] 必填，与 Java 端 MEDIASK_AI_API_KEY 一致

# ---- 数据库 ----
PG_HOST=localhost
PG_PORT=5432
PG_DB=mediask
PG_USER=mediask_ai
PG_PASSWORD=                       # [L1] 必填

# ---- Redis ----
REDIS_HOST=localhost
REDIS_PORT=6379
REDIS_PASSWORD=                    # [L3] 生产必填
REDIS_DB=0

# ---- LLM ----
LLM_MODEL=deepseek-chat
LLM_BASE_URL=https://api.deepseek.com/v1
LLM_API_KEY=                       # [L2] 必填

# ---- Embedding ----
EMBEDDING_PROVIDER=openai_compatible  # openai_compatible | none
EMBEDDING_MODEL=text-embedding-v4
EMBEDDING_BASE_URL=
EMBEDDING_API_KEY=                 # [L2] provider=openai_compatible 时必填
EMBEDDING_DIM=1536

# ---- RAG ----
RAG_TOP_K=5
RAG_SCORE_THRESHOLD=0.2

# ---- AI 护栏 ----
GUARDRAIL_MODE=normal              # normal | strict
```

---

## 14. 相关文档

| 文档 | 说明 |
|------|------|
| [03-CONFIGURATION.md](./03-CONFIGURATION.md) | 配置管理总纲 |
| [03A-JAVA_CONFIG.md](./03A-JAVA_CONFIG.md) | Java 后端配置 |
| [03C-INFRASTRUCTURE_CONFIG.md](./03C-INFRASTRUCTURE_CONFIG.md) | 基础设施配置 |
| [10-PYTHON_AI_SERVICE.md](./10-PYTHON_AI_SERVICE.md) | Python AI 服务架构设计 |
| [11-AI_GUARDRAILS_PLAN.md](./11-AI_GUARDRAILS_PLAN.md) | AI 安全护栏设计 |
| [12-AI_RAG_IMPLEMENTATION_PLAN.md](./12-AI_RAG_IMPLEMENTATION_PLAN.md) | RAG 实现方案 |
| [20-RAG_DATABASE_PGVECTOR_DESIGN.md](./20-RAG_DATABASE_PGVECTOR_DESIGN.md) | RAG 数据库设计 |
