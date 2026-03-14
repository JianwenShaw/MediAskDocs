# AI 表设计逐表说明（V3）

> 本文对 V3 AI 相关表做逐表、逐重点字段说明。
> 目标不是重复 DDL，而是解释这些表为什么存在、关键字段为什么要这样设计、它们在“Java 主业务系统 + Python AI 服务”架构里分别承担什么职责。

## 1. 设计总原则

- Java 维护业务主事实与监管主事实
- Python 维护 AI 执行现场，并把关键结果结构化回传
- 高敏原文、模型运行、护栏命中、复核流程、知识索引必须拆层
- 业务库只存需要追溯、监管、复核和展示的关键事实，不做调试垃圾场

## 2. `ai_session`

### 2.1 这张表回答什么问题

- 这次 AI 会话是谁发起的
- 属于哪个患者
- 属于哪个科室和业务场景
- 是否关联某次挂号订单
- 这次会话当前是否结束

### 2.2 为什么必须存在

`ai_session` 是 AI 域的业务主实体。

如果没有这张表，而是让 Python 服务自己维护一套会话，或者只靠消息表堆出来，会很快遇到这些问题：

- 无法和患者、挂号、病历建立稳定关联
- 无法统一权限和审计口径
- Java 和 Python 容易各自维护一套 session 真相

因此 V3 明确规定：

- Java 管业务会话主事实
- Python 管执行现场事实

### 2.3 关键字段为什么这样设计

- `session_uuid`：对外稳定业务标识，便于 Java 与 Python 传递和排查
- `patient_id`：业务归属的核心锚点
- `department_id`：用于导诊、预问诊、统计、复核分配
- `related_order_id`：把 AI 会话和挂号订单打通，而不是把诊疗链路孤立起来
- `scene_type`：区分预问诊、健康咨询、随访，后续可决定不同 Prompt 和护栏策略
- `entrypoint`：明确这次会话从哪里进入，避免以后 Web、App、后台工具混用时丢上下文
- `chief_complaint_summary`：列表页和挂号联动常用，不必每次解密原文
- `summary`：会话级总结，适合前台、医生工作台和挂号前摘要展示

### 2.4 为什么不把原文放这里

因为这张表应该是“会话索引头”，不是正文表。

如果把原文也塞进来：

- 查询列表会扫大文本
- 高敏内容暴露范围过大
- 后续访问监管边界模糊

## 3. `ai_turn`

### 3.1 这张表回答什么问题

- 一次会话里第几轮交互发生了什么
- 这一轮是否完成、失败或仍在处理中
- 这一轮的输入/输出哈希是什么

### 3.2 为什么必须单独建表

因为“会话”和“轮次”是两层不同粒度：

- 会话是容器
- 轮次是执行单位

很多后续能力都要依赖轮次，而不是会话整体：

- 某一轮是否需要复核
- 某一轮的模型调用延迟
- 某一轮是否命中护栏

### 3.3 关键字段

- `turn_no`：保证会话内顺序稳定
- `turn_status`：支持失败重试、异步执行或流式场景
- `input_hash` / `output_hash`：用于监管和排查，不必总查密文正文

## 4. `ai_turn_content`

### 4.1 这张表回答什么问题

- 用户原话是什么
- 模型原始回复是什么
- 哪些内容是高敏的，需要加密存储

### 4.2 为什么单独拆成正文层

这是 V3 AI 设计里最关键的一层之一。

AI 问诊原文里经常包含：

- 主诉
- 症状过程
- 既往病史
- 身份线索
- 电话、地址、家族史等隐私信息

如果把这些内容和会话索引、模型运行元数据混在一起：

- 高敏内容被过度暴露
- 普通列表查询也会扫大字段
- 访问监管无法精确约束“谁看过原文”

### 4.3 关键字段

- `content_role`：区分 USER / ASSISTANT / SYSTEM，避免一张 turn 只有一个字段装多种文本
- `content_encrypted`：正文密文存储，是核心字段
- `content_masked`：给工作台、列表页或运营检索提供可控预览，不必每次解密
- `content_hash`：用于去重、审计比对和异常排查

## 5. `ai_model_run`

### 5.1 这张表回答什么问题

- 这一轮到底发生了哪次模型调用
- 是哪个 provider 执行的
- 用了哪个模型
- trace_id 是什么
- 是否启用了 RAG
- latency 和 token 消耗是多少
- 是否发生降级

### 5.2 为什么不能塞进 `ai_turn`

因为“业务轮次”和“模型运行”不是同一维度。

未来一个 turn 很可能包含：

- 一次路由判断
- 一次知识检索
- 一次大模型生成
- 一次失败后的重试

如果都挤在 turn 表里，后续就无法表达多次运行、失败重试和 provider 切换。

### 5.3 关键字段

