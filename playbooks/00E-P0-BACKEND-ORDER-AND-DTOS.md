# P0 后端实现顺序与 DTO 清单

> 状态：Backend Build Order
>
> 目标：把 `P0` 后端工作进一步收敛成“先建哪些表、先做哪些接口、每个接口至少需要哪些字段”的执行顺序。

## 1. 使用方式

这份文档不是替代设计文档，而是给开发阶段做排期和接口落地用。

- 范围基线以 [../docs/00A-P0-BASELINE.md](../docs/00A-P0-BASELINE.md) 为准
- 后端任务包以 [00C-P0-BACKEND-TASKS.md](./00C-P0-BACKEND-TASKS.md) 为准
- 当前仓库已经实现的 Java 对外接口契约，以 [00G-P0-CURRENT-API-CONTRACT.md](./00G-P0-CURRENT-API-CONTRACT.md) 为准
- AI 外部契约以 [../docs/10A-JAVA_AI_API_CONTRACT.md](../docs/10A-JAVA_AI_API_CONTRACT.md) 为准

补充说明：

- 本文档仍然承担“实现顺序”和“目标 DTO 清单”的职责，因此会包含尚未落地的接口。
- 如果问题是“当前代码里已经实现了什么、字段到底怎么传、真实业务语义是什么”，不要直接拿目标设计文档代替当前实现，应优先看 `00G`。

## 2. 数据库迁移顺序

## 2.1 推荐批次

| 批次 | 先建表 | 目的 | 解锁的后续能力 |
|------|--------|------|----------------|
| `M1` | `users`、`patient_profile`、`roles`、`permissions`、`user_roles`、`role_permissions` | 登录、角色识别、最小权限基线 | 认证、用户上下文 |
| `M2` | `departments`、`doctors`、`doctor_department_rel`、`data_scope_rules` | 组织主体与医生归属 | 导诊推荐、接诊权限 |
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
| `A2` | `/api/v1/ai/triage/query` | 先打通同步 AI triage 主链 | `M1 + Java ai_triage_result` |
| `A3` | `/api/v1/ai/triage/query/stream` | 打通 SSE 代理与 finalized 承接 | `M1 + Java ai_triage_result` |
| `A6` | `/api/v1/clinic-sessions` | 挂号页门诊查询 | `M6` |
| `A7` | `/api/v1/registrations` | 创建和查看挂号 | `M6` |
| `A8` | `/api/v1/encounters`、`/api/v1/encounters/{id}`、`PATCH /api/v1/encounters/{id}` | 医生接诊入口 | `M6-M7` |
| `A9` | `/api/v1/encounters/{id}/ai-summary` | 医生查看 AI 摘要 | `M5-M7` |
| `A10` | `/api/v1/emr` | 病历录入 | `M7` |
| `A11` | `/api/v1/prescriptions` | 处方录入 | `M7` |
| `A12` | `/api/v1/audit/events`、`/api/v1/audit/data-access` | 最小审计查询 | `M8` |

## 3.2 Python 内部接口优先顺序

| 顺序 | 接口 | 说明 |
|------|------|------|
| `P1` | `/health`、`/ready` | 基础健康检查 |
| `P2` | `/api/v1/knowledge/prepare` | 原始文档解析、清洗与分块 |
| `P3` | `/api/v1/knowledge/index` | 对稳定 `chunk_id` 建立检索投影 |
| `P4` | `/api/v1/knowledge/search` | 检索能力验证 |
| `P5` | `/api/v1/chat` | 非流式生成 |

## 4. 外部 API DTO 清单

## 4.1 认证

| 接口 | 请求 DTO 最小字段 | 响应 `data` 最小字段 |
|------|------------------|----------------------|
| `POST /api/v1/auth/login` | `username`、`password` | `accessToken`、`refreshToken`、`userContext.userId`、`userContext.roles` |
| `GET /api/v1/auth/me` | 无 | `userId`、`username`、`roles`、`displayName` |

