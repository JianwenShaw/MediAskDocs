# DDD 设计指南（毕设收敛版）

> 适用阶段：重写启动前与 P0/P1 实现阶段
>
> 本文目标：统一限界上下文、分层依赖和建模深度，避免把所有模块都建成“重型 DDD”。
>
> 相关文档：总体架构以 [01-OVERVIEW.md](./01-OVERVIEW.md) 为准，实施边界以 [00A-P0-BASELINE.md](./00A-P0-BASELINE.md) 为准。

## 1. 设计立场

MediAsk 使用 DDD，但不是“所有地方都做满配 DDD”。

本项目采用 **务实 DDD**：

- 核心域做深：AI 问诊、门诊挂号、诊疗闭环
- 支撑域做轻：用户、审计、排班允许简化 CRUD 或轻量状态机
- 先守住边界与统一语言，再决定是否需要复杂聚合和领域事件

一句话原则：**DDD 用来收敛复杂业务，不用来制造额外复杂度。**

## 2. 限界上下文

### 2.1 上下文划分

| 上下文 | 类型 | 主要对象 | 当前定位 |
|------|------|----------|----------|
| 用户上下文 | 通用子域 | `User`、`Role`、`Permission` | 做轻，服务认证与最小授权 |
| 排班上下文 | 支撑子域 | `ClinicSession` 生成输入、发布结果 | 做轻，先服务挂号入口 |
| 门诊挂号上下文 | 核心域 | `ClinicSession`、`ClinicSlot`、`RegistrationOrder` | 做深，承担 AI 到线下就诊的承接 |
| 诊疗上下文 | 核心域 | `VisitEncounter`、`EmrRecord`、`PrescriptionOrder` | 做深，承担医生接诊闭环 |
| AI 问诊上下文 | 核心域 | `AiSession`、`AiTurn`、`AiModelRun`、`KnowledgeBase` | 做深，体现大模型与 RAG 能力 |
| 审计上下文 | 通用子域 | `AuditEvent`、`DataAccessLog` | 做准，承担留痕与追溯 |

### 2.2 跨上下文通信

| 模式 | 适用场景 | 说明 |
|------|----------|------|
| Shared Kernel | `UserId`、基础枚举 | 只共享稳定标识和值对象，不共享复杂领域对象 |
| Published Language | 排班 -> 门诊挂号 | 排班发布 `ClinicSession` 这一业务结果，门诊上下文消费 |
| Domain Event | 挂号完成、诊疗结束等 | 用于进程内解耦，不作为 P0 分布式集成总线 |
| ACL | Java -> Python AI 服务 | Java 通过 Client/Port 调 Python，隔离协议细节 |

## 3. 建模深度约定

### 3.1 哪些地方做深

以下场景建议采用完整聚合、值对象、状态机：

- `RegistrationOrder`：挂号创建、取消、支付/履约状态
- `ClinicSession` / `ClinicSlot`：号源分配与库存约束
- `AiSession` / `AiModelRun`：问诊轮次、模型运行、引用追溯
- `EmrRecord` / `PrescriptionOrder`：病历正文与处方生成

### 3.2 哪些地方做轻

以下场景允许使用简化实体 + Application 编排，不强求复杂聚合：

- 用户、角色、权限、数据范围
- 审计事件、访问日志
- 轻量排班输入配置
- 字典、通知、基础主数据

判断标准只有一个：**如果没有明确事务内不变量，就不要为了 DDD 而硬造聚合。**

## 4. 分层与依赖规则

### 4.1 目标分层

```
API / Worker -> Application -> Domain
API / Worker -.装配.-> Infrastructure -> Domain
Common 被各层复用，但不承载业务语义
```

### 4.2 规则冻结

| 规则 | 说明 |
|------|------|
| Domain 不依赖 Application / Infrastructure / API | 领域层必须纯净 |
| Application 不依赖 Infrastructure | 应用层只依赖 Port 与领域对象 |
| Infrastructure 实现 Domain 中定义的 Port | Repository、Client、Publisher 都属于适配器 |
| Controller / Job 只调用 Application | 不直接调用 Repository 或外部 Client |
| 跨上下文传 ID，不传聚合实例 | 避免模型泄漏与级联依赖 |

