# MediAsk RAG 系统重构分析与替代架构方案

## 1. 文档定位

本文用于总结当前 `mediask-rag` 仓库在 RAG / AI 服务方向上的主要问题，并给出一套可以完全替代现有方案的新架构设计。

设计前提如下：

- 不默认继承当前实现
- 允许推翻当前 Python 服务的主链路组织方式
- 以“做成一个真正有完成度、有答辩亮点的毕业设计项目”为目标
- 在保证可落地的前提下，优先提升系统设计合理性、RAG 完整性、工程可维护性与展示效果

---

## 2. 现有方案核心问题总结

### 2.1 文档与实现存在明显脱节

- 文档多次强调“当前代码不作为架构依据”，但仓库里并没有与文档对应的正式可执行 schema。
- [docs/docs/07-DATABASE.md](../docs/07-DATABASE.md) 规划了完整 SQL 组织方式，但仓库中唯一 `.sql` 文件 [docs/docs/15-PERMISSIONS/appendix/A2-SCHEMA.sql](../docs/15-PERMISSIONS/appendix/A2-SCHEMA.sql) 已明确标注为废弃草案。
- 结果是：数据库设计停留在 Markdown 层，工程实现缺少 authoritative DDL、migration 和真实落库基线。

### 2.2 文档口径本身存在冲突

- [docs/PROJECT_PLAN.md](../PROJECT_PLAN.md) 仍写了 `LangChain`、`LangGraph`、SSE 流式等方案。
- 但 [docs/docs/10-PYTHON_AI_SERVICE.md](../docs/10-PYTHON_AI_SERVICE.md) 已明确 `P0` 不强依赖 LangChain/LangGraph，且 Python 不再提供正式流式接口。
- 这说明项目设计口径尚未真正收敛，容易导致后续继续反复重构。

需要补充的是：

- “不做正式流式接口”并不是一个架构上更优的结论，而是此前为了适配 Java 强耦合调用链做出的折中。
- 如果本轮重构目标是把 RAG 服务真正做成独立、标准、可演示的 AI 服务，那么应当恢复并冻结“Python 侧提供正式流式接口”的设计口径。

### 2.3 当前服务是“聊天业务驱动”，不是“RAG 驱动”

- 当前 `ChatService` 同时负责：
  - 护栏判断
  - 知识检索
  - 目录同步
  - Prompt 拼装
  - 结构化输出解析
  - 导诊状态机映射
- 见 [app/services/chat.py](../../app/services/chat.py) 与 [app/services/chat_runtime.py](../../app/services/chat_runtime.py)。
- 这会导致聊天场景、RAG 内核、医疗导诊业务三者高度耦合，任何修改都会沿整条链路扩散。

### 2.4 RAG 主链路不完整

当前已有的能力主要是：

- 文本切块
- embedding
- dense recall
- sparse recall
- RRF 融合

但缺失关键环节：

- query rewrite / query analyze
- rerank
- chunk 邻接扩展
- token budget 上下文构造
- answer grounding 校验
- answer-level citation 精确对齐
- retrieval 评测与回答评测闭环

因此现状更像“带向量检索的聊天接口”，而不是完整 RAG 系统。

### 2.5 检索结果和最终引用被混淆

- 当前 `KnowledgeSearchService` 在检索阶段就直接写 `ai_run_citation`。
- 且 `used_in_answer=True` 被固定写死。
- 见 [app/services/rag/search.py](../../app/services/rag/search.py)。

这会带来两个问题：

- 无法区分“召回候选”与“最终被答案真正使用的证据”
- 无法支持后续的 grounding 分析、回答复盘和 citation 精度评测

这是当前 RAG 设计里最核心的问题之一。

### 2.6 上下文构造质量偏弱

- 当前检索 SQL 只读 `content_preview`，不是 chunk 正文。
- 见 [app/repositories/knowledge_search.py](../../app/repositories/knowledge_search.py) 与 [app/services/chat_prompts.py](../../app/services/chat_prompts.py)。
- 这意味着模型吃到的上下文是裁剪预览，而不是完整证据片段。

结果是：

- 召回到了不代表真正喂给模型了
- 喂给模型了也不代表足够支撑回答
- 引用追溯的可信度被削弱

### 2.7 文档处理链路是伪完成