认证补充约定：

- `POST /api/v1/auth/login` 与 `POST /api/v1/auth/refresh` 的 `data.userContext` 使用同一语义和同一字段集合
- `userContext` 结构对齐 `GET /api/v1/auth/me` 的当前用户上下文
- `null` 字段按现有 Jackson `non_null` 配置省略，不额外返回空字段

## 4.1A 知识导入

| 接口 | 请求 DTO 最小字段 | 响应 `data` 最小字段 |
|------|------------------|----------------------|
| `POST /api/v1/admin/knowledge-documents/import` | 前端传 `multipart/form-data`：`knowledgeBaseId`、`file`；Java 转 Python 为 `knowledge_base_id`、`file` | 前端收到 `documentId`、`jobId`、`lifecycleStatus`、`jobStatus` |

补充约定：

- 该接口是 Java 对外的最小后台知识导入入口，浏览器不直连 Python
- Java 只做认证、授权、审计入口、统一响应包装和网关转发。
- Java 不创建 `knowledge_document`，不持久化 `knowledge_chunk`，不解析文件，不建立索引。
- Python 保存原始文件，创建 `knowledge_document` 和 `ingest_job`，并异步执行解析、切块、embedding 和索引写入。

## 4.1B 知识库与文档治理

| 接口 | 请求 DTO 最小字段 | 响应 `data` 最小字段 |
|------|------------------|----------------------|
| `GET /api/v1/admin/knowledge-bases` | 前端传 `pageNum?`、`pageSize?`、`keyword?`；Java 转 Python 为 `page_num?`、`page_size?`、`keyword?` | 前端收到 camelCase 知识库分页 DTO |
| `POST /api/v1/admin/knowledge-bases` | 前端传 `code`、`name`、`description?`、`defaultEmbeddingModel`、`defaultEmbeddingDimension`、`retrievalStrategy`；Java 转 Python 为 snake_case | 前端收到 camelCase 知识库 DTO |
| `PATCH /api/v1/admin/knowledge-bases/{id}` | Path `id`；前端 Body：`name?`、`description?`、`status?`；Java 转 Python 为 snake_case | 前端收到 camelCase 知识库 DTO |
| `DELETE /api/v1/admin/knowledge-bases/{id}` | Path `id` | 无 |
| `GET /api/v1/admin/knowledge-documents` | 前端传 `knowledgeBaseId`、`pageNum?`、`pageSize?`；Java 转 Python 为 `knowledge_base_id`、`page_num?`、`page_size?` | 前端收到 camelCase 文档分页 DTO |
| `DELETE /api/v1/admin/knowledge-documents/{id}` | Path `id` | 无 |
| `GET /api/v1/admin/ingest-jobs/{id}` | Path `id` | 前端收到 camelCase 入库任务 DTO |
| `GET /api/v1/admin/knowledge-index-versions` | 前端传 `knowledgeBaseId`；Java 转 Python 为 `knowledge_base_id` | 前端收到 camelCase 索引版本列表 DTO |
| `GET /api/v1/admin/knowledge-releases` | 前端传 `knowledgeBaseId`；Java 转 Python 为 `knowledge_base_id` | 前端收到 camelCase 发布记录列表 DTO |
| `POST /api/v1/admin/knowledge-releases` | 前端传 `knowledgeBaseId`、`targetIndexVersionId`；Java 转 Python 为 `knowledge_base_id`、`target_index_version_id` | 前端收到 camelCase 发布结果 DTO |

补充约定：

