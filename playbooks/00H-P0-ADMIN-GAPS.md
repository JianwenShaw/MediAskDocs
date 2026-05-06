# P0 管理端功能缺口清单

> 对照 `docs/` 设计文档与代码现状，列出管理端缺失的功能。
> 每项任务独立可执行，按优先级排列。

## 当前状态

管理端现有 5 个 Controller、24 个端点：

- `AdminPatientController` — 患者 CRUD（5 个端点）
- `AdminDoctorController` — 医生 CRUD（5 个端点）✅
- `KnowledgeAdminController` — 知识库网关（11 个端点）
- `TriageCatalogController` — 分诊目录发布（1 个端点）
- `AuditController` — 审计查询（2 个端点）

---

## 阻塞级：没有这些系统无法正常运转

### 1. 科室管理 `AdminDepartmentController`

**依据**：`departments` 是 P0 表（07E-DATABASE-PRIORITY.md），分诊目录、挂号、AI 导诊都依赖科室数据。

**现状**：只能在 SQL 种子脚本里手动插入科室。

**接口**：
- `GET    /api/v1/admin/departments` — 列表（关键词搜索）
- `POST   /api/v1/admin/departments` — 创建
- `PUT    /api/v1/admin/departments/{id}` — 更新
- `DELETE /api/v1/admin/departments/{id}` — 删除

**涉及模块**：api → application → domain → infra（全链路）

---

### 2. 医生管理 `AdminDoctorController` ✅ 已完成

**依据**：`doctors`、`doctor_department_rel` 是 P0 表。接诊流程依赖医生数据。

**接口**：
- `GET    /api/v1/admin/doctors` — 列表（分页 + 关键词搜索）
- `GET    /api/v1/admin/doctors/{doctorId}` — 详情
- `POST   /api/v1/admin/doctors` — 创建（含用户账号 + 医生档案 + 科室分配）
- `PUT    /api/v1/admin/doctors/{doctorId}` — 更新
- `DELETE /api/v1/admin/doctors/{doctorId}` — 删除/停用

---

### 3. 门诊场次与号源管理 `AdminClinicSessionController`

**依据**：`clinic_session`、`clinic_slot` 是 P0 表。挂号流程依赖场次和号源。

**现状**：患者端只能查询场次和号源，无法创建。

**接口**：
- `GET    /api/v1/admin/clinic-sessions` — 场次列表（分页 + 日期/科室/医生筛选）
- `POST   /api/v1/admin/clinic-sessions` — 创建场次
- `PUT    /api/v1/admin/clinic-sessions/{id}` — 更新场次
- `DELETE /api/v1/admin/clinic-sessions/{id}` — 取消场次
- `GET    /api/v1/admin/clinic-sessions/{id}/slots` — 查看号源
- `POST   /api/v1/admin/clinic-sessions/{id}/slots/generate` — 生成号源
- `PUT    /api/v1/admin/clinic-slots/{id}` — 调整单个号源

**涉及模块**：api → application → domain → infra（全链路）

---

## 重要级：P0 管理运营必需

### 4. 挂号全局视图 `AdminRegistrationController`

**依据**：管理员需要了解全系统挂号情况。

**现状**：患者只能看自己的挂号。

**接口**：
- `GET /api/v1/admin/registrations` — 列表（分页 + 状态/科室/日期/患者筛选）
- `GET /api/v1/admin/registrations/{id}` — 详情

**涉及模块**：api → application → infra（复用现有 outpatient 查询能力）

---

### 5. 就诊全局视图 `AdminEncounterController`

**依据**：管理员需要跨医生查看就诊情况。

**现状**：医生只能看自己的接诊列表。

**接口**：
- `GET /api/v1/admin/encounters` — 列表（分页 + 状态/医生/科室/日期筛选）
- `GET /api/v1/admin/encounters/{id}` — 详情

**涉及模块**：api → application → infra（复用现有 clinical 查询能力）

---

### 6. 用户与角色管理 `AdminUserController`

**依据**：`users`、`user_roles`、`role_permissions` 是 P0 表。权限体系运营必需。

**现状**：管理员只能通过患者管理间接操作部分用户。

**接口**：
- `GET    /api/v1/admin/users` — 用户列表（分页 + 角色/状态筛选）
- `GET    /api/v1/admin/users/{userId}` — 用户详情（含角色列表）
- `PUT    /api/v1/admin/users/{userId}/status` — 启用/禁用
- `PUT    /api/v1/admin/users/{userId}/roles` — 分配角色
- `POST   /api/v1/admin/users/{userId}/reset-password` — 重置密码

**涉及模块**：api → application → domain → infra

---

### 7. AI 护栏事件查询 `AdminGuardrailController`

**依据**：`ai_guardrail_event` 是 P0 表，文档强调护栏留痕是 AI 安全边界。

**现状**：审计查了 event + access_log，但查不了护栏事件。

**接口**：
- `GET /api/v1/admin/guardrail-events` — 列表（分页 + 时间范围/风险等级/会话筛选）

**涉及模块**：api → application → infra（复用现有 audit 查询模式）

---

### 8. AI 会话管理视图

**依据**：管理员需要排查 AI 问答质量、统计使用情况。

**现状**：患者只能看自己的会话。

**接口**：
- `GET /api/v1/admin/ai-sessions` — 列表（分页 + 时间/患者/状态筛选）
- `GET /api/v1/admin/ai-sessions/{sessionId}` — 详情

**涉及模块**：api → application → infra

---

### 9. 病历与处方全局视图

**依据**：管理员需要审计医疗内容质量。

**现状**：EMR/处方只对医生/患者本人开放。

**接口**：
- `GET /api/v1/admin/emrs` — 病历列表（分页 + 时间/科室/医生筛选）
- `GET /api/v1/admin/emrs/{encounterId}` — 病历详情
- `GET /api/v1/admin/prescriptions` — 处方列表（分页 + 时间/科室/医生/状态筛选）
- `GET /api/v1/admin/prescriptions/{encounterId}` — 处方详情

**注意**：这些是敏感只读视图，访问需写入 `data_access_log`。

**涉及模块**：api → application → infra

---

### 10. 管理端统计面板 `AdminDashboardController`

**依据**：运营概览基本需求。

**接口**：
- `GET /api/v1/admin/dashboard/overview` — 患者数、医生数、今日挂号量、今日就诊量、AI 会话量

**涉及模块**：api → application → infra（聚合查询）

---

## 增强级：P1 亮点功能

### 11. 系统字典管理

`sys_dict_type` + `sys_dict_item` 表。前后端枚举统一维护基础设施。

### 12. 药品字典

`drug_catalog` 表。让处方从自由文本升级为主数据驱动。

### 13. AI 复核工作流

`ai_feedback_task` + `ai_feedback_review` 表。AI 结果进入医生复核，"AI 辅助而非替代"闭环。

### 14. 通知系统

`notification` 表。挂号提醒、复核任务通知。

### 15. 轻量排班生成

`doctor_availability_rule`、`schedule_demand_template` 等表。自动生成门诊场次。

---

## 文档待更新

`docs/playbooks/00C-P0-BACKEND-TASKS.md` 标记 Task G（审计）为"未完成"，实际已实现。
