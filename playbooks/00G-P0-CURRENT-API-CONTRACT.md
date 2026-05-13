# P0 当前已实现接口契约（以代码为准）

> 状态：Current Repo Snapshot / Authoritative Against Code
>
> 适用范围：`mediask-api` 当前已经落地的 JSON HTTP 接口
>
> 判定依据：`controller + dto + assembler + usecase + api tests`
>
> 目的：回答“当前代码到底有哪些接口、参数要求是什么、真实业务语义是什么”，避免把目标设计文档误当成当前实现。

## 1. 先说结论

- 现有文档还没有把“当前已实现接口”的参数约束、身份要求和真实业务语义讲到足够完整。
- [../docs/01-OVERVIEW.md](../docs/01-OVERVIEW.md)、[../docs/10A-JAVA_AI_API_CONTRACT.md](../docs/10A-JAVA_AI_API_CONTRACT.md)、[../docs/03A-JAVA_CONFIG.md](../docs/03A-JAVA_CONFIG.md) 里包含大量目标设计或后续规划接口，不能直接当作当前仓库的对外契约。
- [00B-P0-DEVELOPMENT-CHECKLIST.md](./00B-P0-DEVELOPMENT-CHECKLIST.md)、[00C-P0-BACKEND-TASKS.md](./00C-P0-BACKEND-TASKS.md)、[00E-P0-BACKEND-ORDER-AND-DTOS.md](./00E-P0-BACKEND-ORDER-AND-DTOS.md) 适合看完成度和实现顺序，但对当前已实现接口的细节覆盖仍不够。
- 当前代码真实已实现的外部接口包括：认证、当前用户、患者本人资料、医生本人资料、管理员患者管理、管理员医生管理、知识库后台管理、知识文档后台管理、AI triage query / SSE 代理、AI 会话列表 / 明细 / finalized 结果读取、门诊场次查询、挂号、接诊列表、接诊详情、EMR 历史摘要列表、EMR 创建与详情、处方创建/详情/更新药品/开具/取消，以及审计事件/敏感访问查询接口。

## 2. 通用协议

| 主题 | 当前代码口径 |
|------|--------------|
| 统一响应 | 所有 JSON 接口都返回 `Result<T>`，字段固定为 `code`、`msg`、`data`、`requestId`、`timestamp` |
| 成功语义 | `code = 0` 表示成功 |
| 请求串联 | 优先使用请求头 `X-Request-Id`；如果没有该头但有 `X-Trace-Id`，会复用旧值；两者都没有时后端自动生成 |
| 回写位置 | 响应头和响应体都会回写同一个 `requestId` |
| 公开接口 | 只有 `POST /api/v1/auth/login`、`POST /api/v1/auth/refresh` 是公开接口 |
| 认证要求 | 除公开接口外，其余 `/api/**` 都要求登录态 |
| 空字段输出 | 当前 Jackson 配置为 `non_null`，`null` 字段不会出现在 JSON 中 |
| 长整型字段 | 当前 Jackson 配置会把所有对外 `Long/long` 业务字段序列化为字符串，避免前端精度丢失 |
| 业务日期时间字段 | 当前 Jackson 配置会把所有对外 `OffsetDateTime` 业务字段统一序列化为秒级 ISO-8601 字符串，并带时区偏移，例如 `2026-04-19T10:34:54+08:00` |
| 业务日期字段 | 当前 Jackson 配置会把所有对外 `LocalDate` 业务字段统一序列化为 `yyyy-MM-dd`，例如 `2026-04-19` |
| 统一响应时间戳 | `Result.timestamp` 固定为 Unix 毫秒时间戳；它是统一响应元数据，不属于业务日期/日期时间字段规则 |
| 参数错误 | 参数解析失败、类型不匹配、构造器抛 `IllegalArgumentException` 时统一返回 `400 + 1002` |
| 401/403 | 未认证返回 `401`；权限不足或角色不匹配返回 `403` |

补充说明：

- 带 `@AuthorizeScenario` 的接口，会先做场景权限判断；如果权限不满足，会直接返回 `403 + 1003`，不一定进入后续的角色校验逻辑。
- 当前 Python AI 服务联调口径是 `/api/v1/query` 与 `/api/v1/query/stream`；Java 对外暴露 `/api/v1/ai/triage/query` 与 `/api/v1/ai/triage/query/stream`。
- 因为浏览器 `Number` 无法安全表示雪花 ID，诸如 `userId`、`patientId`、`doctorId`、`knowledgeBaseId`、`documentId`、`sessionId` 这类字段在响应 JSON 中都应按字符串解析。
- 前端不要再按“某些接口返回时间字符串、某些接口返回时间数组”的思路适配；当前已实现 JSON API 中，业务日期时间统一是字符串，业务日期统一也是字符串。
- 具体区分规则：
  - 业务日期时间字段：通常命名为 `*At`、`*Time`，例如 `startedAt`、`createdAt`、`slotStartTime`
  - 业务日期字段：通常表示自然日，例如 `birthDate`、`sessionDate`、`dateFrom`、`dateTo`
  - `Result.timestamp`：统一响应包裹层字段，始终为毫秒时间戳

## 3. 当前已实现接口总览

