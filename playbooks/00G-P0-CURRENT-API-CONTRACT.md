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
- 当前代码真实已实现的外部接口包括：认证、当前用户、患者本人资料、医生本人资料、管理员患者管理、知识库后台管理、知识文档后台管理、AI 问诊、AI 会话回看、AI 导诊结果、门诊场次查询、挂号、接诊列表、接诊详情、医生侧 AI 摘要。EMR、处方、审计接口还没有对外落地。

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
| 参数错误 | 参数解析失败、类型不匹配、构造器抛 `IllegalArgumentException` 时统一返回 `400 + 1002` |
| 401/403 | 未认证返回 `401`；权限不足或角色不匹配返回 `403` |

补充说明：

- 带 `@AuthorizeScenario` 的接口，会先做场景权限判断；如果权限不满足，会直接返回 `403 + 1003`，不一定进入后续的角色校验逻辑。
- 当前 Python AI 服务已收口为同步 `/api/v1/chat`；如上层需要“流式”观感，应基于完整回答做伪流式展示，而不是依赖 Python SSE。
- 因为浏览器 `Number` 无法安全表示雪花 ID，诸如 `userId`、`patientId`、`doctorId`、`knowledgeBaseId`、`documentId`、`sessionId` 这类字段在响应 JSON 中都应按字符串解析。

## 3. 当前已实现接口总览

