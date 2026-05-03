# MediAsk RAG Python 服务设计与落地清单

> 当前口径：本文件已同步到 `docs/proposals/rag-python-service-design/` 冻结方案。若本文件与该目录下的冻结文档冲突，以冻结文档为准。

## 1. 定位与边界

`mediask-rag` 是 Java 主系统调用的内部 AI 执行服务。浏览器不直连 Python。

- Python 负责：DeepSeek 调用、护栏、状态机收口、生成最终 `triage_result`、读取 Redis 导诊目录、维护 Python 自有 RAG/AI 执行事实表。
- Java 负责：业务主数据、Redis 导诊目录发布、调用 Python API、保存面向业务承接的最终导诊结果快照。
- Frontend 负责：展示聊天流和结果页，只根据同步响应或 SSE `final` 事件中的 `triage_result` 跳页。

明确不再使用旧口径：

- 不再以 `/api/v1/chat` 作为 Python 新问诊接口。
- 不再使用旧 `/api/v1/knowledge/prepare`、`/api/v1/knowledge/index`、`/api/v1/knowledge/search` 作为 P0 接口。
- Java 不读取 Python 内部 `ai_*`、`query_*`、`knowledge_*` 表来驱动页面或业务流转。
- Frontend/Java 不从自然语言文本或流式 `delta` 反解析科室、风险或完成状态。

## 2. 当前代码结构

```text
app/
    api/v1/chat.py          # 当前承载 /api/v1/query 与 /api/v1/query/stream 路由骨架
    core/errors.py          # 通用错误处理 + query 协议错误响应
    core/settings.py        # 环境变量配置
    db.py                   # psycopg 连接、事务上下文、/ready DB ping
    middleware/request_context.py
    repositories/query.py   # query 主链路表的薄 SQL 仓储函数
    repositories/knowledge.py
    schemas/query.py        # 冻结 query DTO 与 triage_result 判别联合
```

约束：

- 不新增依赖；使用现有 `psycopg`，不引入 ORM。
- 仓储函数保持薄 SQL，不创建无意义 manager/service 类。
- 第一批只提供基础设施与契约，不提前实现 Redis、LLM、状态机、RAG workflow。

## 3. 配置项

```bash
LLM_MODEL=deepseek-chat
LLM_BASE_URL=https://api.deepseek.com/v1
LLM_API_KEY=

PG_HOST=127.0.0.1
PG_PORT=5432
PG_DB=mediask_dev
PG_USER=mediask
PG_PASSWORD=

RAG_TOP_K=5
RAG_VECTOR_TOP_K=30
RAG_KEYWORD_TOP_K=30
RAG_SCORE_THRESHOLD=0.20
```

说明：

- 敏感值必须来自环境变量，不写入代码、测试或提交配置。
- `/ready` 使用真实 PostgreSQL `SELECT 1`；`PG_PASSWORD` 为空时返回 `503 {"status":"not_ready"}` 并记录明确日志。
- DeepSeek 配置在第三批 LLM client 中使用；缺少 `LLM_API_KEY` 时主流程应显式失败。

## 4. HTTP API

### 4.1 健康与就绪

```http
GET /health
GET /ready
```

- `/health` 只表示进程存活。
- `/ready` 验证 PostgreSQL 可连接。

### 4.2 Request ID

- 优先读取 `X-Request-Id`。
- 若缺失但存在旧头 `X-Trace-Id`，接受并规范化到 `request_id`。
- 两者都没有时由 Python 生成 UUID。
- 所有响应头回写 `X-Request-Id`。

### 4.3 同步 Query

```http
POST /api/v1/query
```

请求体：

```json
{
  "scene": "AI_TRIAGE",
  "session_id": null,
  "hospital_scope": "default",
  "user_message": "我这两天一直头痛，还想吐"
}
```

成功响应：

```json
{
  "request_id": "req_01",
  "session_id": "82f7a4c2-7784-4d31-9c6e-6c8fbbe8c2cd",
  "turn_id": "4b1eaf1f-3e28-479f-9fb5-f259db73507a",
  "query_run_id": "9e86fc63-15f1-44db-9c07-ef2e5911d69c",
  "triage_result": {
    "triage_stage": "READY",
    "triage_completion_reason": "SUFFICIENT_INFO",
    "next_action": "VIEW_TRIAGE_RESULT",
    "risk_level": "low",
    "chief_complaint_summary": "近两天持续头痛，伴恶心",
    "recommended_departments": [],
    "care_advice": "建议尽快门诊就诊",
    "catalog_version": "deptcat-v20260423-01",
    "citations": []
  }
}
```

