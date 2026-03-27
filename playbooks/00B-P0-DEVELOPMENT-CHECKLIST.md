# P0 开发清单（页面/API/表/用例映射）

> 状态：Execution Checklist
>
> 适用阶段：毕设 `P0` 开发启动、任务拆分、联调验收
>
> 目的：把当前设计文档收敛为可执行开发清单，避免实现阶段再次回到“功能很多但主链路不深”的状态。

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

## 2. 开发前先冻结的口径

| 主题 | 固定规则 |
|------|----------|
| 浏览器入口 | 浏览器只访问 `mediask-api`，不直连 Python |
| Java 对外协议 | `JSON` 接口统一使用 `Result<T>` |
| AI 流式协议 | `SSE` 统一使用 `message / meta / end / error` |
| 成功语义 | `code = 0` 为成功 |
| 请求串联 | `X-Request-Id` / `request_id` 是唯一主线 |
| Python 写库边界 | Python 只写 `knowledge_chunk_index`、`ai_run_citation` |
| AI 输出边界 | 只做症状整理、风险提示、建议就医、推荐科室、引用展示 |
| 非目标 | 不输出诊断结论、处方建议、药物剂量指导 |

## 3. 分阶段实施清单

## 3.1 Phase A：公共基线

### 后端

- [x] `Result<T>`、错误码、全局异常处理统一
- [x] `X-Request-Id` 入站生成/透传/回写
- [x] Java -> Python 调用透传 `X-Request-Id`
- [ ] Java 对外 SSE 转发骨架完成
- [x] 基础认证链路可用（登录、当前用户、角色识别）

### Python

- [ ] `/health`、`/ready`、`/api/v1/chat`、`/api/v1/chat/stream` 骨架可用
- [ ] `X-API-Key` 校验可用
- [ ] `request_id` 注入日志与 DB 操作

### 验收

- [ ] 任意一次请求都能在 Java 日志中看到 `request_id`
- [x] Java 调 Python 时 `request_id` 不丢失

## 3.2 Phase B：身份、组织、最小权限

### 关键表

- [ ] `users`
- [ ] `user_pii_profile`
- [ ] `patient_profile`
- [ ] `roles`
- [ ] `permissions`
- [ ] `user_roles`
- [ ] `role_permissions`
- [ ] `data_scope_rules`
- [ ] `hospitals`
- [ ] `departments`
- [ ] `doctors`
- [ ] `doctor_department_rel`

### 必做能力

- [ ] 患者 / 医生 / 管理员三类角色可区分
- [ ] 患者只能访问自己的数据
- [ ] 医生只能访问自己职责范围内的数据
- [ ] 管理员可查看最小审计结果

## 3.3 Phase C：知识库与 RAG 底座

### 关键表

- [ ] `knowledge_base`
- [ ] `knowledge_document`
- [ ] `knowledge_chunk`
- [ ] `knowledge_chunk_index`

### 必做能力

- [ ] Java 持久化 `knowledge_document`、`knowledge_chunk`
- [ ] Java 调 Python 建索引
- [ ] Python 写 `knowledge_chunk_index`
- [ ] 至少有一套可演示知识库数据

### 范围控制

- [ ] 文档导入可先用脚本或最小后台接口，不强制先做完整知识库管理后台

## 3.4 Phase D：患者 AI 问诊主链路

### 关键表

- [ ] `ai_session`
- [ ] `ai_turn`
- [ ] `ai_turn_content`
- [ ] `ai_model_run`
- [ ] `ai_guardrail_event`
- [ ] `ai_run_citation`

### Java 对外接口

- [ ] `POST /api/v1/ai/chat`
- [ ] `POST /api/v1/ai/chat/stream`
- [ ] `GET /api/v1/ai/sessions/{sessionId}`
- [ ] `GET /api/v1/ai/sessions/{sessionId}/triage-result`

### Python 内部接口

- [ ] `POST /api/v1/chat`
- [ ] `POST /api/v1/chat/stream`
- [ ] `POST /api/v1/knowledge/search`

### 前端页面

- [ ] 患者登录页
- [ ] AI 问诊页
- [ ] 导诊结果页
- [ ] 高风险提示页

### 必做能力

- [ ] Java 预创建 `ai_model_run`
- [ ] Python 基于 `model_run_id` 写 `ai_run_citation`
- [ ] 回答展示引用、风险等级、下一步动作
- [ ] `high` 风险不继续普通问答，跳转紧急线下处置或人工求助

## 3.5 Phase E：AI 到挂号承接

### 关键表

- [ ] `clinic_session`
- [ ] `clinic_slot`
- [ ] `registration_order`

### Java 对外接口

- [ ] `POST /api/v1/ai/sessions/{sessionId}/registration-handoff`
- [ ] `GET /api/v1/clinic-sessions`
- [ ] `POST /api/v1/registrations`
- [ ] `GET /api/v1/registrations`

### 前端页面

- [ ] 导诊结果页跳挂号
- [ ] 挂号提交页
- [ ] 我的挂号页

### 必做能力

- [ ] AI 结果能带出推荐科室和挂号查询参数
- [ ] 患者能根据推荐科室完成挂号
- [ ] `registration_order.source_ai_session_id` 能追溯到 AI 会话

## 3.6 Phase F：医生接诊、病历、处方

### 关键表

