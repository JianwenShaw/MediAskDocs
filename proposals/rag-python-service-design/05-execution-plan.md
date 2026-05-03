# RAG Python 服务 P0 执行计划

## 1. 文档定位

本文基于以下冻结文档制定 P0 实施计划：

- `01-authoritative-ddl.md`
- `02-integration-contract.md`
- `03-java-boundary-and-owned-data.md`
- `04-postgresql-ddl-v1.sql`

后续 Python RAG 服务实现以这四份文档为准。

旧的 `/api/v1/chat`、旧 `knowledge/*` 接口、Java 读取 Python 内部 AI 表、伪流式驱动业务状态等设计，不再作为新的实现依据。

## 2. 当前仓库基线

当前仓库已有：

- FastAPI 应用入口
- `RequestContextMiddleware`
- 统一错误处理基础
- `POST /api/v1/query` 路由骨架
- `POST /api/v1/query/stream` 路由骨架
- `app/schemas/query.py` 中的初版 DTO
- `docs/sql/20-rag-postgresql-ddl-v1.sql`

当前仍缺：

- 真实数据库访问层
- Redis 导诊目录读取
- Query workflow
- DeepSeek 调用
- 护栏与状态机收口
- RAG 检索
- 结构化结果落库
- 真实 SSE 流式事件
- 覆盖新协议的测试

## 3. 实施原则

- 只实现 P0 文档明确要求的能力。
- 不恢复旧 `/api/v1/chat` 口径。
- 不恢复旧 `knowledge/prepare`、`knowledge/index`、`knowledge/search` 口径。
- 不新增依赖。
- 不让 Java 读取 Python 内部表。
- 不从自然语言文本反解析业务状态。
- 不把最终导诊结果塞进 JSON artifact 作为业务真相。
- 不用模型直接决定最终业务状态，Python 必须本地校验并收口。
- 失败时直接返回错误，不向 Java 提交脏结果。

## 4. 第一批：契约与基础设施收口

### 4.1 校正 API DTO

调整 `app/schemas/query.py`：

- 保留 `QueryRequest` 字段：
  - `scene`
  - `session_id`
  - `hospital_scope`
  - `user_message`
- 校正 `triage_result` 为三态判别联合：
  - `COLLECTING`
  - `READY`
  - `BLOCKED`
- `COLLECTING`：
  - 必须有 `follow_up_questions`
  - 最多 2 条
  - 不包含 `recommended_departments`
  - 不包含 `blocked_reason`
- `READY`：
  - 必须有 `recommended_departments`
  - 最多 3 条
  - 必须有 `catalog_version`
  - `triage_completion_reason` 只允许 `SUFFICIENT_INFO` 或 `MAX_TURNS_REACHED`
- `BLOCKED`：
  - 必须有 `blocked_reason`
  - `recommended_departments` 固定为空数组
  - 不要求 `catalog_version`
  - `next_action` 支持 `MANUAL_SUPPORT` 和 `EMERGENCY_OFFLINE`

### 4.2 校正错误响应

新 query 接口错误响应按联调协议返回：

```json
{
  "request_id": "req_01",
  "error": {
    "code": "TRIAGE_MODEL_SCHEMA_INVALID",
    "message": "model response schema invalid"
  }
}
```

P0 错误码固定为：

- `TRIAGE_REQUEST_INVALID`
- `TRIAGE_CATALOG_ACTIVE_VERSION_MISSING`
- `TRIAGE_CATALOG_VERSION_NOT_FOUND`
- `TRIAGE_CATALOG_DEPARTMENT_INVALID`
- `TRIAGE_MODEL_EMPTY_CONTENT`
- `TRIAGE_MODEL_INVALID_JSON`
- `TRIAGE_MODEL_SCHEMA_INVALID`
- `TRIAGE_STREAM_ASSEMBLY_FAILED`
- `TRIAGE_INTERNAL_ERROR`

