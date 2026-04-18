# P0 开发清单（页面/API/表/用例映射）

> 状态：Execution Checklist / Current Repo Snapshot
>
> 适用阶段：毕设 `P0` 开发推进、任务补漏、联调验收
>
> 目的：把当前设计文档收敛为“基于当前仓库真实完成度”的执行清单，明确除了 `RAG` 之外还差哪些 `P0` 能力。

判定口径：

- 本清单基于当前 `mediask-backend` 仓库中的 Java 代码、SQL 脚本、测试与 `qingniao` 验证脚本判断。
- “表已完成”只表示 schema 已存在；只有接口、用例和链路打通时，才算“能力完成”。
- 当前仓库不包含前端工程，因此页面项默认按“未完成”统计。

## 1. P0 最终验收目标

`P0` 必须至少完成下面这条链路：

1. 患者登录并发起 AI 问诊
2. 系统完成 RAG 检索、生成回答、展示引用与风险提示
3. 患者查看导诊结果、推荐科室和下一步动作
4. 患者从 AI 结果进入挂号
5. 医生在接诊前查看 AI 摘要
6. 医生完成病历、诊断、处方录入
7. 非授权用户无法查看不属于自己范围的病历或 AI 原文
8. 查看敏感正文会留下访问日志

只要这条链路跑通且口径一致，毕设 `P0` 就成立。

## 2. 当前仓库完成度速览

| 能力域 | 当前状态 | 结论 |
|------|----------|------|
| 公共协议与认证 | 完成 | `Result<T>`、错误处理、`requestId`、JWT 登录/刷新/登出/当前用户、结构化日志基线已完成；AI 外部链路已收口到普通 `JSON` 接口 |
| 身份、组织、后台患者管理 | 大体完成 | 用户/角色/权限/组织表齐全；管理员患者管理、患者/医生本人资料接口已落地 |
| 门诊挂号 | 大体完成 | 门诊场次查询、挂号创建、我的挂号、挂号后预创建 `visit_encounter` 已完成 |
| 医生接诊 | 部分完成 | 医生接诊列表已完成；接诊详情、AI 摘要、病历、处方未完成 |
| AI 问诊与 RAG | 部分完成 | Java `chat/sessions/triage-result/registration-handoff` 已落地，并已收口到 `triageStage + finalized snapshot` 模型；知识导入/索引与 Python RAG 写库仍未完成 |
| 审计与敏感访问 | 未完成 | `audit_event`、`data_access_log` 只有 schema，没有写入与查询链路 |
| 对象级授权 | 部分完成 | `ScenarioAuthorization`、`data_scope_rules` 装载已具备；资源解析和 `EMR/AI` 对象级校验未落地 |
| 前端页面 | 未完成 | 当前仓库未包含前端实现 |

## 3. 开发前先冻结的口径

| 主题 | 固定规则 |
|------|----------|
| 浏览器入口 | 浏览器只访问 `mediask-api`，不直连 Python |
| Java 对外协议 | `JSON` 接口统一使用 `Result<T>` |
| AI 问诊协议 | 浏览器仅走 `POST /api/v1/ai/chat`；如需流式观感，只做展示层伪流式 |
| 成功语义 | `code = 0` 为成功 |
| 请求串联 | `X-Request-Id` / `request_id` 是唯一主线 |
| Python 写库边界 | Python 只写 `knowledge_chunk_index`、`ai_run_citation` |
| AI 输出边界 | 只做症状整理、风险提示、建议就医、推荐科室、引用展示 |
| 非目标 | 不输出诊断结论、处方建议、药物剂量指导 |

## 4. 分阶段实施清单

## 4.1 Phase A：公共基线

### 后端

- [x] `Result<T>`、错误码、全局异常处理统一
- [x] `X-Request-Id` 入站生成/透传/回写
- [x] Java -> Python 调用透传 `X-Request-Id`
- [x] 基础认证链路可用（登录、刷新、登出、当前用户、角色识别）
- [x] Java `health/readiness/liveness` 端点已开放
- [x] Java 结构化日志配置落地，日志中稳定输出 `request_id`