| 分组 | 接口 | 认证/身份要求 | 真实业务语义 |
|------|------|---------------|--------------|
| 认证 | `POST /api/v1/auth/login` | 公开 | 用户名密码登录，签发新的 access/refresh token |
| 认证 | `POST /api/v1/auth/refresh` | 公开 | 使用 refresh token 轮换登录态 |
| 认证 | `POST /api/v1/auth/logout` | 已登录 | 要求当前 access token 与 refresh token 属于同一用户、同一会话，再执行退出 |
| 认证 | `GET /api/v1/auth/me` | 已登录 | 返回当前登录用户的实时上下文，而不是只回 token 里的静态声明 |
| 患者本人资料 | `GET /api/v1/patients/me/profile` | 已登录 + 患者本人权限 + `PATIENT` 角色 | 查询当前患者自己的业务档案 |
| 患者本人资料 | `PUT /api/v1/patients/me/profile` | 已登录 + 患者本人权限 + `PATIENT` 角色 | 更新当前患者自己的业务档案 |
| 医生本人资料 | `GET /api/v1/doctors/me/profile` | 已登录 + 医生本人权限 + `DOCTOR` 角色 | 查询当前医生自己的执业档案 |
| 医生本人资料 | `PUT /api/v1/doctors/me/profile` | 已登录 + 医生本人权限 + `DOCTOR` 角色 | 更新当前医生自己的执业档案 |
| 管理员患者管理 | `GET /api/v1/admin/patients` | 已登录 + 管理员患者列表权限 | 后台分页查患者，不是患者自助查询 |
| 管理员患者管理 | `GET /api/v1/admin/patients/{patientId}` | 已登录 + 管理员患者查看权限 | 查指定患者后台详情 |
| 管理员患者管理 | `POST /api/v1/admin/patients` | 已登录 + 管理员患者创建权限 | 后台创建患者账户和患者档案 |
| 管理员患者管理 | `PUT /api/v1/admin/patients/{patientId}` | 已登录 + 管理员患者更新权限 | 后台更新指定患者档案 |
| 管理员患者管理 | `DELETE /api/v1/admin/patients/{patientId}` | 已登录 + 管理员患者删除权限 | 后台软删除指定患者 |
| 知识库后台管理 | `GET /api/v1/admin/knowledge-bases` | 已登录 + 知识库列表权限 | 后台分页查询知识库，并返回每个知识库的 `docCount` |
| 知识库后台管理 | `POST /api/v1/admin/knowledge-bases` | 已登录 + 知识库创建权限 | 后台创建知识库 |
| 知识库后台管理 | `PATCH /api/v1/admin/knowledge-bases/{knowledgeBaseId}` | 已登录 + 知识库更新权限 | 后台更新知识库治理字段或启停状态 |
| 知识库后台管理 | `DELETE /api/v1/admin/knowledge-bases/{knowledgeBaseId}` | 已登录 + 知识库删除权限 | 后台物理删除知识库及其下游文档/chunk |
| 知识文档后台管理 | `POST /api/v1/admin/knowledge-documents/import` | 已登录 + 知识文档导入权限 + 依赖 AI service 配置 | 后台上传文档并触发 prepare/index 链路 |
| 知识文档后台管理 | `GET /api/v1/admin/knowledge-documents` | 已登录 + 知识文档列表权限 | 后台按知识库分页查询文档及处理状态 |
| 知识文档后台管理 | `DELETE /api/v1/admin/knowledge-documents/{documentId}` | 已登录 + 知识文档删除权限 | 后台物理删除文档及其下游 chunk |
| AI 问诊 | `POST /api/v1/ai/chat` | 已登录 + `PATIENT` 角色 + 依赖 AI service 配置 | 患者发起非流式问诊，返回 `answer + triageResult` |
| AI 会话列表 | `GET /api/v1/ai/sessions` | 已登录 + `PATIENT` 角色 + 仅患者本人 + 依赖 AI service 配置 | 返回当前患者的 AI 会话最小摘要列表 |
| AI 会话回看 | `GET /api/v1/ai/sessions/{sessionId}` | 已登录 + `PATIENT` 角色 + 仅患者本人 + 依赖 AI service 配置 | 返回指定会话的基础信息、轮次和消息内容 |
| AI 导诊结果 | `GET /api/v1/ai/sessions/{sessionId}/triage-result` | 已登录 + `PATIENT` 角色 + 仅患者本人 + 依赖 AI service 配置 | 返回指定会话最新成功问诊的结构化导诊结果 |
| AI 挂号承接 | `POST /api/v1/ai/sessions/{sessionId}/registration-handoff` | 已登录 + `PATIENT` 角色 + 仅患者本人 + 依赖 AI service 配置 | 返回指定会话的挂号承接参数或阻断原因 |
| 门诊挂号 | `GET /api/v1/clinic-sessions` | 已登录 | 查询当前可挂号的开放门诊场次 |
| 门诊挂号 | `POST /api/v1/registrations` | 已登录 + `PATIENT` 角色 | 当前患者创建挂号，同时预创建接诊记录 |
| 门诊挂号 | `GET /api/v1/registrations` | 已登录 + `PATIENT` 角色 | 查询当前患者自己的挂号列表 |
| 医生接诊 | `GET /api/v1/encounters` | 已登录 + 接诊列表权限 + `DOCTOR` 角色 | 查询当前医生自己的接诊列表 |
| 医生接诊 | `GET /api/v1/encounters/{encounterId}` | 已登录 + 接诊列表权限 + `DOCTOR` 角色 | 查询当前医生自己的单个接诊详情 |
| 医生接诊 | `GET /api/v1/encounters/{encounterId}/ai-summary` | 已登录 + 接诊列表权限 + `DOCTOR` 角色 | 查询当前医生可查看的接诊 AI 预问诊摘要 |

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
| 请求体 | `username`、`password` |
| `username` 要求 | 非空；会去掉首尾空格 |
| `password` 要求 | 非空；保留首尾空格，不做 trim |
| 响应字段 | `accessToken`、`accessTokenExpiresAt`、`refreshToken`、`refreshTokenExpiresAt`、`userContext` |
| 真实语义 | 校验用户名密码；账号若被禁用或锁定会失败；用户必须至少有一个角色；成功后更新最后登录时间并签发一组新的 access/refresh token |

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

### 7.2 `POST /api/v1/registrations`

| 项目 | 当前代码口径 |
|------|--------------|
| 认证 | 需要登录态和 `PATIENT` 角色 |
| 请求体 | `clinicSessionId`、`clinicSlotId`、`sourceAiSessionId?` |
| `sourceAiSessionId` | 可空，用于挂号与 AI 会话关联 |
| 响应字段 | `registrationId`、`orderNo`、`status` |
| 真实语义 | 当前患者发起挂号；后端使用当前登录用户的 `userId` 作为患者主体，不允许前端自行传 `patientUserId`；创建挂号成功后会立即预创建一条 `visit_encounter`，初始状态固定为 `SCHEDULED` |

补充说明：

- `clinicSessionId`、`clinicSlotId` 在当前 DTO 层没有显式 Bean Validation，但业务上都被当作必需 ID 使用。
- 当前实现会先校验场次是否存在且处于开放状态；不存在时返回 `404 + 3004`。
- 如果号源已满或无法预占，会返回 `409 + 3005`。
- 已登录但不是患者角色时，返回 `403 + 2008`。

