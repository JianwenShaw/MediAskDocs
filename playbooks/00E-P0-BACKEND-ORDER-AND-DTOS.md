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
| `A3` | `/api/v1/ai/sessions/{id}` | 会话详情与回看 | `M5` |
| `A4` | `/api/v1/ai/sessions/{id}/triage-result` | 导诊结果页 | `M5` |
| `A5` | `/api/v1/ai/sessions/{id}/registration-handoff` | AI 到挂号承接 | `M5-M6` |
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
| `POST /api/v1/admin/knowledge-documents/import` | `multipart/form-data`：`knowledgeBaseId`、`file` | `documentId`、`documentUuid`、`chunkCount`、`documentStatus` |

补充约定：

- 该接口是 Java 对外的最小后台知识导入入口，浏览器不直连 Python
- Java 根据上传文件推断 `title` 与 `sourceType`；当前支持 `MARKDOWN / DOCX / PDF`
- 前端不传 `sourceUri`；Java 接收文件后先写入对象存储/文件存储，再内部生成 `sourceUri`
- `dev` 环境下 `sourceUri` 为本地共享目录可读的 `file://...`，默认目录可放在项目根目录下的 `var/knowledge-storage`；`prod` 环境下目标口径为 OSS URI
- Java 不负责解析原始文档格式，只负责创建 `knowledge_document`、调用 Python `prepare`、持久化 `knowledge_chunk`、再调用 Python `index`

## 4.1B 知识库与文档治理

| 接口 | 请求 DTO 最小字段 | 响应 `data` 最小字段 |
|------|------------------|----------------------|
| `GET /api/v1/admin/knowledge-bases` | `pageNum?`、`pageSize?`、`keyword?` | `items[].id`、`kbCode`、`name`、`ownerType`、`ownerDeptId?`、`visibility`、`status`、`docCount` |
| `POST /api/v1/admin/knowledge-bases` | `name`、`kbCode`、`ownerType`、`ownerDeptId?`、`visibility` | `id`、`kbCode`、`name`、`ownerType`、`ownerDeptId?`、`visibility`、`status`、`docCount` |
| `PATCH /api/v1/admin/knowledge-bases/{id}` | Path `id`；Body：`name?`、`ownerType?`、`ownerDeptId?`、`visibility?`、`status?` | `id`、`kbCode`、`name`、`ownerType`、`ownerDeptId?`、`visibility`、`status`、`docCount` |
| `DELETE /api/v1/admin/knowledge-bases/{id}` | Path `id` | 无 |
| `GET /api/v1/admin/knowledge-documents` | `knowledgeBaseId`、`pageNum?`、`pageSize?` | `items[].id`、`documentUuid`、`title`、`sourceType`、`documentStatus`、`chunkCount` |
| `DELETE /api/v1/admin/knowledge-documents/{id}` | Path `id` | 无 |

补充约定：

- `GET /api/v1/admin/knowledge-bases` 的 `keyword` 同时搜索 `name` 与 `kbCode`
- 知识库列表与详情响应中的 `docCount` 为该知识库下文档总数
- `POST /api/v1/admin/knowledge-bases` 创建后状态固定为 `ENABLED`
- `PATCH /api/v1/admin/knowledge-bases/{id}` 支持部分更新，不支持修改 `kbCode`
- `ownerType=DEPARTMENT` 时必须传 `ownerDeptId`
- `GET /api/v1/admin/knowledge-documents` 当前只返回真实已落库字段，不包含失败原因文本
- 知识库删除与知识文档删除当前按软删除实现，并级联标记下游 `knowledge_document` / `knowledge_chunk`

## 4.2 AI 问诊

时间字段总规则：

- 所有业务日期时间字段统一返回秒级 ISO-8601 字符串，包含时区偏移，例如 `2026-04-19T10:34:54+08:00`
- 所有业务日期字段统一返回 `yyyy-MM-dd` 字符串，例如 `2026-04-19`
- `Result.timestamp` 固定为毫秒时间戳；它属于统一响应元数据，不属于业务字段时间格式规则