- 前端只调用 Java 同名接口，不直连 Python。
- 前端和 Java 之间的请求/响应字段使用 camelCase；Java 和 Python 之间使用 Python 合同里的 snake_case。
- Python 返回 4xx 时 Java 保持前端可理解的 4xx 语义：404 映射为 `1004`，其他 4xx 映射为 `1002`；Python 5xx 或网络不可用才映射为 `6001`。
- Java 转发 `X-Request-Id`、`X-Actor-Id`、`X-Hospital-Scope`；当前 P0 `X-Hospital-Scope` 固定为 `default`。
- Java 不读取或拼接 Python 的 `knowledge_*`、`ingest_job`、`knowledge_index_version`、`knowledge_release` 表。
- 字段、状态机和删除/发布语义以 `docs/proposals/04-knowledge-admin-api-contract.md` 的 Python 合同为准。

## 4.2 AI Triage

时间字段总规则：

- 所有业务日期时间字段统一返回秒级 ISO-8601 字符串，包含时区偏移，例如 `2026-04-19T10:34:54+08:00`
- 所有业务日期字段统一返回 `yyyy-MM-dd` 字符串，例如 `2026-04-19`
- `Result.timestamp` 固定为毫秒时间戳；它属于统一响应元数据，不属于业务字段时间格式规则

| 接口 | 请求 DTO 最小字段 | 响应 `data` / 事件最小字段 |
|------|------------------|-----------------------------|
| `POST /api/v1/ai/triage/query` | `sessionId?`、`hospitalScope?`、`userMessage` | `requestId`、`sessionId`、`turnId`、`queryRunId`、`triageResult` |
| `POST /api/v1/ai/triage/query/stream` | `sessionId?`、`hospitalScope?`、`userMessage` | `text/event-stream`：`start/progress/delta/final/error/done`，事件 `data` 对前端统一为 `camelCase` |
| `GET /api/v1/ai/sessions` | 无 | `items[].sessionId`、`sceneType`、`status`、`departmentId?`、`chiefComplaintSummary?`、`summary?`、`startedAt`、`endedAt?` |
| `GET /api/v1/ai/sessions/{sessionId}` | Path `sessionId` | `sessionId`、`sceneType`、`status`、`departmentId?`、`chiefComplaintSummary?`、`summary?`、`startedAt`、`endedAt?`、`turns[]` |
| `GET /api/v1/ai/sessions/{sessionId}/triage-result` | Path `sessionId` | `sessionId`、`resultStatus`、`triageStage`、`riskLevel`、`guardrailAction`、`nextAction`、`finalizedTurnId`、`finalizedAt`、`hasActiveCycle`、`activeCycleTurnNo?`、`chiefComplaintSummary?`、`recommendedDepartments[]`、`careAdvice?`、`citations[]`、`blockedReason?`、`catalogVersion?` |

### `triageResult` 最小字段

| 字段 | 说明 |
|------|------|
| `triageStage` | `COLLECTING / READY / BLOCKED` |
| `triageCompletionReason` | `SUFFICIENT_INFO / MAX_TURNS_REACHED / HIGH_RISK_BLOCKED / null` |
| `riskLevel` | `low / medium / high` |
| `nextAction` | `CONTINUE_TRIAGE / VIEW_TRIAGE_RESULT / EMERGENCY_OFFLINE / MANUAL_SUPPORT` |
| `chiefComplaintSummary` | 症状摘要 |
| `followUpQuestions` | 仅在 `COLLECTING` 场景出现，最多 2 个 |
| `recommendedDepartments` | 推荐科室列表 |
| `careAdvice` | 保守建议或就医提示 |
| `blockedReason` | 高风险阻断原因 |
| `catalogVersion` | READY 结果对应目录版本 |
| `citations` | 引用片段列表 |

补充约定：

- Java 固定向 Python 发送 `scene=AI_TRIAGE`
- Java 会通过 Python `/api/v1/sessions*` 对外提供会话历史读取接口
- Java 调 Python query 和 sessions 接口时统一透传 `X-Request-Id`、`X-API-Key`、`X-Patient-User-Id`
- Java 当前只保存 finalized 快照表 `ai_triage_result`
- `COLLECTING` 不落库；`READY / BLOCKED` 才落库
- `READY` 结果会校验 `catalogVersion + departmentId + departmentName`

## 4.3 挂号承接

