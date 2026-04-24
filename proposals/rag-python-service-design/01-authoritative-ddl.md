# RAG Python 服务 Authoritative DDL 草案

## 1. 文档定位

本文冻结 Python RAG 服务的 P0 数据库设计。

目标不是给出最终 migration 细节，而是冻结以下内容：

- P0 必做表的唯一清单
- 每张表的职责与主键策略
- 主外键关系
- 关键约束与索引
- 状态枚举
- 运行期写入 ownership

后续 Alembic migration 和正式 SQL 必须以本文为准。

## 2. 这次明确推翻的旧设计

这版不是在旧稿上微调，而是做了几处明确收口：

- 删除 `ai_turn_content`
  - P0 每轮只有一条用户输入和一条最终助手输出，单独抽“内容分层表”是过度抽象
- 删除“最终导诊结果存在 `ai_run_artifact` JSON 里”的做法
  - 最终结果改为结构化表，不再让核心结果躲在 JSON 里
- 删除 `query_run.final_*` 这类执行表里的业务结果列
  - 执行事实和业务结果分表存储
- 删除 `ai_model_run.session_id / turn_id`
  - 这些都可由 `query_run_id` 推导，冗余列会制造不一致
- 删除 `ai_guardrail_event.session_id / turn_id`
  - 同上，保留 `query_run_id` 即可
- 删除 `knowledge_chunk.kb_id`
  - `chunk` 归属可由 `document_id -> knowledge_document.kb_id` 推导
- `knowledge_chunk_index`、`retrieval_hit`、`answer_citation` 这类从属明细表改用复合主键
  - 不再为纯明细行引入无意义的独立 `uuid`

## 3. 全局约定

### 3.1 主键策略

- 根实体表主键统一使用 `uuid`
- 纯从属明细表优先使用复合主键
- 不为“只依附父实体存在”的明细行额外制造独立 id

### 3.2 时间字段

- 时间统一使用 `timestamptz`
- 根实体表统一包含 `created_at`
- 需要更新追踪的表额外包含 `updated_at`

### 3.3 外部引用

- `department_id` 使用 Java 业务系统主键，类型固定为 `bigint`
- `catalog_version` 使用 Java 发布的目录版本号，类型固定为 `varchar(64)`
- `request_id` 使用链路 trace id，类型固定为 `varchar(64)`

### 3.4 JSON 字段

只允许在以下场景使用 `jsonb`：

- LLM 原始响应
- 调试 artifact
- 护栏补充明细

核心业务结果和核心关系事实不允许只存在于 JSON 中。

### 3.5 向量与全文检索

- 向量字段使用 `vector(1024)`
- 稀疏检索字段使用 `tsvector`
- P0 embedding 方案冻结为 `text-embedding-v4 @ 1024`
- 若未来需要调整维度，必须通过新 migration 和新索引版本完成，不允许同一套 P0 DDL 混用多种维度
- P0 ANN 索引默认使用 `HNSW + cosine distance`

## 4. 状态枚举

### 4.1 会话与导诊

- `ai_session.scene_code`
  - `AI_TRIAGE`
- `ai_session.current_stage`
  - `COLLECTING`
  - `READY`
  - `BLOCKED`
  - `CLOSED`
- `ai_turn.stage_before`
  - `COLLECTING`
  - `READY`
  - `BLOCKED`
- `ai_turn.stage_after`
  - `COLLECTING`
  - `READY`
  - `BLOCKED`
- `query_run.status`
  - `RUNNING`
  - `SUCCEEDED`
  - `FAILED`
- `query_result_snapshot.triage_stage`
  - `COLLECTING`
  - `READY`
  - `BLOCKED`
- `query_result_snapshot.triage_completion_reason`
  - `SUFFICIENT_INFO`
  - `MAX_TURNS_REACHED`
  - `HIGH_RISK_BLOCKED`
- `query_result_snapshot.next_action`
  - `CONTINUE_TRIAGE`
  - `VIEW_TRIAGE_RESULT`
  - `MANUAL_SUPPORT`
  - `EMERGENCY_OFFLINE`
- `query_result_snapshot.risk_level`
  - `low`
  - `medium`
  - `high`

### 4.2 模型运行与产物

- `ai_model_run.run_type`
  - `TRIAGE_MATERIALS`
  - `RAG_ANSWER`
- `ai_model_run.stream_mode`
  - `SYNC`
  - `SSE`