### 7.3 `GET /api/v1/registrations`

| 项目 | 当前代码口径 |
|------|--------------|
| 认证 | 需要登录态和 `PATIENT` 角色 |
| 查询参数 | `status?` |
| `status` 可选值 | `PENDING_PAYMENT`、`CONFIRMED`、`CANCELLED`、`COMPLETED` |
| 非法 `status` | 返回 `400 + 1002` |
| 响应字段 | `items[].registrationId`、`orderNo`、`status`、`createdAt`、`sourceAiSessionId` |
| 真实语义 | 永远只查当前登录患者自己的挂号列表，不支持按任意患者 ID 查询 |

补充说明：

- 这里的患者主体使用的是当前登录用户的 `userId`。
- `CurrentUserResponse.patientId` 是 `patient_profile.id`，不要和挂号业务里的患者用户 ID 混用。

## 8. 知识库与知识文档后台管理

### 8.1 `GET /api/v1/admin/knowledge-bases`

| 项目 | 当前代码口径 |
|------|--------------|
| 认证 | 需要登录态和知识库列表权限 |
| 查询参数 | `keyword?`、`pageNum?`、`pageSize?` |
| `keyword` 规则 | 透传到仓储层，按 `name` 或 `kbCode` 模糊搜索 |
| `pageNum` 规则 | 默认 `1`；必须大于 `0`；最大 `10000` |
| `pageSize` 规则 | 默认 `20`；必须大于 `0`；最大 `100` |
| 响应结构 | `PageData`，包含 `items`、`pageNum`、`pageSize`、`total`、`totalPages`、`hasNext` |
| 列表项字段 | `id`、`kbCode`、`name`、`ownerType`、`ownerDeptId`、`visibility`、`status`、`docCount` |
| 真实语义 | 面向后台治理使用；`docCount` 为该知识库下文档总数 |

### 8.2 `POST /api/v1/admin/knowledge-bases`

| 字段 | 要求 |
|------|------|
| `name` | 必填；非空 |
| `kbCode` | 必填；非空；创建后作为稳定编码，不支持后续修改 |
| `ownerType` | 必填；当前按枚举名解析 |
| `ownerDeptId` | 可空；当 `ownerType=DEPARTMENT` 时必填 |
| `visibility` | 必填；当前按枚举名解析 |

业务语义：

- 创建成功后状态固定为 `ENABLED`。
- `ownerType`、`visibility` 在当前实现里使用 `Enum.valueOf(...)` 解析，非法值返回 `400 + 1002`。
- `kbCode` 唯一冲突时返回业务异常。

### 8.3 `PATCH /api/v1/admin/knowledge-bases/{knowledgeBaseId}`

| 字段 | 要求 |
|------|------|
| Path `knowledgeBaseId` | 必填；必须大于 `0` |
| `name` | 可空；非空时按新名称更新 |
| `ownerType` | 可空；非空时按枚举名解析 |
| `ownerDeptId` | 可空；仅在请求里传 `ownerType=DEPARTMENT` 时必填 |
| `visibility` | 可空；非空时按枚举名解析 |
| `status` | 可空；非空时按枚举名解析 |

业务语义：

- 当前实现为真正的部分更新；请求体里未传的字段保持原值。
- `kbCode` 不在更新 DTO 中，因此当前接口不支持改编码。
- 不存在的知识库返回 `404 + 6005`。

### 8.4 `DELETE /api/v1/admin/knowledge-bases/{knowledgeBaseId}`

| 项目 | 当前代码口径 |
|------|--------------|
| 认证 | 需要登录态和知识库删除权限 |
| 路径参数 | `knowledgeBaseId`，必须大于 `0` |
| 成功响应 | `Result<Void>` |
| 真实语义 | 后台软删除知识库；当前实现会级联软删除下游 `knowledge_document` 与 `knowledge_chunk` |

### 8.5 `POST /api/v1/admin/knowledge-documents/import`

| 项目 | 当前代码口径 |
|------|--------------|
| 认证 | 需要登录态和知识文档导入权限 |
| 请求格式 | `multipart/form-data` |
| 表单字段 | `knowledgeBaseId`、`file` |
| 响应字段 | `documentId`、`documentUuid`、`chunkCount`、`documentStatus` |
| 真实语义 | Java 接收上传文件，先创建 `knowledge_document` 并落存储，再调用 Python prepare/index，最后返回当前导入结果 |