| 接口 | 请求 DTO 最小字段 | 响应 `data` 最小字段 |
|------|------------------|----------------------|
| `GET /api/v1/clinic-sessions` | `departmentId?`、`dateFrom?`、`dateTo?` | `items[]` |
| `GET /api/v1/clinic-sessions/{id}/slots` | Path `clinicSessionId` | `items[].clinicSlotId`、`slotSeq`、`slotStartTime`、`slotEndTime` |
| `POST /api/v1/registrations` | `clinicSessionId`、`clinicSlotId`、`sourceAiSessionId?` | `registrationId`、`orderNo`、`status` |
| `GET /api/v1/registrations` | `status?` | `items[]` |
| `GET /api/v1/registrations/{id}` | Path `registrationId` | `registrationId`、`orderNo`、`status`、`createdAt`、`sourceAiSessionId`、`clinicSessionId`、`clinicSlotId`、`departmentId`、`departmentName`、`doctorId`、`doctorName`、`sessionDate`、`periodCode`、`fee`、`cancelledAt?`、`cancellationReason?` |
| `PATCH /api/v1/registrations/{id}/cancel` | Path `registrationId` | `registrationId`、`status`、`cancelledAt` |

说明：登录态或 `CurrentUserResponse` 中的 `patientId` 表示 `patient_profile.id`；医疗业务表中的 `patient_id`（如 `registration_order.patient_id`）统一表示 `users.id`，两者不能混用。

补充约定：

- `POST /api/v1/ai/sessions/{id}/registration-handoff` 当前未实现，不应视为现有契约
- `suggestedVisitType` 当前固定为 `OUTPATIENT`，仅表达普通门诊承接类型，不映射现有 `clinicType`
- `registrationQuery` 最小字段为 `departmentId`、`dateFrom`、`dateTo`
- 默认查询窗口为今天起未来 7 天
- `riskLevel=high` 时返回 `blockedReason=EMERGENCY_OFFLINE`，不返回普通挂号查询参数
- `createdAt` 对外统一返回秒级 ISO-8601 字符串，包含时区偏移，例如 `2026-04-19T10:34:54+08:00`
- `registrationQuery.dateFrom`、`registrationQuery.dateTo`、`sessionDate` 这类业务日期字段统一返回 `yyyy-MM-dd` 字符串，不返回数组结构
- `GET /api/v1/clinic-sessions` 返回场次头摘要，不直接内嵌 slot；前端应先选场次，再调用 `GET /api/v1/clinic-sessions/{id}/slots` 拿 `clinicSlotId`
- 历史挂号详情以 `registration_order` 为准；若关联 `clinic_session` / `departments` / `doctors` / `users` 已软删除，详情仍返回订单，相关展示字段允许为空
- `clinic_slot` 最小状态语义按 `AVAILABLE / BOOKED / CANCELLED` 收口；当前取消链路要求 slot 处于 `BOOKED`

## 4.4 接诊、病历、处方