| 分组 | 接口 | 认证/身份要求 | 真实业务语义 |
|------|------|---------------|--------------|
| 认证 | `POST /api/v1/auth/login` | 公开 | 手机号密码登录，签发新的 access/refresh token |
| 认证 | `POST /api/v1/auth/refresh` | 公开 | 使用 refresh token 轮换登录态 |
| 认证 | `POST /api/v1/auth/logout` | 已登录 | 要求当前 access token 与 refresh token 属于同一用户、同一会话，再执行退出 |
| 认证 | `GET /api/v1/auth/me` | 已登录 | 返回当前登录用户的实时上下文，而不是只回 token 里的静态声明 |
| 患者本人资料 | `GET /api/v1/patients/me/profile` | 已登录 + 患者本人权限 + `PATIENT` 角色 | 查询当前患者自己的业务档案 |
| 患者本人资料 | `PUT /api/v1/patients/me/profile` | 已登录 + 患者本人权限 + `PATIENT` 角色 | 更新当前患者自己的业务档案 |
| 患者本人病历 | `GET /api/v1/patients/me/emrs` | 已登录 + `emr:read` 权限 + `PATIENT` 角色 | 查询当前患者自己的病历摘要列表 |
| 医生本人资料 | `GET /api/v1/doctors/me/profile` | 已登录 + 医生本人权限 + `DOCTOR` 角色 | 查询当前医生自己的执业档案 |
| 医生本人资料 | `PUT /api/v1/doctors/me/profile` | 已登录 + 医生本人权限 + `DOCTOR` 角色 | 更新当前医生自己的执业档案 |
| 管理员患者管理 | `GET /api/v1/admin/patients` | 已登录 + 管理员患者列表权限 | 后台分页查患者，不是患者自助查询 |
| 管理员患者管理 | `GET /api/v1/admin/patients/{patientId}` | 已登录 + 管理员患者查看权限 | 查指定患者后台详情 |
| 管理员患者管理 | `POST /api/v1/admin/patients` | 已登录 + 管理员患者创建权限 | 后台创建患者账户和患者档案 |
| 管理员患者管理 | `PUT /api/v1/admin/patients/{patientId}` | 已登录 + 管理员患者更新权限 | 后台更新指定患者档案 |
| 管理员患者管理 | `DELETE /api/v1/admin/patients/{patientId}` | 已登录 + 管理员患者删除权限 | 后台软删除指定患者 |
| 管理员医生管理 | `GET /api/v1/admin/doctors` | 已登录 + 管理员医生列表权限 | 后台分页查医生，含科室归属 |
| 管理员医生管理 | `GET /api/v1/admin/doctors/{doctorId}` | 已登录 + 管理员医生查看权限 | 查指定医生后台详情 |
| 管理员医生管理 | `POST /api/v1/admin/doctors` | 已登录 + 管理员医生创建权限 | 后台创建医生账户、医生档案和科室分配 |
| 管理员医生管理 | `PUT /api/v1/admin/doctors/{doctorId}` | 已登录 + 管理员医生更新权限 | 后台更新指定医生档案和科室分配 |
| 管理员医生管理 | `DELETE /api/v1/admin/doctors/{doctorId}` | 已登录 + 管理员医生删除权限 | 后台软删除指定医生 |
| 管理员科室管理 | `GET /api/v1/admin/departments` | 已登录 + 管理员科室列表权限 | 后台分页查科室，支持关键词搜索 |
| 管理员科室管理 | `GET /api/v1/admin/departments/{id}` | 已登录 + 管理员科室查看权限 | 查指定科室后台详情 |
| 管理员科室管理 | `POST /api/v1/admin/departments` | 已登录 + 管理员科室创建权限 | 后台创建科室 |
| 管理员科室管理 | `PUT /api/v1/admin/departments/{id}` | 已登录 + 管理员科室更新权限 | 后台更新指定科室 |
| 管理员科室管理 | `DELETE /api/v1/admin/departments/{id}` | 已登录 + 管理员科室删除权限 | 后台软删除指定科室 |
| 知识库后台管理 | `GET /api/v1/admin/knowledge-bases` | 已登录 + 知识库列表权限 | Java 网关转发到 Python 知识库列表接口 |
| 知识库后台管理 | `GET /api/v1/admin/knowledge-bases/{knowledgeBaseId}` | 已登录 + 知识库列表权限 | Java 网关转发到 Python 知识库详情接口 |
| 知识库后台管理 | `POST /api/v1/admin/knowledge-bases` | 已登录 + 知识库创建权限 | Java 网关转发到 Python 知识库创建接口 |
| 知识库后台管理 | `PATCH /api/v1/admin/knowledge-bases/{knowledgeBaseId}` | 已登录 + 知识库更新权限 | Java 网关转发到 Python 知识库更新接口 |
| 知识库后台管理 | `DELETE /api/v1/admin/knowledge-bases/{knowledgeBaseId}` | 已登录 + 知识库删除权限 | Java 网关转发到 Python 知识库归档接口 |
| 知识文档后台管理 | `POST /api/v1/admin/knowledge-documents/import` | 已登录 + 知识文档导入权限 + 依赖 `mediask.ai.base-url` | Java 网关转发上传文件到 Python 入库接口 |
| 知识文档后台管理 | `GET /api/v1/admin/knowledge-documents` | 已登录 + 知识文档列表权限 | Java 网关转发到 Python 文档列表接口 |
| 知识文档后台管理 | `GET /api/v1/admin/knowledge-documents/{documentId}` | 已登录 + 知识文档列表权限 | Java 网关转发到 Python 文档详情接口 |
| 知识文档后台管理 | `GET /api/v1/admin/knowledge-documents/{documentId}/chunks` | 已登录 + 知识文档列表权限 | Java 网关转发到 Python 文档 chunk 预览接口 |
| 知识文档后台管理 | `POST /api/v1/admin/knowledge-documents/{documentId}/reingest` | 已登录 + 知识文档导入权限 | Java 网关转发到 Python 文档重新入库接口 |
| 知识文档后台管理 | `DELETE /api/v1/admin/knowledge-documents/{documentId}` | 已登录 + 知识文档删除权限 | Java 网关转发到 Python 文档删除接口 |
| 知识库后台管理 | `GET /api/v1/admin/ingest-jobs` | 已登录 + 入库任务查看权限 | Java 网关转发到 Python 入库任务列表接口 |
| 知识库后台管理 | `GET /api/v1/admin/ingest-jobs/{jobId}` | 已登录 + 入库任务查看权限 | Java 网关转发到 Python 入库任务详情接口 |
| 知识库后台管理 | `GET /api/v1/admin/knowledge-index-versions` | 已登录 + 索引版本列表权限 | Java 网关转发到 Python 索引版本列表接口 |
| 知识库后台管理 | `GET /api/v1/admin/knowledge-releases` | 已登录 + 发布记录列表权限 | Java 网关转发到 Python 发布记录列表接口 |
| 知识库后台管理 | `POST /api/v1/admin/knowledge-releases` | 已登录 + 发布权限 | Java 网关转发到 Python 发布接口 |
| 管理端 AI 评估 | `POST /api/v1/admin/query-evaluations` | 已登录 + `admin:triage-catalog:publish` | Java 网关转发到 Python dry-run 问诊评估接口 |
| AI Triage Query | `POST /api/v1/ai/triage/query` | 已登录 + `PATIENT` 角色 + 依赖 AI service 配置 | 患者发起同步 triage query，返回结构化 `triageResult` |
| AI Triage SSE | `POST /api/v1/ai/triage/query/stream` | 已登录 + `PATIENT` 角色 + 依赖 AI service 配置 | 患者发起流式 triage query，Java 代理 Python SSE，并只在 `final` 前校验和落库 |
| AI Sessions | `GET /api/v1/ai/sessions` | 已登录 + `PATIENT` 角色 + 依赖 AI service 配置 | 查询当前患者 AI 会话摘要列表 |
| AI Session Detail | `GET /api/v1/ai/sessions/{sessionId}` | 已登录 + `PATIENT` 角色 + 依赖 AI service 配置 | 查询当前患者单个 AI 会话详情 |
| AI Session Result | `GET /api/v1/ai/sessions/{sessionId}/triage-result` | 已登录 + `PATIENT` 角色 + 依赖 AI service 配置 | 查询当前患者最近一次 finalized 导诊结果视图 |
| 门诊挂号 | `GET /api/v1/clinic-sessions` | 已登录 | 查询当前可挂号的开放门诊场次 |
| 门诊挂号 | `POST /api/v1/registrations` | 已登录 + `PATIENT` 角色 | 当前患者创建挂号，同时预创建接诊记录 |
| 门诊挂号 | `GET /api/v1/registrations` | 已登录 + `PATIENT` 角色 | 查询当前患者自己的挂号列表 |
| 门诊挂号 | `GET /api/v1/registrations/{registrationId}` | 已登录 + `PATIENT` 角色 | 查询当前患者自己的单个挂号详情 |
| 门诊挂号 | `PATCH /api/v1/registrations/{registrationId}/cancel` | 已登录 + `PATIENT` 角色 | 取消当前患者自己的挂号，并联动释放号源与取消预创建接诊 |
| 医生接诊 | `GET /api/v1/encounters` | 已登录 + 接诊列表权限 + `DOCTOR` 角色 | 查询当前医生自己的接诊列表 |
| 医生接诊 | `GET /api/v1/encounters/{encounterId}` | 已登录 + 接诊列表权限 + `DOCTOR` 角色 | 查询当前医生自己的单个接诊详情 |
| 医生接诊 | `GET /api/v1/encounters/{encounterId}/ai-summary` | 已登录 + 接诊列表权限 + `DOCTOR` 角色 | 查询当前医生可查看的接诊 AI 预问诊摘要 |
| 医生接诊 | `GET /api/v1/encounters/{encounterId}/emr-history` | 已登录 + `emr:read` 权限 + `DOCTOR` 角色 | 查询当前接诊患者的历史病历摘要列表 |
| 医生接诊 | `PATCH /api/v1/encounters/{encounterId}` | 已登录 + 接诊更新权限 + `DOCTOR` 角色 | 更新当前医生自己的接诊状态（开始/完成） |
| 处方 | `POST /api/v1/prescriptions` | 已登录 + 处方创建权限 + `DOCTOR` 角色 | 医生为自己的接诊创建处方（DRAFT） |
| 处方 | `GET /api/v1/prescriptions/{encounterId}` | 已登录 + 处方读取权限 | 查看处方详情（医生按接诊归属、患者按本人） |
| 处方 | `PATCH /api/v1/prescriptions/{encounterId}/items` | 已登录 + 处方更新权限 + `DOCTOR` 角色 | 更新处方药品（仅 DRAFT 状态） |
| 处方 | `POST /api/v1/prescriptions/{encounterId}/issue` | 已登录 + 处方开具权限 + `DOCTOR` 角色 | 开具处方（DRAFT → ISSUED） |
| 处方 | `POST /api/v1/prescriptions/{encounterId}/cancel` | 已登录 + 处方取消权限 + `DOCTOR` 角色 | 取消处方（DRAFT/ISSUED → CANCELLED） |

## 4. 认证与当前用户

### 4.1 `CurrentUserResponse` / `userContext`

`GET /api/v1/auth/me` 的 `data`，以及 `POST /api/v1/auth/login`、`POST /api/v1/auth/refresh` 的 `data.userContext`，使用同一字段语义：

| 字段 | 说明 |
|------|------|
| `userId` | 当前登录用户的 `users.id` |
| `username` | 登录名 |
| `displayName` | 展示名 |
| `userType` | 当前用户类型，如 `PATIENT`、`DOCTOR`、`ADMIN` |
| `roles` | 角色代码列表 |
| `permissions` | 权限代码列表 |
| `dataScopeRules[]` | 数据范围规则，字段为 `resourceType`、`scopeType`、`scopeDepartmentId` |
| `patientId` | 患者档案 ID，仅患者用户有值 |
| `doctorId` | 医生档案 ID，仅医生用户有值 |
| `primaryDepartmentId` | 主科室 ID，仅医生等相关角色可能有值 |

### 4.2 `POST /api/v1/auth/login`

| 项目 | 当前代码口径 |
|------|--------------|
| 认证 | 公开接口 |
| 请求体 | `phone`、`password` |
| `phone` 要求 | 非空；会去掉首尾空格 |
| `password` 要求 | 非空；保留首尾空格，不做 trim |
| 响应字段 | `accessToken`、`accessTokenExpiresAt`、`refreshToken`、`refreshTokenExpiresAt`、`userContext` |
| 真实语义 | 校验手机号密码；账号若被禁用或锁定会失败；用户必须至少有一个角色；成功后更新最后登录时间并签发一组新的 access/refresh token |

补充说明：