### 4.3 增加数据库访问层

使用现有 `psycopg` 实现最小 DB 层，不引入 ORM。

建议新增：

- `app/db.py`
  - 创建数据库连接
  - 提供事务上下文
  - `/ready` 使用真实 DB ping
- `app/repositories/query.py`
  - 写入 query 主链路相关表
- `app/repositories/knowledge.py`
  - 读取知识库、发布版本、chunk index

涉及表：

- `ai_session`
- `ai_turn`
- `query_run`
- `query_result_snapshot`
- `query_result_follow_up_question`
- `query_result_department`
- `ai_model_run`
- `ai_guardrail_event`
- `ai_run_artifact`
- `retrieval_hit`
- `answer_citation`
- `knowledge_base`
- `knowledge_index_version`
- `knowledge_release`
- `knowledge_chunk`
- `knowledge_chunk_index`

### 4.4 验收标准

- `/api/v1/query` 和 `/api/v1/query/stream` DTO 与冻结协议一致。
- validation error 能返回 query 协议错误结构。
- `/ready` 能真实验证数据库连接。
- 不引入新依赖。

## 5. 第二批：Redis 目录与状态机

### 5.1 实现 Redis 导诊目录读取

新增 `app/services/catalog.py`。

读取顺序固定：

1. 读取 `triage_catalog:active:{hospital_scope}`
2. 读取 `triage_catalog:{hospital_scope}:{catalog_version}`

Python 使用规则：

- 只读 Redis。
- 不回写目录。
- 不调用 Java 内部 HTTP 目录接口。
- 只允许从 `department_candidates` 中选择推荐科室。
- 返回结果必须携带 `catalog_version`。

缺少 active 指针、缺少版本 JSON、推荐科室不在目录内、科室名称不严格匹配时，直接失败。

### 5.2 实现输入护栏

新增 `app/services/guardrails.py`。

P0 先实现输入阶段护栏：

- 自伤风险
- 暴力风险
- 胸痛风险
- 呼吸困难风险
- 卒中风险
- 抽搐风险
- 严重出血风险
- 过敏性休克风险
- 其他紧急风险

命中高风险时写入 `ai_guardrail_event`。

### 5.3 实现状态机收口

新增 `app/services/triage_state.py`。

固定执行顺序：

1. 输入护栏检查
2. 读取 Redis 导诊目录
3. 调用 DeepSeek 获取 `triage_materials`
4. 本地 JSON 解析和 schema 校验
5. 目录内科室校验
6. 高风险后处理
7. 最大回合数强制收口
8. 映射为 `COLLECTING / READY / BLOCKED`
9. 组装最终 `triage_result`

强制规则：

- 每个 active triage cycle 最多 5 个患者回合。
- 第 5 个患者回合不得继续返回 `COLLECTING`。
- Python 不直接信任模型的业务判断。

### 5.4 验收标准

- 缺 Redis active 指针时返回 `TRIAGE_CATALOG_ACTIVE_VERSION_MISSING`。
- 缺目录版本时返回 `TRIAGE_CATALOG_VERSION_NOT_FOUND`。
- 非目录科室返回 `TRIAGE_CATALOG_DEPARTMENT_INVALID`。
- 第 5 轮不会返回 `COLLECTING`。
- 高风险输入能返回 `BLOCKED`。

## 6. 第三批：DeepSeek 调用与模型留痕

### 6.1 实现 LLM client

新增 `app/services/llm.py`。

使用现有 `openai` 兼容客户端调用 DeepSeek。

配置来自环境变量：

- `LLM_MODEL`
- `LLM_BASE_URL`
- `LLM_API_KEY`

缺少 `LLM_API_KEY` 时直接失败。

### 6.2 固定模型输出用途

DeepSeek 只负责生成 `triage_materials`。

Python 负责：

- 解析模型 JSON
- 校验 schema
- 校验目录科室
- 执行高风险后处理
- 执行最大轮次收口
- 生成最终 `triage_result`

