# 权限与审计设计：审计追溯与防篡改

## 1. 审计的定位

医疗系统的审计不是“可选日志”，而是合规刚需：

- 可追溯：发生了什么、谁做的、影响了谁/什么资源
- 可举证：关键操作链条完整、字段一致、可检索
- 可治理：权限滥用、越权访问、异常导出可被发现

## 2. 必审计事件（最小集合）

- 登录/登出（含失败）
- 权限变更（角色绑定/解绑、权限字典变更）
- 敏感数据访问（病历/处方/AI 对话等，按实际启用）
- 关键业务操作（创建/修改/取消预约等）
- 数据导出
- 紧急授权与越权访问尝试

## 3. 审计字段（建议口径）

建议审计日志最少包含：

- 主体：`user_id`、`username`、`role`、`department`
- 行为：`action`、`action_name`
- 客体：`resource_type`、`resource_id`、`resource_name`（可选）
- 上下文：`client_ip`、`user_agent`、`trace_id`
- 结果：`success`、`fail_reason`
- 时间：`timestamp`、`created_at`

注意数据最小化原则：

- `request_params` / `old_value` / `new_value` 应脱敏后存储，必要时用摘要/哈希替代原文。

表结构草案见：`MediAskDocs/docs/15-PERMISSIONS/appendix/A2-SCHEMA.sql`

## 4. 审计日志访问权限

建议分级治理：

- 登录日志：普通管理员可查
- 操作日志：部门管理员可查（限范围）
- 权限变更日志：审计员可查
- 敏感数据访问日志：审计员 + 安全员可查
- “查看审计日志”本身也要审计（防止审计滥用）

## 5. 脱敏策略

建议按 `action` 维度配置脱敏规则：

- 姓名/电话/证件号/地址类字段脱敏
- 不在审计日志中保存大段原始病历文本（需要时存摘要）

示意见：`MediAskDocs/docs/15-PERMISSIONS/appendix/A1-CODE_SNIPPETS.md`

## 6. 防篡改与可信度

可选策略（按成本从低到高）：

1. 链式哈希（每条日志包含 `previous_hash`）
2. 异步完整性检查与告警（发现断链/篡改）
3. 写入不可变存储（WORM）或第三方审计存证系统（P3+）

示意见：`MediAskDocs/docs/15-PERMISSIONS/appendix/A1-CODE_SNIPPETS.md`