- 当前实现即使收到无效的 `Authorization` 请求头，也不会影响登录流程。
- `accessTokenExpiresAt`、`refreshTokenExpiresAt` 为毫秒时间戳。

### 4.3 `POST /api/v1/auth/refresh`

| 项目 | 当前代码口径 |
|------|--------------|
| 认证 | 公开接口 |
| 请求体 | `refreshToken` |
| `refreshToken` 要求 | 非空；会做 trim |
| 响应字段 | 与登录接口相同 |
| 真实语义 | 校验 refresh token 存在且未过期；重新加载当前用户；要求用户仍然有角色且仍然拥有 `auth:refresh` 权限；成功后轮换 refresh token，并签发新的 access token |

### 4.4 `POST /api/v1/auth/logout`

| 项目 | 当前代码口径 |
|------|--------------|
| 认证 | 需要登录态 |
| 请求头 | `Authorization: Bearer <accessToken>` |
| 请求体 | `refreshToken` |
| `refreshToken` 要求 | 非空；会做 trim |
| 成功响应 | `Result<Void>` |
| 真实语义 | 不是“只靠 refresh token 就能退出”；当前 access token 和请求体里的 refresh token 必须属于同一用户、同一 refresh session；成功后会把 access token 加入 blocklist，并删除 refresh token |

补充说明：

- 如果 `Authorization` 缺失、不是 `Bearer ` 格式，或 access token 无效，会直接返回 `401`。
- 如果 refresh token 属于其他用户，或者属于同一用户但不是当前 access token 对应的同一 session，会返回 `403 + 2011`。
- 旧版无 `sessionId` 的 access token 也不能用于当前退出流程。

### 4.5 `GET /api/v1/auth/me`

| 项目 | 当前代码口径 |
|------|--------------|
| 认证 | 需要登录态 |
| 请求参数 | 无 |
| 响应字段 | `CurrentUserResponse` |
| 真实语义 | 返回当前登录用户的实时上下文；会重新查当前用户，而不是只信任 token 里的静态声明 |

补充说明：

- 如果用户权限在登录后被后台撤销，`/auth/me` 和其他受保护接口会立即体现最新权限，而不是继续沿用旧 token 的权限快照。

## 5. 患者与医生本人资料

### 5.1 `GET /api/v1/patients/me/profile`

| 项目 | 当前代码口径 |
|------|--------------|
| 认证 | 需要登录态、患者本人查看权限、`PATIENT` 角色 |
| 响应字段 | `patientId`、`patientNo`、`gender`、`birthDate`、`bloodType`、`allergySummary` |
| 真实语义 | 只查当前登录患者自己的业务档案，不支持传任意 `patientId` 查询 |

### 5.2 `PUT /api/v1/patients/me/profile`

| 字段 | 要求 |
|------|------|
| `gender` | 可为空；非空时大小写不敏感，但最终会规范为 `MALE`、`FEMALE`、`OTHER` 三者之一 |
| `birthDate` | 可为空，`LocalDate` |
| `bloodType` | 可为空；空白字符串会转成 `null` |
| `allergySummary` | 可为空；空白字符串会转成 `null` |

业务语义：

- 只更新当前登录患者自己的业务档案。
- 不更新 `username`、`displayName`、手机号等账户基础信息。

### 5.3 `GET /api/v1/doctors/me/profile`

| 项目 | 当前代码口径 |
|------|--------------|
| 认证 | 需要登录态、医生本人查看权限、`DOCTOR` 角色 |
| 响应字段 | `doctorId`、`doctorCode`、`professionalTitle`、`introductionMasked`、`hospitalId`、`primaryDepartmentId`、`primaryDepartmentName` |
| 真实语义 | 只查当前登录医生自己的执业档案 |

### 5.4 `PUT /api/v1/doctors/me/profile`

| 字段 | 要求 |
|------|------|
| `professionalTitle` | 可为空；空白字符串会转成 `null` |
| `introductionMasked` | 可为空；空白字符串会转成 `null` |

业务语义：

- 只更新当前登录医生自己的执业档案。
- 当前实现没有对职称枚举做额外校验。

## 6. 管理员患者管理

### 6.1 `GET /api/v1/admin/patients`

| 项目 | 当前代码口径 |
|------|--------------|
| 认证 | 需要登录态和管理员患者列表权限 |
| 查询参数 | `keyword?`、`pageNum?`、`pageSize?` |
| `keyword` 规则 | 空白字符串会转成 `null` |
| `pageNum` 规则 | 默认 `1`；必须大于 `0`；最大 `10000` |
| `pageSize` 规则 | 默认 `20`；必须大于 `0`；最大 `100` |
| 响应结构 | `PageData`，包含 `items`、`pageNum`、`pageSize`、`total`、`totalPages`、`hasNext` |
| 列表项字段 | `patientId`、`userId`、`patientNo`、`username`、`displayName`、`mobileMasked`、`gender`、`birthDate`、`bloodType`、`accountStatus` |
| 真实语义 | 面向后台管理使用，按关键字分页查患者，不是患者自助查询接口 |

### 6.2 `GET /api/v1/admin/patients/{patientId}`

| 项目 | 当前代码口径 |
|------|--------------|
| 认证 | 需要登录态和管理员患者查看权限 |
| 路径参数 | `patientId`，必须大于 `0` |
| 响应字段 | `patientId`、`userId`、`patientNo`、`username`、`displayName`、`mobileMasked`、`gender`、`birthDate`、`bloodType`、`allergySummary`、`accountStatus` |
| 真实语义 | 查后台完整患者详情；不存在时返回 `404 + 2014` |

### 6.3 `POST /api/v1/admin/patients`

| 字段 | 要求 |
|------|------|
| `username` | 必填；非空；会 trim |
| `phone` | 必填；非空；会 trim |
| `password` | 必填；非空；保留首尾空格，不做 trim |
| `displayName` | 必填；非空；会 trim |
| `mobileMasked` | 可空；空白字符串转 `null` |
| `gender` | 可空；空白字符串转 `null` |
| `birthDate` | 可空，`LocalDate` |
| `bloodType` | 可空；空白字符串转 `null` |
| `allergySummary` | 可空；空白字符串转 `null` |

业务语义：

- 这是后台创建患者账户和患者档案的接口。
- 当前实现会对密码做哈希后再写入。
- 当前实现没有对 `gender`、`bloodType` 做枚举约束校验。

### 6.4 `PUT /api/v1/admin/patients/{patientId}`

| 字段 | 要求 |
|------|------|
| Path `patientId` | 必填；必须大于 `0` |
| `displayName` | 必填；非空；会 trim |
| `phone` | 必填；非空；会 trim |
| `mobileMasked` | 可空；空白字符串转 `null` |
| `gender` | 可空；空白字符串转 `null` |
| `birthDate` | 可空，`LocalDate` |
| `bloodType` | 可空；空白字符串转 `null` |
| `allergySummary` | 可空；空白字符串转 `null` |

业务语义：

- 这是后台更新患者档案的接口。
- 当前实现同样没有对 `gender`、`bloodType` 做枚举约束校验。

### 6.5 `DELETE /api/v1/admin/patients/{patientId}`

| 项目 | 当前代码口径 |
|------|--------------|
| 认证 | 需要登录态和管理员患者删除权限 |
| 路径参数 | `patientId`，必须大于 `0` |
| 成功响应 | `Result<Void>` |
| 真实语义 | 后台软删除指定患者，不是物理删除 |

## 6A. 管理员医生管理

### 6A.1 `GET /api/v1/admin/doctors`

| 项目 | 当前代码口径 |
|------|--------------|
| 认证 | 需要登录态和管理员医生列表权限 |
| 查询参数 | `keyword?`、`pageNum?`、`pageSize?` |
| `keyword` 规则 | 空白字符串会转成 `null`；会匹配用户名、展示名和医生编码 |
| `pageNum` 规则 | 默认 `1`；必须大于 `0`；最大 `10000` |
| `pageSize` 规则 | 默认 `20`；必须大于 `0`；最大 `100` |
| 响应结构 | `PageData`，包含 `items`、`pageNum`、`pageSize`、`total`、`totalPages`、`hasNext` |
| 列表项字段 | `doctorId`、`userId`、`username`、`displayName`、`doctorCode`、`professionalTitle`、`primaryDepartmentName`、`accountStatus` |
| 真实语义 | 面向后台管理使用，按关键字分页查医生，连带主科室名称 |

### 6A.2 `GET /api/v1/admin/doctors/{doctorId}`

| 项目 | 当前代码口径 |
|------|--------------|
| 认证 | 需要登录态和管理员医生查看权限 |
| 路径参数 | `doctorId`，必须大于 `0` |
| 响应字段 | `doctorId`、`userId`、`username`、`displayName`、`phone`、`hospitalId`、`doctorCode`、`professionalTitle`、`introductionMasked`、`departments[]`、`accountStatus` |
| `departments[]` | `departmentId`、`departmentName`、`primary` |
| 真实语义 | 查后台完整医生详情（含科室分配）；不存在时返回 `404 + 2021`；访问会记录 `data_access_log` 并标记 `ADMIN_OPERATION` 目的 |