- `ai_model_run.status`
  - `RUNNING`
  - `SUCCEEDED`
  - `FAILED`
- `ai_run_artifact.artifact_type`
  - `TRIAGE_MATERIALS`
  - `RETRIEVAL_CONTEXT`
  - `LLM_RAW_RESPONSE`
  - `DEBUG_PAYLOAD`

### 4.3 护栏

- `ai_guardrail_event.phase`
  - `INPUT`
  - `OUTPUT`
- `ai_guardrail_event.action`
  - `ALLOW`
  - `FLAG`
  - `BLOCK`
- `ai_guardrail_event.risk_code`
  - `SELF_HARM_RISK`
  - `VIOLENCE_RISK`
  - `CHEST_PAIN_RISK`
  - `RESPIRATORY_DISTRESS_RISK`
  - `STROKE_RISK`
  - `SEIZURE_RISK`
  - `SEVERE_BLEEDING_RISK`
  - `ANAPHYLAXIS_RISK`
  - `OTHER_EMERGENCY_RISK`

### 4.4 知识与发布

- `knowledge_base.status`
  - `ENABLED`
  - `DISABLED`
  - `ARCHIVED`
- `knowledge_document.lifecycle_status`
  - `DRAFT`
  - `ENABLED`
  - `ARCHIVED`
- `knowledge_document.source_type`
  - `MANUAL`
  - `MARKDOWN`
  - `PDF`
  - `DOCX`
- `knowledge_index_version.build_scope`
  - `FULL`
  - `INCREMENTAL`
- `knowledge_index_version.status`
  - `BUILDING`
  - `READY`
  - `FAILED`
  - `ARCHIVED`
- `ingest_job.job_type`
  - `INGEST_DOCUMENT`
  - `REINDEX_DOCUMENT`
  - `REBUILD_KB`
- `ingest_job.status`
  - `PENDING`
  - `RUNNING`
  - `SUCCEEDED`
  - `FAILED`
- `ingest_job.current_stage`
  - `PARSE`
  - `CHUNK`
  - `EMBED`
  - `INDEX`
  - `ACTIVATE`
- `knowledge_release.release_type`
  - `INDEX_ACTIVATION`
- `knowledge_release.status`
  - `DRAFT`
  - `PUBLISHED`
  - `REVOKED`

### 4.5 检索

- `retrieval_hit.retriever_type`
  - `DENSE`
  - `SPARSE`
  - `FUSION`
  - `RERANK`

## 5. P0 表结构

## 5.1 `ai_session`

会话头，表示一条 AI 导诊会话。

| 字段 | 类型 | 约束 | 说明 |
|------|------|------|------|
| `id` | `uuid` | PK | 会话 id |
| `request_id` | `varchar(64)` | nullable | 创建会话时首个 request id |
| `scene_code` | `varchar(32)` | not null | 固定为 `AI_TRIAGE` |
| `hospital_scope` | `varchar(64)` | not null | 导诊目录作用域 |
| `current_stage` | `varchar(32)` | not null | 当前导诊状态 |
| `current_turn_no` | `integer` | not null | 当前已完成轮次 |
| `current_triage_cycle_no` | `integer` | not null | 当前导诊 cycle |
| `closed_at` | `timestamptz` | nullable | 会话关闭时间 |
| `created_at` | `timestamptz` | not null | 创建时间 |
| `updated_at` | `timestamptz` | not null | 更新时间 |

关键索引：

- `idx_ai_session_stage` on (`current_stage`, `created_at desc`)

写入 ownership：

- Python query workflow 创建和更新

## 5.2 `ai_turn`

一轮问答事实。P0 直接在本表存一条用户输入和一条最终助手输出。

| 字段 | 类型 | 约束 | 说明 |
|------|------|------|------|
| `id` | `uuid` | PK | 轮次 id |
| `session_id` | `uuid` | FK -> `ai_session.id` | 所属会话 |
| `turn_no` | `integer` | not null | 会话内轮次号，从 1 递增 |
| `triage_cycle_no` | `integer` | not null | 所属导诊 cycle |
| `user_message_text` | `text` | not null | 本轮用户原文 |
| `assistant_message_text` | `text` | nullable | 本轮最终助手文本 |
| `stage_before` | `varchar(32)` | not null | 本轮执行前状态 |
| `stage_after` | `varchar(32)` | nullable | 本轮执行后状态 |
| `is_finalized` | `boolean` | not null | 是否收口到 `READY/BLOCKED` |
| `created_at` | `timestamptz` | not null | 创建时间 |
| `updated_at` | `timestamptz` | not null | 更新时间 |

