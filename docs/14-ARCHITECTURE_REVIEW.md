# 重写前架构评审与收敛结论

> 状态：Authoritative Baseline
>
> 适用阶段：2026-03 重写启动前
>
> 目的：把已有文档中最容易导致重写返工的口径先冻结，形成一套可直接指导实现的基线。

## 1. 总结论

当前文档体系的大方向是成立的：

- Java 采用模块化单体，Python 独立承载 AI/RAG
- AI 会话、运行元数据、护栏、审计分层建模是合理的
- PostgreSQL + pgvector 统一关系事实与向量检索也是合理的

但在真正开始重写前，必须先冻结以下 4 条基线：

1. 文档为准，当前代码不作为架构依据
2. Java 分层依赖必须统一为可实现的 Hexagonal 口径
3. AI `chat` 的 `model_run_id` 时序必须闭环
4. 知识入库链路必须明确 ownership，避免 Java/Python 双主事实

## 2. P0 实现边界

本轮重写只冻结 `P0`：

- AI/RAG 主链路：会话、轮次、原文、模型运行、检索投影、引用追溯
- 医疗业务闭环：挂号、就诊、病历、诊断、处方
- 最小权限与审计：RBAC、数据范围、操作审计、敏感访问日志

明确降级为 `P1/P2`：

- 复杂排班求解器与排班工程化治理
- AI 人工复核任务流的完整工作台
- 检索全候选留痕、Outbox 可靠投递、归档治理
- 过重的可观测与部署复杂度

## 3. Java 架构基线

### 3.1 模块职责

- `mediask-domain`：领域模型、Port、领域事件
- `mediask-application`：UseCase、事务边界、ACL 编排
- `mediask-infra`：Repository/Client/Redis/DB 适配器
- `mediask-api`：Controller/Security/DTO + Spring Boot 组合根
- `mediask-worker`：任务进程组合根
- `mediask-common`：技术公共能力

### 3.2 依赖规则

- `Application -> Domain`
- `Infrastructure -> Domain`
- `API -> Application + Infrastructure`
- `Worker -> Application + Infrastructure`
- `Domain` 不依赖 `Application/Infrastructure`
- `Application` 不依赖 `Infrastructure`

说明：

- `api/worker` 模块依赖 `infrastructure` 是为了 Spring 装配，不代表 Controller/Job 可以直接写 Repository 或 Client。
- 业务调用链仍然是 `Controller/Job -> UseCase -> Domain Port`。

## 4. AI Chat 基线

### 4.1 主链路

1. Java 创建 `ai_session`
2. Java 创建 `ai_turn`
3. Java 预创建 `ai_model_run(status=RUNNING)`
4. Java 将 `model_run_id`、`turn_id`、`session_uuid` 和 Header `X-Request-Id` 传给 Python
5. Python 执行检索、生成、护栏
6. Python 用 `model_run_id` 直接写 `ai_run_citation`
7. Python 回传 answer / guardrail / tokens / latency
8. Java 更新 `ai_model_run`，并写 `ai_turn_content`、`ai_run_artifact`、`ai_guardrail_event`

### 4.2 为什么要预创建 `ai_model_run`

因为 `ai_run_citation` 必须能稳定外键到一次模型运行。

如果等 Python 返回后再由 Java 创建 `ai_model_run`，就会出现：

- Python 无法稳定写 `ai_run_citation`
- 引用记录和运行记录无法天然关联
- 流式输出时更容易出现半程失败、尾部补写不一致

因此 `model_run_id` 必须由 Java 先分配。

## 5. RAG 入库基线

### 5.1 Ownership

- `knowledge_base / knowledge_document / knowledge_chunk`：Java 业务主事实层
- `knowledge_chunk_index`：Python 检索投影层
- `ai_run_citation`：Python 引用追溯层

### 5.2 P0 推荐链路

1. Java 创建 `knowledge_document(status=UPLOADED/INGESTING)` 并保存源文件位置
2. Java 调用 Python `/knowledge/prepare`
3. Python 完成原始文档解析、清洗、术语归一与 chunk 切分，返回 chunk payload
4. Java 持久化 `knowledge_chunk`
5. Java 调用 Python `/knowledge/index`
6. Python 生成 embedding、构建 `search_lexemes/search_tsv`
7. Python 写入 `knowledge_chunk_index`
8. Java 将 `knowledge_document` 更新为 `ACTIVE`

这样做的原因是：

- 业务事实层只在 Java 保持单一主事实
- Python 负责自己最擅长的解析、切块、检索投影和查询执行
- 数据库权限边界更清晰，和现有 `knowledge_chunk_index/ai_run_citation` 单独写权限设计一致

## 6. AI 输出边界

系统定位是“智能医疗辅助问诊”，不是自动诊断系统。

`P0` 输出边界应冻结为：

- 症状整理
- 风险提示
- 建议就医
- 推荐科室/就诊方向
- 引用依据展示

明确不做：

- 诊断结论
- 处方建议
- 具体药物剂量指导

## 7. 现在最值得直接开工的文档

重写时建议按这个顺序阅读：

1. `07E-DATABASE-PRIORITY.md`
2. `01-OVERVIEW.md`
3. `07B-AI-AUDIT-V3.md`
4. `20-RAG_DATABASE_PGVECTOR_DESIGN.md`
5. `10-PYTHON_AI_SERVICE.md`
6. `19-ERROR_EXCEPTION_RESPONSE_DESIGN.md`

## 8. 一句话结论

这次重写不需要再继续扩设计面，而是要先把 Java 分层、AI `model_run_id` 时序、RAG 入库 ownership 这三件事彻底定死。
