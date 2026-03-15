# 权限与审计设计：RBAC 与角色模型

> 执行边界说明：`P0` 只固定最小角色模型和权限码规范；角色继承、角色互斥、临时授权有效期等生产级治理能力后置到 `P1/P2`。

## 1. RBAC 的定位

RBAC 只解决“能不能做”，不解决“能看哪些数据”。

当前项目中：

- RBAC 决定谁能访问接口、页面、操作按钮
- 数据范围规则决定谁能查看哪些病历、AI 会话、挂号与处方

## 2. `P0` 最小角色集

| 角色 | 当前职责 |
|------|----------|
| `PATIENT` | 发起 AI 问诊、查看自己的挂号/病历/处方 |
| `DOCTOR` | 查看自己职责范围内的挂号、接诊、病历、处方、AI 摘要 |
| `ADMIN` | 维护基础账号/角色/权限关系，查看最小审计结果 |

说明：

- 如需单独 `AUDITOR` 角色，可作为 `P1` 增强
- `P0` 不要求角色继承树、角色互斥规则引擎、复杂授权时效治理

## 3. 权限码命名规范

统一使用：`<domain>:<action>`

示例：

- `ai:chat`
- `registration:create`
- `encounter:query`
- `emr:update`
- `prescription:create`
- `audit:query`
- `authz:grant`

约束：

- 同一资源只保留一套 action 词汇，避免 `read/query` 长期并存
- 新增权限码要优先贴合当前主链路，而不是先铺完整后台树

## 4. `P0` 最小权限面

| 角色 | 典型权限 |
|------|----------|
| `PATIENT` | `ai:chat`、`registration:create`、`registration:query:self` |
| `DOCTOR` | `registration:query`、`encounter:query`、`emr:create`、`emr:update`、`prescription:create` |
| `ADMIN` | `user:query`、`authz:grant`、`audit:query` |

说明：

- `:self` 这类细粒度语义仍然需要数据范围规则配合，不能只靠 RBAC
- 医生是否能看具体某条病历，最终取决于对象级授权和 `data_scope_rules`

## 5. `P1/P2` 保留能力

以下能力设计可以保留，但不作为 `P0` 前置：

- `P1`：权限树、独立审计员角色、权限配置页完善
- `P2`：角色继承、角色互斥、临时授权有效期、审批流联动

## 6. 权限变更治理

当前最小要求：

- 角色绑定/解绑必须写 `audit_event`
- 高敏数据访问必须落 `data_access_log`
- 权限变更后如使用缓存，需要失效对应缓存

审批流不是 `P0` 前置条件；当前阶段只要保证权限变更可追溯即可。

## 7. 一句话结论

`P0` 的 RBAC 不追求“角色体系多精细”，而是先把患者、医生、管理员三类主体的最小权限边界定死，再用数据范围规则补足医疗场景约束。
