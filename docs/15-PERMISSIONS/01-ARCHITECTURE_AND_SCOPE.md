# 权限与审计设计：架构与范围

## 1. 目标

医疗系统的权限与合规模块目标是：

- 功能权限：谁能做什么（RBAC/权限码）。
- 数据权限：谁能看哪些数据（科室/归属/自有/团队/临时授权）。
- 敏感操作保护：二次确认、审批流、紧急授权（break-glass）。
- 审计追溯：关键行为可回放、可举证、可检索。
- 最小化合规：隐私数据最小记录、可控留存、可控访问。

## 2. 系统上下文（以当前项目为准）

本项目是一个医疗场景的后端系统，核心业务包括排班、预约挂号、医生管理，并包含 AI 相关数据域与指标能力（如 AI 复核提交与统计）。更完整的“当前已落地能力”请以 `MediAskDocs/docs/01-OVERVIEW.md` 为准。

## 3. 范围与非目标

### 3.1 本目录讨论的范围

- API 请求进入后的授权链路（AuthN/AuthZ/DataScope/Audit）。
- 管理端权限管理（角色/权限/用户角色）。
- 医生/患者侧对业务数据的访问控制与审计。
- AI 指标/对话数据（如存在）的访问控制与审计口径。

### 3.2 非目标（本期不展开实现细节）

- 具体 Spring Security / MyBatis-Plus 的代码实现细节。
- 电子签名、CA、时间戳、区块链存证等 P3+ 能力的工程落地细节。
- 具体 UI 菜单渲染与前端交互实现。

## 4. 设计原则

- 最小权限：默认拒绝、按需授予。
- 职责分离：审计员/安全员与系统管理员角色互斥，避免既当裁判又当运动员。
- 纵深防御：功能权限 + 数据权限 + 对象级授权 + 频率限制 + 黑白名单 + 审计。
- 数据最小化：审计日志不保存不必要的敏感原文；需要时以摘要/哈希替代。

## 5. 端到端授权链路（抽象）

```mermaid
flowchart TB
  Client[Client] --> Gateway[Gateway/Ingress]
  Gateway --> AuthN[AuthN: Token/JWT]
  AuthN --> Blacklist[Blacklist/Allowlist]
  Blacklist --> RateLimit[Rate limiting]
  RateLimit --> FuncAuthZ[Func AuthZ: RBAC/Authorities]
  FuncAuthZ --> Confirm[Sensitive confirm / Approval]
  Confirm --> DataScope[Data scope filter]
  DataScope --> Confidentiality[Confidentiality level check]
  Confidentiality --> ABAC[ABAC (optional)]
  ABAC --> Handler[Business handler]
  Handler --> Audit[Audit log write]
  Audit --> Integrity[Integrity check (async)]
  Handler --> Resp[Response]
```

## 6. 文档导航

- 功能权限与角色模型：`MediAskDocs/docs/15-PERMISSIONS/02-RBAC_AND_ROLE_MODEL.md`
- 数据权限、密级与对象级授权：`MediAskDocs/docs/15-PERMISSIONS/03-DATA_SCOPE_AND_CONFIDENTIALITY.md`
- 敏感操作保护与风控：`MediAskDocs/docs/15-PERMISSIONS/04-SENSITIVE_OPERATIONS.md`
- 审计、脱敏与防篡改：`MediAskDocs/docs/15-PERMISSIONS/05-AUDIT_AND_INTEGRITY.md`
- 演进路线：`MediAskDocs/docs/15-PERMISSIONS/06-ROADMAP.md`
- 参考实现与样例：`MediAskDocs/docs/15-PERMISSIONS/appendix/00-INDEX.md`

