# RAG Python 服务 Authoritative DDL 草案

## 1. 文档定位

本文是 `docs/proposals/` 基线下的数据库冻结稿。

目标不是输出最终可执行 SQL，而是先冻结以下内容：

- `P0` 必做表的唯一清单
- 每张表的字段职责
- 主外键关系
- 关键索引
- 状态枚举
- 运行期写入 ownership

后续 Alembic migration 和正式 DDL 必须以本文为准，不再回退到旧的 `docs/docs/*` 口径。

## 2. 设计边界

本文只覆盖 Python RAG 服务自有数据，不覆盖 Java 业务主数据。

明确不纳入 Python RAG 服务 ownership 的内容：

- 科室主数据
- 排班、挂号、接诊
- 医生、患者、订单

这些仍归 Java 业务系统。

Python RAG 服务只消费一份由 Java 发布的导诊目录读模型，目录本体不落本服务 PostgreSQL。

## 3. 全局约定

### 3.1 主键与时间字段

- 所有服务自有主键统一使用 `uuid`
- 时间统一使用 `timestamptz`
- 除明确例外外，表统一包含 `created_at`
- 需要更新追踪的表额外包含 `updated_at`

### 3.2 外部引用

- `department_id` 使用 Java 业务系统主键，类型按 `bigint` 冻结
- `catalog_version` 使用 Java 发布的字符串版本号，类型按 `varchar(64)` 冻结
- `request_id` 使用字符串 trace id，类型按 `varchar(64)` 冻结

### 3.3 JSON 字段

以下场景允许使用 `jsonb`：

- 模型结构化产物
- 护栏明细
- 调试 artifact

其余核心业务字段不使用大而全的 `jsonb` 代替结构化列。

### 3.4 向量与全文检索

- 向量字段使用 `vector`
- 稀疏检索字段使用 `tsvector`

## 4. 状态枚举

P0 统一冻结以下枚举值。

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
- `query_run.final_triage_stage`
  - `COLLECTING`
  - `READY`
  - `BLOCKED`
- `query_run.final_completion_reason`
  - `SUFFICIENT_INFO`
  - `MAX_TURNS_REACHED`
  - `HIGH_RISK_BLOCKED`

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
  - `FINAL_TRIAGE_RESULT`
  - `RETRIEVAL_CONTEXT`
  - `RISK_SUMMARY`
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
| `request_id` | `varchar(64)` | nullable | 创建会话时的首个 trace id |
| `scene_code` | `varchar(32)` | not null | 固定为 `AI_TRIAGE` |
| `hospital_scope` | `varchar(64)` | not null | 导诊目录作用域 |
| `current_stage` | `varchar(32)` | not null | 当前导诊状态 |
| `current_turn_no` | `integer` | not null | 当前已完成轮次 |
| `current_triage_cycle_no` | `integer` | not null | 当前导诊 cycle 序号 |
| `closed_at` | `timestamptz` | nullable | 会话关闭时间 |
| `created_at` | `timestamptz` | not null | 创建时间 |
| `updated_at` | `timestamptz` | not null | 更新时间 |

关键索引：

- `idx_ai_session_stage` on (`current_stage`, `created_at desc`)

写入 ownership：

- Python query workflow 创建和更新

## 5.2 `ai_turn`

一轮问答事实，绑定一次用户输入和本轮系统输出。

| 字段 | 类型 | 约束 | 说明 |
|------|------|------|------|
| `id` | `uuid` | PK | 轮次 id |
| `session_id` | `uuid` | FK -> `ai_session.id` | 所属会话 |
| `turn_no` | `integer` | not null | 会话内轮次号，从 1 递增 |
| `triage_cycle_no` | `integer` | not null | 所属导诊 cycle |
| `stage_before` | `varchar(32)` | not null | 本轮执行前状态 |
| `stage_after` | `varchar(32)` | nullable | 本轮执行后状态 |
| `is_finalized` | `boolean` | not null | 本轮是否收口到 `READY/BLOCKED` |
| `created_at` | `timestamptz` | not null | 创建时间 |

