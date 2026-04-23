# 跨服务接口冻结文档（总纲）

## 1. 文档定位

本文是 Python、Java、前端三方联调接口的**唯一权威来源**。

后续实现、DTO、联调、前端跳页均以本文为准。已有的以下文档作为设计背景参考，但接口口径以本文为最终冻结版：

- `rag-python-service-design/02-integration-contract.md`
- `rag-python-service-design/03-java-boundary-and-owned-data.md`
- `triage-catalog-redis-design.md`
- `ai-triage-state-machine-and-llm-contract.md`

本文拆分为以下子文档：

| 文档 | 内容 |
|------|------|
| `00-interface-overview.md`（本文） | 参与方边界、通信架构、数据所有权、ID 语义、端到端顺序 |
| `01-python-api-contract.md` | Java → Python HTTP API、triage_result、状态机、失败契约 |
| `02-gateway-api-contract.md` | Frontend → Java Gateway API、前端行为冻结 |
| `03-redis-catalog-contract.md` | Redis 导诊目录合同 |

---

## 2. 参与方与边界

### 2.1 三方职责

| 参与方 | 职责 |
|--------|------|
| **Python** | DeepSeek 调用、护栏、状态机收口、生成最终 `triage_result`、读取 Redis 导诊目录 |
| **Java** | 业务主数据、发布 Redis 导诊目录、唯一对外网关（JWT / CORS）、接收并持久化 finalized 结果、导诊结果页与挂号承接 |
| **Frontend** | 展示聊天流和结果页，只根据 `final` 事件或同步响应里的 `triage_result` 跳页 |

### 2.2 通信架构

```
Frontend (port 3000/5173)
    │
    ▼  JWT, /api/v1/ai/triage/*
┌──────────────────────────────────────────┐
│  Java Spring Boot (port 8989)            │
│  网关：CORS / JWT / SSE 透传 / 持久化    │
└───────────────┬──────────────────────────┘
                │  POST /api/v1/query[/stream]
                │  X-Request-Id
                ▼
┌──────────────────────────────────────────┐
│  Python FastAPI (port 8000)              │
│  状态机 / 护栏 / LLM / 结果组装          │
└───────────────┬──────────────────────────┘
                │  Redis READ
                ▼
┌──────────────────────────────────────────┐
│  Redis                                   │
│  triage_catalog:active:{scope}           │
│  triage_catalog:{scope}:{version}        │
└──────────────────────────────────────────┘
```

**前端只与 Java (8989) 通信，不直连 Python。**

### 2.3 明确禁止

- Frontend 从流式 `delta` 文本推断业务状态或推荐科室
- Java 从自然语言反解析科室
- Java 根据 `department_name` 模糊匹配科室 ID
- Java 根据流式文本判断是否进入结果页
- Python 在 query 主链路中实时拉取 Java 内部 HTTP 目录接口（目录从 Redis 读取）

---

## 3. 数据所有权边界

### 3.1 Python 拥有的表

以下表属于 Python RAG 服务内部实现，Java 不得直接读取：

**Session & Generation：**
- `ai_session`
- `ai_turn`
- `query_run`
- `query_result_snapshot`
- `query_result_follow_up_question`
- `query_result_department`
- `ai_model_run`
- `ai_run_artifact`
- `ai_guardrail_event`

**Document & Index：**
- `knowledge_base`
- `knowledge_document`
- `knowledge_chunk`
- `knowledge_chunk_index`

**Publish & Visibility：**
- `knowledge_index_version`
- `ingest_job`
- `knowledge_release`

**Retrieval & Evidence：**
- `retrieval_hit`
- `answer_citation`

### 3.2 Java 拥有的数据

- 科室主数据（departments）
- 排班、挂号、接诊
- 患者业务数据
- 新增：`ai_triage_result`（导诊结果快照）

### 3.3 Java 持久化的 AI 结果字段

Java 收到 Python 返回的 `triage_result` 后，至少持久化以下字段：

| 字段 | 来源 |
|------|------|
| `session_id` | 响应信封 |
| `turn_id` | 响应信封 |
| `query_run_id` | 响应信封 |
| `triage_stage` | `triage_result` |
| `triage_completion_reason` | `triage_result` |
| `next_action` | `triage_result` |
| `risk_level` | `triage_result` |
| `chief_complaint_summary` | `triage_result` |
| `recommended_departments` | `triage_result`（JSONB） |
| `care_advice` | `triage_result` |
| `blocked_reason` | `triage_result` |
| `catalog_version` | `triage_result` |
| `created_at` | 自动生成 |

### 3.4 Java 禁止事项

- 直接查询 Python 的 `ai_*` 表
- 直接查询 Python 的 `knowledge_*` 表
- 直接查询 Python 的 `query_run` / `retrieval_hit` / `answer_citation`
- 根据 Python 数据库里的中间态判断页面流转
- 从 Python 内部表拼接结果页

---

## 4. ID 语义

| ID | 类型 | 生成方 | 说明 |
|----|------|--------|------|
| `session_id` | UUID (string) | Python | 会话标识，首轮由 Python 生成 |
| `turn_id` | UUID (string) | Python | 轮次标识，每轮由 Python 生成 |
| `query_run_id` | UUID (string) | Python | 单次 query 运行标识 |
| `request_id` | varchar(64) | Java（优先）/ Python | 链路追踪 ID，Java 网关传入 `X-Request-Id` |
| `department_id` | bigint | Java（Snowflake） | 科室主键，Python 只引用不生成 |
| `catalog_version` | varchar(64) | Java | 格式 `deptcat-v{YYYYMMDD}-{seq}` |

---

## 5. 端到端顺序

### 5.1 标准流式请求

1. 前端发起 `POST /api/v1/ai/triage/query/stream`（带 JWT）
2. Java 网关校验 JWT，生成 `X-Request-Id`，转发至 Python `POST /api/v1/query/stream`
3. Python 创建 `session_id`、`turn_id`、`query_run_id`
4. Python 发送 `start` 事件
5. Python 完成输入护栏，发送 `progress`
6. Python 读取 Redis 导诊目录，发送 `progress`
7. Python 调用 DeepSeek，完成 `triage_materials`
8. Python 本地校验并做状态机收口
9. Python 发送 `final`（含完整 `triage_result`）
10. Python 发送 `done`
11. Java 根据 `final` 结果持久化，透传给前端
12. 前端根据 `next_action` 驱动页面流转

### 5.2 标准同步请求

1. 前端发起 `POST /api/v1/ai/triage/query`（带 JWT）
2. Java 网关校验 JWT，转发至 Python `POST /api/v1/query`
3. Python 完整执行 query workflow
4. Python 返回 `QueryResponse`（含 `triage_result`）
5. Java 持久化，返回给前端
6. 前端根据 `next_action` 驱动页面流转

---

## 6. 一句话结论

本文把三方协作冻结为唯一链路：

`DeepSeek → Python 校验与状态机 → triage_result → Java 网关承接 → Frontend 跳页`

后续任何实现都不得再回到"文本反解析"和"伪流式驱动业务状态"的旧模式。