### 6A.3 `POST /api/v1/admin/doctors`

| 字段 | 要求 |
|------|------|
| `username` | 必填；非空；会 trim |
| `phone` | 必填；非空；会 trim |
| `password` | 必填；非空；保留首尾空格，不做 trim |
| `displayName` | 必填；非空；会 trim |
| `hospitalId` | 必填；必须大于 `0` |
| `professionalTitle` | 可空；空白字符串转 `null` |
| `introductionMasked` | 可空；空白字符串转 `null` |
| `departmentIds` | 可空；第一个为默认主科室 |

业务语义：

- 这是后台创建医生账户、医生档案和科室分配的一体化接口。
- 创建时会生成 `userId` 和 `doctorId`，`doctorCode` 由后端自动生成（`DOC_` 前缀 + 雪花 ID），前端不需要传。
- 写入 `users`、`doctors`、`user_roles`（DOCTOR 角色）和 `doctor_department_rel`。
- 当前实现会对密码做哈希后再写入。
- 用户名/手机号冲突分别返回 `2022`/`2024`。
- DOCTOR 角色不存在时返回 `2025`。

### 6A.4 `PUT /api/v1/admin/doctors/{doctorId}`

| 字段 | 要求 |
|------|------|
| Path `doctorId` | 必填；必须大于 `0` |
| `displayName` | 必填；非空；会 trim |
| `phone` | 必填；非空；会 trim |
| `professionalTitle` | 可空；空白字符串转 `null` |
| `introductionMasked` | 可空；空白字符串转 `null` |
| `departmentIds` | 可空；采用全量替换策略 |

业务语义：

- 这是后台更新医生档案和科室分配的接口。
- 更新采用乐观锁；并发冲突返回 `2026`。
- 更新成功后会使对应 `CacheKeyGenerator.doctorProfileByUserId` 缓存失效。

### 6A.5 `DELETE /api/v1/admin/doctors/{doctorId}`

| 项目 | 当前代码口径 |
|------|--------------|
| 认证 | 需要登录态和管理员医生删除权限 |
| 路径参数 | `doctorId`，必须大于 `0` |
| 成功响应 | `Result<Void>` |
| 真实语义 | 后台软删除指定医生（`users` + `doctors` + 科室关系置为 `DISABLED`） |

---

## 6B. 管理员科室管理

### 6B.1 `GET /api/v1/admin/departments`

| 项目 | 当前代码口径 |
|------|--------------|
| 认证 | 需要登录态和管理员科室列表权限 |
| 查询参数 | `keyword?`、`pageNum?`、`pageSize?` |
| `keyword` 规则 | 空白字符串会转成 `null`；会匹配 `name` 和 `deptCode` |
| `pageNum` 规则 | 默认 `1`；必须大于 `0`；最大 `10000` |
| `pageSize` 规则 | 默认 `20`；必须大于 `0`；最大 `100` |
| 响应结构 | `PageData`，包含 `items`、`pageNum`、`pageSize`、`total`、`totalPages`、`hasNext` |
| 列表项字段 | `id`、`hospitalId`、`deptCode`、`name`、`deptType`、`sortOrder`、`status` |
| 真实语义 | 面向后台管理使用，按关键字分页查科室，按 `sortOrder` 升序、`id` 升序排列 |

### 6B.2 `GET /api/v1/admin/departments/{id}`

| 项目 | 当前代码口径 |
|------|--------------|
| 认证 | 需要登录态和管理员科室查看权限 |
| 路径参数 | `id`，必须大于 `0` |
| 响应字段 | `id`、`hospitalId`、`deptCode`、`name`、`deptType`、`sortOrder`、`status` |
| 真实语义 | 查后台完整科室详情；不存在时返回 `404 + 2028` |

### 6B.3 `POST /api/v1/admin/departments`

| 字段 | 要求 |
|------|------|
| `hospitalId` | 必填；必须大于 `0` |
| `name` | 必填；非空；会 trim |
| `deptType` | 必填；非空；会 trim；约束为 `CLINICAL` / `TECHNICAL` / `MANAGEMENT` |

业务语义：

- 这是后台创建科室的接口。
- 创建时会生成雪花 ID，`deptCode` 由后端自动生成（`DEPT_` 前缀 + 雪花 ID），`sortOrder` 默认为 `0`，前端不需要传。
- 初始 `status` 固定为 `ACTIVE`，`version` 固定为 `0`。
- `deptCode` 在同一 `hospitalId` 下唯一（`uk_departments_code`），冲突返回 `2029`。
- 创建成功记录 `audit_event`。

### 6B.4 `PUT /api/v1/admin/departments/{id}`

| 字段 | 要求 |
|------|------|
| Path `id` | 必填；必须大于 `0` |
| `name` | 必填；非空；会 trim |
| `deptType` | 必填；非空；会 trim |
| `status` | 必填；非空；会 trim；约束为 `ACTIVE` / `DISABLED` |
| `sortOrder` | 可空；默认 `0` |

业务语义：

- 这是后台更新科室的接口。
- 更新采用乐观锁（`version` 字段），并发冲突返回 `2030`。
- 科室不存在时返回 `404 + 2028`。
- 更新成功记录 `audit_event`。

### 6B.5 `DELETE /api/v1/admin/departments/{id}`

| 项目 | 当前代码口径 |
|------|--------------|
| 认证 | 需要登录态和管理员科室删除权限 |
| 路径参数 | `id`，必须大于 `0` |
| 成功响应 | `Result<Void>` |
| 真实语义 | 后台软删除指定科室（MyBatis-Plus 逻辑删除，`deletedAt` 置为当前时间）；不存在时返回 `404 + 2028`；成功记录 `audit_event` |

---

## 7. 门诊场次与挂号

### 7.1 `GET /api/v1/clinic-sessions`

| 项目 | 当前代码口径 |
|------|--------------|
| 认证 | 需要登录态 |
| 查询参数 | `departmentId?`、`dateFrom?`、`dateTo?` |
| `departmentId` 规则 | 可空；非空时必须大于 `0` |
| 日期格式 | `yyyy-MM-dd` |
| 响应字段 | `items[].clinicSessionId`、`departmentId`、`departmentName`、`doctorId`、`doctorName`、`sessionDate`、`periodCode`、`clinicType`、`remainingCount`、`fee` |
| 真实语义 | 查“当前可挂号的开放门诊场次”，不是完整排班管理接口 |

补充说明：

- 当前实现没有额外限制必须是患者才能调用；任意已登录用户都可以查询。
- `periodCode`、`clinicType` 当前直接输出枚举名。
- 该接口只返回场次头摘要，不直接返回可提交的 `clinicSlotId`。
- `dateFrom`、`dateTo`、`sessionDate` 作为业务日期字段，统一返回 `yyyy-MM-dd` 字符串。

### 7.2 `GET /api/v1/clinic-sessions/{clinicSessionId}/slots`

| 项目 | 当前代码口径 |
|------|--------------|
| 认证 | 需要登录态 |
| 路径参数 | `clinicSessionId` |
| 响应字段 | `items[].clinicSlotId`、`slotSeq`、`slotStartTime`、`slotEndTime` |
| 真实语义 | 查询指定开放门诊场次下当前仍可挂的具体号源，供前端选号后再提交挂号 |

补充说明：

- 当前只返回 `slot_status = AVAILABLE` 的号源。
- `slotStartTime`、`slotEndTime` 统一返回秒级 ISO-8601 字符串，包含时区偏移。
- 前端应先查 `GET /api/v1/clinic-sessions` 选场次，再查本接口拿 `clinicSlotId`。

### 7.3 `POST /api/v1/registrations`

| 项目 | 当前代码口径 |
|------|--------------|
| 认证 | 需要登录态和 `PATIENT` 角色 |
| 请求体 | `clinicSessionId`、`clinicSlotId`、`sourceAiSessionId?` |
| `sourceAiSessionId` | 可空，用于挂号与 AI 会话关联 |
| 响应字段 | `registrationId`、`orderNo`、`status` |
| 真实语义 | 当前患者发起挂号；后端使用当前登录用户的 `userId` 作为患者主体，不允许前端自行传 `patientUserId`；创建挂号成功后会立即预创建一条 `visit_encounter`，初始状态固定为 `SCHEDULED` |

补充说明：

- `clinicSessionId`、`clinicSlotId` 在当前 DTO 层没有显式 Bean Validation，但业务上都被当作必需 ID 使用。
- 当前实现创建成功后 `status` 固定返回 `CONFIRMED`。
- 当前实现会原样承接可选 `sourceAiSessionId`，用于后续医生端读取接诊 AI 摘要。
- 当前实现会先校验场次是否存在且处于开放状态；不存在时返回 `404 + 3004`。
- 如果号源已满或无法预占，会返回 `409 + 3005`。
- 已登录但不是患者角色时，返回 `403 + 2008`。

### 7.4 `GET /api/v1/registrations`