唯一约束：

- (`session_id`, `turn_no`)

关键索引：

- `idx_ai_turn_session_no` on (`session_id`, `turn_no`)

写入 ownership：

- Python query workflow 创建和更新

## 5.3 `query_run`

一次 query workflow 的执行根节点，是同步与流式共同的 trace 根。

| 字段 | 类型 | 约束 | 说明 |
|------|------|------|------|
| `id` | `uuid` | PK | query run id |
| `request_id` | `varchar(64)` | not null | 本次请求 trace id |
| `session_id` | `uuid` | FK -> `ai_session.id` | 所属会话 |
| `turn_id` | `uuid` | unique FK -> `ai_turn.id` | 所属轮次 |
| `kb_id` | `uuid` | nullable FK -> `knowledge_base.id` | 本次实际命中的知识库 |
| `scene_code` | `varchar(32)` | not null | 固定为 `AI_TRIAGE` |
| `request_text` | `text` | not null | 用户输入原文快照 |
| `normalized_query_text` | `text` | nullable | 归一化查询文本 |
| `hospital_scope` | `varchar(64)` | not null | 导诊目录作用域 |
| `catalog_version` | `varchar(64)` | nullable | 本次运行实际使用的目录版本 |
| `index_version_id` | `uuid` | nullable FK -> `knowledge_index_version(id, kb_id)` | 本次运行实际使用的索引版本，必须属于 `kb_id` |
| `status` | `varchar(16)` | not null | 运行状态 |
| `started_at` | `timestamptz` | not null | 开始时间 |
| `finished_at` | `timestamptz` | nullable | 结束时间 |
| `created_at` | `timestamptz` | not null | 创建时间 |

P0 约束：

- `index_version_id` 非空时 `kb_id` 必须非空
- `index_version_id` 必须属于同一个 `kb_id`

关键索引：

- `idx_query_run_session` on (`session_id`, `created_at desc`)
- `idx_query_run_request` on (`request_id`)
- `idx_query_run_status` on (`status`, `created_at desc`)

写入 ownership：

- Python query workflow 创建和收口

## 5.4 `query_result_snapshot`

一次 query 的结构化业务结果快照。它是 `triage_result` 的数据库真相。

| 字段 | 类型 | 约束 | 说明 |
|------|------|------|------|
| `query_run_id` | `uuid` | PK FK -> `query_run.id` | 所属 query run |
| `triage_stage` | `varchar(32)` | not null | `COLLECTING / READY / BLOCKED` |
| `triage_completion_reason` | `varchar(32)` | nullable | 收口原因 |
| `next_action` | `varchar(32)` | not null | 前端动作 |
| `risk_level` | `varchar(16)` | nullable | 风险等级 |
| `chief_complaint_summary` | `text` | not null | 主诉摘要 |
| `catalog_version` | `varchar(64)` | nullable | READY 结果使用的目录版本 |
| `care_advice` | `text` | nullable | 就医建议 |
| `blocked_reason` | `varchar(64)` | nullable | 阻断原因 |
| `created_at` | `timestamptz` | not null | 结果落库时间 |

P0 约束：

- `COLLECTING`
  - `triage_completion_reason` 必须为 `null`
  - `next_action` 必须为 `CONTINUE_TRIAGE`
  - `risk_level` 必须为 `null`
  - `catalog_version` 必须为 `null`
  - `blocked_reason` 必须为 `null`
  - `care_advice` 必须为 `null`
- `READY`
  - `triage_completion_reason` 必须为 `SUFFICIENT_INFO / MAX_TURNS_REACHED`
  - `next_action` 必须为 `VIEW_TRIAGE_RESULT`
  - `risk_level` 必须非空
  - `catalog_version` 必须非空
  - `blocked_reason` 必须为 `null`
  - `care_advice` 必须非空
- `BLOCKED`
  - `triage_completion_reason` 必须为 `HIGH_RISK_BLOCKED`
  - `next_action` 必须为 `MANUAL_SUPPORT / EMERGENCY_OFFLINE`
  - `risk_level` 必须为 `high`
  - `catalog_version` 必须为 `null`
  - `blocked_reason` 必须非空
  - `care_advice` 必须非空