- `provider_run_id`：Python 侧执行主键，便于跨系统追踪
- `provider_name`：明确这次执行来自 `PYTHON_AI` 还是其他 provider
- `id`：由 Java 在调用 Python 前预创建，作为稳定 `model_run_id`
- `trace_id`：全链路最关键字段，必须稳定透传
- `rag_enabled`：区分纯 LLM 回答和 RAG 回答
- `retrieval_provider`：便于未来把检索能力切换到别的系统时仍可追踪
- `tokens_input` / `tokens_output` / `latency_ms`：成本、性能、告警和容量规划的基础数据
- `run_status` / `is_degraded`：用于降级监控，不应埋在日志里就结束
- `request_payload_hash` / `response_payload_hash`：用于对账和排查，不要求全量存原始 payload

## 6. `ai_run_artifact`

### 6.1 这张表回答什么问题

- 这次运行产出了哪些通用结构化中间产物
- 比如摘要、路由决策、RAG 上下文快照、调试载荷

> **注意**：V3 迁移至 PostgreSQL + pgvector 后，RAG 检索引用（citations）已由专门的 `ai_run_citation` 表承担（详见第 14 节），`ai_run_artifact` 定位为通用调试/中间产物存储。

### 6.2 为什么需要它

模型执行后，真正有业务价值的往往不是“完整原文”，而是结构化结果：

- citations 给前端展示
- summary 给挂号页或病历页展示
- routing 给后续分诊/复核逻辑使用

这些结果不是消息原文，也不是运行元数据，所以需要独立的 artifact 层。

### 6.3 关键字段

- `artifact_type`：区分摘要、引用、路由、RAG 上下文等产物
- `artifact_json`：仅用于低敏或脱敏产物，如摘要、引用、路由结果
- `artifact_encrypted`：用于 `RAG_CONTEXT`、`PROMPT_DEBUG` 等高敏产物
- `retention_until`：为高敏调试载荷设置保留截止时间，避免长期滞留在主业务库

## 7. `ai_guardrail_event`

### 7.1 这张表回答什么问题

- 这次运行被判成什么风险等级
- 最终采取了什么动作
- 命中了哪些规则

### 7.2 为什么必须独立成事件表

护栏不是消息属性，而是监管事实。

你未来经常会问：

- 高风险会话有多少
- 哪类规则触发最多
- 某个模型最近拒答率是否异常

如果把它继续当成消息附属字段，统计和合规视角都会很别扭。

### 7.3 关键字段

- `risk_level`：监管与风控主视角
- `action_taken`：是通过、谨慎回答还是拒答
- `matched_rule_codes`：规则命中详情，支撑复盘
- `input_hash` / `output_hash`：满足追溯而不强制长期暴露原文
- `event_detail_json`：留扩展空间，如命中片段、二级分类等

## 8. `ai_feedback_task`

### 8.1 这张表回答什么问题

- 哪些 AI 结果需要医生复核
- 任务是否已分配
- 指派给了谁
- 当前是否关闭

### 8.2 为什么要有任务表

复核不是简单评论，而是一个流程。至少存在：

- 待办
- 指派
- 处理中
- 已关闭
- 已取消

如果没有任务表，医生工作台和运营后台都很难做。

### 8.3 关键字段

- `task_type`：区分正式评审、纠错、点赞点踩等模式
- `task_status`：支持完整工作流
- `assigned_doctor_id`：支持责任归属和工作台待办
- `created_by`：明确任务来源，是系统自动还是人工发起

## 9. `ai_feedback_review`

### 9.1 这张表回答什么问题

- 任务最终复核结论是什么
- 谁复核的
- 评分多少
- 是否有纠错摘要或意见

### 9.2 为什么和任务分开

因为任务表示“流程状态”，结果表示“处理产出”。

两者分开后更清晰：

- `ai_feedback_task` 管待办和分派
- `ai_feedback_review` 管最终结论

### 9.3 关键字段

- `review_result`：通过、拒绝、纠正
- `review_score`：支持质量评估
- `correction_summary`：承载医生纠正结论
- `review_comment`：保留人工意见

## 10. `knowledge_base`

### 10.1 这张表回答什么问题

- 系统里有哪些知识库
- 是系统级的还是科室级的
- 使用什么向量后端和 embedding 模型

### 10.2 为什么需要它

因为知识不是只有一份全局文档集合。后续很可能出现：

- 系统公共知识库
- 某科室私有知识库
- 某专题临时知识库

`knowledge_base` 是知识治理和可见性控制的入口。

### 10.3 关键字段

- `owner_type` / `owner_dept_id`：明确知识归属边界
- `embedding_model`：方便后续重建索引和追溯入库策略
- `vector_backend`：显式记录向量后端，V3 默认为 `PGVECTOR`（PostgreSQL + pgvector 扩展），不假设永远只有一种后端

## 11. `knowledge_document`

### 11.1 这张表回答什么问题

- 某个知识库里有哪些文档
- 文档来源是什么
- 当前入库状态如何

### 11.2 为什么不只保留 chunk

因为文档是运营和治理单位，chunk 只是检索单位。

如果没有文档层，后续这些操作会非常困难：

- 某篇文档下线
- 某篇文档重建索引
- 某篇文档替换版本
- 后台查看某篇文档的来源和分类

### 11.3 关键字段