补充说明：

- 该 controller 本身带 `mediask.ai.service.base-url` 和 `mediask.ai.service.api-key` 条件开关；未配置时，该接口不会暴露。
- 当前支持的 `sourceType` 由 Java 根据文件名推断。

### 8.6 `GET /api/v1/admin/knowledge-documents`

| 项目 | 当前代码口径 |
|------|--------------|
| 认证 | 需要登录态和知识文档列表权限 |
| 查询参数 | `knowledgeBaseId`、`pageNum?`、`pageSize?` |
| `knowledgeBaseId` 规则 | 必填；作为知识库过滤条件 |
| `pageNum` 规则 | 默认 `1`；必须大于 `0`；最大 `10000` |
| `pageSize` 规则 | 默认 `20`；必须大于 `0`；最大 `100` |
| 响应结构 | `PageData`，包含 `items`、`pageNum`、`pageSize`、`total`、`totalPages`、`hasNext` |
| 列表项字段 | `id`、`documentUuid`、`title`、`sourceType`、`documentStatus`、`chunkCount` |
| 真实语义 | 只按知识库分页查文档；`chunkCount` 为该文档下 chunk 总数 |

补充说明：

- 当前接口不返回失败原因文本；真实表结构里没有 `last_error_message` 字段。

### 8.7 `DELETE /api/v1/admin/knowledge-documents/{documentId}`

| 项目 | 当前代码口径 |
|------|--------------|
| 认证 | 需要登录态和知识文档删除权限 |
| 路径参数 | `documentId`，必须大于 `0` |
| 成功响应 | `Result<Void>` |
| 真实语义 | 后台软删除文档；当前实现会级联软删除下游 `knowledge_chunk` |

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
- 当前实现只做接诊列表，不包含接诊详情、AI 摘要、病历、处方。
- 没有接诊权限的医生会先在场景鉴权阶段收到 `403 + 1003`。

## 10. 当前已实现 AI 接口补充

### 10.1 `POST /api/v1/ai/chat`

| 项目 | 当前代码口径 |
|------|--------------|
| 认证/身份 | 已登录 + `PATIENT` 角色 |
| 请求体 | `sessionId?`、`message`、`departmentId?`、`sceneType`、`useStream` |
| 额外约束 | `useStream` 必须是 `false`；否则返回 `400 + 1002` |
| 响应字段 | `sessionId`、`turnId`、`answer`、`triageResult` |
| `triageResult` | `triageStage`、`riskLevel`、`guardrailAction`、`nextAction`、`followUpQuestions[]`、`chiefComplaintSummary?`、`recommendedDepartments[]`、`careAdvice?`、`citations[]` |

补充说明：

- 当前实现已经收口到 `triageStage = COLLECTING / READY / BLOCKED`
- `COLLECTING` 时返回 `followUpQuestions`，`nextAction = CONTINUE_TRIAGE`
- 聊天态已移除 `GO_REGISTRATION`；`READY` 统一先进入结果页，`nextAction = VIEW_TRIAGE_RESULT`

### 10.2 伪流式展示口径

| 项目 | 当前代码口径 |
|------|--------------|
| Python 能力 | 仅提供同步 `/api/v1/chat` |
| 上层表现 | Java 或前端可基于完整 `answer` 做伪流式展示 |
| 结构化真相 | 只消费完整 `triageResult`，不从展示文本反解析 |

### 10.3 `GET /api/v1/ai/sessions`

| 项目 | 当前代码口径 |
|------|--------------|
| 认证/身份 | 已登录 + `PATIENT` 角色 |
| 访问范围 | 当前仅患者本人可查看自己的 AI 会话列表 |
| 查询参数 | 当前无 |
| 排序 | `startedAt DESC`，同一时间按 `sessionId DESC` |
| 响应字段 | `items[].sessionId`、`sceneType`、`status`、`departmentId?`、`chiefComplaintSummary?`、`summary?`、`startedAt`、`endedAt?` |
| 返回范围 | 仅最小摘要，不返回 `turns[]`、消息原文或导诊结构化结果 |

### 10.4 `GET /api/v1/ai/sessions/{sessionId}`