唯一约束：

- (`session_id`, `turn_no`)

关键索引：

- `idx_ai_turn_session_no` on (`session_id`, `turn_no`)

写入 ownership：

- Python query workflow 创建
- Python 状态机收口后更新 `stage_after` 和 `is_finalized`

## 5.3 `ai_turn_content`

轮次内正文分层存储表。

| 字段 | 类型 | 约束 | 说明 |
|------|------|------|------|
| `id` | `uuid` | PK | 内容 id |
| `turn_id` | `uuid` | FK -> `ai_turn.id` | 所属轮次 |
| `content_role` | `varchar(16)` | not null | `USER` / `ASSISTANT` / `SYSTEM` |
| `content_type` | `varchar(32)` | not null | `RAW_TEXT` / `NORMALIZED_TEXT` / `FINAL_TEXT` |
| `content_order` | `integer` | not null | 同轮内容顺序 |
| `text_content` | `text` | not null | 文本内容 |
| `created_at` | `timestamptz` | not null | 创建时间 |

唯一约束：

- (`turn_id`, `content_role`, `content_type`, `content_order`)

关键索引：

- `idx_ai_turn_content_turn` on (`turn_id`, `content_order`)

写入 ownership：

- Python query workflow 写用户原文和最终回复文本

## 5.4 `ai_model_run`

一次模型调用事实，面向 DeepSeek 文本生成调用。

| 字段 | 类型 | 约束 | 说明 |
|------|------|------|------|
| `id` | `uuid` | PK | 模型运行 id |
| `session_id` | `uuid` | FK -> `ai_session.id` | 所属会话 |
| `turn_id` | `uuid` | FK -> `ai_turn.id` | 所属轮次 |
| `query_run_id` | `uuid` | FK -> `query_run.id` | 所属 query run |
| `provider` | `varchar(32)` | not null | 固定为 `DEEPSEEK` |
| `model` | `varchar(64)` | not null | 固定为 `deepseek-chat` |
| `run_type` | `varchar(32)` | not null | 本次调用用途 |
| `stream_mode` | `varchar(16)` | not null | `SYNC` / `SSE` |
| `status` | `varchar(16)` | not null | 运行状态 |
| `input_tokens` | `integer` | nullable | 输入 token |
| `output_tokens` | `integer` | nullable | 输出 token |
| `started_at` | `timestamptz` | not null | 开始时间 |
| `finished_at` | `timestamptz` | nullable | 结束时间 |
| `error_code` | `varchar(64)` | nullable | 模型调用失败码 |
| `created_at` | `timestamptz` | not null | 创建时间 |

关键索引：

- `idx_ai_model_run_turn` on (`turn_id`, `started_at desc`)
- `idx_ai_model_run_query` on (`query_run_id`)

写入 ownership：

- Python LLM integration 创建和完结

## 5.5 `ai_run_artifact`

模型调用和 query workflow 的结构化产物快照。

| 字段 | 类型 | 约束 | 说明 |
|------|------|------|------|
| `id` | `uuid` | PK | 产物 id |
| `model_run_id` | `uuid` | FK -> `ai_model_run.id` | 所属模型运行 |
| `query_run_id` | `uuid` | FK -> `query_run.id` | 所属 query run |
| `artifact_type` | `varchar(32)` | not null | 产物类型 |
| `artifact_json` | `jsonb` | not null | 结构化内容 |
| `created_at` | `timestamptz` | not null | 创建时间 |

关键索引：

- `idx_ai_run_artifact_query_type` on (`query_run_id`, `artifact_type`)

写入 ownership：

- Python query workflow

固定产物：

- `TRIAGE_MATERIALS`
- `FINAL_TRIAGE_RESULT`

## 5.6 `ai_guardrail_event`

护栏留痕表。