| 接口 | 请求 DTO 最小字段 | 响应 `data` 最小字段 |
|------|------------------|----------------------|
| `GET /api/v1/encounters` | `status?` | `items[].encounterId`、`registrationId`、`patientUserId`、`patientName`、`departmentId`、`departmentName`、`sessionDate`、`periodCode`、`encounterStatus`、`startedAt`、`endedAt` |
| `GET /api/v1/encounters/{id}` | Path `encounterId` | `encounterId`、`registrationId`、`patientSummary` |
| `GET /api/v1/encounters/{id}/ai-summary` | Path `encounterId` | `encounterId`、`sessionId`、`chiefComplaintSummary`、`riskLevel`、`recommendedDepartments`、`careAdvice`、`citations`、`blockedReason`、`catalogVersion`、`finalizedAt` |
| `GET /api/v1/encounters/{id}/emr-history` | Path `encounterId` | `items[].emrRecordId`、`encounterId`、`recordNo`、`recordStatus`、`departmentId`、`departmentName`、`doctorId`、`doctorName`、`sessionDate`、`chiefComplaintSummary`、`createdAt` |
| `PATCH /api/v1/encounters/{id}` | Path `encounterId` + Body `action` | `encounterId`、`encounterStatus`、`startedAt`、`endedAt` |
| `GET /api/v1/patients/me/emrs` | 无 | `items[].emrRecordId`、`encounterId`、`recordNo`、`recordStatus`、`departmentId`、`departmentName`、`doctorId`、`doctorName`、`sessionDate`、`chiefComplaintSummary`、`createdAt` |
| `POST /api/v1/emr` | `encounterId`、`chiefComplaintSummary?`、`content`、`diagnoses[]` | `recordId`、`recordNo`、`encounterId`、`recordStatus`、`version` |
| `GET /api/v1/emr/{encounterId}` | Path `encounterId` | `emrRecordId`、`content`、`diagnoses[]` |
| `POST /api/v1/prescriptions` | `encounterId`、`items[]` | `prescriptionOrderId`、`encounterId`、`status`、`version`、`items[]` |
| `GET /api/v1/prescriptions/{encounterId}` | Path `encounterId` | `prescriptionOrderId`、`encounterId`、`status`、`version`、`items[]` |
| `PATCH /api/v1/prescriptions/{encounterId}/items` | Path `encounterId` + Body `items[]` | `prescriptionOrderId`、`encounterId`、`status`、`version`、`items[]` |
| `POST /api/v1/prescriptions/{encounterId}/issue` | Path `encounterId` | `prescriptionOrderId`、`encounterId`、`status`、`version` |
| `POST /api/v1/prescriptions/{encounterId}/cancel` | Path `encounterId` | `prescriptionOrderId`、`encounterId`、`status`、`version` |

补充约定：

- `GET /api/v1/encounters` 只基于 `visit_encounter` 查询，不用 `registration_order` 直接拼“待接诊”列表。
- 挂号创建成功后即预创建 `visit_encounter`，初始状态固定为 `SCHEDULED`。
- `GET /api/v1/encounters/{id}/ai-summary` 通过 `registration_order.source_ai_session_id` 关联 AI 会话；没有关联 AI 问诊或没有 finalized triage 结果时，统一返回 `404 + 4005`
- `GET /api/v1/encounters/{id}/emr-history` 只返回当前接诊患者的历史病历摘要，不返回病历正文；当前 `encounterId` 对应病历会从列表中排除
- `status` 只接受 `SCHEDULED`、`IN_PROGRESS`、`COMPLETED`、`CANCELLED`，不传则返回当前医生全部可见记录。
- `PATCH /api/v1/encounters/{id}` 的 `action` 仅支持 `START`、`COMPLETE`。`START` 仅允许 `SCHEDULED -> IN_PROGRESS`；`COMPLETE` 仅允许 `IN_PROGRESS -> COMPLETED`。
- `COMPLETE` 成功后同步更新 `registration_order.order_status = COMPLETED`；当前不联动 `clinic_slot`。
- `startedAt`、`endedAt` 对外统一返回秒级 ISO-8601 字符串，包含时区偏移，例如 `2026-04-19T10:34:54+08:00`
- `sessionDate` 作为业务日期字段，统一返回 `yyyy-MM-dd` 字符串
- `POST /api/v1/prescriptions` 的 `items[]` 最小字段固定为：`sortOrder`、`drugName`、`drugSpecification?`、`dosageText?`、`frequencyText?`、`durationText?`、`quantity`、`unit?`、`route?`
- `GET /api/v1/prescriptions/{encounterId}` 返回单张处方而不是列表；P0 口径固定为“一个 `encounter` 最多一张有效处方”
- 创建处方前必须已存在 `emr_record`；`prescription_order.record_id` 直接关联该接诊对应病历
- 处方状态支持 `DRAFT` → `ISSUED` → `CANCELLED`（DRAFT 也可直接取消）；`updateItems` 仅允许 DRAFT 状态
- P0 处方录入不依赖药品字典、库存、审方规则或配伍校验；处方项按人工录入文本字段持久化
- `POST /api/v1/emr` 的 `diagnoses[]` 最小字段固定为：`diagnosisType`（`PRIMARY` / `SECONDARY`）、`diagnosisCode?`、`diagnosisName`、`isPrimary`、`sortOrder`
- `POST /api/v1/emr` 的 `content` 为病历正文，存储时做 AES 加密、PII 脱敏（身份证/手机号/姓名）和 SHA-256 哈希；`chiefComplaintSummary` 为可选摘要字段，存于 `emr_record` 表本身，便于列表展示
- `GET /api/v1/patients/me/emrs` 只返回当前患者本人的病历摘要列表，病历全文继续通过 `GET /api/v1/emr/{encounterId}` 读取
- 病历状态支持 `DRAFT` → `SIGNED` → `AMENDED`；创建后默认为 `DRAFT`，`sign()` 仅允许从 `DRAFT` 转换，`amend()` 仅允许从 `SIGNED` 转换
- `POST /api/v1/emr` 成功后返回 `recordNo`（人类可读编号，如 `EMR123456`）、`recordStatus`、`version`（乐观锁版本号）