- `prepare` 标称支持 `PDF` / `DOCX` / `MANUAL` / `MARKDOWN`
- 实际实现只是 `read_text(encoding="utf-8")`
- 见 [app/services/rag/prepare.py](../../app/services/rag/prepare.py)

这意味着：

- `PDF/DOCX` 当前并未真实支持
- 文档解析能力和文档设计目标不一致
- 对毕设来说，这是很容易在答辩中被追问出问题的点

### 2.8 业务适配层反向污染了 RAG 内核

- 当前 Python 服务在主链路中同步拉取 Java 科室目录，并把目录版本校验直接嵌入问答流程。
- 见 [app/services/triage/catalog.py](../../app/services/triage/catalog.py)。

这说明当前没有把：

- 通用 RAG 能力
- 医疗导诊场景适配
- 上游业务系统依赖

三者拆层。

结果就是：任何业务依赖波动，都会直接打断 AI 主链路。

### 2.9 缺少异步 ingestion 和索引状态机

当前 `prepare`、`index`、`search` 都是同步接口式思维，缺少：

- ingestion job
- 异步 worker
- 文档状态流转闭环
- 索引版本切换
- 重试与失败补偿

这会导致项目只能维持 demo 级文档入库，而很难支撑“知识库治理”这一毕业设计亮点。

### 2.10 缺少评测闭环

当前没有形成完整评测体系：

- 没有 retrieval benchmark
- 没有 answer groundedness 评测
- 没有 citation precision / recall
- 没有 gold set
- 没有知识库更新后的回归评测

对于 RAG 项目而言，没有评测闭环，系统很难证明“做对了”。

### 2.11 测试更多是契约骨架，不是能力验证

仓库当前测试以 `unittest + mock` 为主。

实际核对结果：

- `uv run pytest` 无法直接运行，因为 `pytest` 不在当前依赖中
- `uv run python3 -m unittest discover -s tests` 可以跑过 37 个测试

但这些测试主要验证：

- DTO 校验
- 路由响应结构
- mock 检索排序逻辑
- mock 目录同步逻辑

缺少真实验证：

- PostgreSQL + pgvector 集成
- embedding/LLM 接入
- 文档解析
- 异步索引链路
- 端到端 RAG 主流程

---

## 3. 为什么建议直接重构，而不是继续补丁式演进

原因不是“代码写得不够优雅”，而是当前系统的组织中心错了。

当前组织方式是：

`chat API -> 导诊逻辑 -> 顺便调用 RAG`

更合理的组织方式应该是：

`知识处理 -> 检索 -> 重排 -> 证据构造 -> 生成 -> 场景适配`

也就是说：

- 当前是“聊天驱动 RAG”
- 新方案应改为“RAG 内核驱动场景”

如果继续在现有结构上加功能，只会不断把医疗场景、知识检索、问答生成、审计留痕缠得更紧。

---

## 4. 新架构设计总览

建议把新系统设计为：

**FastAPI API 进程 + Worker 进程 + PostgreSQL + Redis + 对象存储**

整体采用“单服务内部分层 + 异步任务驱动”，不建议在毕设阶段继续拆更多微服务。

### 4.1 目标架构

```text
Browser / Java Business System
            |
            v
      FastAPI Query API
            |
            v
    Query Workflow / Scene Adapter
            |
            v
      RAG Core Pipeline
            |
    +-------+--------+
    |                |
    v                v
PostgreSQL       LLM / Embedding / Reranker
pgvector

Document Upload / KB Admin
            |
            v
       Ingest API
            |
            v
      Job Queue / Worker
            |
            v
 Parse -> Chunk -> Embed -> Index -> Activate
```

### 4.2 设计原则

- RAG 内核和医疗业务场景彻底拆层
- ingestion 与 query 分离
- 检索候选和最终引用分离
- Python 侧提供标准流式接口，Java 不再承担伪流式拼装职责
- 支持异步任务和索引版本切换
- 支持评测、回归和治理
- 技术亮点集中在“可追溯、可评测、可演化”

---

## 5. 核心链路详细说明

### 5.1 文档处理与索引链路

建议流程：

