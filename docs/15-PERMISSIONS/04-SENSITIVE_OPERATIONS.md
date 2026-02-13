# 权限与审计设计：敏感操作保护

## 1. 敏感操作的定义

满足任意条件即可视为敏感操作：

- 影响患者权益或医疗安全（撤销处方、修改病历关键字段等）
- 涉及批量导出/批量查看隐私数据
- 权限/角色变更
- 越权访问的临时授权（break-glass）

## 2. 二次确认（Require Confirm）

建议二次确认具备以下能力：

- 类型：密码确认 / 验证码 / 填写理由 / 审批确认
- 有效期：确认在短时间窗口内有效（例如 5 分钟）
- 强制审计：二次确认通过与否都要留痕

伪代码示意见：`MediAskDocs/docs/15-PERMISSIONS/appendix/A1-CODE_SNIPPETS.md`

## 3. 权限变更审批流

高敏感角色/权限的授予建议走审批流。

```mermaid
flowchart TB
  Apply[提交申请] --> Dept[部门主管审批]
  Dept -->|驳回| Reject[驳回并通知申请人]
  Dept -->|通过| Leader[分管领导审批(可选)]
  Leader -->|驳回| Reject
  Leader -->|通过| Grant[执行授权]
  Grant --> Audit[写入审计日志]
```

审批单与表结构草案见：`MediAskDocs/docs/15-PERMISSIONS/appendix/A2-SCHEMA.sql`

## 4. 紧急授权（Break-glass）

急诊/抢救等场景允许“先授权、后审查”，但必须满足：

- 强制填写理由（不可空）
- 严格时效（例如小时级）
- 强制审计（写紧急标记）
- 事后复核与告警（到期提醒、复核未完成提醒）

示意见：`MediAskDocs/docs/15-PERMISSIONS/appendix/A1-CODE_SNIPPETS.md`

## 5. 黑白名单与频率限制

### 5.1 黑白名单

在 RBAC 之外提供临时性拦截/放行能力：

- 维度：`FUNCTION` / `API` / `IP` / `USER`
- 支持有效期与原因
- 变更必须审计

### 5.2 频率限制

目的：

- 防止高频调用造成安全与性能风险
- 对敏感操作设置额外阈值（例如“每天最多 10 次”）

示意见：`MediAskDocs/docs/15-PERMISSIONS/appendix/A1-CODE_SNIPPETS.md`