- `document_uuid`：文档稳定标识
- `source_uri`：方便追溯来源
- `content_hash`：支持去重和重入库判定
- `document_status`：把入库过程和启用状态显式化，而不是只看日志
- `ingested_by_service`：明确是谁做的入库

## 12. `knowledge_chunk`

### 12.1 这张表回答什么问题

- 文档被切成了哪些块
- 每块文本内容是什么
- 对应哪个 section/page
- 在检索系统里对应哪个稳定锚点

### 12.2 为什么 chunk 文本仍然要留在业务主表

因为业务系统有明确需要：

- citations 展示
- 后台预览引用片段
- 对 RAG 结果做人工抽查
- 对文档分块质量做运营治理

即便向量检索已统一到同一 PostgreSQL 实例（通过 pgvector），chunk 正文仍需保留在 `knowledge_chunk` 业务主表中，以便业务系统直接查询和展示引用。

### 12.3 关键字段

- `chunk_index`：文档内稳定顺序
- `content`：引用展示的基础（`knowledge_chunk_index` 中的向量由此正文生成）
- `section_title` / `page_no`：增强可追溯性
- `vector_ref_id`：**已废弃**——V3 统一迁移至 PostgreSQL + pgvector 后，`knowledge_chunk.id` 本身即为 `knowledge_chunk_index` 的稳定锚点，不再需要额外的外部向量库引用 ID
- `metadata_json`：给未来补充 chunk 标签、清洗策略等扩展位

## 13. `knowledge_chunk_index`

> 本表由 [20-RAG_DATABASE_PGVECTOR_DESIGN.md](./20-RAG_DATABASE_PGVECTOR_DESIGN.md) 引入，属于检索投影层。

### 13.1 这张表回答什么问题

- 某个 chunk 的向量表示是什么
- 关键词索引（tsvector）是什么
- 用什么模型、什么维度生成的 embedding

### 13.2 为什么必须单独建表

这张表是 `knowledge_chunk` 的检索投影，而不是业务主事实。

分离的原因：

- 业务主事实层（`knowledge_chunk`）由 Java 主导，关注正文、section/page、引用展示
- 检索投影层由 Python 主导，关注向量、tsvector、embedding 模型版本
- 两者的写入时机和责任方不同：Java 创建 chunk 记录，Python 在 embedding 完成后写入索引
- 分离后可以独立重建索引而不影响业务主事实

### 13.3 关键字段

- `chunk_id`：外键指向 `knowledge_chunk.id`，稳定锚点
- `embedding`：`VECTOR(1536)` 类型，由 pgvector 扩展提供
- `search_tsv`：PostgreSQL `tsvector` 类型，用于关键词召回和混合检索
- `embedding_model`：记录生成向量的模型版本，便于重建索引时判断是否需要重算
- `indexed_at`：索引写入时间戳

### 13.4 持久化边界

此表由 Python AI 服务直接写入 PostgreSQL，不经过 Java 回传。这是 V3 中 Python 直接写库的两张表之一（另一张是 `ai_run_citation`）。

## 14. `ai_run_citation`

> 本表由 [20-RAG_DATABASE_PGVECTOR_DESIGN.md](./20-RAG_DATABASE_PGVECTOR_DESIGN.md) 引入，属于引用追溯层。

### 14.1 这张表回答什么问题

- 某次 AI 回答引用了哪些知识 chunk
- 每个引用的相似度分数和排名是多少
- 引用是否被最终采纳进回答

### 14.2 为什么需要它

V3 之前，RAG 引用信息存放在 `ai_run_artifact` 的 JSON 中，这带来几个问题：

- 无法按 chunk 维度查询"这个知识片段被引用了多少次"
- 无法做引用质量统计和知识库热度分析
- JSON 内的引用字段缺乏外键约束，无法保证引用的 chunk 确实存在

`ai_run_citation` 把引用关系从 JSON 提升为独立关系事实，支持：

- 单条引用粒度的追溯
- 按 chunk/document/knowledge_base 维度的引用统计
- 引用正确率回归分析

### 14.3 关键字段

- `model_run_id`：外键指向 `ai_model_run.id`，由 Java 预创建后传给 Python
- `chunk_id`：外键指向 `knowledge_chunk.id`
- `retrieval_rank`：本次检索中的排名
- `vector_score` / `keyword_score` / `fusion_score` / `rerank_score`：用于回溯召回与重排效果
- `used_in_answer`：是否被最终纳入回答上下文

### 14.4 持久化边界

此表由 Python AI 服务在 RAG 检索完成后直接写入 PostgreSQL。前提是 Java 已预创建 `ai_model_run` 并把 `model_run_id` 传给 Python。Python 知道检索结果的完整排名和分数，Java 无法也不应二次推测这些执行现场事实。

## 15. 一句话总结

`05-ai.sql` 的设计本质上是在把 AI 领域拆成七种事实：

- 业务会话
- 高敏原文
- 执行运行
- 风险护栏
- 复核
- 知识索引与业务元数据
- 检索投影与引用追溯（`knowledge_chunk_index` + `ai_run_citation`）

只有这样，Java 和 Python 的边界才会稳定，后续的监管、复核、性能和扩展性才不会打架。