1. 上传文档，写入 `knowledge_document`
2. 创建 `ingest_job`
3. Worker 异步执行解析
4. 执行清洗、归一化、chunk 切分
5. 生成 embedding 与 lexical index
6. 写入 `knowledge_chunk` 与 `knowledge_chunk_index`
7. 生成新的 `index_version`
8. 激活该版本为当前检索版本

这样做的好处：

- 避免同步长耗时请求
- 支持失败重试
- 支持重建索引
- 支持“新索引构建完成后再切换”

### 5.2 检索与召回链路

建议流程：

1. query normalize
2. 可选 query rewrite
3. dense retrieval
4. sparse retrieval
5. fusion
6. rerank
7. chunk merge / 邻接扩展
8. context packing

建议最小策略：

- dense：pgvector
- sparse：`tsvector` 或 BM25
- fusion：RRF
- rerank：对 top20 做轻量重排

### 5.3 重排与上下文构造

建议单独建 `Context Builder`，负责：

- 去重
- 合并相邻 chunk
- 去掉弱相关片段
- 控制 token budget
- 生成最终喂给模型的 evidence blocks

这是当前系统缺失最明显、但对效果提升很大的能力。

### 5.4 生成与回答策略

建议输出结构统一为：

- `answer`
- `abstain_reason`
- `risk_level`
- `citations`
- `evidence_summary`
- `is_grounded`

生成策略应改为：

- 先判断是否足够回答
- 不足则拒答或保守答复
- 足够则生成 grounded answer
- 生成后再做 citation 对齐或 grounding 检查

不要继续沿用“召回了几个 chunk 就默认能答”的路径。

### 5.5 标准流式传输接口

这一点需要明确修正：

- 新方案应当正式支持标准流式接口。
- 之前否定流式，并不是因为 RAG 不适合流式，而是因为 Java 服务耦合在主链路中，Python 很难直接持有完整生成过程。
- 既然本轮设计目标是“以 RAG 服务为中心重构”，就应该让 Python 重新成为流式输出的第一责任方。

建议接口口径如下：

- `POST /api/v1/query`
  - 返回完整结构化结果
  - 适合后台任务、评测、同步调用
- `POST /api/v1/query/stream`
  - 返回标准 `text/event-stream`
  - 由 Python 直接向前端或 Java 网关输出真实流

建议优先采用 SSE，而不是先上 WebSocket，原因是：

- 更适合单向 token 输出
- FastAPI 实现简单
- 对毕设更容易讲清楚
- 与“问答生成流”场景天然匹配

建议流式事件模型如下：

- `start`
  - 返回 `query_run_id`、`session_id`、`turn_id`
- `retrieval`
  - 返回已完成的检索阶段信息，如召回数量、命中的知识库
- `delta`
  - 返回模型生成的增量文本
- `citation`
  - 在生成后段或结束前补发引用信息
- `final`
  - 返回完整结构化结果：`answer`、`citations`、`risk_level`、`abstain_reason`、`is_grounded`
- `done`
  - 标识流结束
- `error`
  - 显式返回错误，不做静默降级

关键约束建议冻结为：

- Java 如继续存在，只做调用方或网关，不再自己拼伪流式文本
- 检索、重排、grounding 仍在流开始前或流中受控执行，不允许为了“看起来快”绕开 RAG 主链路
- 结构化结果以 `final` 事件为准，不从中间 `delta` 反解析业务字段
- `query_run`、`ai_model_run`、`answer_citation` 等落库记录必须与流式请求共享同一条 trace

这会让系统从“能回答”提升到“能以标准 AI 服务方式回答”，对毕设展示也更有说服力。

### 5.6 医疗导诊场景适配

医疗导诊不应成为 RAG 内核的一部分。

应作为 `scene adapter`：

- 输入：用户消息、上下文、上游业务参数
- 调用：通用 query workflow
- 输出：导诊结构化结果

这样后续还可以扩展：

- 通用知识问答
- 患者教育
- 医生参考问答
- 病历检索辅助

### 5.7 异步任务设计

建议至少有以下任务类型：

- `ingest_document`
- `reindex_document`
- `rebuild_knowledge_base`
- `run_eval_suite`
- `refresh_scene_cache`

### 5.8 缓存与存储设计

建议：

- PostgreSQL：权威数据与向量索引
- Redis：任务队列、catalog cache、query embedding cache
- Object Storage / Local FS：原始文档、解析中间产物

