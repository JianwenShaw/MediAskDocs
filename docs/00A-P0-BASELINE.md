# 毕设实施基线（P0/P1/P2）

> 状态：Authoritative Execution Baseline
>
> 适用阶段：开发启动前、实现阶段、论文与答辩范围说明
>
> 目的：把“目标蓝图”和“当前必须落地的范围”分开，避免继续按完整医院系统平均推进。

## 1. 一句话主线

本项目的毕设主线固定为：

**患者发起 AI 辅助问诊 -> RAG 检索与引用追溯 -> 推荐科室/建议就医 -> 挂号 -> 医生接诊 -> 病历/诊断/处方 -> 权限控制与敏感访问留痕。**

只要这条链路做深，题目“基于大模型的智能医疗辅助问诊系统”就成立。

## 2. 冻结的关键口径

| 主题 | 决策 |
|------|------|
| 系统形态 | `Java 模块化单体 + Python 独立 AI 服务` |
| 浏览器入口 | 浏览器只访问 `mediask-api`，**不直连** Python AI 服务 |
| Python 定位 | `mediask-ai` 是 Java 的内部 AI 执行服务，不持有业务主事实 |
| Java 分层 | `API/Worker -> Application -> Domain`；`Infrastructure -> Domain`；`Application` **不依赖** `Infrastructure` |
| 统一响应 | Java 对外统一使用 `Result<T>`：`{code, msg, data, requestId, timestamp}` |
| 成功语义 | `code = 0` 表示成功，非 0 表示失败 |
| 请求串联主线 | `X-Request-Id` / `request_id` 是跨网关、Java、Python、审计的统一串联主键 |
| AI 写库边界 | Python 只写 `knowledge_chunk_index` 与 `ai_run_citation`；其余 AI 业务事实由 Java 维护 |
| AI 输出边界 | 只做症状整理、风险提示、建议就医、推荐科室、引用展示；**不做诊断结论和处方建议** |
| 排班定位 | 排班是亮点能力，但当前阶段必须做轻，不抢主线 |
| 审计定位 | `audit_event + data_access_log` 是 P0 必需；更重的事件投递与归档属于后续增强 |
| 可观测性基线 | P0 最小要求是 `request_id + 结构化日志 + 健康/就绪检查（Java: /actuator/health/readiness，Python: /health,/ready） + 基础 metrics`；完整观测栈按时间预算选做 |

## 3. P0：必须落地的能力

### 3.1 功能闭环

`P0` 至少打通以下演示链路：

1. 患者登录并发起 AI 问诊
2. 系统基于知识库执行 RAG 检索与生成
3. 回答展示引用来源、风险提示与建议就医/推荐科室
4. 患者基于推荐结果完成挂号
5. 医生查看挂号信息与 AI 摘要后接诊
6. 医生生成病历、诊断、处方
7. 非授权用户无法查看不属于自己范围的敏感病历
8. 查看病历正文、AI 原文等敏感内容会留下访问日志

### 3.2 P0 必做模块

| 能力域 | P0 说明 |
|------|---------|
| 用户与身份 | 患者/医生/管理员最小角色模型，支持登录与身份区分 |
| AI 会话 | `ai_session`、`ai_turn`、`ai_turn_content`、`ai_model_run`、`ai_guardrail_event` |
| RAG | `knowledge_base`、`knowledge_document`、`knowledge_chunk`、`knowledge_chunk_index`、`ai_run_citation` |
| 医疗闭环 | `clinic_session`、`clinic_slot`、`registration_order`、`visit_encounter`、`emr_record`、`emr_record_content`、`emr_diagnosis`、`prescription_order`、`prescription_item` |
| 权限与审计 | `roles`、`permissions`、`user_roles`、`role_permissions`、`data_scope_rules`、`audit_event`、`data_access_log` |
| 前端页面 | 患者 H5：登录、AI 问诊、导诊结果、挂号；医生 Web：工作台、接诊、病历、处方；管理员：最小审计查询 |

### 3.3 P0 必须明确的实现规则

- Java 先创建 `ai_model_run`，Python 使用该 `model_run_id` 写 `ai_run_citation`
- 文档必须先由 Java 持久化 `knowledge_document` / `knowledge_chunk`，再调用 Python 建索引
- AI 流式输出由客户端请求 Java，Java 再调用 Python 并转发 SSE
- 所有对外错误响应遵循统一错误码与 `requestId` 口径
- 医疗敏感正文采用“索引/密文分离”或最小等价实现，禁止在列表查询中直接暴露原文

## 4. P1：推荐增强，但不阻塞主链路

以下能力做出来会明显提升答辩质量，但不应阻塞 P0：

- AI 复核任务流：`ai_feedback_task`、`ai_feedback_review`
- 轻量排班生成：医生可用时间 + 科室需求模板 -> 自动生成候选排班 -> 发布为 `clinic_session`
- `ai_run_artifact` 等结构化中间产物展示
- 通知与字典：`notification`、`sys_dict_type`、`sys_dict_item`
- 本地观测增强：Prometheus、Grafana、Loki 等面板与日志聚合

## 5. P2：保留设计，不作为当前实现重点

以下内容可以保留在文档里，但不应占用当前主要实现时间：

- 插件化排班求解器、JSON DSL、冲突最小集、增量重排
- `domain_event_stream`、`outbox_event`、`integration_event_archive`
- `SkyWalking + Elasticsearch` 全链路 APM
- Java 自研配置加密链路、密钥 CLI、复杂运维治理
- 角色继承、角色互斥、审批流、break-glass、WORM 等生产级权限治理
- 全量前端 Monorepo 平台化拆分与非主链路后台页面

## 6. 当前阶段最容易做过头的地方

为避免继续过度设计，以下原则直接冻结：

- 不按“完整医院信息系统”平均推进所有领域
- 不为了展示工程深度而优先做微服务治理、事件总线、复杂 APM
- 不把排班做成独立论文级优化平台
- 不在 P0 引入多套响应协议、多套请求 ID、多套权限口径
- 不让 Python 成为业务主事实写入方

## 7. 推荐阅读顺序

开发启动前，按以下顺序阅读即可：

1. `docs/00A-P0-BASELINE.md`
2. `docs/07E-DATABASE-PRIORITY.md`
3. `docs/01-OVERVIEW.md`
4. `docs/07B-AI-AUDIT-V3.md`
5. `docs/20-RAG_DATABASE_PGVECTOR_DESIGN.md`
6. `docs/10-PYTHON_AI_SERVICE.md`
7. `docs/19-ERROR_EXCEPTION_RESPONSE_DESIGN.md`

## 8. 一句话结论

当前阶段最重要的不是继续铺设计面，而是把主链路做深，并把 `AI 入口`、`统一响应`、`分层依赖`、`RAG ownership`、`P0/P1/P2 边界` 这几件事彻底定死。
