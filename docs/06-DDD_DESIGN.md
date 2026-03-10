# DDD 设计指南（V3 统一语言版）

> 领域驱动设计（DDD）核心概念与实践模式。
>
> **注意**：具体代码实现请参考代码仓库，文档仅说明概念和模式。

---

## 1. 核心概念

领域驱动设计（DDD）是一种以**业务领域为核心**的软件开发方法：

- **统一语言**：开发人员与领域专家使用相同术语
- **边界上下文**：明确模块边界，避免概念混淆
- **分层架构**：职责清晰，依赖单向

### 为什么选择 DDD

| 医疗业务特点 | DDD 优势 |
|-------------|---------|
| 业务规则复杂 | 业务逻辑内聚在领域层 |
| 领域知识密集 | 聚合根保证数据一致性 |
| 强一致性要求 | 清晰分层支持技术替换 |
| 长期演化需求 | 统一语言降低沟通成本 |

---

## 2. 边界上下文划分

```
┌─────────────────────────────────────────────────────────────┐
│                      边界上下文                              │
├─────────────────────────────────────────────────────────────┤
│  用户上下文      →  User, Role, Permission                   │
│  门诊挂号上下文  →  ClinicSession, ClinicSlot, RegistrationOrder │
│  诊疗上下文      →  VisitEncounter, EmrRecord, PrescriptionOrder │
│  AI 问诊上下文   →  AiSession, AiTurn, RAG Engine            │
└─────────────────────────────────────────────────────────────┘
                        ↓
              HTTP 调用（跨上下文）
```

**跨上下文通信**：
- 用户上下文 → 门诊挂号/诊疗上下文：组合关系
- 门诊挂号/诊疗上下文 → AI 问诊：HTTP 调用（业务解耦）

---

## 3. 分层架构

```
┌─────────────────────────────────────────┐
│  用户接口层 (API Layer)                 │
│  Controller / Request / Response / VO   │
└───────────────────┬─────────────────────┘
                    │ 依赖
                    ▼
┌─────────────────────────────────────────┐
│  应用层 (Application Layer)             │
│  ApplicationService / Event Publisher   │
└───────────────────┬─────────────────────┘
                    │ 依赖
                    ▼
┌─────────────────────────────────────────┐
│  领域层 (Domain Layer) ← 核心！         │
│  Entity / ValueObject / DomainService   │
│  Repository 接口 / DomainEvent          │
└───────────────────┬─────────────────────┘
                    │ 实现（依赖倒置）
                    ▼
┌─────────────────────────────────────────┐
│  基础设施层 (Infrastructure Layer)      │
│  RepositoryImpl / Mapper / Converter    │
│  外部服务客户端 / Redis / 事件总线      │
└─────────────────────────────────────────┘
```

### 依赖规则

| 规则 | 说明 |
|------|------|
| 上层依赖下层 | API → Application → Domain → Infra |
| Domain 独立 | 纯 Java，不依赖 Spring / Infra / DAL |
| Infra 实现接口 | Repository 接口定义在 Domain，Impl 在 Infra |

---

## 4. 构造块

### 4.1 实体（Entity）

**特性**：
- 具有唯一标识（ID）
- 生命周期中属性可变
- 通过 ID 判断相等性，而非属性

**模式**：
```java
// 聚合根示例模式
public class RegistrationOrder {

    private RegistrationOrderId id;      // 唯一标识
    private RegistrationOrderNo orderNo; // 业务标识
    private UserId patientId;            // 值对象
    private ClinicSessionId sessionId;   // 门诊场次
    private RegistrationStatus status;   // 值对象

    // 工厂方法
    public static RegistrationOrder create(UserId patientId, ClinicSessionId sessionId) {
        // 创建逻辑 + 领域事件
    }

    // 业务行为（内聚规则）
    public void confirm() { /* 状态流转 */ }
    public void cancel(String reason) { /* 状态流转 */ }
}
```

### 4.2 值对象（Value Object）

**特性**：
- 无唯一标识
- 通过属性判断相等性
- 不可变（Immutable）

**模式**：
```java
// 值对象模式
public record RegistrationStatus(String code, String description) {

    public static final RegistrationStatus CREATED = new RegistrationStatus("CREATED", "已创建");
    public static final RegistrationStatus CONFIRMED = new RegistrationStatus("CONFIRMED", "已确认");

    public boolean canConfirm() {
        return this.equals(CREATED);
    }
}
```

### 4.3 聚合（Aggregate）

**特性**：
- 一组相关对象的集合
- 通过**聚合根**保证一致性边界
- 外部只能通过聚合根访问内部对象

**设计原则**：
- 小聚合优于大聚合
- 聚合间通过 ID 引用（`UserId` 而非完整 `User` 对象）
- 跨聚合操作通过**领域事件**实现最终一致性