唯一约束：

- (`query_run_id`, `triage_stage`)

写入 ownership：

- Python query workflow 在生成最终结构化结果后写入

## 5.5 `query_result_follow_up_question`

`COLLECTING` 状态下的追问问题明细表。

| 字段 | 类型 | 约束 | 说明 |
|------|------|------|------|
| `query_run_id` | `uuid` | PK FK -> `query_result_snapshot.query_run_id` | 所属 query run |
| `triage_stage` | `varchar(32)` | FK -> `query_result_snapshot(query_run_id, triage_stage)` | 固定为 `COLLECTING`，防止写到 READY/BLOCKED 结果下 |
| `question_order` | `integer` | PK | 顺序，P0 只允许 1..2 |
| `question_text` | `text` | not null | 追问内容 |
| `created_at` | `timestamptz` | not null | 创建时间 |

P0 约束：

- `question_order` 只允许 `1..2`
- `triage_stage` 固定为 `COLLECTING`

关键索引：

- `idx_qrfq_query` on (`query_run_id`, `question_order`)

写入 ownership：

- Python query workflow

## 5.6 `query_result_department`

`READY` 状态下的推荐科室明细表。

| 字段 | 类型 | 约束 | 说明 |
|------|------|------|------|
| `query_run_id` | `uuid` | PK FK -> `query_result_snapshot.query_run_id` | 所属 query run |
| `triage_stage` | `varchar(32)` | FK -> `query_result_snapshot(query_run_id, triage_stage)` | 固定为 `READY`，防止写到 COLLECTING/BLOCKED 结果下 |
| `priority` | `integer` | PK | 推荐优先级，P0 只允许 1..3 |
| `department_id` | `bigint` | not null | 科室 id |
| `department_name` | `varchar(128)` | not null | 科室名称快照 |
| `reason` | `text` | not null | 推荐理由 |
| `created_at` | `timestamptz` | not null | 创建时间 |

P0 约束：

- `priority` 只允许 `1..3`
- `triage_stage` 固定为 `READY`

关键索引：

- `idx_qrd_department` on (`department_id`)

写入 ownership：

- Python query workflow

## 5.7 `ai_model_run`

一次模型调用事实。

| 字段 | 类型 | 约束 | 说明 |
|------|------|------|------|
| `id` | `uuid` | PK | 模型运行 id |
| `query_run_id` | `uuid` | FK -> `query_run.id` | 所属 query run |
| `provider` | `varchar(32)` | not null | 固定为 `DEEPSEEK` |
| `model` | `varchar(64)` | not null | 固定为 `deepseek-chat` |
| `run_type` | `varchar(32)` | not null | 调用用途 |
| `stream_mode` | `varchar(16)` | not null | `SYNC / SSE` |
| `status` | `varchar(16)` | not null | 运行状态 |
| `input_tokens` | `integer` | nullable | 输入 token |
| `output_tokens` | `integer` | nullable | 输出 token |
| `started_at` | `timestamptz` | not null | 开始时间 |
| `finished_at` | `timestamptz` | nullable | 结束时间 |
| `error_code` | `varchar(64)` | nullable | 失败码 |
| `created_at` | `timestamptz` | not null | 创建时间 |

关键索引：

- `idx_ai_model_run_query` on (`query_run_id`, `started_at desc`)

写入 ownership：

- Python LLM integration

## 5.8 `ai_guardrail_event`

护栏留痕表。

| 字段 | 类型 | 约束 | 说明 |
|------|------|------|------|
| `id` | `uuid` | PK | 事件 id |
| `query_run_id` | `uuid` | FK -> `query_run.id` | 所属 query run |
| `phase` | `varchar(16)` | not null | 输入或输出阶段 |
| `risk_code` | `varchar(64)` | not null | 风险类型 |
| `action` | `varchar(16)` | not null | 护栏动作 |
| `detail_json` | `jsonb` | nullable | 补充明细 |
| `created_at` | `timestamptz` | not null | 创建时间 |

关键索引：

- `idx_ai_guardrail_query` on (`query_run_id`, `created_at`)
- `idx_ai_guardrail_risk` on (`risk_code`, `created_at desc`)

写入 ownership：

- Python safety 模块

## 5.9 `ai_run_artifact`