不建议在 P0 缓存最终医疗回答。

### 5.9 评测、监控、可观测性设计

建议最小指标：

- `ingest_job_success_rate`
- `query_latency_ms`
- `retrieval_hit_rate`
- `citation_coverage`
- `abstain_rate`
- `cache_hit_rate`

建议最小评测维度：

- `Recall@K`
- `MRR`
- `Citation Precision`
- `Grounded Answer Rate`
- `Safety Violation Rate`

### 5.10 面向毕设展示的亮点设计

推荐亮点：

- 异步文档入库与索引版本切换
- 混合检索 + 重排
- 标准 SSE 真流式回答
- 显式证据引用追溯
- grounded answer / abstain 机制
- 检索与回答评测闭环
- 医疗场景护栏与风险分级

---

## 6. 模块与职责划分

建议新的 Python 服务按以下方式组织：

```text
app/
  api/
    query.py
    ingest.py
    admin.py
  workflows/
    query_workflow.py
    ingest_workflow.py
    eval_workflow.py
  domain/
    knowledge/
    retrieval/
    generation/
    safety/
    scene/
  repositories/
  integrations/
    llm/
    embedding/
    reranker/
    object_storage/
    upstream_business/
  worker/
  observability/
```

### 6.1 核心职责说明

- `api`
  - 只处理协议、认证、DTO、响应映射
- `workflows`
  - 编排完整链路，不承载底层算法细节
- `domain.knowledge`
  - 管文档、chunk、index version
- `domain.retrieval`
  - 管 query analyze、召回、融合、重排、context build
- `domain.generation`
  - 管 prompt、structured output、citation grounding
- `domain.safety`
  - 管 PII、护栏、医疗边界
- `domain.scene`
  - 管医疗导诊等场景适配
- `repositories`
  - 只做数据访问
- `integrations`
  - 统一封装 LLM / Embedding / Reranker / 上游接口
- `worker`
  - 处理异步任务与周期任务

---

## 7. 数据模型与新数据库表清单

这里给出一份面向“重构后的 Python RAG 服务”的新表清单。

注意边界：

- 这份表清单只覆盖 RAG / AI 服务自有数据，不再把挂号、接诊、病历、排班等整套业务库混进 Python 服务的主设计。
- 如果项目仍与 Java 共用同一个 PostgreSQL 实例，这些业务表可以共存，但不属于 Python RAG 服务的核心 ownership。
- 目标不是继续维护原来那套“大而全”的 AI 子集，而是收敛出一套真正能支撑 RAG 主链路、流式回答、评测闭环的 authoritative baseline。

### 7.1 设计取向

这套新表设计围绕五条主线组织：

- 会话与模型运行
- 文档与索引
- 发布与可见性控制
- 检索与证据追溯
- 评测与质量闭环
- 人工复核与治理

另外需要先冻结一个关键判断：

- 如果系统要支持“显式发布”，`knowledge_document` 就不应该继续同时承担“文档源事实 + ingestion 状态 + 对外发布状态”三类职责。
- 更合理的做法是把这三件事拆开：
  - `knowledge_document` 只回答“这篇文档是什么”
  - `ingest_job` 只回答“这篇文档处理得怎么样”
  - `knowledge_index_version / knowledge_release` 只回答“这篇文档或这批索引是否已正式上线”

### 7.2 建议保留并改造的旧表

以下设计思路是合理的，可以保留：

- `knowledge_document / knowledge_chunk / knowledge_chunk_index` 三层分离
- Python 写检索投影层
- PostgreSQL + pgvector 统一存储
- `request_id` 全链路透传

建议保留但改造的表如下：

| 旧表 | 处理建议 | 原因 |
|------|----------|------|
| `ai_session` | 保留 | 会话头仍然有必要 |
| `ai_turn` | 保留 | 多轮问答仍需轮次建模 |
| `ai_turn_content` | 保留 | 原文与高敏内容应分层 |
| `ai_model_run` | 保留并增强 | 需要承载同步/流式两类生成运行信息 |
| `ai_run_artifact` | 保留 | 用于存结构化产物与中间结果快照 |
| `ai_guardrail_event` | 保留 | 医疗场景需要独立护栏留痕 |
| `knowledge_base` | 保留 | 知识库治理入口仍成立 |
| `knowledge_document` | 保留但收缩职责 | 只保留文档源事实，不再混入发布语义 |
| `knowledge_chunk` | 保留并增强 | 继续作为稳定引用锚点 |
| `knowledge_chunk_index` | 保留并增强 | 继续作为检索投影层 |