| 项目 | 当前代码口径 |
|------|--------------|
| 认证 | 需要登录态和 `PATIENT` 角色 |
| 查询参数 | `status?` |
| `status` 可选值 | `CONFIRMED`、`CANCELLED`、`COMPLETED` |
| 非法 `status` | 返回 `400 + 1002` |
| 响应字段 | `items[].registrationId`、`orderNo`、`status`、`createdAt`、`sourceAiSessionId` |
| 真实语义 | 永远只查当前登录患者自己的挂号列表，不支持按任意患者 ID 查询 |

补充说明：

- 这里的患者主体使用的是当前登录用户的 `userId`。
- `CurrentUserResponse.patientId` 是 `patient_profile.id`，不要和挂号业务里的患者用户 ID 混用。
- `createdAt` 当前统一返回秒级 ISO-8601 字符串，包含时区偏移，例如 `2026-04-19T10:34:54+08:00`。
- `sourceAiSessionId` 当前为普通字符串字段，原样返回；未关联 AI 问诊时省略或返回 `null`。

### 7.5 `GET /api/v1/registrations/{registrationId}`

| 项目 | 当前代码口径 |
|------|--------------|
| 认证 | 需要登录态和 `PATIENT` 角色 |
| 路径参数 | `registrationId` |
| 响应字段 | `registrationId`、`orderNo`、`status`、`createdAt`、`sourceAiSessionId`、`clinicSessionId`、`clinicSlotId`、`departmentId`、`departmentName`、`doctorId`、`doctorName`、`sessionDate`、`periodCode`、`fee`、`cancelledAt?`、`cancellationReason?` |
| 真实语义 | 只允许查看当前登录患者自己的挂号详情；不存在或不属于本人时统一返回 `404 + 3008`；关联医生/科室/场次若已软删除，历史订单仍应可查看 |

补充说明：

- `createdAt`、`cancelledAt` 当前统一返回秒级 ISO-8601 字符串，包含时区偏移。
- `sessionDate` 当前统一返回 `yyyy-MM-dd` 字符串，例如 `2026-04-03`。
- `periodCode` 当前直接返回枚举名，例如 `MORNING`。
- `sourceAiSessionId` 当前为普通字符串字段，原样返回；未关联 AI 问诊时省略或返回 `null`。
- 当关联主数据已软删除时，`departmentName`、`doctorName`、`sessionDate`、`periodCode` 允许返回 `null`。

### 7.9 `GET /api/v1/encounters/{encounterId}/ai-summary`

| 项目 | 当前代码口径 |
|------|--------------|
| 认证 | 需要登录态、`DOCTOR` 角色和 `encounter:query` 权限 |
| 路径参数 | `encounterId` |
| 响应字段 | `encounterId`、`sessionId`、`chiefComplaintSummary`、`riskLevel`、`recommendedDepartments`、`careAdvice`、`citations`、`blockedReason`、`catalogVersion`、`finalizedAt` |
| 真实语义 | 医生读取自己接诊关联的 AI 结构化摘要；不返回完整问诊原文或患者侧会话详情 |

补充说明：

- 该接口通过 `registration_order.source_ai_session_id` 追到 AI 会话，再读取 triage-result。
- `encounterId` 和 `recommendedDepartments[].departmentId` 以字符串返回。
- `finalizedAt` 当前统一返回秒级 ISO-8601 字符串，包含时区偏移。
- 如果接诊不存在、不是当前医生、未关联 AI 问诊，或关联会话没有 finalized triage 结果，分别返回现有的 `4004`、`4003`、`4005`。

### 7.6 `PATCH /api/v1/registrations/{registrationId}/cancel`

| 项目 | 当前代码口径 |
|------|--------------|
| 认证 | 需要登录态和 `PATIENT` 角色 |
| 路径参数 | `registrationId` |
| 请求体 | 无 |
| 响应字段 | `registrationId`、`status`、`cancelledAt` |
| 真实语义 | 只允许取消当前登录患者自己的挂号；取消成功后会释放对应占用号源、刷新场次剩余号数，并把预创建的 `visit_encounter` 置为 `CANCELLED` |

补充说明：

- 不存在或不属于本人时返回 `404 + 3008`。
- 当挂号状态已不允许取消，或关联接诊不再处于 `SCHEDULED`，或号源无法释放时，返回 `409 + 3009`。
- 当前仅 `CONFIRMED` 状态允许取消；其他状态会触发 `409 + 3006`。
- 取消时要求 slot 当前为 `BOOKED`，成功后回退为 `AVAILABLE`。

## 8. 知识库后台管理网关

### 8.1 `GET /api/v1/admin/knowledge-bases`

| 项目 | 当前代码口径 |
|------|--------------|
| 认证 | 需要登录态和知识库列表权限 |
| 前端查询参数 | `keyword?`、`pageNum?`、`pageSize?` |
| Java 转 Python 查询参数 | `keyword?`、`page_num?`、`page_size?` |
| 响应结构 | Python 返回的分页 DTO，Java 将 `data` 字段递归转为 camelCase 后外层包装 `Result<T>` |
| 真实语义 | Java 只做认证、鉴权、请求头透传和错误映射，不查询 Java 本地 `knowledge_*` 表 |

### 8.2 `POST /api/v1/admin/knowledge-bases`

| 字段 | 要求 |
|------|------|
| 前端请求体 | camelCase 字段，如 `code`、`name`、`description`、`defaultEmbeddingModel`、`defaultEmbeddingDimension`、`retrievalStrategy` |
| Java 转 Python 请求体 | 递归转为 snake_case，如 `default_embedding_model`、`default_embedding_dimension`、`retrieval_strategy` |

业务语义：

- Java 不解析知识库治理字段，不生成知识库 ID，不维护状态机。
- Java 转发 `X-Request-Id`、`X-Actor-Id`、`X-Hospital-Scope`，其中 P0 `X-Hospital-Scope` 固定为 `default`。
- Python 响应作为 `data` 转为 camelCase 后返回给前端。

### 8.2A `GET /api/v1/admin/knowledge-bases/{knowledgeBaseId}`

| 项目 | 当前代码口径 |
|------|--------------|
| 认证 | 需要登录态和知识库列表权限 |
| 路径参数 | `knowledgeBaseId`，按字符串透传给 Python |
| 响应结构 | Python 返回的详情 DTO，Java 将 `data` 字段递归转为 camelCase 后外层包装 `Result<T>` |
| 真实语义 | Java 不读取本地知识库表，只做鉴权、请求头透传和错误映射 |

### 8.3 `PATCH /api/v1/admin/knowledge-bases/{knowledgeBaseId}`

| 字段 | 要求 |
|------|------|
| Path `knowledgeBaseId` | 必填；按字符串透传给 Python |
| 前端请求体 | camelCase 字段；当前字段如 `name?`、`description?`、`status?` |
| Java 转 Python 请求体 | 递归转为 snake_case 后转发 |

业务语义：

- Java 不判断字段是否可更新；字段约束以 Python 合同为准。

### 8.4 `DELETE /api/v1/admin/knowledge-bases/{knowledgeBaseId}`

| 项目 | 当前代码口径 |
|------|--------------|
| 认证 | 需要登录态和知识库删除权限 |
| 路径参数 | `knowledgeBaseId`，按字符串透传给 Python |
| 成功响应 | `Result<Void>` |
| 真实语义 | Java 转发删除请求；归档、索引重建或发布撤销由 Python 决定 |

### 8.5 `POST /api/v1/admin/knowledge-documents/import`

| 项目 | 当前代码口径 |
|------|--------------|
| 认证 | 需要登录态和知识文档导入权限 |
| 请求格式 | `multipart/form-data` |
| 前端表单字段 | `knowledgeBaseId`、`file` |
| Java 转 Python 表单字段 | `knowledge_base_id`、`file` |
| 响应字段 | 前端收到 `documentId`、`jobId`、`lifecycleStatus`、`jobStatus` 等 camelCase 字段 |
| 真实语义 | Java 接收上传文件后直接转发给 Python；Python 保存文件、创建文档和入库任务 |

补充说明：

- 该网关依赖 `mediask.ai.base-url`；未配置时请求失败并返回 `6001`。
- Java 不推断 `sourceType`，不生成 `sourceUri`，不持久化 chunk。

### 8.6 `GET /api/v1/admin/knowledge-documents`

| 项目 | 当前代码口径 |
|------|--------------|
| 认证 | 需要登录态和知识文档列表权限 |
| 前端查询参数 | `knowledgeBaseId`、`keyword?`、`lifecycleStatus?`、`latestJobStatus?`、`pageNum?`、`pageSize?` |
| Java 转 Python 查询参数 | `knowledge_base_id`、`keyword?`、`lifecycle_status?`、`latest_job_status?`、`page_num?`、`page_size?` |
| 响应结构 | Python 返回的分页 DTO，Java 将 `data` 字段递归转为 camelCase 后外层包装 `Result<T>` |
| 真实语义 | Java 不查询 `knowledge_document`；列表字段以 Python API 为准 |

### 8.7 `GET /api/v1/admin/knowledge-documents/{documentId}`