LLM 原始响应和调试产物。它不再承载最终导诊结果真相。

| 字段 | 类型 | 约束 | 说明 |
|------|------|------|------|
| `id` | `uuid` | PK | 产物 id |
| `model_run_id` | `uuid` | nullable FK -> `ai_model_run.id` | 所属模型运行 |
| `query_run_id` | `uuid` | FK -> `query_run.id` | 所属 query run |
| `artifact_type` | `varchar(32)` | not null | 产物类型 |
| `artifact_json` | `jsonb` | not null | 结构化或原始 JSON |
| `created_at` | `timestamptz` | not null | 创建时间 |

关键索引：

- `idx_ai_run_artifact_query_type` on (`query_run_id`, `artifact_type`)

写入 ownership：

- Python query workflow / LLM integration

## 5.10 `knowledge_base`

知识库主表，保存治理配置的默认值。

| 字段 | 类型 | 约束 | 说明 |
|------|------|------|------|
| `id` | `uuid` | PK | 知识库 id |
| `hospital_scope` | `varchar(64)` | not null | 知识库所属医院或院区作用域 |
| `code` | `varchar(64)` | not null | 作用域内稳定业务编码 |
| `name` | `varchar(128)` | not null | 知识库名称 |
| `description` | `text` | nullable | 描述 |
| `default_embedding_model` | `varchar(64)` | not null | 默认 embedding 模型 |
| `default_embedding_dimension` | `integer` | not null | 默认 embedding 维度，P0 固定 1024 |
| `retrieval_strategy` | `varchar(64)` | not null | 默认检索策略，如 `HYBRID_RRF` |
| `status` | `varchar(16)` | not null | 可用状态 |
| `created_at` | `timestamptz` | not null | 创建时间 |
| `updated_at` | `timestamptz` | not null | 更新时间 |

唯一约束：

- (`hospital_scope`, `code`)

关键索引：

- `idx_knowledge_base_scope_status` on (`hospital_scope`, `status`)

写入 ownership：

- Python KB admin / ingestion workflow

## 5.11 `knowledge_document`

文档源事实表，不承载发布语义。

| 字段 | 类型 | 约束 | 说明 |
|------|------|------|------|
| `id` | `uuid` | PK | 文档 id |
| `kb_id` | `uuid` | FK -> `knowledge_base.id` | 所属知识库 |
| `title` | `varchar(255)` | not null | 文档标题 |
| `source_type` | `varchar(32)` | not null | 来源类型 |
| `source_uri` | `text` | nullable | 原始来源地址或对象路径 |
| `mime_type` | `varchar(128)` | nullable | 文档 MIME |
| `content_hash` | `varchar(128)` | not null | 原文内容哈希 |
| `owner_ref` | `varchar(128)` | nullable | 负责人或导入人标识 |
| `lifecycle_status` | `varchar(16)` | not null | 文档生命周期 |
| `deleted_at` | `timestamptz` | nullable | 逻辑删除时间 |
| `created_at` | `timestamptz` | not null | 创建时间 |
| `updated_at` | `timestamptz` | not null | 更新时间 |

唯一约束：

- (`kb_id`, `content_hash`)

关键索引：

- `idx_knowledge_document_kb_status` on (`kb_id`, `lifecycle_status`)

写入 ownership：

- Python ingest API / admin

## 5.12 `knowledge_chunk`

稳定证据单元。`chunk` 归属于文档，不再重复保存 `kb_id`。

| 字段 | 类型 | 约束 | 说明 |
|------|------|------|------|
| `id` | `uuid` | PK | chunk id |
| `document_id` | `uuid` | FK -> `knowledge_document.id` | 所属文档 |
| `chunk_no` | `integer` | not null | 文档内序号 |
| `content_text` | `text` | not null | chunk 正文 |
| `content_preview` | `text` | not null | 展示摘要 |
| `page_no` | `integer` | nullable | 页码 |
| `section_path` | `varchar(512)` | nullable | 章节路径 |
| `token_count` | `integer` | not null | token 计数 |
| `created_at` | `timestamptz` | not null | 创建时间 |

唯一约束：

- (`document_id`, `chunk_no`)

关键索引：

- `idx_knowledge_chunk_document` on (`document_id`, `chunk_no`)

写入 ownership：

- Python ingestion worker

## 5.13 `knowledge_index_version`

索引版本事实。实际 embedding 配置在这里冻结，不依赖知识库默认值推断。