### 7.3 建议直接删除或替换的旧表设计

- 检索即写最终 citation
- `ChatService` 作为系统总编排器
- 同步式 ingestion
- 非正式 schema 设计
- “只靠文档描述、不落 migration”

具体建议如下：

| 旧表 / 旧设计 | 处理建议 | 原因 |
|---------------|----------|------|
| `ai_run_citation` | 删除，拆成 `retrieval_hit` + `answer_citation` | 召回候选与最终引用是两类事实，不能混表 |
| `ai_retrieval_run` | 不单独建表，合并进 `query_run` | 对当前毕设范围来说单独拆表收益不高 |
| “文档入库状态只写在接口流程里” | 删除 | 改为 `knowledge_document + ingest_job` 状态驱动 |
| `knowledge_document.published_at + ACTIVE` | 删除这类混合语义 | 发布状态不应和文档源事实、处理状态混在一起 |
| “伪流式只返回完整 answer 再前端打字机展示” | 删除 | 新方案要求 Python 提供真实流式接口 |

### 7.4 确定版表结构

这里不再保留多套备选结构，直接冻结为唯一方案：

- 采用 `标准版 + 显式发布`
- 发布粒度先按 `index version` 管理
- 不引入 `knowledge_release_item`
- 不引入额外审批子表

这套方案的职责拆分如下：

- `knowledge_document`
  - 只存文档源事实
- `ingest_job`
  - 只存处理状态
- `knowledge_index_version`
  - 只存索引构建与激活状态
- `knowledge_release`
  - 只存发布动作与发布结果

建议把新表清单收敛为 `P0 必做 16 张 + P1 建议 6 张`。

#### 7.4.1 P0 必做表

| 表名 | 模块 | 处理方式 | 作用 |
|------|------|----------|------|
| `ai_session` | 会话 | 保留 | 会话头，表示一次问答会话 |
| `ai_turn` | 会话 | 保留 | 多轮消息与轮次管理 |
| `ai_turn_content` | 会话 | 保留 | 用户原文、附件文本、脱敏前内容等高敏正文 |
| `ai_model_run` | 生成 | 保留并增强 | 记录一次模型调用，支持同步/流式、模型参数、耗时、状态 |
| `ai_run_artifact` | 生成 | 保留 | 记录摘要、路由结果、结构化 JSON、调试产物 |
| `ai_guardrail_event` | 安全 | 保留 | 记录输入/输出护栏命中 |
| `knowledge_base` | 知识治理 | 保留 | 知识库主表 |
| `knowledge_document` | 知识治理 | 保留但收缩职责 | 文档元数据、来源信息、内容哈希、所有权，不再承载发布状态 |
| `knowledge_chunk` | 知识治理 | 保留并增强 | chunk 正文、定位信息、引用展示信息 |
| `knowledge_chunk_index` | 检索 | 保留并增强 | 向量、稀疏检索字段、权重、激活状态 |
| `knowledge_index_version` | 索引治理 | 新增 | 管理索引版本、激活版本、构建批次 |
| `ingest_job` | ingestion | 新增 | 文档解析、切块、嵌入、建索引任务状态 |
| `knowledge_release` | 发布治理 | 新增 | 显式发布某个索引版本，控制是否进入线上检索 |
| `query_run` | 查询链路 | 新增 | 一次 query workflow 的顶层事实，贯穿同步与流式 |
| `retrieval_hit` | 检索追溯 | 新增 | 记录召回候选、分数、rank、来源召回器 |
| `answer_citation` | 回答追溯 | 新增 | 记录最终回答真正使用的证据 chunk |

#### 7.4.2 P1 建议表