### Python

- [ ] `/health`、`/ready`、`/api/v1/chat` 服务骨架可用
- [ ] `X-API-Key` 校验可用
- [ ] `request_id` 注入日志与 DB 操作

### 验收

- [x] 任意一次请求都能在 Java 日志中看到 `request_id`
- [x] Java 调 Python 时 `request_id` 不丢失
- [x] Java `requestId` 在成功/失败响应中稳定回写

## 4.2 Phase B：身份、组织、最小权限

### 关键表

- [x] `users`
- [x] `user_pii_profile`
- [x] `patient_profile`
- [x] `roles`
- [x] `permissions`
- [x] `user_roles`
- [x] `role_permissions`
- [x] `data_scope_rules`
- [x] `hospitals`
- [x] `departments`
- [x] `doctors`
- [x] `doctor_department_rel`

### 必做能力

- [x] 患者 / 医生 / 管理员三类角色可区分
- [x] 管理员患者管理接口可用（列表、详情、新增、修改、删除）
- [x] 患者可查看/更新本人资料，只能查询自己的挂号列表
- [x] 医生可查看/更新本人资料，只能查询自己的接诊列表
- [x] `data_scope_rules` 已装载到当前登录用户上下文
- [ ] `EMR_RECORD` / `AI_SESSION` 的对象级资源解析与数据范围校验闭环
- [ ] 管理员最小审计查询能力

## 4.3 Phase C：知识库与 RAG 底座

### 关键表

- [x] `knowledge_base`
- [x] `knowledge_document`
- [x] `knowledge_chunk`
- [x] `knowledge_chunk_index`

### 必做能力

- [x] Java 侧 AI Client、`AiChatPort`、Python DTO/错误映射基础设施已具备
- [ ] Java 调 Python 解析文档并接收 chunk payload
- [ ] Java 持久化 `knowledge_document`、`knowledge_chunk`
- [ ] Java 调 Python 建索引
- [ ] Python 写 `knowledge_chunk_index`
- [ ] 至少有一套可演示知识文档与 chunk 数据

### 范围控制

- [ ] 文档导入脚本或最小后台接口落地

## 4.4 Phase D：患者 AI 问诊主链路

### 关键表

- [x] `ai_session`
- [x] `ai_turn`
- [x] `ai_turn_content`
- [x] `ai_model_run`
- [x] `ai_guardrail_event`
- [x] `ai_run_citation`

### Java 对外接口

- [x] `POST /api/v1/ai/chat`
- [x] `GET /api/v1/ai/sessions`
- [x] `GET /api/v1/ai/sessions/{sessionId}`
- [x] `GET /api/v1/ai/sessions/{sessionId}/triage-result`

### Python 内部接口

- [ ] `POST /api/v1/knowledge/prepare`
- [ ] `POST /api/v1/chat`
- [ ] `POST /api/v1/knowledge/index`
- [ ] `POST /api/v1/knowledge/search`

### 前端页面

- [ ] 患者登录页
- [ ] AI 问诊页
- [ ] 导诊结果页
- [ ] 高风险提示页

### 必做能力

- [x] Java 侧 `AiChatInvocation` / `AiChatReply` 与 Python `/api/v1/chat` 契约已定义
- [ ] Java 预创建 `ai_model_run`
- [ ] Java 持久化 `ai_session`、`ai_turn`、`ai_turn_content`
- [ ] Python 基于 `model_run_id` 写 `ai_run_citation`
- [ ] 回答展示引用、风险等级、下一步动作
- [ ] `high` 风险不继续普通问答，跳转紧急线下处置或人工求助

## 4.5 Phase E：AI 到挂号承接

### 关键表

- [x] `clinic_session`
- [x] `clinic_slot`
- [x] `registration_order`