| 字段 | 类型 | 约束 | 说明 |
|------|------|------|------|
| `id` | `uuid` | PK | 索引版本 id |
| `kb_id` | `uuid` | FK -> `knowledge_base.id` | 所属知识库 |
| `version_code` | `varchar(64)` | not null | 知识库内版本号 |
| `embedding_model` | `varchar(64)` | not null | 本版本实际 embedding 模型 |
| `embedding_dimension` | `integer` | not null | 本版本实际向量维度，P0 固定 1024 |
| `build_scope` | `varchar(16)` | not null | 全量或增量 |
| `status` | `varchar(16)` | not null | 构建状态 |
| `source_document_count` | `integer` | not null | 本次构建包含文档数 |
| `started_at` | `timestamptz` | not null | 开始构建时间 |
| `finished_at` | `timestamptz` | nullable | 结束时间 |
| `created_at` | `timestamptz` | not null | 创建时间 |

唯一约束：

- (`kb_id`, `version_code`)
- (`id`, `kb_id`) 用于约束发布与 query 使用的索引版本必须属于同一知识库

关键索引：

- `idx_knowledge_index_version_kb_status` on (`kb_id`, `status`)

写入 ownership：

- Python ingestion workflow

## 5.14 `knowledge_chunk_index`

检索投影层，一条记录表示一个 chunk 在一个索引版本中的可检索投影。

| 字段 | 类型 | 约束 | 说明 |
|------|------|------|------|
| `chunk_id` | `uuid` | PK FK -> `knowledge_chunk.id` | 所属 chunk |
| `index_version_id` | `uuid` | PK FK -> `knowledge_index_version.id` | 所属索引版本 |
| `embedding` | `vector(1024)` | not null | dense retrieval 向量 |
| `search_lexemes` | `text` | not null | Python 归一化分词结果 |
| `search_tsv` | `tsvector` | not null | 由 `search_lexemes` 生成的稀疏检索字段 |
| `indexed_at` | `timestamptz` | not null | 建索引时间 |

关键索引：

- `idx_kci_index_version` on (`index_version_id`)
- `idx_kci_search_tsv` gin (`search_tsv`)
- `idx_kci_embedding` hnsw (`embedding`) with cosine distance

写入 ownership：

- Python ingestion worker

## 5.15 `ingest_job`

文档处理任务表。

| 字段 | 类型 | 约束 | 说明 |
|------|------|------|------|
| `id` | `uuid` | PK | 作业 id |
| `kb_id` | `uuid` | FK -> `knowledge_base.id` | 所属知识库 |
| `document_id` | `uuid` | nullable FK -> `knowledge_document.id` | 目标文档 |
| `target_index_version_id` | `uuid` | nullable FK -> `knowledge_index_version(id, kb_id)` | 目标索引版本，必须属于同一知识库 |
| `job_type` | `varchar(32)` | not null | 作业类型 |
| `status` | `varchar(16)` | not null | 任务状态 |
| `current_stage` | `varchar(16)` | not null | 当前阶段 |
| `error_code` | `varchar(64)` | nullable | 失败码 |
| `error_message` | `text` | nullable | 失败信息 |
| `started_at` | `timestamptz` | nullable | 开始时间 |
| `finished_at` | `timestamptz` | nullable | 结束时间 |
| `created_at` | `timestamptz` | not null | 创建时间 |

关键索引：

- `idx_ingest_job_status` on (`status`, `created_at`)
- `idx_ingest_job_document` on (`document_id`, `created_at desc`)

写入 ownership：

- Python ingest API 创建
- Python worker 更新状态

## 5.16 `knowledge_release`

显式发布表，只管理索引版本上线动作。

| 字段 | 类型 | 约束 | 说明 |
|------|------|------|------|
| `id` | `uuid` | PK | 发布 id |
| `kb_id` | `uuid` | FK -> `knowledge_base.id` | 所属知识库 |
| `release_code` | `varchar(64)` | not null | 知识库内发布编号 |
| `release_type` | `varchar(32)` | not null | 固定为 `INDEX_ACTIVATION` |
| `target_index_version_id` | `uuid` | FK -> `knowledge_index_version(id, kb_id)` | 发布目标版本，必须属于同一知识库 |
| `status` | `varchar(16)` | not null | 发布状态 |
| `published_by` | `varchar(128)` | nullable | 发布人 |
| `published_at` | `timestamptz` | nullable | 发布时间 |
| `revoked_at` | `timestamptz` | nullable | 撤销时间 |
| `created_at` | `timestamptz` | not null | 创建时间 |