| 表名 | 模块 | 处理方式 | 作用 |
|------|------|----------|------|
| `eval_dataset` | 评测 | 新增 | 评测集头信息 |
| `eval_case` | 评测 | 新增 | 单条问题、标准证据、标准答案 |
| `eval_run` | 评测 | 新增 | 一次评测批次执行 |
| `eval_case_result` | 评测 | 新增 | 每条 case 的检索与回答结果 |
| `ai_feedback_task` | 人工复核 | 保留或降为 P1 | 医生/人工复核任务 |
| `ai_feedback_review` | 人工复核 | 保留或降为 P1 | 复核结论、问题标签、修正建议 |

### 7.5 推荐字段职责

为了让后续 DDL 设计更稳，建议先冻结每张表的职责边界。

#### 7.5.1 会话与生成

- `ai_session`
  - 一次会话级容器
  - 关联用户、场景类型、当前状态
- `ai_turn`
  - 一轮问答事实
  - 关联用户消息、系统回复、轮次序号
- `ai_turn_content`
  - 存原始文本、预处理文本、附件抽取文本
  - 保留高敏内容分层
- `ai_model_run`
  - 记录每次模型运行
  - 建议增加：`run_type`、`stream_mode`、`status`、`started_at`、`finished_at`
- `ai_run_artifact`
  - 记录结构化产物
  - 如 query rewrite、路由判断、risk summary、final structured output

#### 7.5.2 文档与索引

- `knowledge_base`
  - 知识库入口
  - 管 embedding 配置、检索策略、可见性
- `knowledge_document`
  - 文档源事实
  - 只保存标题、来源、所有权、内容哈希、逻辑删除等稳定信息
- `knowledge_chunk`
  - 稳定证据单元
  - 保存正文、预览、页码、段落位置、引用标题
- `knowledge_chunk_index`
  - 检索投影
  - 保存 `embedding`、`search_tsv`、权重、是否激活
- `knowledge_index_version`
  - 索引版本事实
  - 支持“构建完成后切换”，避免查询读到半成品
- `ingest_job`
  - ingestion 作业状态
  - 建议区分：`PARSE / CHUNK / EMBED / INDEX / ACTIVATE`
- `knowledge_release`
  - 显式发布事实
  - 建议字段至少包含：`release_type`、`target_index_version_id`、`status`、`published_at`、`published_by`

#### 7.5.3 检索与证据追溯

- `query_run`
  - 一次完整查询主链路事实
  - 是同步接口和流式接口共同的 trace 根节点
  - 建议关联：`session_id`、`turn_id`、`model_run_id`、`index_version_id`
- `retrieval_hit`
  - 记录候选召回
  - 应保存：`retriever_type`、`rank`、`vector_score`、`keyword_score`、`fusion_score`、`rerank_score`
- `answer_citation`
  - 记录最终答案使用的证据
  - 应保存：`query_run_id`、`chunk_id`、`citation_order`、`snippet`

#### 7.5.4 推荐状态语义

建议把状态语义明确拆成三层：

- `knowledge_document`
  - 不放 `ACTIVE / PUBLISHED`
  - 只保留文档生命周期，如 `DRAFT / ENABLED / ARCHIVED`
- `ingest_job`
  - 放处理状态，如 `PENDING / RUNNING / SUCCEEDED / FAILED`
- `knowledge_release`
  - 放发布状态，如 `DRAFT / PUBLISHED / REVOKED`

这样就不会再出现“一个字段同时表示处理完成和已上线”的混乱。

### 7.6 推荐删除后的新旧映射

| 旧结构 | 新结构 |
|--------|--------|
| `ai_run_citation` | `retrieval_hit` + `answer_citation` |
| 检索流程内隐式状态 | `query_run` |
| 文档入库阶段散落在接口/脚本中 | `ingest_job` |
| 只有当前索引、没有版本概念 | `knowledge_index_version` |
| `knowledge_document.published_at + ACTIVE` | `knowledge_release` |

### 7.7 为什么这版表清单更合理

这版表清单相较原方案，主要有四个改进：

1. 表数量显著收敛，聚焦 Python RAG 服务真正拥有的核心数据。
2. 数据事实分层更清晰，尤其是把“检索候选”和“最终引用”拆开了。
3. 把“文档事实”“处理状态”“发布状态”拆开了，可以自然支持显式发布。
4. 可以同时支撑同步接口和标准流式接口，不会再因为流式而破坏追溯结构。
5. 兼顾毕设可落地性，P0 足够完整，P1 又能形成答辩亮点。

---