| 字段 | 类型 | 约束 | 说明 |
|------|------|------|------|
| `id` | `uuid` | PK | 事件 id |
| `session_id` | `uuid` | FK -> `ai_session.id` | 所属会话 |
| `turn_id` | `uuid` | FK -> `ai_turn.id` | 所属轮次 |
| `query_run_id` | `uuid` | FK -> `query_run.id` | 所属 query run |
| `phase` | `varchar(16)` | not null | 输入或输出阶段 |
| `risk_code` | `varchar(64)` | not null | 风险类型 |
| `action` | `varchar(16)` | not null | 护栏动作 |
| `detail_json` | `jsonb` | nullable | 补充明细 |
| `created_at` | `timestamptz` | not null | 创建时间 |

关键索引：

- `idx_ai_guardrail_turn` on (`turn_id`, `created_at`)
- `idx_ai_guardrail_risk` on (`risk_code`, `created_at desc`)

写入 ownership：

- Python safety 模块

## 5.7 `knowledge_base`

知识库主表。

| 字段 | 类型 | 约束 | 说明 |
|------|------|------|------|
| `id` | `uuid` | PK | 知识库 id |
| `code` | `varchar(64)` | unique not null | 稳定业务编码 |
| `name` | `varchar(128)` | not null | 知识库名称 |
| `description` | `text` | nullable | 描述 |
| `embedding_model` | `varchar(64)` | not null | 当前 embedding 模型名 |
| `retrieval_strategy` | `varchar(64)` | not null | 如 `HYBRID_RRF` |
| `status` | `varchar(16)` | not null | 可用状态 |
| `created_at` | `timestamptz` | not null | 创建时间 |
| `updated_at` | `timestamptz` | not null | 更新时间 |

写入 ownership：

- Python KB admin / ingestion workflow

## 5.8 `knowledge_document`

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

## 5.9 `knowledge_chunk`

稳定证据单元。

| 字段 | 类型 | 约束 | 说明 |
|------|------|------|------|
| `id` | `uuid` | PK | chunk id |
| `kb_id` | `uuid` | FK -> `knowledge_base.id` | 所属知识库 |
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

## 5.10 `knowledge_chunk_index`

检索投影层，一条记录对应一个 chunk 在一个索引版本中的可检索状态。

| 字段 | 类型 | 约束 | 说明 |
|------|------|------|------|
| `id` | `uuid` | PK | 索引记录 id |
| `kb_id` | `uuid` | FK -> `knowledge_base.id` | 所属知识库 |
| `chunk_id` | `uuid` | FK -> `knowledge_chunk.id` | 所属 chunk |
| `index_version_id` | `uuid` | FK -> `knowledge_index_version.id` | 所属索引版本 |
| `embedding` | `vector` | not null | 向量字段 |
| `search_tsv` | `tsvector` | not null | 稀疏检索字段 |
| `weight` | `numeric(6,3)` | not null | 检索权重 |
| `created_at` | `timestamptz` | not null | 创建时间 |

唯一约束：

- (`chunk_id`, `index_version_id`)

关键索引：

- `idx_kci_index_version` on (`index_version_id`)
- `idx_kci_search_tsv` gin (`search_tsv`)
- `idx_kci_embedding` ivfflat (`embedding`)

写入 ownership：

- Python ingestion worker

## 5.11 `knowledge_index_version`

索引版本事实。

| 字段 | 类型 | 约束 | 说明 |
|------|------|------|------|
| `id` | `uuid` | PK | 索引版本 id |
| `kb_id` | `uuid` | FK -> `knowledge_base.id` | 所属知识库 |
| `version_code` | `varchar(64)` | unique not null | 版本号 |
| `build_scope` | `varchar(16)` | not null | 全量或增量 |
| `status` | `varchar(16)` | not null | 构建状态 |
| `source_document_count` | `integer` | not null | 本次构建包含文档数 |
| `started_at` | `timestamptz` | not null | 开始构建时间 |
| `finished_at` | `timestamptz` | nullable | 结束时间 |
| `created_at` | `timestamptz` | not null | 创建时间 |

关键索引：

- `idx_knowledge_index_version_kb_status` on (`kb_id`, `status`)

写入 ownership：

- Python ingestion workflow

## 5.12 `ingest_job`