关键索引：

- `idx_knowledge_release_kb_status` on (`kb_id`, `status`)
- `idx_knowledge_release_target` on (`target_index_version_id`)

P0 约束：

- 同一 `kb_id` 同时最多一条 `PUBLISHED` 记录
- (`kb_id`, `release_code`) 唯一

写入 ownership：

- Python admin / ingestion activation

## 5.17 `retrieval_hit`

召回候选事实，不表示已被答案引用。

| 字段 | 类型 | 约束 | 说明 |
|------|------|------|------|
| `query_run_id` | `uuid` | PK FK -> `query_run.id` | 所属 query run |
| `retriever_type` | `varchar(16)` | PK | 召回器类型 |
| `rank_no` | `integer` | PK | 排名 |
| `chunk_id` | `uuid` | FK -> `knowledge_chunk.id` | 命中 chunk |
| `vector_score` | `double precision` | nullable | 向量分 |
| `keyword_score` | `double precision` | nullable | 稀疏检索分 |
| `fusion_score` | `double precision` | nullable | 融合分 |
| `rerank_score` | `double precision` | nullable | 重排分 |
| `selected_for_context` | `boolean` | not null | 是否进入 context packing |
| `created_at` | `timestamptz` | not null | 创建时间 |

关键索引：

- `idx_retrieval_hit_chunk` on (`chunk_id`)

写入 ownership：

- Python retrieval workflow

## 5.18 `answer_citation`

最终答案真正使用的证据记录。

| 字段 | 类型 | 约束 | 说明 |
|------|------|------|------|
| `query_run_id` | `uuid` | PK FK -> `query_run.id` | 所属 query run |
| `citation_order` | `integer` | PK | 引用顺序 |
| `chunk_id` | `uuid` | FK -> `knowledge_chunk.id` | 被引用 chunk |
| `snippet` | `text` | not null | 最终展示片段 |
| `created_at` | `timestamptz` | not null | 创建时间 |

关键索引：

- `idx_answer_citation_chunk` on (`chunk_id`)

写入 ownership：

- Python generation / grounding workflow

## 6. 主外键关系

- `ai_session 1 -> n ai_turn`
- `ai_turn 1 -> 1 query_run`
- `query_run 1 -> 1 query_result_snapshot`
- `query_result_snapshot 1 -> n query_result_follow_up_question`
- `query_result_snapshot 1 -> n query_result_department`
- `query_run 1 -> n ai_model_run`
- `query_run 1 -> n ai_guardrail_event`
- `query_run 1 -> n ai_run_artifact`
- `knowledge_base 1 -> n knowledge_document`
- `knowledge_document 1 -> n knowledge_chunk`
- `knowledge_index_version 1 -> n knowledge_chunk_index`
- `query_run 1 -> n retrieval_hit`
- `query_run 1 -> n answer_citation`

## 7. 运行期写入时序

### 7.1 一次 query 请求

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

### 7.2 一次 ingestion 请求

1. 创建 `knowledge_document`
2. 创建 `knowledge_index_version`
3. 创建 `ingest_job`
4. worker 写 `knowledge_chunk`
5. worker 写 `knowledge_chunk_index`
6. worker 更新 `knowledge_index_version.status`
7. 发布时创建 `knowledge_release`

## 8. 明确删除的旧设计

正式 DDL 中不得继续保留：

- `ai_turn_content`
- “最终导诊结果只存在 `ai_run_artifact(FINAL_TRIAGE_RESULT)`”
- `query_run.final_*` 混合执行事实和业务结果
- `knowledge_chunk.kb_id`
- `ai_model_run.session_id / turn_id`
- `ai_guardrail_event.session_id / turn_id`
- `ai_run_citation`
- “检索候选和最终引用混表”
- “只有当前索引、没有索引版本”

## 9. 一句话结论

这版把 Python RAG 服务的数据事实拆成了五层：

- 会话与轮次事实
- 执行与审计事实
- 结构化结果事实
- 文档与索引事实
- 检索与证据事实

后续实现必须按这五层落库，不再回到“聊天内容表泛化”和“最终结果塞 JSON”那套旧设计。
