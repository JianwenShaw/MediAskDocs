# 权限与审计设计：RBAC 与角色模型

## 1. RBAC 的定位

RBAC 解决“能不能做”（功能权限），不解决“能看哪些数据”（数据权限）。

本项目以权限码（authority）作为授权粒度，配合角色（role）进行授权管理。

## 2. 权限码命名规范

建议权限码统一为：

- 形式：`<domain>:<action>`
- 示例：`schedule:query`、`registration:create`、`registration:cancel`
- 约束：
  - `domain` 使用业务领域名或稳定资源名（`schedule`、`registration`、`emr`、`prescription`、`doctor`、`authz`、`ai` 等）
  - `action` 使用动词集合（`query/read/create/update/delete/approve/audit/auto` 等）

说明：当前代码/测试侧已存在的权限码（例如排班的 `schedule:query/create/update/delete/auto`）应作为现状基线，新增命名需在此基础上扩展，避免同一资源出现两套 action（如 `read` 与 `query` 并存）长期难以治理。

## 3. 权限树（菜单/按钮/API）

权限树的价值：

- 前端菜单可按权限动态渲染。
- 批量授权可按父节点聚合子权限。
- 展示时更易理解权限结构与边界。

权限节点建议包含属性：

- `code`：权限码（唯一）
- `type`：`MENU` / `BUTTON` / `API`
- `parentId`：父节点（用于树形关系）
- `path` + `method`：当权限用于 API 访问控制时可作为映射信息

权限树示例（示意，不代表最终字典）见：`MediAskDocs/docs/15-PERMISSIONS/appendix/A3-EXAMPLES.md`

## 4. 角色模型（继承/互斥/有效期）

### 4.1 角色继承

医疗系统存在天然角色层级，可用“继承”减少重复授权：

- 主治医师继承住院医/实习医基础权限
- 高密级数据访问权限仅授予更高等级角色

角色继承的工程实现示意放在：`MediAskDocs/docs/15-PERMISSIONS/appendix/A1-CODE_SNIPPETS.md`

### 4.2 角色互斥（职责分离）

互斥的典型目的：

- 审计与执行分离：审计员不应拥有系统管理员能力
- 开方与审核分离：医生与药房审核岗位互斥（视流程而定）
- 患者与医护身份互斥（若业务不允许同一账号兼任）

互斥规则的校验示意见：`MediAskDocs/docs/15-PERMISSIONS/appendix/A1-CODE_SNIPPETS.md`

### 4.3 用户角色有效期（临时授权）

临时授权场景：

- 进修医生、会诊专家
- 某患者的临时越权访问（有理由、有时效）

建议在用户-角色关联上增加：

- `valid_from` / `valid_until`
- `grant_reason` / `grantor_id`
- `is_emergency`（紧急授权标记）

表结构草案见：`MediAskDocs/docs/15-PERMISSIONS/appendix/A2-SCHEMA.sql`

## 5. 权限变更治理

权限变更属于敏感操作，建议最小要求：

- 变更行为必须审计（谁给谁授予/移除了什么）
- 高敏感角色/权限走审批流（见 `04-SENSITIVE_OPERATIONS.md`）
- 变更后需要权限缓存失效（若采用缓存）