### 6.3 写入模型运行事实

每次模型调用写入 `ai_model_run`：

- `provider = DEEPSEEK`
- `model = deepseek-chat`
- `run_type = TRIAGE_MATERIALS`
- `stream_mode = SYNC` 或 `SSE`
- `status = RUNNING / SUCCEEDED / FAILED`

原始响应写入 `ai_run_artifact`：

- `artifact_type = LLM_RAW_RESPONSE`

最终导诊结果只写结构化结果表，不作为 JSON artifact 的业务真相。

### 6.4 验收标准

- 模型空 content 返回 `TRIAGE_MODEL_EMPTY_CONTENT`。
- 模型 JSON 解析失败返回 `TRIAGE_MODEL_INVALID_JSON`。
- 模型 schema 校验失败返回 `TRIAGE_MODEL_SCHEMA_INVALID`。
- 模型运行成功和失败都能更新 `ai_model_run.status`。

## 7. 第四批：RAG 检索闭环

### 7.1 读取已发布知识版本

根据 `hospital_scope` 找到可用知识库与已发布索引版本：

- `knowledge_base.status = ENABLED`
- `knowledge_release.status = PUBLISHED`
- `knowledge_index_version.status = READY`

如果没有已发布知识版本，query workflow 应明确失败或按产品确认后的规则处理；P0 不默认静默降级。

### 7.2 实现混合检索

新增 `app/services/retrieval.py`。

P0 检索策略：

- dense vector 检索
- sparse `search_tsv` 检索
- RRF 融合
- 选取上下文 chunk

检索使用：

- `knowledge_chunk_index.embedding`
- `knowledge_chunk_index.search_tsv`
- `knowledge_chunk.content_text`
- `knowledge_chunk.content_preview`

### 7.3 写入检索与证据事实

召回候选写入 `retrieval_hit`。

最终答案使用的证据写入 `answer_citation`。

`triage_result.citations` 从 `answer_citation` 对应数据组装。

### 7.4 验收标准

- 能基于已发布索引版本检索。
- dense 和 sparse 结果能融合排序。
- `retrieval_hit` 能记录召回候选。
- `answer_citation` 能记录最终引用。
- `READY` 响应能返回 citations。

## 8. 第五批：同步 Query 接口

### 8.1 实现 `POST /api/v1/query`

新增 `app/services/query_workflow.py`。

一次同步请求的写入顺序：

1. 创建或读取 `ai_session`
2. 创建 `ai_turn`
3. 创建 `query_run`
4. 输入护栏命中时写 `ai_guardrail_event`
5. 需要模型调用时写 `ai_model_run`
6. 需要调试或保留原始响应时写 `ai_run_artifact`
7. 检索阶段写 `retrieval_hit`
8. 生成最终结构化结果后写 `query_result_snapshot`
9. `COLLECTING` 时写 `query_result_follow_up_question`
10. `READY` 时写 `query_result_department`
11. 有 grounding 证据时写 `answer_citation`
12. 更新 `ai_turn.assistant_message_text / stage_after / is_finalized`
13. 更新 `query_run.status`
14. 更新 `ai_session.current_stage`

### 8.2 返回结构

同步接口返回：

```json
{
  "request_id": "req_01",
  "session_id": "82f7a4c2-7784-4d31-9c6e-6c8fbbe8c2cd",
  "turn_id": "4b1eaf1f-3e28-479f-9fb5-f259db73507a",
  "query_run_id": "9e86fc63-15f1-44db-9c07-ef2e5911d69c",
  "triage_result": {}
}
```

### 8.3 验收标准

- 首轮 `session_id = null` 时能创建新会话。
- 后续轮次能按 `session_id` 追加 `ai_turn`。
- `COLLECTING` 写追问明细。
- `READY` 写推荐科室明细。
- `BLOCKED` 写阻断结果。
- `query_run.status` 最终为 `SUCCEEDED` 或 `FAILED`。