| 项目 | 当前代码口径 |
|------|--------------|
| 认证 | 需要登录态和知识文档列表权限 |
| 路径参数 | `documentId`，按字符串透传给 Python |
| 响应结构 | Python 返回的详情 DTO，Java 将 `data` 字段递归转为 camelCase 后外层包装 `Result<T>` |
| 真实语义 | Java 不查询 `knowledge_document`；详情字段以 Python API 为准 |

### 8.8 `GET /api/v1/admin/knowledge-documents/{documentId}/chunks`

| 项目 | 当前代码口径 |
|------|--------------|
| 认证 | 需要登录态和知识文档列表权限 |
| 路径参数 | `documentId`，按字符串透传给 Python |
| 前端查询参数 | `pageNum?`、`pageSize?` |
| Java 转 Python 查询参数 | `page_num?`、`page_size?` |
| 响应结构 | Python 返回的分页 DTO，Java 将 `data` 字段递归转为 camelCase 后外层包装 `Result<T>` |
| 真实语义 | Java 不查询 chunk，只转发分页预览请求 |

### 8.9 `POST /api/v1/admin/knowledge-documents/{documentId}/reingest`

| 项目 | 当前代码口径 |
|------|--------------|
| 认证 | 需要登录态和知识文档导入权限 |
| 路径参数 | `documentId`，按字符串透传给 Python |
| 成功响应 | Python 返回的任务 DTO，Java 将 `data` 字段递归转为 camelCase 后外层包装 `Result<T>` |
| 真实语义 | Java 不上传新文件，不重建索引，只请求 Python 基于已有 `source_uri` 重新创建入库任务 |

### 8.10 `DELETE /api/v1/admin/knowledge-documents/{documentId}`

| 项目 | 当前代码口径 |
|------|--------------|
| 认证 | 需要登录态和知识文档删除权限 |
| 路径参数 | `documentId`，按字符串透传给 Python |
| 成功响应 | `Result<Void>` |
| 真实语义 | Java 转发删除请求；文档删除、索引重建或发布撤销由 Python 决定 |

### 8.11 入库任务、索引版本与发布

| 接口 | 当前代码口径 |
|------|--------------|
| `GET /api/v1/admin/ingest-jobs` | 需要入库任务查看权限；前端查询参数 `knowledgeBaseId`、`documentId?`、`status?`、`pageNum?`、`pageSize?`；Java 转 Python 为 `knowledge_base_id`、`document_id?`、`status?`、`page_num?`、`page_size?`；响应 `data` 转 camelCase |
| `GET /api/v1/admin/ingest-jobs/{jobId}` | 需要入库任务查看权限；Path `jobId` 按字符串透传 |
| `GET /api/v1/admin/knowledge-index-versions` | 需要索引版本列表权限；前端查询参数 `knowledgeBaseId`，Java 转 Python 为 `knowledge_base_id`，响应 `data` 转 camelCase |
| `GET /api/v1/admin/knowledge-releases` | 需要发布记录列表权限；前端查询参数 `knowledgeBaseId`，Java 转 Python 为 `knowledge_base_id`，响应 `data` 转 camelCase |
| `POST /api/v1/admin/knowledge-releases` | 需要发布权限；前端请求体 `knowledgeBaseId`、`targetIndexVersionId`，Java 转 Python 为 `knowledge_base_id`、`target_index_version_id`，响应 `data` 转 camelCase |

补充说明：

- Java 不读取 Python 的 `ingest_job`、`knowledge_index_version`、`knowledge_release` 表。
- Java 当前实现用 typed request/query/payload 对象承接前端入参，再在 Python 适配器内统一转为 snake_case；不要在 Controller 中拼 Python 协议细节。
- Java 调 Python 时按 operation 记录结构化日志，至少包含 `operation`、`requestId`、`actorId`、`hospitalScope`、`resourceId`、`durationMs`，但不记录上传文件内容。
- Python 4xx 响应映射为 Java 侧统一 4xx 错误；其中 404 映射为 `1004`，其他 4xx 映射为 `1002`。
- Python 5xx 或网络不可用映射为 `6001`，响应解析异常映射为 `6003`。

## 9. 医生接诊列表

### 9.1 `GET /api/v1/encounters`

| 项目 | 当前代码口径 |
|------|--------------|
| 认证 | 需要登录态、接诊列表权限、`DOCTOR` 角色 |
| 查询参数 | `status?` |
| `status` 可选值 | `SCHEDULED`、`IN_PROGRESS`、`COMPLETED`、`CANCELLED` |
| 非法 `status` | 返回 `400 + 1002` |
| 响应字段 | `items[].encounterId`、`registrationId`、`patientUserId`、`patientName`、`departmentId`、`departmentName`、`sessionDate`、`periodCode`、`encounterStatus`、`startedAt`、`endedAt` |
| 真实语义 | 永远只查当前登录医生自己的接诊列表，不支持传任意 `doctorId` 查询 |

补充说明：

- 当前控制器会从登录态取 `doctorId`，再传给 UseCase。
- 当前实现已覆盖接诊列表、接诊详情、AI 摘要、当前接诊患者历史病历摘要、EMR、处方。
- 没有接诊权限的医生会先在场景鉴权阶段收到 `403 + 1003`。

### 9.2 `GET /api/v1/encounters/{encounterId}`

| 项目 | 当前代码口径 |
|------|--------------|
| 认证 | 需要登录态、接诊列表权限、`DOCTOR` 角色 |
| 路径参数 | `encounterId` |
| 响应字段 | `encounterId`、`registrationId`、`patientSummary.patientUserId`、`patientSummary.patientName`、`patientSummary.gender?`、`patientSummary.departmentId`、`patientSummary.departmentName`、`patientSummary.sessionDate`、`patientSummary.periodCode`、`patientSummary.encounterStatus`、`patientSummary.startedAt`、`patientSummary.endedAt?`、`patientSummary.age?` |
| 真实语义 | 永远只查当前登录医生自己的单条接诊详情，不支持传任意 `doctorId` 查询 |

补充说明：

- `patientSummary.gender` 来自 `patient_profile.gender`，当前直接返回业务值 `MALE`、`FEMALE`、`OTHER`，未填写时允许为 `null`。
- `patientSummary.age` 当前按接诊 `sessionDate` 与 `birthDate` 计算；任一字段缺失时返回 `null`。
- `patientSummary.patientUserId`、`departmentId`、`encounterId`、`registrationId` 对外统一序列化为字符串。
- `patientSummary.sessionDate` 统一返回 `yyyy-MM-dd` 字符串；`startedAt`、`endedAt` 统一返回带时区偏移的秒级 ISO-8601 字符串。
- 接诊不存在返回 `404 + 4004`；接诊不属于当前医生返回 `403 + 4003`。

### 9.3 `GET /api/v1/encounters/{encounterId}/emr-history`

| 项目 | 当前代码口径 |
|------|--------------|
| 认证 | 需要登录态、`emr:read` 权限、`DOCTOR` 角色 |
| 路径参数 | `encounterId` |
| 响应字段 | `items[].emrRecordId`、`encounterId`、`recordNo`、`recordStatus`、`departmentId`、`departmentName?`、`doctorId`、`doctorName?`、`sessionDate?`、`chiefComplaintSummary?`、`createdAt` |
| 真实语义 | 先按当前 `encounterId` 校验医生是否可访问该接诊，再返回该患者的历史病历摘要列表，不返回病历正文 |

补充说明：

- 这个接口的访问控制是对象级的：医生只能用自己可见的当前接诊作为入口查看历史病历。
- 返回列表会排除当前 `encounterId` 自己对应的病历，避免当前病历和历史病历重复展示。
- 当前实现只查摘要投影，不解密 `contentEncrypted`，病历全文仍需调用 `GET /api/v1/emr/{encounterId}`。
- `departmentName`、`doctorName`、`sessionDate` 在关联历史组织或排班记录已软删除时允许为空。

### 9.4 `PATCH /api/v1/encounters/{encounterId}`

| 项目 | 当前代码口径 |
|------|--------------|
| 认证 | 需要登录态、接诊更新权限、`DOCTOR` 角色 |
| 路径参数 | `encounterId` |
| 请求体 | `action`，可选值：`START`、`COMPLETE` |
| 非法 `action` | 返回 `400 + 1002` |
| 响应字段 | `encounterId`、`encounterStatus`、`startedAt`、`endedAt` |
| 真实语义 | 永远只允许当前登录医生更新自己的接诊记录；`START` 仅允许 `SCHEDULED -> IN_PROGRESS`，`COMPLETE` 仅允许 `IN_PROGRESS -> COMPLETED` |

补充说明：

- `COMPLETE` 成功后会同步把对应 `registration_order.order_status` 更新为 `COMPLETED`。
- `START` 执行时会要求关联挂号状态为 `CONFIRMED`。
- 当前实现不联动 `clinic_slot` 状态。
- 状态流转不合法返回 `409 + 4010`；并发更新冲突返回 `409 + 4011`；挂号状态同步失败返回 `409 + 4012`。
- 接诊不存在返回 `404 + 4004`；接诊不属于当前医生返回 `403 + 4003`。