| 接口 | 请求 DTO 最小字段 | 响应 `data` / 事件最小字段 |
|------|------------------|-----------------------------|
| `POST /api/v1/ai/chat` | `sessionId?`、`message`、`departmentId?`、`sceneType`、`useStream` | `sessionId`、`turnId`、`answer`、`triageResult` |
| `GET /api/v1/ai/sessions` | 无 | `items[].sessionId`、`sceneType`、`status`、`departmentId?`、`chiefComplaintSummary?`、`summary?`、`startedAt`、`endedAt?` |
| `GET /api/v1/ai/sessions/{id}` | Path `sessionId` | `sessionId`、`sceneType`、`status`、`departmentId?`、`chiefComplaintSummary?`、`summary?`、`startedAt`、`endedAt?`、`turns[]` |
| `GET /api/v1/ai/sessions/{id}/triage-result` | Path `sessionId` | `sessionId`、`resultStatus`、`triageStage`、`riskLevel`、`guardrailAction`、`nextAction`、`recommendedDepartments`、`careAdvice`、`citations` |

### `triageResult` 最小字段

| 字段 | 说明 |
|------|------|
| `resultStatus` | `CURRENT / UPDATING` |
| `triageStage` | `COLLECTING / READY / BLOCKED` |
| `riskLevel` | `low / medium / high` |
| `guardrailAction` | `allow / caution / refuse` |
| `nextAction` | `CONTINUE_TRIAGE / VIEW_TRIAGE_RESULT / EMERGENCY_OFFLINE / MANUAL_SUPPORT` |
| `finalizedTurnId` | 当前结果对应的 finalized turn |
| `finalizedAt` | 当前结果完成时间 |
| `hasActiveCycle` | 当前是否存在新的 active cycle 在收集 |
| `activeCycleTurnNo` | 若有进行中 active cycle，其患者轮次 |
| `chiefComplaintSummary` | 症状摘要 |
| `followUpQuestions` | 仅在 chat / stream 的 `COLLECTING` 场景出现，最多 2 个 |
| `recommendedDepartments` | 推荐科室列表 |
| `careAdvice` | 保守建议或就医提示 |
| `citations` | 引用片段列表 |

`GET /api/v1/ai/sessions` 补充约定：

- 当前实现仅允许患者本人查看自己的会话列表
- 当前版本不分页、不筛选，按 `startedAt DESC` 返回
- 只返回最小摘要字段，不携带 `turns[]` 或导诊结构化结果
- `startedAt`、`endedAt` 对外统一返回秒级 ISO-8601 字符串，包含时区偏移，例如 `2026-04-19T10:34:54+08:00`

`GET /api/v1/ai/sessions/{id}` 补充约定：

- 当前实现仅允许患者本人回看自己的 AI 会话
- `turns[]` 至少返回 `turnId`、`turnNo`、`turnStatus`、`startedAt`、`completedAt?`、`errorCode?`、`errorMessage?`、`messages[]`
- `messages[]` 至少返回 `role`、`content`、`createdAt`
- `startedAt`、`endedAt`、`turns[].startedAt`、`turns[].completedAt`、`messages[].createdAt` 对外统一返回秒级 ISO-8601 字符串，包含时区偏移，例如 `2026-04-19T10:34:54+08:00`

## 4.3 挂号承接

| 接口 | 请求 DTO 最小字段 | 响应 `data` 最小字段 |
|------|------------------|----------------------|
| `POST /api/v1/ai/sessions/{id}/registration-handoff` | Path `sessionId` | `sessionId`、`recommendedDepartmentId?`、`recommendedDepartmentName?`、`chiefComplaintSummary?`、`suggestedVisitType?`、`blockedReason?`、`registrationQuery?` |
| `GET /api/v1/clinic-sessions` | `departmentId?`、`dateFrom?`、`dateTo?` | `items[]` |
| `GET /api/v1/clinic-sessions/{id}/slots` | Path `clinicSessionId` | `items[].clinicSlotId`、`slotSeq`、`slotStartTime`、`slotEndTime` |
| `POST /api/v1/registrations` | `clinicSessionId`、`clinicSlotId`、`sourceAiSessionId?` | `registrationId`、`orderNo`、`status` |
| `GET /api/v1/registrations` | `status?` | `items[]` |
| `GET /api/v1/registrations/{id}` | Path `registrationId` | `registrationId`、`orderNo`、`status`、`createdAt`、`sourceAiSessionId`、`clinicSessionId`、`clinicSlotId`、`departmentId`、`departmentName`、`doctorId`、`doctorName`、`sessionDate`、`periodCode`、`fee`、`cancelledAt?`、`cancellationReason?` |
| `PATCH /api/v1/registrations/{id}/cancel` | Path `registrationId` | `registrationId`、`status`、`cancelledAt` |