## 4.5 审计

| 接口 | 请求 DTO 最小字段 | 响应 `data` 最小字段 |
|------|------------------|----------------------|
| `GET /api/v1/audit/events` | `from?`、`to?`、`actionCode?`、`operatorUserId?`、`patientUserId?`、`encounterId?`、`resourceType?`、`resourceId?`、`successFlag?`、`requestId?`、`pageNo?`、`pageSize?` | `PageData(items[].operatorUserId, items[].operatorUsername, items[].actorDepartmentId, items[].patientUserId, items[].encounterId, items[].reasonText, items[].clientIp, items[].userAgent)` |
| `GET /api/v1/audit/data-access` | `from?`、`to?`、`resourceType?`、`resourceId?`、`operatorUserId?`、`patientUserId?`、`encounterId?`、`accessAction?`、`accessResult?`、`requestId?`、`pageNo?`、`pageSize?` | `PageData(items[].operatorUserId, items[].operatorUsername, items[].actorDepartmentId, items[].patientUserId, items[].encounterId, items[].clientIp, items[].userAgent)` |

## 5. Java -> Python 内部 DTO 清单

## 5.1 Java 调 Python Chat

| 方向 | 最小字段 |
|------|----------|
| Java -> Python | `modelRunId`、`sessionId`、`turnId`、`message`、`sceneType`、`departmentId?`、`requestId` |
| Python -> Java | `answer`、`risk_level`、`guardrail_action`、`chief_complaint_summary`、`recommended_departments`、`care_advice`、`citations` |

`recommended_departments[]` 最小字段：

- `department_id`
- `department_name`
- `priority`
- `reason`

补充约定：

- `department_id` 由 Python 内部映射规则直接产出，不要求 Java 再根据聊天文本或科室名反推

## 5.1A Java 调 Python 知识库后台 API

| 方向 | 最小字段 |
|------|----------|
| Java -> Python | 后台知识库同名接口请求；统一携带 `X-Request-Id`、`X-Actor-Id`、`X-Hospital-Scope` |
| Python -> Java | 知识库、文档、入库任务、索引版本、发布记录的端点专属 DTO |

说明：

- Java 不再调用旧 `knowledge/prepare` 协议，也不传 `documentId/documentUuid/sourceUri` 让 Python 解析。
- 文档导入通过 `POST /api/v1/admin/knowledge-documents/import` 接收前端 `knowledgeBaseId + file`，并转为 `knowledge_base_id + file` 发给 Python。
- Python 负责保存文件、创建 `knowledge_document` / `ingest_job`、解析、清洗、切块、embedding、索引和发布。

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
