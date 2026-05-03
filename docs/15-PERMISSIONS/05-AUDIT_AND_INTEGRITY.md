# 权限与审计设计：审计追溯与防篡改

> 执行边界说明：`P0` 先做 `audit_event + data_access_log`；`audit_payload` 作为 `P1` 增强，链式哈希、WORM 等更重防篡改能力后置到 `P2/P3`。

## 1. 审计的定位

医疗系统的审计不是“可选日志”，而是合规刚需：

- 可追溯：发生了什么、谁做的、影响了谁/什么资源
- 可举证：关键操作链条完整、字段一致、可检索
- 可治理：权限滥用、越权访问、异常导出可被发现

`P0` 的目标不是先搭一个“大而全的审计平台”，而是先把真实医疗主链路中的责任闭环做实：

- 关键医疗动作能回答“谁在什么时候对谁做了什么，结果如何”
- 敏感数据访问能回答“谁看了什么、因为什么看、是否被允许”
- 同一次请求能通过 `request_id` 串起网关、Java、Python、审计记录

当前阶段默认采用两张权威表：

- `audit_event`：关键动作审计
- `data_access_log`：敏感访问监管

不把病历原文、AI 原文、身份证号、手机号等高敏内容直接塞进 `P0` 主表；`audit_payload` 作为 `P1` 再补。

## 2. 必审计事件（最小集合）

### 2.1 `audit_event`：关键动作审计

- 认证：登录成功、登录失败、登出
- 挂号：挂号创建、挂号取消
- 接诊：接诊开始、接诊状态变更
- 病历：病历创建、病历保存
- 诊断：诊断保存
- 处方：处方创建、处方保存
- 权限与账号：角色绑定、角色解绑、权限关系变更
- 审计自身：审计查询、审计导出
- 安全：对象级越权访问拒绝、高权限操作拒绝

### 2.2 `data_access_log`：敏感访问监管

`P0` 必须对以下敏感资源的查看类动作留痕：

- 病历正文
- 诊断详情
- 处方详情
- AI 原文 / 完整问诊明细
- 患者身份信息详情
- 审计明细本身

`P0` 必记的访问动作：

- `VIEW`
- `EXPORT`
- `DOWNLOAD`
- `PRINT`

当前若还没有导出、下载、打印接口，可以先不实现对应用例，但字段与动作码口径先定死。

### 2.3 角色视角

- 医生：重点审计病历、诊断、处方、AI 原文、患者身份信息访问
- 患者：重点审计本人病历、处方、AI 明细的查看与导出，便于发现账号盗用
- 管理员：重点审计权限变更、审计查询、审计导出、敏感档案查询
- 系统服务：如存在代执行、补偿或批处理任务，按 `actor_type = SYSTEM` 记录

## 3. 审计字段（建议口径）

### 3.1 `audit_event` 最小字段

- 主体：`actor_type`、`operator_user_id`、`operator_role_code`、`actor_department_id`
- 行为：`action_code`
- 客体：`resource_type`、`resource_id`
- 医疗关联：`patient_user_id`、`encounter_id`
- 上下文：`client_ip`、`user_agent`、`request_id`（P2 可选 `trace_id`）
- 结果：`success_flag`、`error_code`、`error_message`
- 附加：`reason_text`（导出、高权限变更、二次确认理由等）
- 时间：`occurred_at`、`created_at`

### 3.2 `data_access_log` 最小字段

- 主体：`actor_type`、`operator_user_id`、`operator_role_code`、`actor_department_id`
- 客体：`resource_type`、`resource_id`
- 医疗关联：`patient_user_id`、`encounter_id`
- 访问：`access_action`、`access_purpose_code`
- 结果：`access_result`、`deny_reason_code`
- 上下文：`client_ip`、`user_agent`、`request_id`（P2 可选 `trace_id`）
- 时间：`occurred_at`、`created_at`

### 3.3 动作码与最小化原则

- `action_code` 必须使用稳定的业务动作码，而不是只写 `CREATE`、`UPDATE` 这类粗粒度值
- 推荐示例：`AUTH_LOGIN_SUCCESS`、`REGISTRATION_CREATE`、`EMR_SAVE`、`PRESCRIPTION_SAVE`、`ROLE_ASSIGN`、`AUDIT_EXPORT`
- 审计日志默认不保存病历原文、AI 原文、PII 原文
- 若后续确需保留前后值、请求载荷或受控预览，统一进入 `audit_payload`

当前表结构以 `docs/07-DATABASE.md`、`docs/07D-AUDIT-TABLES-V3.md` 为准；`appendix/A2-SCHEMA.sql` 仅保留为早期草案存档。

## 4. 审计日志访问权限

建议分级治理：

- 登录日志：普通管理员可查
- 操作日志：部门管理员可查（限范围）
- 权限变更日志：审计员可查
- 敏感数据访问日志：审计员 + 安全员可查
- “查看审计日志”本身也要审计（防止审计滥用）

`P0` 当前若尚未拆出独立 `AUDITOR` 角色，可先由 `ADMIN` 持有最小审计查询能力，但必须保留后续拆角色的空间。

## 5. 脱敏策略

建议按 `action_code` / `resource_type` 维度配置脱敏规则：

- 姓名/电话/证件号/地址类字段脱敏
- 不在审计日志中保存大段原始病历文本（需要时存摘要）
- 查询条件、导出条数、目标角色等非高敏附加信息可进入轻量 `metadata_json`，但不应承载正文和 PII

示意见：`MediAskDocs/docs/15-PERMISSIONS/appendix/A1-CODE_SNIPPETS.md`

## 6. 防篡改与可信度

可选策略（按成本从低到高）：

1. 链式哈希（每条日志包含 `previous_hash`）
2. 异步完整性检查与告警（发现断链/篡改）
3. 写入不可变存储（WORM）或第三方审计存证系统（P3+）

`P0` 不把这些能力做成实现前置条件；当前优先级仍然是：

1. 对象级授权做准
2. `audit_event` / `data_access_log` 写实
3. 审计查询本身可追溯

示意见：`MediAskDocs/docs/15-PERMISSIONS/appendix/A1-CODE_SNIPPETS.md`