文档处理任务表。

| 字段 | 类型 | 约束 | 说明 |
|------|------|------|------|
| `id` | `uuid` | PK | 作业 id |
| `kb_id` | `uuid` | FK -> `knowledge_base.id` | 所属知识库 |
| `document_id` | `uuid` | FK -> `knowledge_document.id` | 目标文档 |
| `target_index_version_id` | `uuid` | FK -> `knowledge_index_version.id` | 目标索引版本 |
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

## 5.13 `knowledge_release`

显式发布表，只管理索引版本上线动作。

| 字段 | 类型 | 约束 | 说明 |
|------|------|------|------|
| `id` | `uuid` | PK | 发布 id |
| `kb_id` | `uuid` | FK -> `knowledge_base.id` | 所属知识库 |
| `release_code` | `varchar(64)` | unique not null | 发布编号 |
| `release_type` | `varchar(32)` | not null | 固定为索引激活 |
| `target_index_version_id` | `uuid` | FK -> `knowledge_index_version.id` | 发布目标版本 |
| `status` | `varchar(16)` | not null | 发布状态 |
| `published_by` | `varchar(128)` | nullable | 发布人 |
| `published_at` | `timestamptz` | nullable | 发布时间 |
| `revoked_at` | `timestamptz` | nullable | 撤销时间 |
| `created_at` | `timestamptz` | not null | 创建时间 |

关键索引：

- `idx_knowledge_release_kb_status` on (`kb_id`, `status`)
- `idx_knowledge_release_target` on (`target_index_version_id`)

写入 ownership：

- Python admin / ingestion activation

P0 约束：

- 同一 `kb_id` 同时最多一条 `PUBLISHED` 记录

## 5.14 `query_run`

一次 query workflow 的顶层事实，是同步和流式的共同 trace 根节点。

| 字段 | 类型 | 约束 | 说明 |
|------|------|------|------|
| `id` | `uuid` | PK | query run id |
| `request_id` | `varchar(64)` | not null | 本次请求 trace id |
| `session_id` | `uuid` | FK -> `ai_session.id` | 所属会话 |
| `turn_id` | `uuid` | FK -> `ai_turn.id` | 所属轮次 |
| `kb_id` | `uuid` | FK -> `knowledge_base.id` | 命中知识库 |
| `scene_code` | `varchar(32)` | not null | 固定为 `AI_TRIAGE` |
| `request_text` | `text` | not null | 用户输入原文 |
| `normalized_query_text` | `text` | nullable | 归一化后的查询文本 |
| `hospital_scope` | `varchar(64)` | not null | 导诊目录作用域 |
| `catalog_version` | `varchar(64)` | nullable | 本次读取到的目录版本 |
| `index_version_id` | `uuid` | FK -> `knowledge_index_version.id` | 本次使用的索引版本 |
| `status` | `varchar(16)` | not null | 运行状态 |
| `final_triage_stage` | `varchar(32)` | nullable | 最终导诊状态 |
| `final_completion_reason` | `varchar(32)` | nullable | 最终收口原因 |
| `started_at` | `timestamptz` | not null | 开始时间 |
| `finished_at` | `timestamptz` | nullable | 结束时间 |
| `created_at` | `timestamptz` | not null | 创建时间 |

关键索引：

- `idx_query_run_session` on (`session_id`, `created_at desc`)
- `idx_query_run_request` on (`request_id`)
- `idx_query_run_status` on (`status`, `created_at desc`)

写入 ownership：

- Python query workflow 创建和收口

## 5.15 `retrieval_hit`

召回候选事实，不表示已被答案引用。

| 字段 | 类型 | 约束 | 说明 |
|------|------|------|------|
| `id` | `uuid` | PK | hit id |
| `query_run_id` | `uuid` | FK -> `query_run.id` | 所属 query run |
| `chunk_id` | `uuid` | FK -> `knowledge_chunk.id` | 命中 chunk |
| `retriever_type` | `varchar(16)` | not null | 召回器类型 |
| `rank_no` | `integer` | not null | 排名 |
| `vector_score` | `double precision` | nullable | 向量分 |
| `keyword_score` | `double precision` | nullable | 稀疏检索分 |
| `fusion_score` | `double precision` | nullable | 融合分 |
| `rerank_score` | `double precision` | nullable | 重排分 |
| `selected_for_context` | `boolean` | not null | 是否进入 context packing |
| `created_at` | `timestamptz` | not null | 创建时间 |

