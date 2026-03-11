# 架构评审与优化建议

> 本文档对当前项目 DDD 实现进行诚实评估，分析模块划分合理性，并给出优化建议。

---

## 1. 当前架构概览

### 1.1 模块结构

```
mediask-be/
├── mediask-api        # API 接入层 - REST 控制器、Security、Request/Response
├── mediask-service    # 应用服务层 - 用例编排、Command 处理、DTO 转换
├── mediask-domain    # 领域层 - 聚合根、值对象、领域服务、仓储接口
├── mediask-infra     # 基础设施层 - 仓储实现、Redis、事件发布器、外部服务
├── mediask-dal      # 数据访问层 - DO、Mapper
├── mediask-common    # 通用层 - 工具、异常、常量
└── mediask-worker   # 异步任务 - 定时任务
```

### 1.2 依赖关系

```
API → Service → Domain
           ↓
        Infra → DAL
```

| 模块 | 依赖 | 职责 |
|------|------|------|
| mediask-api | Service, Common | HTTP 入口、认证授权、API 文档 |
| mediask-service | Domain, Infra, Common | 用例编排、事务管理 |
| mediask-domain | Common | 核心业务（纯 POJO，无 Spring 依赖） |
| mediask-infra | Domain, DAL, Common | 技术实现：Redis、事件发布器、外部服务 |
| mediask-dal | Common | 数据对象、Mapper |

---

## 2. DDD 实现评估

### 2.1 做得好的部分

| DDD 模式 | 实现情况 | 示例代码 |
|----------|----------|----------|
| **聚合根** | ✅ 清晰 | `Appointment`、`DoctorSchedule` |
| **工厂方法** | ✅ 规范 | `Appointment.create()`、`DoctorSchedule.create()` |
| **领域事件** | ✅ 完善 | `AppointmentCreatedEvent`、`ScheduleStatusChangedEvent` |
| **值对象** | ✅ 合理 | `AppointmentId`、`TimePeriod`、`SlotCapacity` |
| **充血模型** | ✅ 核心实体 | `markAsPaid()`、`decreaseSlot()` 等业务行为 |

**代码示例 - 聚合根设计**：

```java
// DoctorSchedule.java - 体现了聚合根的核心职责
public class DoctorSchedule {
    private ScheduleId id;
    private DoctorId doctorId;
    private SlotCapacity capacity;
    private ScheduleStatus status;

    // 业务规则内聚在聚合根内
    public void decreaseSlot() {
        if (!status.canAppointment()) {
            throw new IllegalStateException("排班状态不允许预约");
        }
        if (!capacity.hasAvailable()) {
            throw new IllegalStateException("号源已满");
        }
        this.capacity = capacity.decrease();
        // 状态自动变更
        if (capacity.isFull()) {
            this.status = ScheduleStatus.FULL;
        }
        // 发布领域事件
        addDomainEvent(new ScheduleSlotDecreasedEvent(...));
    }
}
```

### 2.2 需要改进的部分

| 问题 | 描述 | 建议 |
|------|------|------|
| **User 贫血模型** | 只有数据字段，业务逻辑在 Service | 简单实体可保持现状，复杂实体需改造 |
| **排班算法位置** | 遗传算法、约束引擎在 Domain 层 | 建议迁移至 Infra 层（技术能力） |
| **Service 层较重** | 部分业务逻辑仍在 ApplicationService | 下沉到 Domain 层 |

### 2.3 诚实评估

**是否真正实现了 DDD？**

- **核心业务**：✅ 是（预约、排班、号源管理）
  - 聚合根设计规范
  - 状态机完整
  - 领域事件解耦

- **技术实现**：⚠️ 需商榷
  - 排班调度算法更像"技术能力"而非"业务逻辑"
  - 放在 Domain 层可能造成关注点混合

**排班算法位置建议**：

```
当前：Domain 层（algorithm/constraint/、algorithm/solver/）
建议：Infra 层（与 pgvector 客户端、AI 服务同级）
```

理由：
- 算法是"如何做"，DDD 关注"做什么"
- 算法可能依赖 OptaPlanner 等专业库，不应污染 Domain
- 便于后续技术替换（如换用不同的求解器）

---

## 3. 模块划分分析

### 3.1 当前设计的优劣

