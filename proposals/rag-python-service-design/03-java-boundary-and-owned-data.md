# Java 服务边界与自有数据冻结版

## 1. 文档定位

本文回答一个关键问题：

在新的 `docs/proposals/` 基线下，Java 服务是否还需要读取 Python RAG 服务内部 AI 表。

结论固定为：

**Java 不再读取 Python RAG 服务内部 AI 表。**

Java 只做三件事：

- 维护业务主数据
- 发布 Redis 导诊目录
- 调用 Python API 并消费最终结构化 `triage_result`

## 2. Python 与 Java 的数据边界

### 2.1 Python 自有数据

以下数据属于 Python RAG 服务内部实现事实：

- `ai_session`
- `ai_turn`
- `ai_turn_content`
- `ai_model_run`
- `ai_run_artifact`
- `ai_guardrail_event`
- `knowledge_base`
- `knowledge_document`
- `knowledge_chunk`
- `knowledge_chunk_index`
- `knowledge_index_version`
- `ingest_job`
- `knowledge_release`
- `query_run`
- `retrieval_hit`
- `answer_citation`

这些表的作用是：

- 支撑 RAG 主链路
- 支撑追踪与审计
- 支撑证据追溯
- 支撑知识治理
- 支撑评测与调试

这些表**不属于 Java 运行时依赖**。

### 2.2 Java 自有数据

以下数据仍归 Java 业务系统：

- 科室主数据
- 排班、挂号、接诊
- 患者业务数据
- AI 导诊结果页承接数据
- AI 导诊历史记录

Java 应保存的是**最终业务结果快照**，不是 Python 内部执行明细。

## 3. Java 禁止读取的内容

新方案下，Java 不应再做以下事情：

- 直接查询 Python 的 `ai_*` 表
- 直接查询 Python 的 `knowledge_*` 表
- 直接查询 Python 的 `query_run / retrieval_hit / answer_citation`
- 根据 Python 数据库里的中间态判断页面流转
- 从 Python 内部表拼接结果页

一句话说：

**Python 内部库对 Java 来说不是集成接口。**

## 4. Java 正确的集成方式

Java 和 Python 的运行时集成只通过两种通道：

### 4.1 Redis 目录发布

Java 发布：

- `triage_catalog:active:{hospital_scope}`
- `triage_catalog:{hospital_scope}:{catalog_version}`

Python 只读，不回写。

### 4.2 Python HTTP API

Java 调用：

- `POST /api/v1/query`
- `POST /api/v1/query/stream`

Java 只消费 Python 返回的：

- `request_id`
- `session_id`
- `turn_id`
- `query_run_id`
- `triage_result`

运行时不再需要数据库直连读取 Python 内部事实。

## 5. Java 应该保留的 AI 结果数据

Java 仍然应该保留一套自己的“业务承接结果表”。

原因很直接：

- 结果页要展示
- 挂号链路要承接
- 用户历史要查询
- Java 业务系统不能反向依赖 Python 内部表

因此 Java 应落库的是：

- 会话级业务快照
- 每轮 finalized 导诊结果
- 推荐科室承接结果
- 高风险阻断结果

而不是 Python 的中间执行痕迹。

## 6. Java 建议保留的数据字段

P0 建议 Java 至少持久化以下字段：

- `session_id`
- `turn_id`
- `query_run_id`
- `triage_stage`
- `triage_completion_reason`
- `next_action`
- `risk_level`
- `chief_complaint_summary`
- `recommended_departments`
- `care_advice`
- `blocked_reason`
- `catalog_version`
- `created_at`

这些字段来自 Python 返回的最终结构化结果。

## 7. Java 建议删除的旧依赖

如果当前 Java 侧已经存在以下依赖，应视为旧设计并逐步删除：

- 读取 Python AI 表生成结果页
- 读取 Python AI 表判断是否完成导诊
- 读取 Python AI 表提取推荐科室
- 从聊天文本里反解析科室和风险状态
- 根据中间流式文本判断是否跳转结果页

## 8. Java 最小承接模型建议

P0 不需要让 Java 再维护一套复杂 AI 内部模型。

Java 最小只需要两类数据：

### 8.1 导诊结果快照

用于：

- 结果页展示
- 历史记录
- 高风险记录

### 8.2 挂号承接信息

用于：

- 从导诊结果页进入挂号页
- 根据 `department_id` 查询业务排班与号源

也就是说，Java 只保留**业务面向的数据模型**，不保留 Python 的内部 RAG 运行模型。

## 9. 结果页与挂号承接边界

固定边界如下：

- Python 负责推荐方向
- Java 负责业务承接

具体来说：

- Python 给出 `recommended_departments`
- Java 校验 `catalog_version + department_id`
- Java 根据 `department_id` 查业务排班和号源
- Java 生成结果页和挂号入口

Python 不负责：

- 查排班
- 查号源
- 生成挂号订单参数

## 10. 为什么这样更合理

这样拆分有四个直接收益：

1. Python 和 Java 解耦，运行时不再跨服务读内部库。
2. Python 可以独立演进 RAG 内部实现，而不破坏 Java。
3. Java 只承接稳定业务真相，联调面更小。
4. 答辩时边界清楚，容易解释“谁拥有什么数据”。

## 11. 最终冻结结论

最终口径固定为：

- Java 不读取 Python RAG 服务内部 AI 表
- Python 内部表只服务 Python 自己
- Java 只通过 Redis 和 Python API 与 Python 集成
- Java 自己持久化最终业务结果快照

一句话总结：

**Java 不再读 Python 的 AI 内部库，只接 Python 的最终结构化结果，并在 Java 自己的业务域里完成结果页与挂号承接。**
