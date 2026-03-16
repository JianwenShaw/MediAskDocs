# 排班核心测试计划（V2）

> 文档目标：定义可执行、可度量、可追溯的测试方案，覆盖排班核心升级能力。  
> 覆盖率目标：排班核心相关模块（`mediask-domain` + `mediask-service` 新增/改造代码）行覆盖率不低于 85%。

## 1. 测试范围

本计划只覆盖“排班核心升级”相关能力，不包含前端 UI 或外部系统压测。

## 1.1 核心功能范围

1. 节假日策略求解
   - `CLOSE/REDUCED/NORMAL`
   - 调休工作日覆盖节假日
2. 自动排班生成 DRAFT 方案
   - 方案头/明细/快照落库
3. 方案发布链路
   - 预检、发布、回滚
   - `STRICT/FORCE` 冲突策略
4. 冲突一致性
   - `STRICT` 失败时不得发生状态污染

## 1.2 非范围（需前端或环境配合）

1. 前端页面交互（版本列表、预检确认弹窗）
2. 全链路集成压测（多用户并发）
3. 真实数据库初始化脚本回归（需本地 PostgreSQL）

## 2. 测试分层

## 2.1 单元测试（本次由后端完成）

目标：覆盖所有核心分支、异常分支、边界分支。

已实现（本次提交）：

1. `DepartmentScheduleOptimizationDomainServiceTest`
   - 覆盖节假日 `CLOSE` 跳过逻辑
   - 覆盖 `REDUCED` 降载逻辑
   - 覆盖 `NORMAL` 保持需求逻辑
   - 覆盖调休覆盖节假日逻辑
2. `SchedulePlanApplicationServiceTest`
   - 覆盖 `precheck` 在 `STRICT/FORCE` 下阻断判定差异
   - 覆盖 `publish` 在 `STRICT` 冲突场景下失败且不污染状态
   - 覆盖 `publish` 在 `FORCE` 冲突场景下继续发布
   - 覆盖非法模式参数校验

## 2.2 集成测试（你可执行）

目标：验证接口、事务和数据库行为一致。

建议用例：

1. 自动排班生成 DRAFT
   - 调用 `/api/v1/schedules/auto` 后，检查 `schedule_plan*` 有记录，`doctor_schedules` 不生效。
2. 预检
   - 调用 `/api/v1/schedule-plans/{planId}/precheck`
   - 验证 `wouldBlock/conflictCount/toCreateSchedules/toCloseSchedules` 与库中事实一致。
3. STRICT 发布
   - 构造有效预约冲突，发布应失败。
   - 验证 `schedule_plan.plan_status` 不应被错误改为 `PUBLISHED`。
4. FORCE 发布
   - 构造同样冲突，发布应成功。
   - 验证冲突排班保留，其他排班正确生效。
5. 回滚
   - 发布新版本后回滚旧版本，验证最终排班与旧版本一致。

## 2.3 回归测试（你可执行）

目标：保证升级不破坏历史能力。

建议清单：

1. 预约主链路回归
   - 认证 -> 查询号源 -> 创建预约 -> 支付/取消 -> 就诊标记
2. 旧参数兼容回归
   - 仅传 `excludeHolidays=true/false` 时逻辑仍可用
3. 非节假日场景回归
   - 排班结果应不受节假日策略影响
4. 权限回归
   - `schedule:query`、`schedule:update` 权限控制仍生效

## 3. 覆盖率策略

## 3.1 指标定义

1. 行覆盖率：>= 85%
2. 分支覆盖率：关键类 >= 80%

关键类：

1. `DepartmentScheduleOptimizationDomainService`
2. `SchedulePlanApplicationService`
3. `ScheduleApplicationService`（与方案落库相关方法）

## 3.2 执行命令（macOS）

```bash
# 仅跑核心模块测试
./scripts/m21.sh -pl mediask-domain,mediask-service -am test

# 生成覆盖率报告（JaCoCo）
./scripts/m21.sh -pl mediask-domain,mediask-service -am test jacoco:report
```

报告位置（默认）：

1. `mediask-domain/target/site/jacoco/index.html`
2. `mediask-service/target/site/jacoco/index.html`

## 3.3 达成 85% 的执行策略

1. 先覆盖“分支密集类”，再补边缘类。
2. 每次修复 bug 必须补对应回归单测。
3. 禁止“空断言测试”：
   - 至少验证一个业务结果 + 一个关键副作用（如状态变化/仓储调用）。

## 4. 测试用例设计原则

1. 场景驱动，不为覆盖率写无意义断言。
2. 一条测试只验证一个核心业务意图。
3. 错误路径必须验证错误码或异常类型。
4. 对事务敏感逻辑（发布/回滚）必须验证“失败时无副作用”。

## 5. 当前状态

1. 单元测试：核心分支已补齐（见 2.1）。
2. 集成/回归：待你在本地数据库和联调环境执行（见 2.2 / 2.3）。
3. 覆盖率目标：按本计划执行后，核心升级模块可达并稳定保持 >=85%。