- [ ] `visit_encounter`
- [ ] `emr_record`
- [ ] `emr_record_content`
- [ ] `emr_diagnosis`
- [ ] `prescription_order`
- [ ] `prescription_item`

### Java 对外接口

- [ ] `GET /api/v1/encounters`
- [ ] `GET /api/v1/encounters/{encounterId}`
- [ ] `GET /api/v1/encounters/{encounterId}/ai-summary`
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

- [ ] 医生可看到 AI 摘要，不默认展示 AI 原文
- [ ] 医生完成病历、诊断、处方闭环
- [ ] 病历正文与索引分层，列表不直接暴露正文

## 3.7 Phase G：权限、对象级授权、审计留痕

### 关键表

- [ ] `audit_event`
- [ ] `data_access_log`

### Java 对外接口

- [ ] `GET /api/v1/audit/events`
- [ ] `GET /api/v1/audit/data-access`

### 必做能力

- [ ] 所有按 ID 查看病历、AI 原文、处方详情的接口做对象级授权
- [ ] 非授权访问返回稳定错误码
- [ ] 查看病历正文、AI 原文时写 `data_access_log`
- [ ] 登录、挂号、病历保存、处方保存、权限变更等关键动作写 `audit_event`

## 4. 页面 / API / 表 / 用例映射

| 页面/模块 | 核心 API | 核心表 | 主要用例 |
|-----------|----------|--------|----------|
| 患者登录 | `/api/v1/auth/*` | `users`、`user_roles` | 登录、识别身份 |
| AI 问诊页 | `/api/v1/ai/chat`、`/api/v1/ai/chat/stream` | `ai_session`、`ai_turn`、`ai_model_run` | 发起问诊、流式问答 |
| 导诊结果页 | `/api/v1/ai/sessions/{id}/triage-result` | `ai_run_citation`、`knowledge_chunk` | 展示引用、风险和推荐科室 |
| 挂号承接 | `/api/v1/ai/sessions/{id}/registration-handoff` | `ai_session`、`clinic_session` | 把 AI 结果转为挂号入口 |
| 挂号页 | `/api/v1/clinic-sessions`、`/api/v1/registrations` | `clinic_session`、`clinic_slot`、`registration_order` | 查门诊、创建挂号 |
| 医生接诊页 | `/api/v1/encounters/*`、`/api/v1/encounters/{id}/ai-summary` | `visit_encounter`、`registration_order` | 查看接诊信息与 AI 摘要 |
| 病历页 | `/api/v1/emr/*` | `emr_record`、`emr_record_content`、`emr_diagnosis` | 保存病历与诊断 |
| 处方页 | `/api/v1/prescriptions/*` | `prescription_order`、`prescription_item` | 保存处方 |
| 审计页 | `/api/v1/audit/*` | `audit_event`、`data_access_log` | 查询操作审计与访问日志 |

## 5. 联调验收清单

### 主链路验收

- [ ] 患者 AI 问诊成功，返回引用和风险提示
- [ ] 中风险可进入挂号承接
- [ ] 高风险走紧急线下处置或人工求助，不继续普通问答
- [ ] 患者完成挂号
- [ ] 医生查看 AI 摘要并完成病历、处方

### 权限验收

- [ ] 患者不能查看他人病历/挂号/AI 会话
- [ ] 医生不能查看不在自己范围内的病历和 AI 原文
- [ ] 管理员能看最小审计结果，但不是默认全量看所有敏感正文

### 审计验收

- [ ] 关键业务动作存在 `audit_event`
- [ ] 查看病历正文、AI 原文存在 `data_access_log`
- [ ] 一次请求能用 `request_id` 串到 Java、Python、审计

## 6. 当前阶段明确不做

- [ ] 不先做复杂排班求解平台
- [ ] 不先做 `domain_event_stream`、`outbox_event`、`integration_event_archive`
- [ ] 不先做审批流、break-glass、黑白名单、ABAC
- [ ] 不先做完整知识库后台平台化治理
- [ ] 不先做 SkyWalking / Elasticsearch 级重型观测栈

## 7. 推荐开发顺序

1. 公共基线：响应、错误、`request_id`、认证
2. 基础主数据：用户、角色、科室、医生
3. 知识库与 RAG 底座
4. 患者 AI 问诊 + 导诊结果
5. AI 到挂号承接
6. 医生接诊 + 病历 + 处方
7. 对象级授权 + 审计留痕

## 8. 一句话结论

`P0` 不是“把所有模块都做一点”，而是把 `AI 问诊 -> 导诊 -> 挂号 -> 接诊 -> 病历/处方 -> 权限/审计` 这一条链路做深、做通、做一致。

## 9. 拆分阅读

- 后端任务拆分见 [00C-P0-BACKEND-TASKS.md](./00C-P0-BACKEND-TASKS.md)
- 前端任务拆分见 [00D-P0-FRONTEND-TASKS.md](./00D-P0-FRONTEND-TASKS.md)
- 后端实现顺序与 DTO 清单见 [00E-P0-BACKEND-ORDER-AND-DTOS.md](./00E-P0-BACKEND-ORDER-AND-DTOS.md)
- 前端页面原型与状态流转见 [00F-P0-FRONTEND-PROTOTYPES-AND-FLOWS.md](./00F-P0-FRONTEND-PROTOTYPES-AND-FLOWS.md)