## 9. 第六批：流式 Query 接口

### 9.1 实现 `POST /api/v1/query/stream`

返回标准 `text/event-stream`。

SSE 事件固定为：

- `start`
- `progress`
- `delta`
- `final`
- `error`
- `done`

### 9.2 流式强约束

- 前端只能根据 `final` 事件跳页。
- Java 只消费 `final` 中的 `triage_result` 作为业务真相。
- `delta` 只用于展示自然语言。
- Python 必须在服务端完整组装 DeepSeek JSON，再生成 `final`。
- Python 不得把 DeepSeek keep-alive 注释直接透给业务端。

### 9.3 标准事件顺序

一次标准流式请求顺序：

1. 创建 `session_id`、`turn_id`、`query_run_id`
2. 发送 `start`
3. 完成输入护栏并发送 `progress`
4. 读取 Redis 导诊目录并发送 `progress`
5. 调 DeepSeek，并在消费上游流时连续发送 `delta`
6. 完成 `triage_materials`
7. 本地校验并做状态机收口
8. 发送 `final`
9. 发送 `done`

### 9.4 验收标准

- `start` 中包含 `request_id/session_id/turn_id/query_run_id`。
- `progress.step` 只使用冻结枚举。
- 流式成功时，如果上游返回文本增量，则在 `final` 前收到 `delta`。
- `final` 中包含完整 `triage_result`。
- 出错时发送 `error` 事件。
- 不通过 `delta` 驱动业务状态。

## 10. 第七批：测试与联调

### 10.1 单元测试

补充测试：

- `triage_result` 三态 DTO 校验。
- `COLLECTING` 最多 2 个追问。
- `READY` 最多 3 个科室。
- `BLOCKED` 固定高风险。
- Redis 目录读取与校验。
- 第 5 轮强制收口。
- 非目录科室失败。
- 模型空 content 失败。
- 模型非法 JSON 失败。
- 模型 schema 不合法失败。

### 10.2 API 测试

补充测试：

- `/api/v1/query` 成功返回 `COLLECTING`。
- `/api/v1/query` 成功返回 `READY`。
- `/api/v1/query` 成功返回 `BLOCKED`。
- `/api/v1/query/stream` 事件顺序正确。
- `/api/v1/query/stream` 出错时返回 `error`。

### 10.3 联调检查

与 Java 联调时确认：

- Java 发布 Redis 目录。
- Java 调用 `/api/v1/query` 或 `/api/v1/query/stream`。
- Java 不读取 Python 内部 AI 表。
- Java 校验 `catalog_version + department_id + department_name`。
- Java 只根据 `triage_result.next_action` 驱动页面流转。
- 前端不从 `delta` 文本推断状态。

### 10.4 验证命令

本地验证使用：

```bash
uv run pytest
```

## 11. 推荐实施顺序

建议分三轮落地。

第一轮：

- DTO 校正
- 错误响应校正
- DB 连接层
- Redis 目录读取
- 同步 `/api/v1/query` 的最小 workflow

第二轮：

- DeepSeek 调用
- 模型 schema 校验
- 状态机收口
- 结构化结果落库
- RAG 检索与 citations

第三轮：

- 真实 `/api/v1/query/stream`
- 完整测试
- Java 联调修正
- 删除或更新旧 TODO 中与新方案冲突的内容

## 12. 最终验收口径

P0 完成后应满足：

- Python 对外只暴露冻结 query 接口。
- Java 只通过 Redis 和 Python HTTP API 集成。
- Python 内部表只服务 Python 自己。
- `triage_result` 是唯一业务输出真相。
- 最终导诊结果落在结构化结果表中。
- 前端只根据 `next_action` 跳页。
- 流式文本不参与业务状态判断。
- 任一关键前置条件缺失时明确失败，不提交脏结果。