关键索引：

- `idx_retrieval_hit_query_rank` on (`query_run_id`, `rank_no`)
- `idx_retrieval_hit_chunk` on (`chunk_id`)

写入 ownership：

- Python retrieval workflow

## 5.16 `answer_citation`

最终答案真正使用的证据记录。

| 字段 | 类型 | 约束 | 说明 |
|------|------|------|------|
| `id` | `uuid` | PK | citation id |
| `query_run_id` | `uuid` | FK -> `query_run.id` | 所属 query run |
| `chunk_id` | `uuid` | FK -> `knowledge_chunk.id` | 被引用 chunk |
| `citation_order` | `integer` | not null | 引用顺序 |
| `snippet` | `text` | not null | 最终展示片段 |
| `created_at` | `timestamptz` | not null | 创建时间 |

唯一约束：

- (`query_run_id`, `citation_order`)

关键索引：

- `idx_answer_citation_query` on (`query_run_id`, `citation_order`)

写入 ownership：

- Python generation / grounding workflow

## 6. 主外键关系

核心关系固定为：

- `ai_session 1 -> n ai_turn`
- `ai_turn 1 -> n ai_turn_content`
- `ai_turn 1 -> 1 query_run`
- `query_run 1 -> n ai_model_run`
- `query_run 1 -> n ai_run_artifact`
- `query_run 1 -> n ai_guardrail_event`
- `knowledge_base 1 -> n knowledge_document`
- `knowledge_document 1 -> n knowledge_chunk`
- `knowledge_index_version 1 -> n knowledge_chunk_index`
- `query_run 1 -> n retrieval_hit`
- `query_run 1 -> n answer_citation`

## 7. 运行期写入时序

## 7.1 一次 query 请求

1. 创建或读取 `ai_session`
2. 创建 `ai_turn`
3. 创建 `query_run`
4. 写入 `ai_turn_content` 用户原文
5. 输入护栏命中时写 `ai_guardrail_event`
6. 创建 `ai_model_run`
7. 写 `ai_run_artifact(TRIAGE_MATERIALS)`
8. 写 `retrieval_hit`
9. 写 `answer_citation`
10. 写 `ai_run_artifact(FINAL_TRIAGE_RESULT)`
11. 更新 `query_run`
12. 更新 `ai_turn.stage_after` 和 `is_finalized`
13. 更新 `ai_session.current_stage`

## 7.2 一次 ingestion 请求

1. 创建 `knowledge_document`
2. 创建 `knowledge_index_version`
3. 创建 `ingest_job`
4. worker 写 `knowledge_chunk`
5. worker 写 `knowledge_chunk_index`
6. worker 更新 `knowledge_index_version.status`
7. 发布时创建 `knowledge_release`

## 8. 明确删除的旧设计

以下设计在正式 DDL 中不得继续保留：

- `ai_run_citation`
- `knowledge_document.published_at`
- `knowledge_document.ACTIVE` 兼具发布语义
- “检索候选和最终引用混表”
- “只有当前索引、没有索引版本”

## 9. P1 暂缓项

本文不展开以下 `P1` 表：

- `eval_dataset`
- `eval_case`
- `eval_run`
- `eval_case_result`
- `ai_feedback_task`
- `ai_feedback_review`

P0 migration 完成后，再单独冻结评测和人工复核表。

## 10. 一句话结论

这份 DDL 草案把 Python RAG 服务的数据事实固定成了四层：

- 会话与生成事实
- 文档与索引事实
- 发布与可见性事实
- 检索与证据事实

后续实现必须按这四层落库，不再回到旧的聊天驱动混合设计。