### 4.4 SSE Query

```http
POST /api/v1/query/stream
```

事件固定为：

- `start`
- `progress`
- `delta`
- `final`
- `error`
- `done`

强约束：

- 只有 `final.triage_result` 是业务真相。
- `delta` 只用于展示自然语言。
- `delta` 会在 Python 消费上游 LLM 流时实时发出，不等待整段回答完成。
- Python 必须完整组装模型 JSON 并本地校验后再发送 `final`。
- SSE 响应头固定包含 `Cache-Control: no-cache`、`Connection: keep-alive`、`X-Accel-Buffering: no`，避免代理缓冲把真流式变成伪流式。

## 5. `triage_result` 判别联合

`triage_result` 必须是三态判别联合，不允许一个大而松散的可空对象。

### 5.1 `COLLECTING`

- `triage_completion_reason` 固定为 `null`。
- `next_action` 固定为 `CONTINUE_TRIAGE`。
- 必须有 `follow_up_questions`，最多 2 条。
- 不包含 `recommended_departments`、`blocked_reason`。

### 5.2 `READY`

- `triage_completion_reason` 只允许 `SUFFICIENT_INFO` 或 `MAX_TURNS_REACHED`。
- `next_action` 固定为 `VIEW_TRIAGE_RESULT`。
- 必须有 `recommended_departments`，最多 3 条。
- 必须有 `catalog_version`。

### 5.3 `BLOCKED`

- `triage_completion_reason` 固定为 `HIGH_RISK_BLOCKED`。
- `next_action` 支持 `MANUAL_SUPPORT` 和 `EMERGENCY_OFFLINE`。
- `risk_level` 固定为 `high`。
- 必须有 `blocked_reason`。
- `recommended_departments` 固定为空数组。
- 不要求 `catalog_version`。

## 6. 错误响应

`/api/v1/query` 与 `/api/v1/query/stream` 的 HTTP 错误响应固定为：

```json
{
  "request_id": "req_01",
  "error": {
    "code": "TRIAGE_REQUEST_INVALID",
    "message": "Invalid request: body.user_message"
  }
}
```

P0 query 错误码：

- `TRIAGE_REQUEST_INVALID`
- `TRIAGE_CATALOG_ACTIVE_VERSION_MISSING`
- `TRIAGE_CATALOG_VERSION_NOT_FOUND`
- `TRIAGE_CATALOG_DEPARTMENT_INVALID`
- `TRIAGE_MODEL_EMPTY_CONTENT`
- `TRIAGE_MODEL_INVALID_JSON`
- `TRIAGE_MODEL_SCHEMA_INVALID`
- `TRIAGE_STREAM_ASSEMBLY_FAILED`
- `TRIAGE_INTERNAL_ERROR`

非 query 接口可继续使用通用错误结构；Java 对外仍统一包装为 `Result<T>`。

## 7. 数据与仓储边界

Python 自有表包括：

- `ai_session`
- `ai_turn`
- `query_run`
- `query_result_snapshot`
- `query_result_follow_up_question`
- `query_result_department`
- `ai_model_run`
- `ai_guardrail_event`
- `ai_run_artifact`
- `knowledge_base`
- `knowledge_document`
- `knowledge_chunk`
- `knowledge_chunk_index`
- `knowledge_index_version`
- `knowledge_release`
- `retrieval_hit`
- `answer_citation`

这些表只支撑 Python 内部 RAG 主链路、追踪、审计、证据追溯和知识治理。Java 运行时集成只消费 Python HTTP API 返回的最终结构化结果，不读取这些内部表。

## 8. 分批落地

第一批已落地：

- query DTO 与 `triage_result` 三态契约收口。
- query 接口错误响应结构。
- psycopg DB 连接、事务上下文、`/ready` 真实 DB ping。
- query/knowledge 薄 SQL 仓储函数。

后续批次：

1. Redis 导诊目录读取、输入护栏、状态机收口。
2. DeepSeek 调用与模型留痕。
3. RAG 检索与 citations。
4. 结构化结果落库与同步 query workflow。
5. 真实 SSE 流式事件。
6. 端到端测试与联调。