### 4.4 仓储（Repository）

**特性**：
- 提供聚合的持久化和查询接口
- 仓储接口定义在**领域层**
- 仓储实现放在**基础设施层**

**模式**：
```java
// 领域层：仓储接口
public interface RegistrationOrderRepository {
    void save(RegistrationOrder order);
    Optional<RegistrationOrder> findById(RegistrationOrderId id);
    Optional<RegistrationOrder> findByOrderNo(RegistrationOrderNo no);
    boolean existsByPatientAndSession(UserId patientId, ClinicSessionId sessionId);
}

// 基础设施层：仓储实现
@Repository
public class RegistrationOrderRepositoryImpl implements RegistrationOrderRepository {
    // 使用 Mapper / Converter 实现
}
```

### 4.5 领域事件

**特性**：
- 解耦聚合间的依赖
- 实现最终一致性
- 事件携带足够信息

**模式**：
```java
// 事件定义（领域层）
public record RegistrationConfirmedEvent(
    RegistrationOrderId orderId,
    LocalDateTime occurredOn
) { }

// 发布（应用层）
registrationOrder.getDomainEvents().forEach(eventPublisher::publish);

// 监听（基础设施层）
@Async
@EventListener
public void handle(RegistrationConfirmedEvent event) {
    // 发送通知等
}
```

---

## 5. 统一语言对照

| 业务术语 | 领域对象 | 说明 |
|---------|---------|------|
| 挂号订单 | `RegistrationOrder` | 患者挂号后的交易实体 |
| 挂号单号 | `RegistrationOrderNo` | 唯一业务标识（值对象） |
| 门诊场次 | `ClinicSession` | 医生对外发布的可挂号场次 |
| 号源 | `ClinicSlot` | 可交易的最小号源单元 |
| 实际就诊 | `VisitEncounter` | 挂号履约后的就诊事实 |
| 病历 | `EmrRecord` | 结构化诊疗记录索引头 |
| 处方 | `PrescriptionOrder` | 处方主实体 |
| AI 会话 | `AiSession` | 患者问诊主会话 |

---

## 6. 最佳实践清单

### DO

- [x] 识别真正的不变量（事务内保证的约束）
- [x] 聚合内部对象通过聚合根访问
- [x] 聚合间通过 ID 引用，避免级联加载
- [x] 使用领域事件解耦聚合
- [x] 充血模型：实体包含业务行为

### DON'T

- [ ] 聚合过大（包含太多实体）
- [ ] 跨聚合的事务（应使用最终一致性）
- [ ] 在聚合外部修改聚合内部状态
- [ ] 聚合间直接依赖对象引用
- [ ] 贫血模型：实体只有 getter/setter，业务逻辑在 Service

---

## 7. 常见问题

### Q: MyBatis-Plus 如何适配 DDD？

**核心原则**：DO 与领域对象分离

```
RegistrationOrderDO (数据库表映射) ← Converter → RegistrationOrder (领域对象)
```

**仓储实现**：
```java
@Repository
public class RegistrationOrderRepositoryImpl implements RegistrationOrderRepository {

    private final RegistrationOrderMapper mapper;
    private final RegistrationOrderConverter converter;

    @Override
    public void save(RegistrationOrder order) {
        RegistrationOrderDO dataObject = converter.toDO(order);
        mapper.insert(dataObject);  // 或 updateById
    }
}
```

### Q: 贫血模型 vs 充血模型？

| 贫血模型（Anti-Pattern） | 充血模型（DDD 推荐） |
|------------------------|---------------------|
| 实体只有 getter/setter | 实体包含业务行为 |
| 业务逻辑在 Service | 状态变更内聚在实体 |
| `order.setStatus("X")` | `order.confirm()` |

---

## 8. 参考实现

| 构造块 | 参考代码 |
|--------|----------|
| 聚合根 | `RegistrationOrder` / `ClinicSession` / `EmrRecord` |
| 值对象 | `RegistrationStatus` / `ClinicType` / `AiSessionId` |
| 仓储接口 | `RegistrationOrderRepository` / `EmrRecordRepository` |
| 仓储实现 | `RegistrationOrderRepositoryImpl` / `EmrRecordRepositoryImpl` |
| 领域事件 | `RegistrationConfirmedEvent` / `AiReviewSubmittedEvent` |
| 应用服务 | `RegistrationApplicationService` / `EncounterApplicationService` |

---

## 9. 学习资源

- 📖 《领域驱动设计》- Eric Evans
- 📖 《实现领域驱动设计》- Vaughn Vernon
- 🎥 [DDD 实战课](https://time.geekbang.org/column/intro/100037301)