## 8. 技术选型建议

### 8.1 必须做

- `FastAPI`
- `PostgreSQL + pgvector`
- `Redis`
- `SQLAlchemy 2`
- `Alembic`
- `OpenAI SDK`
- 标准 `SSE` 流式接口
- 中文分词库 `jieba` 或 `pkuseg`

### 8.2 建议做

- 任务队列：`ARQ + Redis` 或 `Celery + Redis`
- 对象存储：`MinIO` 或本地文件存储
- 监控：`Prometheus + Grafana`
- reranker：优先远程 API 方案

### 8.3 可选加分项

- `LangGraph`
- `OpenTelemetry`
- 反馈标注后台
- 简易评测面板

注意：

- LangChain / LangGraph 不应再作为主链路基础前提
- 它们只能是增强项，不能继续主导架构

---

## 9. 新方案相较旧方案的收益与代价

### 9.1 主要收益

- 架构清晰，便于论文和答辩讲解
- RAG 主链路完整度明显提升
- 检索、引用、回答可追溯
- 支持异步入库和版本治理
- 支持评测和回归
- 场景扩展更容易

### 9.2 主要代价

- 需要重做 schema 和 migration
- 需要引入 worker / queue / cache
- 初期实现工作量高于继续 patch 当前代码
- 部分现有代码需要直接废弃

---

## 10. 分阶段实施路线图

### 10.1 第一阶段：必须做

- 冻结新边界：RAG 内核 vs 医疗场景适配
- 冻结接口口径：`/api/v1/query` + `/api/v1/query/stream`
- 输出 authoritative schema
- 建立 migration
- 建立新目录结构
- 建立 ingestion job 和 worker 骨架

### 10.2 第二阶段：必须做

- 实现真实文档解析与 chunk
- 实现 hybrid retrieval
- 实现 query run / retrieval hit / answer citation
- 实现标准 SSE 真流式输出
- 完成最小可用的 RAG 主链路

### 10.3 第三阶段：必须做

- 实现 generation + grounding
- 实现保守答复 / abstain 策略
- 实现医疗导诊场景 adapter
- 完成端到端联调

### 10.4 第四阶段：建议做

- 加入 rerank
- 加入缓存
- 加入最小评测集
- 加入基础 dashboard

### 10.5 第五阶段：可选加分项

- 反馈闭环
- 多场景 scene adapter
- 评测看板
- 更细的安全策略与解释能力

---

## 11. 毕设亮点总结

如果按新方案落地，答辩时最值得强调的亮点是：

1. RAG 不是外挂功能，而是系统一等公民
2. 系统具备“业务事实层 / 检索投影层 / 回答证据层”三层模型
3. 文档入库采用异步任务与索引版本化
4. 检索链路采用 hybrid retrieval + rerank
5. 回答具备显式 citation 与 grounded answer 机制
6. 系统具备最小可行评测闭环
7. 医疗场景中实现了保守答复与风险护栏，而非无约束生成

---

## 12. 风险点与降级方案

### 12.1 时间风险

如果时间不足，不要优先做：

- Agent 编排
- 多模型协同
- 复杂前端工作台
- 复杂事件总线

### 12.2 技术降级策略

- 如果 reranker 来不及，先做 dense + sparse + RRF
- 如果任务队列太重，先用 DB job table + polling worker
- 如果对象存储来不及，先用本地文件系统
- 如果 PDF/DOCX 全支持来不及，P0 只支持 Markdown / 文本可抽取 PDF
- 如果业务系统范围太大，优先做深 RAG 主链路，再做最小挂号承接演示

### 12.3 工程边界建议

当前最不该继续做的事情是：

- 继续在现有 `chat` 主链路上堆逻辑
- 继续扩“文档很多、实现很浅”的大蓝图
- 把时间花在重型基础设施而不是 RAG 质量本身

---

## 13. 最终建议

对当前仓库，建议采取的策略不是“继续补完现有 Python 服务”，而是：

**以新 RAG 架构为中心重建主链路，把现有实现中还能复用的 request_id、错误协议、pgvector 选型等保留下来，其余围绕聊天主流程强耦合的部分直接废弃。**

如果目标是“做一个真正像样的 RAG 毕设项目”，这条路线明显优于继续在现有结构上修补。
