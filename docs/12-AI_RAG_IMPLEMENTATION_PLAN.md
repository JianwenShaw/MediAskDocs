# RAG Python 服务 P0 实施计划

> 当前口径：本文件同步 `docs/proposals/rag-python-service-design/05-execution-plan.md`。后续实现以 `01-authoritative-ddl.md`、`02-integration-contract.md`、`03-java-boundary-and-owned-data.md`、`04-postgresql-ddl-v1.sql` 为准。

## 1. 背景与边界

- Python 负责 DeepSeek 调用、护栏、状态机收口、生成 `triage_result`、RAG 检索和内部执行事实落库。
- Java 负责业务主数据、Redis 导诊目录发布、调用 Python API、保存业务承接结果。
- Frontend 只根据同步响应或 SSE `final` 事件里的 `triage_result` 驱动跳页。

不再作为 P0 实现依据：

- 旧 `/api/v1/chat`。
- 旧 `/api/v1/knowledge/prepare`、`/api/v1/knowledge/index`、`/api/v1/knowledge/search`。
- Java 读取 Python 内部 AI/RAG 表。
- 伪流式文本驱动业务状态。
- 从自然语言回答反解析推荐科室或风险状态。

## 2. 当前仓库基线

已有：

- FastAPI 应用入口。
- `RequestContextMiddleware`。
- `POST /api/v1/query` 路由骨架。
- `POST /api/v1/query/stream` 路由骨架。
- `app/schemas/query.py` 冻结 DTO。
- query 专用错误响应结构。
- `app/db.py` psycopg 连接、事务上下文、`/ready` DB ping。
- `app/repositories/query.py`、`app/repositories/knowledge.py` 薄 SQL 仓储函数。
- `docs/sql/20-rag-postgresql-ddl-v1.sql`。

仍缺：

- Redis 导诊目录读取。
- Query workflow。
- DeepSeek 调用。
- 护栏与状态机收口。
- RAG 检索。
- 结构化结果落库主流程。
- 真实 SSE 流式事件。
- 覆盖新协议的端到端测试。

## 3. 实施原则

- 只实现冻结文档明确要求的能力。
- 不恢复旧 `/api/v1/chat` 口径。
- 不恢复旧 `knowledge/*` 口径。
- 不新增依赖。
- 不让 Java 读取 Python 内部表。
- 不从自然语言文本反解析业务状态。
- 不把最终导诊结果塞进 JSON artifact 作为业务真相。
- 不用模型直接决定最终业务状态，Python 必须本地校验并收口。
- 失败时直接返回错误，不向 Java 提交脏结果。

## 4. 分批实施

### 第一批：契约与基础设施收口

已完成：

- `QueryRequest` 固定为 `scene/session_id/hospital_scope/user_message`，必填字段按冻结协议校验。
- `triage_result` 收口为 `COLLECTING/READY/BLOCKED` 三态判别联合。
- `/api/v1/query` 与 `/api/v1/query/stream` validation/AppError 使用 query 错误结构：

```json
{
  "request_id": "req_01",
  "error": {
    "code": "TRIAGE_REQUEST_INVALID",
    "message": "Invalid request: body.user_message"
  }
}
```

- `/ready` 使用 PostgreSQL `SELECT 1` 验证连接。
- 新增最小 DB 层和薄 SQL 仓储函数。

### 第二批：Redis 目录与状态机

- 读取 `triage_catalog:active:{hospital_scope}`。
- 读取 `triage_catalog:{hospital_scope}:{catalog_version}`。
- 实现输入护栏，命中高风险时写 `ai_guardrail_event`。
- 实现本地状态机收口：护栏、目录、模型材料、JSON/schema 校验、目录内科室校验、高风险后处理、最大回合数收口、映射三态结果。
- 第 5 个患者回合不得继续返回 `COLLECTING`。

### 第三批：DeepSeek 调用与模型留痕

- 使用现有 OpenAI 兼容客户端调用 DeepSeek。
- 配置来自 `LLM_MODEL`、`LLM_BASE_URL`、`LLM_API_KEY`。
- 缺少 `LLM_API_KEY` 时显式失败。
- DeepSeek 只生成 `triage_materials`；Python 负责业务状态收口。
- 写入 `ai_model_run`、`ai_run_artifact`。

### 第四批：RAG 检索与 citations

- 读取当前 hospital scope 下可用知识库和发布索引版本。
- 执行向量/关键词/融合检索。
- 写入 `retrieval_hit` 与 `answer_citation`。
- `triage_result.citations` 来自 `answer_citation`。

### 第五批：结构化结果落库与同步接口

- `/api/v1/query` 完整执行一次 workflow。
- 创建或读取 `ai_session`。
- 创建 `ai_turn` 与 `query_run`。
- 根据最终三态写 `query_result_snapshot`。
- `COLLECTING` 写 `query_result_follow_up_question`。
- `READY` 写 `query_result_department`。
- 更新 `ai_turn`、`ai_session`、`query_run.status`。

### 第六批：真实 SSE

- `/api/v1/query/stream` 输出真实 `text/event-stream`。
- 事件固定为 `start/progress/delta/final/error/done`。
- `final` 中的 `triage_result` 是唯一业务真相。
- `delta` 只用于展示自然语言，不驱动业务状态。

### 第七批：端到端测试与联调

- DTO 与错误协议测试。
- Redis 目录缺失、版本缺失、非目录科室测试。
- 第 5 轮强制收口测试。
- 高风险 `BLOCKED` 测试。
- 同步与 SSE 主链路测试。

## 5. 当前验证命令

```bash
uv run python3 -m pytest
uv run ruff check
```

说明：在部分沙箱环境中，直接 `uv run pytest` 可能因为 import path 或 uv cache 权限失败；以本仓库当前验证命令为准。
