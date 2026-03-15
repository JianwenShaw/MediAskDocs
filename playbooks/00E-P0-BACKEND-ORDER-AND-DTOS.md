# P0 后端实现顺序与 DTO 清单

> 状态：Backend Build Order
>
> 目标：把 `P0` 后端工作进一步收敛成“先建哪些表、先做哪些接口、每个接口至少需要哪些字段”的执行顺序。

## 1. 使用方式

这份文档不是替代设计文档，而是给开发阶段做排期和接口落地用。

- 范围基线以 [../docs/00A-P0-BASELINE.md](../docs/00A-P0-BASELINE.md) 为准
- 后端任务包以 [00C-P0-BACKEND-TASKS.md](./00C-P0-BACKEND-TASKS.md) 为准
- AI 外部契约以 [../docs/10A-JAVA_AI_API_CONTRACT.md](../docs/10A-JAVA_AI_API_CONTRACT.md) 为准

## 2. 数据库迁移顺序

## 2.1 推荐批次

| 批次 | 先建表 | 目的 | 解锁的后续能力 |
|------|--------|------|----------------|
| `M1` | `users`、`user_pii_profile`、`patient_profile`、`roles`、`permissions`、`user_roles`、`role_permissions` | 登录、角色识别、最小权限基线 | 认证、用户上下文 |
| `M2` | `hospitals`、`departments`、`doctors`、`doctor_department_rel`、`data_scope_rules` | 组织主体与医生归属 | 导诊推荐、接诊权限 |
| `M3` | `knowledge_base`、`knowledge_document`、`knowledge_chunk` | 知识库业务主事实 | 文档导入、知识治理 |
| `M4` | `knowledge_chunk_index` | 检索投影 | 向量检索、关键词召回 |
| `M5` | `ai_session`、`ai_turn`、`ai_turn_content`、`ai_model_run`、`ai_guardrail_event`、`ai_run_citation` | AI 问诊闭环 | 问诊、引用、护栏 |
| `M6` | `clinic_session`、`clinic_slot`、`registration_order` | 挂号入口 | AI 到挂号承接 |
| `M7` | `visit_encounter`、`emr_record`、`emr_record_content`、`emr_diagnosis`、`prescription_order`、`prescription_item` | 接诊、病历、处方 | 医疗业务闭环 |
| `M8` | `audit_event`、`data_access_log` | 关键动作与敏感访问留痕 | 权限/审计验收 |

## 2.2 迁移原则

- Java 业务主事实先建，Python 检索投影后建
- `knowledge_chunk_index` 必须晚于 `knowledge_chunk`
- `ai_run_citation` 必须晚于 `ai_model_run` 与 `knowledge_chunk`
- 审计表不需要最后才建，但建议放在业务主链可运行后立即接入

## 2.3 最小表间依赖

| 表 | 关键依赖 |
|----|----------|
| `patient_profile` | `users` |
| `user_roles` | `users`、`roles` |
| `role_permissions` | `roles`、`permissions` |
| `doctor_department_rel` | `doctors`、`departments` |
| `knowledge_document` | `knowledge_base` |
| `knowledge_chunk` | `knowledge_document` |
| `knowledge_chunk_index` | `knowledge_chunk` |
| `ai_turn` | `ai_session` |
| `ai_turn_content` | `ai_turn` |
| `ai_model_run` | `ai_turn` |
| `ai_run_citation` | `ai_model_run`、`knowledge_chunk` |
| `clinic_slot` | `clinic_session` |
| `registration_order` | `clinic_session`、`clinic_slot`、`ai_session` |
| `visit_encounter` | `registration_order` |
| `emr_record` | `visit_encounter` |
| `emr_record_content` | `emr_record` |
| `emr_diagnosis` | `emr_record` |
| `prescription_order` | `visit_encounter` |
| `prescription_item` | `prescription_order` |

## 3. API 实现顺序

## 3.1 外部接口优先顺序

| 顺序 | 接口 | 说明 | 依赖批次 |
|------|------|------|----------|
| `A1` | `/api/v1/auth/login`、`/api/v1/auth/me` | 先解决身份入口 | `M1` |
| `A2` | `/api/v1/ai/chat` | 先打通非流式 AI 主链 | `M1-M5` |
| `A3` | `/api/v1/ai/chat/stream` | 再补流式回答 | `M1-M5` |
| `A4` | `/api/v1/ai/sessions/{id}` | 会话详情与回看 | `M5` |
| `A5` | `/api/v1/ai/sessions/{id}/triage-result` | 导诊结果页 | `M5` |
| `A6` | `/api/v1/ai/sessions/{id}/registration-handoff` | AI 到挂号承接 | `M5-M6` |
| `A7` | `/api/v1/clinic-sessions` | 挂号页门诊查询 | `M6` |
| `A8` | `/api/v1/registrations` | 创建和查看挂号 | `M6` |
| `A9` | `/api/v1/encounters`、`/api/v1/encounters/{id}` | 医生接诊入口 | `M6-M7` |
| `A10` | `/api/v1/encounters/{id}/ai-summary` | 医生查看 AI 摘要 | `M5-M7` |
| `A11` | `/api/v1/emr` | 病历录入 | `M7` |
| `A12` | `/api/v1/prescriptions` | 处方录入 | `M7` |
| `A13` | `/api/v1/audit/events`、`/api/v1/audit/data-access` | 最小审计查询 | `M8` |

## 3.2 Python 内部接口优先顺序

| 顺序 | 接口 | 说明 |
|------|------|------|
| `P1` | `/health`、`/ready` | 基础健康检查 |
| `P2` | `/api/v1/knowledge/index` | 知识向量化入库 |
| `P3` | `/api/v1/knowledge/search` | 检索能力验证 |
| `P4` | `/api/v1/chat` | 非流式生成 |
| `P5` | `/api/v1/chat/stream` | 流式生成 |