| 项目 | 当前代码口径 |
|------|--------------|
| 认证/身份 | 已登录 + `PATIENT` 角色 |
| 访问范围 | 当前仅患者本人可查看自己的 AI 会话 |
| 响应字段 | `sessionId`、`sceneType`、`status`、`departmentId?`、`chiefComplaintSummary?`、`summary?`、`startedAt`、`endedAt?`、`turns[]` |
| `turns[]` | `turnId`、`turnNo`、`turnStatus`、`startedAt`、`completedAt?`、`errorCode?`、`errorMessage?`、`messages[]` |
| `messages[]` | `role`、`content`、`createdAt` |

### 10.5 `GET /api/v1/ai/sessions/{sessionId}/triage-result`

| 项目 | 当前代码口径 |
|------|--------------|
| 认证/身份 | 已登录 + `PATIENT` 角色 |
| 访问范围 | 当前仅患者本人可查看自己的导诊结果 |
| 响应字段 | `sessionId`、`resultStatus`、`triageStage`、`riskLevel`、`guardrailAction`、`nextAction`、`finalizedTurnId`、`finalizedAt`、`hasActiveCycle`、`activeCycleTurnNo`、`chiefComplaintSummary?`、`recommendedDepartments[]`、`careAdvice?`、`citations[]` |
| 数据来源 | 当前读取最近一次 finalized `ai_model_run.triage_snapshot_json`，并结合 guardrail 与 citations 组装 |

补充说明：

- 如果历史上已有 finalized 结果，而当前新一轮仍在 `COLLECTING`，接口返回旧结果并标记 `resultStatus = UPDATING`
- 如果从未产出过 finalized snapshot 且当前仍 `COLLECTING`，接口返回 `409 + 6021`
- 成功返回时 `triageStage` 只允许 `READY` 或 `BLOCKED`

### 10.6 `POST /api/v1/ai/sessions/{sessionId}/registration-handoff`

| 项目 | 当前代码口径 |
|------|--------------|
| 认证/身份 | 已登录 + `PATIENT` 角色 |
| 访问范围 | 当前仅患者本人可查看自己的挂号承接结果 |
| 请求体 | 无 |
| 响应字段 | `sessionId`、`recommendedDepartmentId?`、`recommendedDepartmentName?`、`chiefComplaintSummary?`、`suggestedVisitType?`、`blockedReason?`、`registrationQuery?` |
| `registrationQuery` | `departmentId`、`dateFrom`、`dateTo` |
| 普通分支 | 当前固定返回 `suggestedVisitType=OUTPATIENT`，并生成“今天起未来 7 天”的挂号查询窗口 |
| 高风险分支 | `blockedReason=EMERGENCY_OFFLINE`，不返回普通挂号查询参数 |
| 缺少推荐科室 | 非高风险但没有推荐科室时，返回 `409 + 6020` |

补充说明：

- 当前只消费最近一次 finalized snapshot，不再从聊天文本或收集中轮次临时反组装

### 10.7 `GET /api/v1/internal/triage-department-catalogs/{hospitalScope}`

| 项目 | 当前代码口径 |
|------|--------------|
| 认证 | 需要 `X-API-Key`，仅供 Python 内部调用 |
| 路径参数 | `hospitalScope` |
| 响应结构 | 直接返回原始 JSON；不包 `Result<T>` |
| 响应字段 | `hospital_scope`、`department_catalog_version`、`department_candidates[]` |
| `department_candidates[]` | `department_id`、`department_name`、`routing_hint`、`aliases[]`、`sort_order` |

补充说明：

- 当前目录语义是“可导诊目录”，不是 `departments` 全量透出
- 当前实现由 Java 基于活动中的临床科室做受控投影，不新增独立目录表

## 11. 容易被文档误导的未实现接口

下面这些接口在设计文档里已经出现，但当前代码里还没有对应 controller，不应当被当成当前可调用契约：

- `POST /api/v1/emr`
- `GET /api/v1/emr/{encounterId}`
- `POST /api/v1/prescriptions`
- `GET /api/v1/prescriptions/{encounterId}`
- `GET /api/v1/audit/events`
- `GET /api/v1/audit/data-access`

## 12. 一句话结论

如果目的是“按当前代码联调或写前后端接口文档”，应以本文档为准；如果目的是“看目标架构或后续计划”，再看 `01-OVERVIEW`、`10A`、`00E` 等设计/排期文档。