**优势**：
- 分层清晰，职责明确
- API 不直接依赖 Domain/Infra，符合依赖倒置
- Service 层作为 Application Layer 定位明确

**痛点**：
- Service 层同时承担"用例编排"和"对外接口适配"？
- 如果要支持多种接入方式（REST、gRPC、Admin API），业务逻辑如何复用？

### 3.2 是否需要引入 App 模块？

**问题**：是否需要在 API 和 Service 之间增加 `mediask-app` 模块？

```
方案 A：当前结构（推荐）
API → Service → Domain

方案 B：引入 App 模块
API → App → Domain
    ↓
  Infra
```

**结论**：**当前结构已足够**

理由：
1. Service 层定位清晰（Application Layer）
2. API 层仅做 HTTP 适配和参数转换
3. 未出现"业务逻辑分散"的问题
4. 增加模块会提升复杂度

---

## 4. DDD 必要性评估

### 4.1 DDD 带来的价值

| 业务特点 | DDD 优势 |
|----------|----------|
| 排班调度复杂 | 约束规则内聚在聚合根 |
| 预约状态机完整 | 状态流转由实体保证 |
| 医疗业务严谨 | 统一语言、边界清晰 |
| 长期演进 | 核心业务与基础设施分离 |

### 4.2 DDD 带来的成本

| 成本 | 说明 |
|------|------|
| 学习成本 | 团队需要理解聚合、值对象、领域事件 |
| 代码量 | 值对象、事件增加代码行数 |
| 过度设计风险 | 简单 CRUD 场景不必强行 DDD |

### 4.3 务实建议

**保留 DDD 的部分**：
- 预约系统（`Appointment`、`DoctorSchedule`）
- 号源管理（`SlotCapacity`、`AppointmentSlot`）
- 状态机逻辑

**可简化的地方**：
- 用户管理（`User` 保持贫血模型即可）
- 权限系统（简单实体无需复杂设计）
- 日志、统计等辅助功能

**迁移到 Infra**：
- 排班调度算法
- 外部 AI 服务调用
- 文件存储

---

## 5. 优化建议

### 5.1 短期（影响小）

| 任务 | 说明 |
|------|------|
| 明确 Service 层为 Application Layer | 在文档和代码注释中强调 |
| 补充 User 实体的业务行为 | 如 `User.canLogin()`、`User.changePassword()` |

### 5.2 中期（需规划）

| 任务 | 说明 |
|------|------|
| 迁移排班算法到 Infra | 创建 `SchedulingService` 实现排班求解 |
| 抽取 Bounded Context | 预约上下文、排班上下文独立演进 |
| 完善领域事件机制 | 引入事件总线，统一事件处理 |

### 5.3 长期（可选）

| 任务 | 说明 |
|------|------|
| 引入 CQRS | 读查询与写命令分离 |
| 事件溯源 | 完整追溯业务状态变化 |
| 战术设计细化 | 规范 Factory、Repository 使用 |

---

## 6. 总结

### 当前架构评价

| 维度 | 评分 | 说明 |
|------|------|------|
| 分层清晰度 | ⭐⭐⭐⭐⭐ | API/Service/Domain/Infra 边界明确 |
| DDD 实践度 | ⭐⭐⭐⭐ | 核心业务符合 DDD，简单实体可简化 |
| 可维护性 | ⭐⭐⭐⭐ | 代码组织清晰，命名规范 |
| 过度设计 | ⭐⭐⭐ | 整体适中，算法层可优化 |

### 核心结论

1. **当前 DDD 实现是合格的** - 核心业务实体设计规范
2. **模块划分基本合理** - 无需引入额外 App 模块
3. **排班算法建议下沉** - 从 Domain 迁移至 Infra
4. **保持务实** - 简单场景不必强行 DDD，复杂场景深耕领域模型

### 行动清单

- [ ] 评估排班算法迁移工作量
- [ ] 明确 Service 层 Application Layer 定位
- [ ] 考虑 User 实体的业务行为补充
- [ ] 定期回顾架构与技术债

---

## 参考

- [06-DDD_DESIGN.md](./06-DDD_DESIGN.md) - DDD 设计规范
- [01-OVERVIEW.md](./01-OVERVIEW.md) - 架构概览
- [ROADMAP.md](../ROADMAP.md) - 路线图