## 4. 外部 API DTO 清单

## 4.1 认证

| 接口 | 请求 DTO 最小字段 | 响应 `data` 最小字段 |
|------|------------------|----------------------|
| `POST /api/v1/auth/login` | `username`、`password` | `accessToken`、`userId`、`roles` |
| `GET /api/v1/auth/me` | 无 | `userId`、`username`、`roles`、`displayName` |

## 4.2 AI 问诊

| 接口 | 请求 DTO 最小字段 | 响应 `data` / 事件最小字段 |
|------|------------------|-----------------------------|
| `POST /api/v1/ai/chat` | `sessionId?`、`message`、`departmentId?`、`sceneType`、`useStream` | `sessionId`、`turnId`、`answer`、`triageResult` |
| `POST /api/v1/ai/chat/stream` | 同上 | `message` 文本片段；`meta.sessionId`、`meta.turnId`、`meta.triageResult` |
| `GET /api/v1/ai/sessions/{id}` | Path `sessionId` | `sessionId`、`sceneType`、`turns[]` |
| `GET /api/v1/ai/sessions/{id}/triage-result` | Path `sessionId` | `sessionId`、`riskLevel`、`guardrailAction`、`nextAction`、`recommendedDepartments`、`careAdvice`、`citations` |

### `triageResult` 最小字段

| 字段 | 说明 |
|------|------|
| `riskLevel` | `low / medium / high` |
| `guardrailAction` | `allow / caution / refuse` |
| `nextAction` | `VIEW_TRIAGE_RESULT / GO_REGISTRATION / EMERGENCY_OFFLINE / MANUAL_SUPPORT` |
| `chiefComplaintSummary` | 症状摘要 |
| `recommendedDepartments` | 推荐科室列表 |
| `careAdvice` | 保守建议或就医提示 |
| `citations` | 引用片段列表 |

## 4.3 挂号承接

| 接口 | 请求 DTO 最小字段 | 响应 `data` 最小字段 |
|------|------------------|----------------------|
| `POST /api/v1/ai/sessions/{id}/registration-handoff` | Path `sessionId` | `sessionId`、`recommendedDepartmentId`、`recommendedDepartmentName`、`chiefComplaintSummary`、`suggestedVisitType`、`registrationQuery` |
| `GET /api/v1/clinic-sessions` | `departmentId?`、`dateFrom?`、`dateTo?` | `items[]` |
| `POST /api/v1/registrations` | `clinicSessionId`、`clinicSlotId`、`sourceAiSessionId?` | `registrationId`、`orderNo`、`status` |
| `GET /api/v1/registrations` | `status?` | `items[]` |

## 4.4 接诊、病历、处方

| 接口 | 请求 DTO 最小字段 | 响应 `data` 最小字段 |
|------|------------------|----------------------|
| `GET /api/v1/encounters` | `status?` | `items[]` |
| `GET /api/v1/encounters/{id}` | Path `encounterId` | `encounterId`、`registrationId`、`patientSummary` |
| `GET /api/v1/encounters/{id}/ai-summary` | Path `encounterId` | `encounterId`、`sessionId`、`chiefComplaintSummary`、`structuredSummary`、`riskLevel`、`latestCitations` |
| `POST /api/v1/emr` | `encounterId`、`chiefComplaint`、`historyOfPresentIllness`、`diagnoses[]` | `emrRecordId`、`encounterId` |
| `GET /api/v1/emr/{encounterId}` | Path `encounterId` | `emrRecordId`、`content`、`diagnoses[]` |
| `POST /api/v1/prescriptions` | `encounterId`、`items[]` | `prescriptionOrderId`、`status` |
| `GET /api/v1/prescriptions/{encounterId}` | Path `encounterId` | `prescriptionOrderId`、`items[]` |

## 4.5 审计

| 接口 | 请求 DTO 最小字段 | 响应 `data` 最小字段 |
|------|------------------|----------------------|
| `GET /api/v1/audit/events` | `from?`、`to?`、`action?`、`operatorUserId?` | `items[]` |
| `GET /api/v1/audit/data-access` | `from?`、`to?`、`resourceType?`、`operatorUserId?` | `items[]` |

## 5. Java -> Python 内部 DTO 清单

## 5.1 Java 调 Python Chat

| 方向 | 最小字段 |
|------|----------|
| Java -> Python | `modelRunId`、`sessionId`、`turnId`、`message`、`sceneType`、`departmentId?`、`requestId` |
| Python -> Java | `answer`、`risk_level`、`guardrail_action`、`chief_complaint_summary`、`recommended_departments`、`care_advice`、`citations` |

## 5.2 Python 失败响应

| 字段 | 说明 |
|------|------|
| `code` | 内部错误码，落在 `6xxx/9xxx` |
| `msg` | 错误摘要 |
| `requestId` | 透传后的请求标识 |
| `timestamp` | 毫秒时间戳 |

## 6. 开发时最容易出错的地方

- 不要让浏览器直接依赖 Python 内部返回字段命名
- 不要在 `SSE` 里继续包 `Result<T>`
- 不要让 Python 反写业务主事实表
- 不要等全部业务做完才补审计；至少在病历正文、AI 原文查看时先落 `data_access_log`
- 不要把 `trace_id` 当作 `P0` 主串联键

## 7. 一句话结论

后端真正需要的不是“更多接口”，而是按依赖顺序先把表和 DTO 定稳，再让 Java 外部协议、Python 内部执行协议和数据库事实模型三者对齐。