## 10. 当前已实现 AI 接口补充

### 10.1 `POST /api/v1/ai/triage/query`

| 项目 | 当前代码口径 |
|------|--------------|
| 认证/身份 | 已登录 + `PATIENT` 角色 |
| 请求体 | `sessionId?`、`hospitalScope?`、`userMessage` |
| 默认值 | `hospitalScope` 为空时固定使用 `default` |
| 响应字段 | `requestId`、`sessionId`、`turnId`、`queryRunId`、`triageResult` |
| `triageResult` | `triageStage`、`triageCompletionReason`、`nextAction`、`riskLevel?`、`chiefComplaintSummary?`、`followUpQuestions[]`、`recommendedDepartments[]`、`careAdvice?`、`blockedReason?`、`catalogVersion?`、`citations[]` |

补充说明：

- Java 对 Python 固定发送 `/api/v1/query` 和 `scene=AI_TRIAGE`
- Java 对 Python query 和 sessions 接口都会透传 `X-Patient-User-Id`
- 当前响应不再包含旧 `answer`
- `COLLECTING` 不落库
- `READY` / `BLOCKED` 会在 Java 侧校验后写入 `ai_triage_result`
- `READY` 场景会校验 `catalogVersion + departmentId + departmentName`

### 10.2 `POST /api/v1/ai/triage/query/stream`

| 项目 | 当前代码口径 |
|------|--------------|
| 认证/身份 | 已登录 + `PATIENT` 角色 |
| 请求体 | 与同步 query 相同 |
| Content-Type | `text/event-stream` |
| Java 行为 | 调 Python `/api/v1/query/stream`，再把 `start/progress/delta/final/error/done` 重组后输出给前端 |
| 结构化真相 | 只认 `final` 事件里的完整 `triage_result` |

补充说明：

- `delta` 只用于展示，不可驱动业务状态
- Java 到 Python 仍用 `snake_case`，但浏览器侧收到的 SSE `data` 统一是 `camelCase`
- `start`：`requestId`、`sessionId`、`turnId`、`queryRunId`
- `progress`：`step`
- `delta`：`textDelta`
- `final`：与同步 query `data` 相同的 `camelCase` 结构
- `error`：`code`、`message`
- `done`：`{}`
- Java 只在 `final` 事件校验通过后才承认该次 finalized 结果
- 如果 `final` 解析失败、目录校验失败或落库失败，Java 会返回 `error` 事件而不是继续输出成功 `final`

### 10.3 `GET /api/v1/ai/sessions`

| 项目 | 当前代码口径 |
|------|--------------|
| 认证/身份 | 已登录 + `PATIENT` 角色 |
| 请求参数 | 无 |
| 响应字段 | `items[].sessionId`、`sceneType`、`status`、`departmentId?`、`chiefComplaintSummary?`、`summary?`、`startedAt`、`endedAt?` |
| 真实语义 | Java 直接转发 Python `/api/v1/sessions`，返回当前患者会话摘要列表 |

补充说明：

- 浏览器看到的是 `camelCase`
- `departmentId` 对外按字符串返回
- 当前不读本地 `ai_triage_result` 回填会话列表

### 10.4 `GET /api/v1/ai/sessions/{sessionId}`

| 项目 | 当前代码口径 |
|------|--------------|
| 认证/身份 | 已登录 + `PATIENT` 角色 |
| 路径参数 | `sessionId` |
| 响应字段 | 顶层摘要字段 + `turns[].turnId`、`turnNo`、`turnStatus`、`startedAt`、`completedAt`、`errorCode`、`errorMessage`、`messages[]` |
| 真实语义 | Java 直接转发 Python `/api/v1/sessions/{session_id}`，返回当前患者单个会话详情 |

补充说明：

- `messages[]` 直接反映 Python 已持久化历史消息
- Python `404` 会映射为 Java `404 + 1004`

### 10.5 `GET /api/v1/ai/sessions/{sessionId}/triage-result`

| 项目 | 当前代码口径 |
|------|--------------|
| 认证/身份 | 已登录 + `PATIENT` 角色 |
| 路径参数 | `sessionId` |
| 响应字段 | `sessionId`、`resultStatus`、`triageStage`、`riskLevel`、`guardrailAction`、`nextAction`、`finalizedTurnId`、`finalizedAt`、`hasActiveCycle`、`activeCycleTurnNo?`、`chiefComplaintSummary?`、`recommendedDepartments[]`、`careAdvice?`、`citations[]`、`blockedReason?`、`catalogVersion?` |
| 真实语义 | Java 直接转发 Python `/api/v1/sessions/{session_id}/triage-result`，返回当前患者最近一次 finalized 结果视图 |

补充说明：

- 这个接口不读本地 `ai_triage_result`
- Python `404` 会映射为 Java `404 + 1004`
- Python “结果未就绪” 的 `409` 会映射为 Java `409 + 6101`

### 10.6 `POST /api/v1/admin/triage-catalog/publish`

| 项目 | 当前代码口径 |
|------|--------------|
| 认证/身份 | 已登录 + `ADMIN` 权限 `admin:triage-catalog:publish` |

### 10.7 `POST /api/v1/admin/query-evaluations`

| 项目 | 当前代码口径 |
|------|--------------|
| 认证/身份 | 已登录 + `ADMIN` 权限 `admin:triage-catalog:publish` |
| 前端请求体 | `hospitalScope?`、`userMessage` |
| Java 转 Python 请求体 | `scene=AI_TRIAGE`、`hospital_scope`、`user_message` |
| Java -> Python 请求头 | `X-Request-Id`、`X-API-Key`、`X-Actor-Id`、`X-Hospital-Scope` |
| 响应字段 | `requestId`、`triageResult`、`evaluation`，其中 `evaluation.primaryDepartmentId` 对前端按字符串返回 |
| 真实语义 | 这是管理端 dry-run 调试接口，不创建真实 `session`，不写 `ai_turn`、`query_run`、`query_result_snapshot` 或 Java finalized snapshot |

补充说明：

- `triageResult` 仍是业务真相，`evaluation` 只是评估视图。
- `hospitalScope` 为空时 Java 默认使用 `default`。
- Python 返回管理端 triage 应用失败时，Java 对前端统一返回 `6007`。
- Python 网络不可用映射为 `6001`，响应结构非法映射为 `6003`。
| 查询参数 | `hospitalScope?`，默认 `default` |
| 响应结构 | `Result<T>` |
| 响应字段 | `catalogVersion`、`candidateCount`、`publishedAt` |
| Redis active key | `triage_catalog:active:{hospital_scope}` |
| Redis content key | `triage_catalog:{hospital_scope}:{catalog_version}` |
| Redis content 字段 | `hospital_scope`、`catalog_version`、`published_at`、`department_candidates[]` |
| `department_candidates[]` | `department_id`、`department_name`、`routing_hint`、`aliases[]`、`sort_order` |

补充说明：

- 当前目录语义是“可导诊目录”，不是 `departments` 全量透出。
- 当前实现由 Java 基于活动中的临床科室做受控投影，不新增独立目录表。
- Python 不调用 Java 内部 HTTP 目录接口，只按 `docs/proposals/03-redis-catalog-contract.md` 读取 Redis。
- `publishedAt` 当前统一返回秒级 ISO-8601 字符串，包含时区偏移，例如 `2026-04-19T10:34:54+08:00`。

## 11. 当前已实现 EMR 接口

### 11.1 `GET /api/v1/patients/me/emrs`

| 项目 | 当前代码口径 |
|------|--------------|
| 认证/身份 | 已登录 + `emr:read` 权限 + `PATIENT` 角色 |
| 请求参数 | 无 |
| 响应字段 | `items[].emrRecordId`、`encounterId`、`recordNo`、`recordStatus`、`departmentId`、`departmentName?`、`doctorId`、`doctorName?`、`sessionDate?`、`chiefComplaintSummary?`、`createdAt` |
| 真实语义 | 永远只返回当前登录患者自己的病历摘要列表，不支持传任意患者 ID |

补充说明：

- 这里的列表是病历摘要，不包含 `content` 和 `diagnoses[]`。
- `emrRecordId`、`encounterId`、`departmentId`、`doctorId` 对外按字符串返回。
- `sessionDate` 按 `yyyy-MM-dd` 返回；`createdAt` 按带时区偏移的秒级 ISO-8601 字符串返回。

### 11.2 `POST /api/v1/emr`

| 项目 | 当前代码口径 |
|------|--------------|
| 认证/身份 | 已登录 + `emr:create` 权限 + `DOCTOR` 角色 |
| 请求体 | `encounterId`、`chiefComplaintSummary?`、`content`、`diagnoses[]` |
| 响应字段 | `recordId`、`recordNo`、`encounterId`、`recordStatus`、`version` |
| 真实语义 | 医生为自己的接诊创建病历草稿；一个接诊当前只允许一份病历 |

补充说明：

