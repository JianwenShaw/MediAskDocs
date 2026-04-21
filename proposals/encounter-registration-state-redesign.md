# 就诊-挂号状态机重构方案（P0 可落地版）

## Summary
- 目标：把 `registration_order` 与 `visit_encounter` 从“松耦合双状态”改为“统一迁移规则 + 强一致联动”，解决状态不清晰、约束不闭合、联动冲突难定位的问题。
- 方案边界：按你确认的方向执行  
`双聚合 + 统一门禁`、`去掉待支付`、`强一致失败回滚`、`允许破坏性调整`、`单表轻量状态流水`。
- 本次不做：支付系统、异步补偿、复杂审计平台、NO_SHOW 等扩展状态。

## Key Changes
- 状态模型收敛
  - `registration_order.order_status` 收敛为：`CONFIRMED | CANCELLED | COMPLETED`。
  - `visit_encounter.encounter_status` 保持：`SCHEDULED | IN_PROGRESS | CANCELLED | COMPLETED`。
  - `clinic_slot.slot_status` 收敛为：`AVAILABLE | BOOKED`（去掉 `LOCKED` 在当前主链路的使用）。
- 统一迁移矩阵（单一真相）
  - 注册创建：`registration: CONFIRMED` + `encounter: SCHEDULED` + `slot: BOOKED`（同事务）。
  - 取消挂号：仅允许 `registration=CONFIRMED` 且 `encounter=SCHEDULED` 且 `slot=BOOKED`，结果为  
`registration=CANCELLED`、`encounter=CANCELLED`、`slot=AVAILABLE`（同事务）。
  - 开始接诊：仅允许 `encounter: SCHEDULED -> IN_PROGRESS`（要求关联 `registration=CONFIRMED`）。
  - 完成接诊：仅允许 `encounter: IN_PROGRESS -> COMPLETED`，并同步 `registration: CONFIRMED -> COMPLETED`（同事务）。
- 代码结构落点
  - 在 application 层新增“统一状态迁移策略组件”（纯规则，不加过度抽象），所有挂号/接诊状态变更都必须经过该组件。
  - Repository 更新改为“带期望状态的条件更新”语义（避免先查后改造成规则分散），冲突统一返回现有业务冲突码。
- 数据库与迁移
  - 调整 `sql/04-appointment.sql` 的状态枚举约束：移除 `PENDING_PAYMENT`、`LOCKED`。
  - 增加 `status_transition_log` 单表，字段固定：  
`id, entity_type, entity_id, from_status, to_status, action, operator_user_id, request_id, occurred_at, created_at`。
  - 增加一次性数据迁移脚本：将历史 `PENDING_PAYMENT` 按业务规则迁移（默认迁到 `CONFIRMED`，若已取消/完成则按终态归并），并修正对应 slot 状态一致性。
- 文档同步
  - 更新 `docs/playbooks/00G-P0-CURRENT-API-CONTRACT.md` 的状态枚举、取消/完成联动语义。
  - 更新 `docs/docs/07-DATABASE.md` 的状态定义、约束与流水表说明。
  - 在 docs 中新增“状态迁移矩阵”专节（挂号/接诊/号源三者联动）。

## Public API / Interface / Type Changes
- API 契约变化
  - `POST /api/v1/registrations` 返回 `status` 固定为 `CONFIRMED`。
  - `GET /api/v1/registrations` 的 `status` 可选值变为：`CONFIRMED | CANCELLED | COMPLETED`。
  - `PATCH /api/v1/registrations/{id}/cancel` 仅处理 `CONFIRMED` 取消路径，不再区分 `PENDING_PAYMENT/CONFIRMED` 分支。
- 类型变化
  - `RegistrationStatus` 枚举删除 `PENDING_PAYMENT`。
  - 号源状态口径删除 `LOCKED` 依赖分支。
- 仓储接口变化
  - `RegistrationOrderRepository` 与 `VisitEncounterRepository` 增加/改造“按期望状态更新”的方法签名，保证迁移规则在接口层可表达且可测试。

## Test Plan
- 用例级测试
  - 创建挂号后，三实体状态一次性落在 `CONFIRMED/SCHEDULED/BOOKED`。
  - 合法取消成功联动三表；任一条件不满足返回冲突且事务回滚。
  - `START` 仅允许 `SCHEDULED`；`COMPLETE` 仅允许 `IN_PROGRESS` 且同步挂号完成。
  - 并发冲突下返回既有冲突码，不出现“单边成功”。
- 持久化测试
  - 条件更新必须校验期望状态，状态不匹配时 0 行更新。
  - 每次有效迁移都写入 `status_transition_log`，字段完整（尤其 `request_id`、`operator_user_id`）。
- 契约测试
  - 注册列表/详情不再出现 `PENDING_PAYMENT`。
  - 取消接口与接诊更新接口的错误码语义与文档一致。

## Assumptions
- 本次不引入支付确认接口，挂号创建即视为已确认。
- 允许一次性破坏性状态口径调整，不保留旧状态兼容映射。
- 先完成最小闭环；`NO_SHOW/EXPIRED/REFUNDED` 作为下一阶段扩展状态再引入。