### Java 对外接口

- [x] `POST /api/v1/ai/sessions/{sessionId}/registration-handoff`
- [x] `GET /api/v1/clinic-sessions`
- [x] `POST /api/v1/registrations`
- [x] `GET /api/v1/registrations`

### 前端页面

- [ ] 导诊结果页跳挂号
- [ ] 挂号提交页
- [ ] 我的挂号页

### 必做能力

- [x] 患者能基于现有门诊场次完成挂号
- [x] 挂号成功后预创建 `visit_encounter`
- [x] `registration_order.source_ai_session_id` 字段已预留
- [x] AI 结果能带出推荐科室和挂号查询参数
- [x] `registration_order.source_ai_session_id` 字段已支持通过现有挂号入参承接，后续仅补强校验与验收

## 4.6 Phase F：医生接诊、病历、处方

### 关键表

- [x] `visit_encounter`
- [x] `emr_record`
- [x] `emr_record_content`
- [x] `emr_diagnosis`
- [x] `prescription_order`
- [x] `prescription_item`

### Java 对外接口

- [x] `GET /api/v1/encounters`
- [x] `GET /api/v1/encounters/{encounterId}`
- [x] `GET /api/v1/encounters/{encounterId}/ai-summary`
- [ ] `POST /api/v1/emr`
- [ ] `GET /api/v1/emr/{encounterId}`
- [ ] `POST /api/v1/prescriptions`
- [ ] `GET /api/v1/prescriptions/{encounterId}`

### 前端页面

- [ ] 医生工作台
- [ ] 接诊列表/详情页
- [ ] 病历编辑页
- [ ] 处方编辑页

### 必做能力

- [x] 医生可查看本人接诊列表
- [ ] 医生可查看接诊详情
- [ ] 医生可看到 AI 摘要，不默认展示 AI 原文
- [ ] 医生完成病历、诊断、处方闭环
- [ ] 病历正文与索引分层查询落地，列表不直接暴露正文

## 4.7 Phase G：权限、对象级授权、审计留痕

### 关键表

- [x] `audit_event`
- [x] `data_access_log`

### Java 对外接口

- [ ] `GET /api/v1/audit/events`
- [ ] `GET /api/v1/audit/data-access`

### 必做能力

- [x] `ScenarioAuthorization`、`ScenarioCode`、`data_scope_rules` 基础骨架已存在
- [x] 现有 401/403 接口返回统一错误体与稳定 `requestId`
- [ ] 所有按 ID 查看病历、AI 原文、处方详情的接口做对象级授权
- [ ] 非授权访问触发敏感访问留痕
- [ ] 查看病历正文、AI 原文时写 `data_access_log`
- [ ] 登录、挂号、病历保存、处方保存、权限变更等关键动作写 `audit_event`

## 5. 页面 / API / 表 / 用例 / 当前状态映射