## 5. 战术设计构造块

### 5.1 聚合根

聚合根负责：

- 维护事务内不变量
- 封装状态迁移
- 对外暴露有限行为
- 挂载领域事件

示例：

- `RegistrationOrder.confirm()`
- `RegistrationOrder.cancel(reason)`
- `ClinicSession.allocateSlot(patientId)`
- `EmrRecord.revise(content, doctorId)`

### 5.2 实体

实体用于表达“有身份、会变化”的对象，例如：

- `RegistrationOrder`
- `VisitEncounter`
- `AiSession`
- `PrescriptionOrder`

### 5.3 值对象

值对象优先于裸类型，典型包括：

- `UserId`
- `RegistrationStatus`
- `RiskLevel`
- `ClinicType`
- `DepartmentId`

值对象必须不可变，比较基于值，而不是引用。

### 5.4 Repository

Repository 只围绕聚合根建立，一个聚合根一个 Repository：

- `RegistrationOrderRepository`
- `ClinicSessionRepository`
- `EmrRecordRepository`
- `AiSessionRepository`

查询列表、报表、只读投影允许不返回完整聚合，可在 Application/Query 侧走轻量查询模型。

### 5.5 Domain Event

Domain Event 用于表达“已经发生的业务事实”，命名使用过去式。

适合用事件的场景：

- `RegistrationConfirmedEvent`
- `EncounterStartedEvent`
- `AiReviewSubmittedEvent`

不适合用事件的场景：

- 同一用例内本来就应该直接调用的步骤
- 只是为了“看起来像微服务”而拆的内部流程

### 5.6 Domain Service

当逻辑跨多个实体/值对象、又不属于单个聚合根时，使用 Domain Service。

典型场景：

- 号源分配策略
- 处方合法性校验
- AI 结果与医疗流程之间的领域映射

## 6. 推荐聚合清单

| 上下文 | 推荐聚合根 | 备注 |
|------|------------|------|
| 用户 | `User` | 权限关系允许简化实现 |
| 排班 | `ScheduleGenerationJob`（P1） | P0 可只落发布后的 `ClinicSession` |
| 门诊挂号 | `ClinicSession`、`RegistrationOrder` | 核心状态机 |
| 诊疗 | `VisitEncounter`、`EmrRecord`、`PrescriptionOrder` | 医生接诊闭环 |
| AI 问诊 | `AiSession`、`KnowledgeBase` | P0 重点体现 RAG 与引用追溯 |
| 审计 | `AuditEvent` | 允许贫血化 |

## 7. P0 建模规则

为了让文档能直接指导开发，P0 阶段再额外冻结以下规则：

1. 一个用例只维护必要聚合，不追求“所有规则都塞进同一个聚合”
2. 列表查询、工作台查询、审计检索优先走 Query Model，不强制装配完整聚合
3. Java 与 Python 的边界不做“共享领域模型”，只共享请求契约和稳定 ID
4. Python 不成为业务主事实写入方，只维护检索投影和引用追溯
5. 审计与权限只做最小合规能力，不把审批流、break-glass、WORM 拉进 P0

## 8. Application 层应该做什么

Application 层负责：

- 接收 Command / Query
- 开启事务
- 加载聚合根
- 调用领域行为
- 保存聚合根
- 发布事件
- 组装 DTO

Application 层不负责：

- 手写持久化细节
- 直接拼接外部协议细节
- 承担领域规则判断

## 9. 常见反模式

以下做法在本项目中应直接避免：

- Controller 直接查 Mapper / Repository
- Application 直接依赖 Infrastructure Client
- 把跨上下文对象整体传来传去
- 为简单 CRUD 强行设计大聚合
- 把领域事件当成分布式总线提前实现
- 因为“医疗系统听起来很复杂”而把所有模块都建成重型状态机

## 10. 一句话结论

MediAsk 的 DDD 重点不是“把每个模块都做成教科书示例”，而是：**把 AI、挂号、诊疗这三条核心链路的边界和不变量建对，把其余支撑域做轻。**