- `diagnoses[]` 最小字段固定为：`diagnosisType`、`diagnosisCode?`、`diagnosisName`、`isPrimary`、`sortOrder`。
- `content` 是病历正文，入库时会执行 AES 加密、PII 脱敏和 SHA-256 哈希。
- 成功返回的人类可读编号 `recordNo` 形如 `EMR123456`。

### 11.3 `GET /api/v1/emr/{encounterId}`

| 项目 | 当前代码口径 |
|------|--------------|
| 认证/身份 | 已登录 + `emr:read` 权限；患者按本人、医生按对象级接诊可见性 |
| 路径参数 | `encounterId` |
| 响应字段 | `emrRecordId`、`content`、`diagnoses[]` |
| 真实语义 | 返回单次接诊对应病历的全文详情 |

补充说明：

- 患者访问时按 `SELF_SERVICE` 目的记录敏感访问日志；医生访问时按 `TREATMENT` 目的记录。
- 当前返回的是全文详情，不是摘要投影。
- 接口找不到病历时返回 `404 + 4008`。

## 12. 当前已实现处方接口

### 12.1 `POST /api/v1/prescriptions`

| 项目 | 当前代码口径 |
|------|--------------|
| 认证/身份 | 需要登录态、处方创建权限、`DOCTOR` 角色 |
| 请求体 | `encounterId`、`items[]` |
| `items[]` | `sortOrder`、`drugName`、`drugSpecification?`、`dosageText?`、`frequencyText?`、`durationText?`、`quantity`、`unit?`、`route?` |
| 响应字段 | `prescriptionOrderId`、`encounterId`、`status`、`items[]` |
| 真实语义 | 仅允许当前登录医生为自己的接诊记录创建处方；P0 固定为一个 `encounter` 最多一张 `DRAFT` 处方 |

补充说明：

- 创建前必须已存在对应 `emr_record`，否则返回 `404 + 4014`
- 接诊不存在或不属于当前医生时返回 `404 + 4013`
- 同一接诊重复创建处方返回 `409 + 4015`
- 当前实现不依赖药品字典、库存、审方规则或配伍校验
- `prescriptionOrderId`、`encounterId` 对外统一序列化为字符串

### 12.2 `GET /api/v1/prescriptions/{encounterId}`

| 项目 | 当前代码口径 |
|------|--------------|
| 认证/身份 | 需要登录态、处方读取权限、`DOCTOR` 角色 |
| 路径参数 | `encounterId` |
| 响应字段 | `prescriptionOrderId`、`encounterId`、`status`、`version`、`items[]` |
| 真实语义 | 当前只允许医生查看自己接诊范围内的处方详情，不返回列表 |

补充说明：

- 接诊不存在或不属于当前医生时返回 `404 + 4013`
- 处方不存在返回 `404 + 4016`
- 当前已对处方详情接入对象级授权与访问留痕；医生按接诊归属访问，患者按本人处方自助访问
- `prescriptionOrderId`、`encounterId` 对外统一序列化为字符串

### 12.3 `PATCH /api/v1/prescriptions/{encounterId}/items`

| 项目 | 当前代码口径 |
|------|--------------|
| 认证/身份 | 需要登录态、处方更新权限、`DOCTOR` 角色 |
| 路径参数 | `encounterId` |
| 请求体 | `items[]`：`sortOrder`、`drugName`、`drugSpecification?`、`dosageText?`、`frequencyText?`、`durationText?`、`quantity`、`unit?`、`route?` |
| 响应字段 | `prescriptionOrderId`、`encounterId`、`status`、`version`、`items[]` |
| 真实语义 | 仅允许当前登录医生更新自己接诊的 DRAFT 处方药品；采用全量替换策略（删除旧项 + 插入新项），使用乐观锁保证并发安全 |

补充说明：

- 接诊不存在或不属于当前医生时返回 `404 + 4013`
- 处方不存在返回 `404 + 4016`
- 处方状态非 DRAFT 时返回 `409 + 4017`
- 并发更新冲突（乐观锁失败）返回 `409 + 4018`
- `items` 不能为空；`prescriptionOrderId`、`encounterId` 对外统一序列化为字符串

### 12.4 `POST /api/v1/prescriptions/{encounterId}/issue`

| 项目 | 当前代码口径 |
|------|--------------|
| 认证/身份 | 需要登录态、处方开具权限、`DOCTOR` 角色 |
| 路径参数 | `encounterId` |
| 请求体 | 无 |
| 响应字段 | `prescriptionOrderId`、`encounterId`、`status`、`version` |
| 真实语义 | 将当前登录医生自己接诊的 DRAFT 处方开具为 ISSUED 状态 |

补充说明：

- 接诊不存在或不属于当前医生时返回 `404 + 4013`
- 处方不存在返回 `404 + 4016`
- 处方状态非 DRAFT 时返回 `409 + 4017`
- 并发更新冲突（乐观锁失败）返回 `409 + 4018`
- `prescriptionOrderId`、`encounterId` 对外统一序列化为字符串

### 12.5 `POST /api/v1/prescriptions/{encounterId}/cancel`

| 项目 | 当前代码口径 |
|------|--------------|
| 认证/身份 | 需要登录态、处方取消权限、`DOCTOR` 角色 |
| 路径参数 | `encounterId` |
| 请求体 | 无 |
| 响应字段 | `prescriptionOrderId`、`encounterId`、`status`、`version` |
| 真实语义 | 将当前登录医生自己接诊的 DRAFT 或 ISSUED 处方取消为 CANCELLED 状态 |

补充说明：

- 接诊不存在或不属于当前医生时返回 `404 + 4013`
- 处方不存在返回 `404 + 4016`
- 处方状态非 DRAFT 且非 ISSUED 时返回 `409 + 4017`
- 并发更新冲突（乐观锁失败）返回 `409 + 4018`
- `prescriptionOrderId`、`encounterId` 对外统一序列化为字符串

### 12.6 处方状态流转

| 当前状态 | 允许操作 | 目标状态 |
|----------|----------|----------|
| `DRAFT` | `updateItems` | `DRAFT`（药品更新） |
| `DRAFT` | `issue` | `ISSUED` |
| `DRAFT` | `cancel` | `CANCELLED` |
| `ISSUED` | `cancel` | `CANCELLED` |

所有状态变更均使用乐观锁（`version` 字段）保证并发安全。

## 13. 审计查询接口

### 13.1 `GET /api/v1/audit/events`

| 项目 | 当前代码口径 |
|------|--------------|
| 认证 | 需要登录态与 `audit:query` 权限 |
| 对象授权 | 走 `AUDIT_EVENT_QUERY` 场景鉴权；拒绝访问会写失败审计 |
| 查询参数 | `from?`、`to?`、`actionCode?`、`operatorUserId?`、`patientUserId?`、`encounterId?`、`resourceType?`、`resourceId?`、`successFlag?`、`requestId?`、`pageNo?`、`pageSize?` |
| `resourceId` 口径 | 字符串业务键 |
| 响应结构 | `PageData`，包含 `items`、`pageNum`、`pageSize`、`total`、`totalPages`、`hasNext` |
| 响应项关键字段 | `operatorUserId`、`operatorUsername`、`operatorRoleCode`、`actorDepartmentId`、`patientUserId`、`encounterId`、`reasonText`、`clientIp`、`userAgent`、`resourceType`、`resourceId`、`successFlag` |
| 真实语义 | 查询 `audit_event`，并对本次查询本身写 `AUDIT_QUERY` 审计；查询摘要会记录操作者、患者、接诊、时间窗和结果条件 |

### 13.2 `GET /api/v1/audit/data-access`

| 项目 | 当前代码口径 |
|------|--------------|
| 认证 | 需要登录态与 `audit:query` 权限 |
| 对象授权 | 走 `AUDIT_DATA_ACCESS_QUERY` 场景鉴权；拒绝访问会写失败审计 |
| 查询参数 | `from?`、`to?`、`resourceType?`、`resourceId?`、`operatorUserId?`、`patientUserId?`、`encounterId?`、`accessAction?`、`accessResult?`、`requestId?`、`pageNo?`、`pageSize?` |
| `resourceId` 口径 | 字符串业务键 |
| 响应结构 | `PageData`，包含 `items`、`pageNum`、`pageSize`、`total`、`totalPages`、`hasNext` |
| 响应项关键字段 | `operatorUserId`、`operatorUsername`、`operatorRoleCode`、`actorDepartmentId`、`patientUserId`、`encounterId`、`clientIp`、`userAgent`、`accessAction`、`accessPurposeCode`、`accessResult`、`denyReasonCode` |
| 真实语义 | 查询 `data_access_log`，并对本次查询本身写 `AUDIT_QUERY` 审计；支持按接诊直接回看病历/处方/AI 敏感访问轨迹 |

## 13. 一句话结论

如果目的是“按当前代码联调或写前后端接口文档”，应以本文档为准；如果目的是“看目标架构或后续计划”，再看 `01-OVERVIEW`、`10A`、`00E` 等设计/排期文档。