| 页面/模块 | 核心 API | 核心表 | 主要用例 | 当前状态 |
|-----------|----------|--------|----------|----------|
| 认证 | `/api/v1/auth/login`、`/api/v1/auth/refresh`、`/api/v1/auth/logout`、`/api/v1/auth/me` | `users`、`user_roles` | 登录、刷新、登出、识别身份 | 已实现 |
| 患者/医生本人资料 | `/api/v1/patients/me/profile`、`/api/v1/doctors/me/profile` | `patient_profile`、`doctors`、`doctor_department_rel` | 查看/更新本人资料 | 已实现 |
| 管理员患者管理 | `/api/v1/admin/patients/*` | `users`、`patient_profile`、`user_roles` | 后台管理患者 | 已实现 |
| AI 问诊页 | `/api/v1/ai/chat` | `ai_session`、`ai_turn`、`ai_model_run` | 发起问诊、有限收集、结果页准入 | 后端已实现，前端未开始 |
| 导诊结果页 | `/api/v1/ai/sessions/{id}/triage-result` | `ai_run_citation`、`knowledge_chunk` | 展示引用、风险和推荐科室 | 后端已实现，前端未开始 |
| 挂号页 | `/api/v1/clinic-sessions`、`/api/v1/registrations` | `clinic_session`、`clinic_slot`、`registration_order` | 查门诊、创建挂号、查看我的挂号 | 已实现 |
| AI 到挂号承接 | `/api/v1/ai/sessions/{id}/registration-handoff` | `ai_session`、`registration_order` | 把 AI 结果转为挂号入口 | 后端已实现，前端未开始 |
| 医生接诊列表 | `/api/v1/encounters` | `visit_encounter`、`registration_order` | 医生查看本人待接诊记录 | 已实现 |
| 接诊详情 / 病历 / 处方 | `/api/v1/encounters/{id}`、`/api/v1/emr/*`、`/api/v1/prescriptions/*` | `visit_encounter`、`emr_*`、`prescription_*` | 接诊详情、病历录入、处方录入 | 未开始 |
| 审计页 | `/api/v1/audit/*` | `audit_event`、`data_access_log` | 审计查询与敏感访问追溯 | 未开始 |

## 6. 联调验收清单

### 当前已可验证

- [x] 患者登录 -> 查询门诊场次 -> 创建挂号 -> 查看我的挂号
- [x] 挂号成功后，医生可在 `/api/v1/encounters` 看到待接诊记录
- [x] 现有受保护接口的 `401/403/400` 响应统一返回 `Result` + `requestId`
- [x] `qingniao` 已覆盖管理员患者分页、门诊场次查询、挂号最小链路、医生接诊列表最小链路

### 除 RAG 之外仍未完成

- [x] Java 对外 AI 主链接口与导诊结果页接口
- [ ] AI -> 挂号承接接口
- [ ] 接诊详情、AI 摘要、病历、处方接口与写库链路
- [ ] 对象级授权真正落到 `EMR_RECORD` / `AI_SESSION`
- [ ] `audit_event`、`data_access_log` 写入与查询
- [ ] Java 结构化日志与 `request_id` 输出闭环
- [ ] Java、Python、审计三端通过同一 `request_id` 串联

## 7. 当前阶段明确不做

- [ ] 不先做复杂排班求解平台
- [ ] 不先做 `domain_event_stream`、`outbox_event`、`integration_event_archive`
- [ ] 不先做审批流、break-glass、黑白名单、ABAC
- [ ] 不先做完整知识库后台平台化治理
- [ ] 不先做 SkyWalking / Elasticsearch 级重型观测栈

## 8. 推荐剩余开发顺序

1. AI 主链：`ai_session/ai_turn/ai_model_run` + `/api/v1/ai/chat`
2. Python AI 服务：`/health`、`/ready`、`/api/v1/chat`、`/api/v1/knowledge/*`
3. RAG 检索闭环：知识导入、索引、检索、引用回填
4. AI -> 挂号承接：`triage-result` + `registration-handoff`
5. 诊疗闭环：接诊详情、AI 摘要、病历、处方
6. 权限与审计：对象级授权、`audit_event`、`data_access_log`
7. 可观测性收口：结构化日志、`request_id`、AI 结果页链路串联

## 9. 拆分阅读

- 后端任务拆分见 [00C-P0-BACKEND-TASKS.md](./00C-P0-BACKEND-TASKS.md)
- 前端任务拆分见 [00D-P0-FRONTEND-TASKS.md](./00D-P0-FRONTEND-TASKS.md)
- 后端实现顺序与 DTO 清单见 [00E-P0-BACKEND-ORDER-AND-DTOS.md](./00E-P0-BACKEND-ORDER-AND-DTOS.md)
- 前端页面原型与状态流转见 [00F-P0-FRONTEND-PROTOTYPES-AND-FLOWS.md](./00F-P0-FRONTEND-PROTOTYPES-AND-FLOWS.md)