说明：登录态或 `CurrentUserResponse` 中的 `patientId` 表示 `patient_profile.id`；医疗业务表中的 `patient_id`（如 `registration_order.patient_id`）统一表示 `users.id`，两者不能混用。

补充约定：

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
| `GET /api/v1/encounters/{id}/ai-summary` | Path `encounterId` | `encounterId`、`sessionId`、`chiefComplaintSummary`、`structuredSummary`、`riskLevel`、`recommendedDepartments`、`latestCitations` |
| `PATCH /api/v1/encounters/{id}` | Path `encounterId` + Body `action` | `encounterId`、`encounterStatus`、`startedAt`、`endedAt` |
| `POST /api/v1/emr` | `encounterId`、`chiefComplaint`、`historyOfPresentIllness`、`diagnoses[]` | `emrRecordId`、`encounterId` |
| `GET /api/v1/emr/{encounterId}` | Path `encounterId` | `emrRecordId`、`content`、`diagnoses[]` |
| `POST /api/v1/prescriptions` | `encounterId`、`items[]` | `prescriptionOrderId`、`encounterId`、`status`、`items[]` |
| `GET /api/v1/prescriptions/{encounterId}` | Path `encounterId` | `prescriptionOrderId`、`encounterId`、`status`、`items[]` |

补充约定：

- `GET /api/v1/encounters` 只基于 `visit_encounter` 查询，不用 `registration_order` 直接拼“待接诊”列表。
- 挂号创建成功后即预创建 `visit_encounter`，初始状态固定为 `SCHEDULED`。
- `status` 只接受 `SCHEDULED`、`IN_PROGRESS`、`COMPLETED`、`CANCELLED`，不传则返回当前医生全部可见记录。
- `PATCH /api/v1/encounters/{id}` 的 `action` 仅支持 `START`、`COMPLETE`。`START` 仅允许 `SCHEDULED -> IN_PROGRESS`；`COMPLETE` 仅允许 `IN_PROGRESS -> COMPLETED`。
- `COMPLETE` 成功后同步更新 `registration_order.order_status = COMPLETED`；当前不联动 `clinic_slot`。
- `startedAt`、`endedAt` 对外统一返回秒级 ISO-8601 字符串，包含时区偏移，例如 `2026-04-19T10:34:54+08:00`
- `sessionDate` 作为业务日期字段，统一返回 `yyyy-MM-dd` 字符串
- `POST /api/v1/prescriptions` 的 `items[]` 最小字段固定为：`sortOrder`、`drugName`、`drugSpecification?`、`dosageText?`、`frequencyText?`、`durationText?`、`quantity`、`unit?`、`route?`
- `GET /api/v1/prescriptions/{encounterId}` 返回单张处方而不是列表；P0 口径固定为“一个 `encounter` 最多一张有效处方”
- 创建处方前必须已存在 `emr_record`；`prescription_order.record_id` 直接关联该接诊对应病历
- P0 处方状态只实现 `DRAFT`；`ISSUED`、`CANCELLED` 保留给后续独立动作，不在本轮实现
- P0 处方录入不依赖药品字典、库存、审方规则或配伍校验；处方项按人工录入文本字段持久化

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

`recommended_departments[]` 最小字段：

- `department_id`
- `department_name`
- `priority`
- `reason`

补充约定：

- `department_id` 由 Python 内部映射规则直接产出，不要求 Java 再根据聊天文本或科室名反推

## 5.1A Java 调 Python Knowledge Prepare

| 方向 | 最小字段 |
|------|----------|
| Java -> Python | `documentId`、`documentUuid`、`knowledgeBaseId`、`title`、`sourceType`、`sourceUri` |
| Python -> Java | `chunks[].chunkIndex`、`chunks[].content`、`chunks[].sectionTitle?`、`chunks[].pageNo?`、`chunks[].charStart?`、`chunks[].charEnd?`、`chunks[].tokenCount?`、`chunks[].contentPreview?`、`chunks[].citationLabel?` |

说明：

- Java 对上传文件做来源编排，内部生成 `sourceType/sourceUri`，不负责格式解析
- Python 负责根据 `sourceType/sourceUri` 解析原始文档、清洗与切块

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
