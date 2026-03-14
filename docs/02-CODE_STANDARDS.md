# 代码规范与工程最佳实践

> **设计立场**：本文档为 MediAsk 项目的目标代码规范，与 [01-OVERVIEW.md](./01-OVERVIEW.md) 的六边形架构、6 模块结构保持一致。
>
> **注意**：本文件用于指导重写阶段的实现，规范优先于旧代码。

---

## 1. 模块结构与职责

### 1.1 六模块总览 `[对齐 ADR-004]`

| 模块 | 六边形角色 | 职责 | 关键类/接口 |
|------|-----------|------|------------|
| `mediask-api` | Interface Adapter + Composition Root | REST 控制器、JWT 认证、Security 过滤、DTO 序列化、Spring Boot 启动装配 | `*Controller`、`*Request`、`*Response`、`*Assembler`、`*Application` |
| `mediask-application` | Application Layer | 用例编排、事务边界、Command/Query 对象 | `*UseCase`、`*Command`、`*Query` |
| `mediask-domain` | Domain Core + Driven Port | 聚合根、实体、值对象、领域服务、领域事件、Port 接口 | `*`（Entity）、`*Id`（VO）、`*Repository`、`*Port`、`*Event` |
| `mediask-infrastructure` | Driven Adapter（被驱动侧适配器） | Repository 实现、DO/Mapper、Redis/锁、AI 客户端 | `*RepositoryImpl`、`*DO`、`*Mapper`、`*Converter`、`*Client` |
| `mediask-common` | 技术公共库 | 异常体系、统一响应、工具类、全局常量 | `Result<T>`、`BizException`、`SysException`、`ErrorCode` |
| `mediask-worker` | Driving Adapter（驱动侧适配器） | 定时任务、事件消费者、批量作业 | `*Scheduler`、`*Consumer`、`*Job` |

### 1.2 依赖规则（编译期强制）

```
mediask-api → mediask-application → mediask-domain
mediask-api → mediask-infrastructure → mediask-domain
mediask-worker → mediask-application
mediask-worker → mediask-infrastructure
所有模块 → mediask-common
```

| 规则 | 说明 |
|------|------|
| Domain **不依赖**任何其他业务模块 | 纯 Java，不引入 Spring、MyBatis、Redis 等框架依赖 |
| Application **依赖** Domain + Common | 编排领域对象，管理事务边界，只面向 Port 与领域对象编程 |
| Infrastructure **依赖** Domain + Common | 实现 Domain 中定义的 Port 接口 |
| API **模块依赖** Application + Infrastructure | 负责 Spring 装配；但 Controller、Assembler、Security 鉴权逻辑只调用 Application |
| Worker **模块依赖** Application + Infrastructure | 负责任务进程装配；但 Job、Consumer 只调用 Application |
| Common 被所有模块依赖 | 仅包含无业务语义的技术工具 |

### 1.3 禁止的依赖方向

| 禁止 | 原因 |
|------|------|
| API 业务代码 → Domain | Controller/Assembler 不应绕过 Application 直接操作领域对象 |
| API 业务代码 → Infrastructure | Controller/Assembler/Scheduler 不应直接操作 Repository/Client |
| Domain → Infrastructure | 违反依赖倒置，领域层必须通过 Port 接口抽象基础设施 |
| Domain → Application | 内层不依赖外层 |
| Infrastructure → Application | 被驱动侧不应反向依赖应用层 |

---

## 2. 命名规范

### 2.1 类命名

| 类型 | 后缀/模式 | 所在模块 | 示例 |
|------|----------|---------|------|
| REST 控制器 | `*Controller` | api | `RegistrationController` |
| 请求 DTO | `*Request` | api | `CreateRegistrationRequest` |
| 响应 DTO | `*Response` | api | `RegistrationDetailResponse` |
| 视图对象 | `*VO` | api | `ClinicSessionVO` |
| Assembler | `*Assembler` | api | `RegistrationAssembler` |
| 用例 | `*UseCase` | application | `CreateRegistrationUseCase` |
| Command | `*Command` | application | `CreateRegistrationCommand` |
| Query | `*Query` | application | `ListRegistrationQuery` |
| 聚合根/实体 | 业务名词，无后缀 | domain | `RegistrationOrder`、`ClinicSession` |
| 值对象 | `*Id`、`*Status`、`*Type`、`*Period` 等 | domain | `UserId`、`RegistrationStatus`、`ClinicType` |
| 领域服务 | `*DomainService` | domain | `SlotAllocationDomainService` |
| 领域事件 | `*Event`（过去式命名） | domain | `RegistrationConfirmedEvent` |
| Repository 接口 | `*Repository` | domain | `RegistrationOrderRepository` |
| 外部服务端口 | `*Port` | domain | `AiServicePort`、`PaymentPort` |
| Repository 实现 | `*RepositoryImpl` | infrastructure | `RegistrationOrderRepositoryImpl` |
| 数据对象 | `*DO` | infrastructure | `RegistrationOrderDO` |
| Mapper | `*Mapper` | infrastructure | `RegistrationOrderMapper` |
| DO ↔ Domain 转换 | `*Converter` | infrastructure | `RegistrationOrderConverter` |
| 外部客户端 | `*Client` | infrastructure | `AiServiceClient` |
| 枚举 | 业务名词（无 `Enum` 后缀） | domain | `RegistrationStatus`、`ClinicType` |
| 异常 | `*Exception` | common/domain | `BizException`、`SysException` |
| 工具类 | `*Utils` | common | `DateUtils`、`SnowflakeIdGenerator` |
| 错误码 | `ErrorCode` | common | `ErrorCode.SLOT_NOT_AVAILABLE` |

### 2.2 方法命名

```java
// ---- UseCase ----
// 统一入口方法名为 execute
Result<RegistrationDetailDTO> execute(CreateRegistrationCommand command);

// ---- Repository ----
// 查询方法使用 findBy* / listBy* / existsBy*
Optional<RegistrationOrder> findById(RegistrationOrderId id);
List<ClinicSession> listByDoctorIdAndDate(DoctorId doctorId, LocalDate date);
boolean existsByPatientAndSession(UserId patientId, ClinicSessionId sessionId);

// 持久化方法使用 save / remove
void save(RegistrationOrder order);
void remove(RegistrationOrderId id);

// ---- 聚合根行为方法 ----
// 业务动词，清晰表达领域含义
order.confirm();
order.cancel(CancelReason reason);
session.allocateSlot(UserId patientId);
emr.revise(EmrContent newContent, DoctorId revisedBy);

// ---- Controller ----
// RESTful 风格，HTTP 动词即语义
@PostMapping   createRegistration(...)
@GetMapping    getRegistrationDetail(...)
@PutMapping    updateRegistration(...)
@DeleteMapping cancelRegistration(...)
```

### 2.3 变量命名

```java
// 清晰表达业务含义，使用完整英文单词
private RegistrationOrderId orderId;
private UserId patientId;
private DoctorId doctorId;
private LocalDateTime createdAt;
private RegistrationStatus status;
private int totalSlots;
private int availableSlots;

// 禁止：拼音、无意义缩写、单字母变量（循环变量除外）
// uid / xm / ctime / dto1 / temp
```

### 2.4 包命名

按限界上下文组织，每个上下文内部按六边形层级划分：

```
me.jianwen.mediask.domain.outpatient.model      # 聚合根、实体、值对象
me.jianwen.mediask.domain.outpatient.event       # 领域事件
me.jianwen.mediask.domain.outpatient.service     # 领域服务
me.jianwen.mediask.domain.outpatient.port        # Repository 接口、外部服务端口
me.jianwen.mediask.domain.shared                 # 跨上下文共享的值对象

me.jianwen.mediask.application.outpatient.command   # Command 对象
me.jianwen.mediask.application.outpatient.query     # Query 对象
me.jianwen.mediask.application.outpatient.usecase   # UseCase 实现

me.jianwen.mediask.infrastructure.persistence.outpatient   # DO、Mapper、Converter、RepositoryImpl
me.jianwen.mediask.infrastructure.cache                    # Redis 相关
me.jianwen.mediask.infrastructure.ai                       # AI 服务客户端

me.jianwen.mediask.api.controller.outpatient     # REST 控制器
me.jianwen.mediask.api.dto.outpatient            # Request / Response / VO
me.jianwen.mediask.api.assembler.outpatient      # DTO ↔ Command / Domain 转换
```

---

## 3. 分层代码模式

### 3.1 Interface Adapter 层（mediask-api）

**职责**：HTTP 协议适配 — 参数校验、DTO 转换、调用 UseCase、返回统一响应。

**禁止**：包含任何业务编排逻辑、直接操作 Domain 对象或 Repository。

```java
@RestController
@RequestMapping("/api/v1/registrations")
@RequiredArgsConstructor
public class RegistrationController {

    private final CreateRegistrationUseCase createRegistrationUseCase;
    private final RegistrationAssembler assembler;

    @PostMapping
    public Result<RegistrationDetailResponse> create(
            @RequestBody @Validated CreateRegistrationRequest request) {
        // 1. DTO → Command
        CreateRegistrationCommand command = assembler.toCommand(request);
        // 2. 调用 UseCase
        RegistrationDetailDTO dto = createRegistrationUseCase.execute(command);
        // 3. DTO → Response
        return Result.ok(assembler.toResponse(dto));
    }
}
```

### 3.2 Application 层（mediask-application）

**职责**：用例编排 — 事务管理、加载聚合根、调用领域行为、持久化、发布事件。

**禁止**：包含领域规则判断（应委托给聚合根或领域服务）。

```java
@Service
@RequiredArgsConstructor
@Slf4j
public class CreateRegistrationUseCase {

    private final ClinicSessionRepository sessionRepository;
    private final RegistrationOrderRepository orderRepository;
    private final EventPublisherPort eventPublisher;

    @Transactional
    public RegistrationDetailDTO execute(CreateRegistrationCommand command) {
        // 1. 加载聚合根
        ClinicSession session = sessionRepository.findById(command.sessionId())
                .orElseThrow(() -> new BizException(ErrorCode.SESSION_NOT_FOUND));

        // 2. 领域行为（业务规则在聚合根内部）
        RegistrationOrder order = session.allocateSlot(command.patientId());

        // 3. 持久化
        sessionRepository.save(session);
        orderRepository.save(order);

        // 4. 发布领域事件
        order.domainEvents().forEach(eventPublisher::publish);

        log.info("创建挂号成功, orderId={}, patientId={}, sessionId={}",
                order.getId(), command.patientId(), command.sessionId());

        return toDTO(order);
    }
}
```

### 3.3 Domain Core（mediask-domain）

**职责**：业务规则、状态变更、领域事件产生。

**强制**：纯 Java，零框架依赖（不使用 Spring、MyBatis、Lombok 等注解）。

```java
// ── 聚合根 ──
public class RegistrationOrder {

    private RegistrationOrderId id;
    private RegistrationNo registrationNo;
    private UserId patientId;
    private ClinicSessionId sessionId;
    private RegistrationStatus status;
    private final List<DomainEvent> domainEvents = new ArrayList<>();

    // 工厂方法
    public static RegistrationOrder create(UserId patientId, ClinicSessionId sessionId) {
        RegistrationOrder order = new RegistrationOrder();
        order.id = RegistrationOrderId.generate();
        order.registrationNo = RegistrationNo.generate();
        order.patientId = patientId;
        order.sessionId = sessionId;
        order.status = RegistrationStatus.PENDING_PAYMENT;
        order.domainEvents.add(new RegistrationCreatedEvent(order.id, patientId, sessionId));
        return order;
    }

    // 行为方法
    public void confirm() {
        if (!this.status.canConfirm()) {
            throw new BizException(ErrorCode.INVALID_STATUS_TRANSITION);
        }
        this.status = RegistrationStatus.CONFIRMED;
        this.domainEvents.add(new RegistrationConfirmedEvent(this.id));
    }

    public void cancel(CancelReason reason) {
        if (!this.status.canCancel()) {
            throw new BizException(ErrorCode.INVALID_STATUS_TRANSITION);
        }
        this.status = RegistrationStatus.CANCELLED;
        this.domainEvents.add(new RegistrationCancelledEvent(this.id, reason));
    }

    public List<DomainEvent> domainEvents() {
        return Collections.unmodifiableList(domainEvents);
    }

    public void clearDomainEvents() {
        domainEvents.clear();
    }
}

// ── 值对象（Java record） ──
public record RegistrationOrderId(long value) {
    public static RegistrationOrderId generate() {
        return new RegistrationOrderId(SnowflakeIdGenerator.nextId());
    }
}

public record UserId(long value) {}

// ── 领域事件（Java record） ──
public record RegistrationConfirmedEvent(
    RegistrationOrderId orderId
) implements DomainEvent {}

// ── Repository 接口（Driven Port） ──
public interface RegistrationOrderRepository {
    Optional<RegistrationOrder> findById(RegistrationOrderId id);
    void save(RegistrationOrder order);
    void remove(RegistrationOrderId id);
}

// ── 外部服务端口（Driven Port） ──
public interface EventPublisherPort {
    void publish(DomainEvent event);
}
```

### 3.4 Infrastructure 层（mediask-infrastructure）

**职责**：技术实现 — 数据持久化、缓存、外部服务调用。实现 Domain 中定义的 Port 接口。

```java
// ── Repository 实现（Driven Adapter） ──
@Repository
@RequiredArgsConstructor
public class RegistrationOrderRepositoryImpl implements RegistrationOrderRepository {

    private final RegistrationOrderMapper mapper;
    private final RegistrationOrderConverter converter;

    @Override
    public Optional<RegistrationOrder> findById(RegistrationOrderId id) {
        RegistrationOrderDO dataObject = mapper.selectById(id.value());
        return Optional.ofNullable(dataObject).map(converter::toDomain);
    }

    @Override
    public void save(RegistrationOrder order) {
        RegistrationOrderDO dataObject = converter.toDO(order);
        if (mapper.selectById(dataObject.getId()) == null) {
            mapper.insert(dataObject);
        } else {
            mapper.updateById(dataObject);
        }
    }

    @Override
    public void remove(RegistrationOrderId id) {
        mapper.deleteById(id.value());
    }
}

// ── DO（数据对象） ──
@Data
@TableName("registration_order")
public class RegistrationOrderDO {
    @TableId(type = IdType.INPUT)
    private Long id;
    private String registrationNo;
    private Long patientId;
    private Long sessionId;
    private String status;
    private Integer version;
    private LocalDateTime createdAt;
    private LocalDateTime updatedAt;
    private LocalDateTime deletedAt;
}

// ── Converter（DO ↔ Domain） ──
@Component
public class RegistrationOrderConverter {

    public RegistrationOrder toDomain(RegistrationOrderDO dataObject) {
        // DO → Domain Entity 转换逻辑
    }

    public RegistrationOrderDO toDO(RegistrationOrder entity) {
        // Domain Entity → DO 转换逻辑
    }
}
```

---

## 4. 统一响应与异常体系

> 详见 [19-ERROR_EXCEPTION_RESPONSE_DESIGN.md](./19-ERROR_EXCEPTION_RESPONSE_DESIGN.md)。

### 4.1 统一响应体

```json
{
  "code": 0,
  "msg": "success",
  "data": {},
  "requestId": "req_01hrx6m5q4x5v2f6k4w4x1c7pz",
  "timestamp": 1741234567890
}
```

- `code = 0` 表示成功，非零表示失败
- `requestId` **必须**出现在每个响应中
- `timestamp` 为 Unix 毫秒时间戳

```java
// 成功
Result.ok(data)

// 失败（由 GlobalExceptionHandler 统一处理，Controller 不应手动构造失败响应）
throw new BizException(ErrorCode.SLOT_NOT_AVAILABLE);
```

### 4.2 异常体系

| 异常类 | 用途 | 触发场景 |
|--------|------|---------|
| `BizException` | 可预期的业务规则违反 | 参数校验失败、状态机转换非法、资源不存在、权限不足 |
| `SysException` | 不可预期的系统/基础设施故障 | DB/Redis 不可用、RPC 超时、框架内部错误 |
| `GlobalExceptionHandler` | 统一异常 → `Result` 映射 | 捕获所有异常，转换为标准响应格式 |

### 4.3 错误码分段

| 范围 | 领域 |
|------|------|
| `0` | 成功 |
| `1xxx` | 通用/公共（参数错误、认证失败、权限不足） |
| `2xxx` | 用户上下文 |
| `3xxx` | 门诊挂号上下文 |
| `4xxx` | 诊疗上下文 |
| `5xxx` | 排班上下文 |
| `6xxx` | AI 问诊上下文（含 Python 服务错误） |
| `9xxx` | 系统级兜底 |

### 4.4 异常使用规则

- **永远抛出异常**，而非在 Controller 中手动构造 `Result.fail(...)`
- **优先使用领域特定错误码**，禁止复用其他领域的 code
- **禁止泄露敏感信息**（SQL、堆栈、凭证）到 `msg` 字段

---

## 5. 对象转换规范

### 5.1 转换层次

| 转换方向 | 负责类 | 所在模块 |
|----------|--------|---------|
| Request DTO → Command | `*Assembler` | api |
| Domain → Response DTO | `*Assembler` | api |
| DO ↔ Domain Entity | `*Converter` | infrastructure |

### 5.2 实现方式

- 使用 **MapStruct** 生成转换代码（编译期，无反射开销）
- Converter 由 Spring 管理（`@Component` / `@Mapper(componentModel = "spring")`）
- **禁止**在 Controller 或 UseCase 中手写字段逐一赋值

### 5.3 转换原则

- Assembler **不依赖** Domain 层的领域对象（只处理 DTO ↔ Command/Response）
- Converter 负责 DO ↔ Domain 的双向转换，**包括枚举映射和值对象拆装**
- 复杂聚合根的重建逻辑应放在 Converter 中，不要散落在 RepositoryImpl

---

## 6. 领域模型设计规范

### 6.1 聚合根设计

| 规则 | 说明 |
|------|------|
| 一个聚合根 = 一个事务边界 = 一个 Repository | 聚合根是持久化和一致性的最小单位 |
| 外部引用只用 ID | 跨聚合引用使用 `UserId`、`DoctorId` 等值对象，不持有对方实体引用 |
| 行为放在聚合根内 | `order.confirm()` 而非 `orderService.confirm(order)` |
| 工厂方法创建 | `RegistrationOrder.create(...)` 而非 `new RegistrationOrder()` + setter |
| 领域事件由聚合根产生 | 事件收集在聚合根内部，由 Application 层取出并发布 |

### 6.2 值对象设计

- 使用 Java `record` 实现，天然不可变 + 值相等
- 包含自校验逻辑（compact constructor 中校验）
- 包含工厂方法（如 `RegistrationOrderId.generate()`）

```java
public record PhoneNumber(String value) {
    public PhoneNumber {
        if (value == null || !value.matches("^1[3-9]\\d{9}$")) {
            throw new BizException(ErrorCode.INVALID_PHONE_NUMBER);
        }
    }
}
```

### 6.3 领域事件设计

- 过去式命名：`RegistrationConfirmedEvent`，`EmrCreatedEvent`
- 使用 Java `record`，只包含必要的标识信息
- 通过 `EventPublisherPort`（Driven Port）发布，Infrastructure 层提供 Spring ApplicationEvent 实现
- 跨聚合/跨上下文通信**必须**通过领域事件，不允许跨聚合直接调用

### 6.4 枚举设计

```java
public enum RegistrationStatus {
    PENDING_PAYMENT("待支付"),
    CONFIRMED("已确认"),
    CHECKED_IN("已报到"),
    IN_CONSULTATION("就诊中"),
    COMPLETED("已完成"),
    CANCELLED("已取消");

    private final String description;

    RegistrationStatus(String description) {
        this.description = description;
    }

    public String getDescription() {
        return description;
    }

    // 状态机：定义合法转换
    public boolean canConfirm() {
        return this == PENDING_PAYMENT;
    }

    public boolean canCancel() {
        return this == PENDING_PAYMENT || this == CONFIRMED;
    }

    public boolean canCheckIn() {
        return this == CONFIRMED;
    }
}
```

---

## 7. 常量与 Redis Key 管理

### 7.1 Redis Key 管理规范（强制）

- **所有 Redis Key 必须通过统一入口生成**，禁止在业务类中手写字符串拼接
- 统一使用 `:` 作为分隔符，命名模式：`业务域:子域:标识`
- Key 前缀由 Infrastructure 层统一管理，Application/Domain 只传业务参数
- Pattern 查询（如批量删除）也必须通过统一入口生成

```java
// infrastructure 层统一管理
public final class CacheKeyGenerator {

    private static final String DELIMITER = ":";

    private CacheKeyGenerator() {}

    // 限流 Key
    public static String rateLimitAuthLogin(String account) {
        return String.join(DELIMITER, "rate:limit:auth:login", account);
    }

    // 号源缓存 Key
    public static String slotInventory(long sessionId) {
        return String.join(DELIMITER, "cache:slot:inventory", String.valueOf(sessionId));
    }

    // JWT 黑名单 Key
    public static String jwtBlacklist(String jti) {
        return String.join(DELIMITER, "auth:jwt:blacklist", jti);
    }
}
```

### 7.2 全局常量

- 放在 `mediask-common` 的 `constant` 包中
- 按业务域分类（`AuthConstants`、`OutpatientConstants`）
- 禁止使用魔法数字和魔法字符串

---

## 8. 日志规范

### 8.1 基本规则

```java
// 使用 SLF4J + 占位符，禁止字符串拼接
log.info("创建挂号成功, orderId={}, patientId={}, sessionId={}",
        orderId, patientId, sessionId);

log.warn("号源不足, sessionId={}, requestedSlots={}, availableSlots={}",
        sessionId, requested, available);

log.error("持久化失败, orderId={}", orderId, exception);
```

### 8.2 日志级别使用

| 级别 | 适用场景 |
|------|---------|
| `ERROR` | 系统异常、不可恢复的失败（需要人工介入） |
| `WARN` | 业务异常、可恢复的失败、降级场景 |
| `INFO` | 关键业务节点（创建、状态变更、支付、登录） |
| `DEBUG` | 开发调试信息（生产环境默认关闭） |

### 8.3 Request Context 链路

- `RequestContextFilter` 从请求头 `X-Request-Id` 读取（或自动生成 UUID），兼容旧头 `X-Trace-Id`
- 写入 MDC（`requestId`、`requestUri`；P2 可选 `traceId`），logback 自动输出
- 跨服务调用（Java → Python）时通过 `X-Request-Id` 请求头透传
- 详见 [16-LOGGING_DESIGN/00-INDEX.md](./16-LOGGING_DESIGN/00-INDEX.md)、[17-OBSERVABILITY.md](./17-OBSERVABILITY.md) 和 [17A-REQUEST_CONTEXT_IMPLEMENTATION.md](./17A-REQUEST_CONTEXT_IMPLEMENTATION.md)

---

## 9. 接口设计规范

### 9.1 RESTful 设计

| HTTP 方法 | 语义 | 示例 |
|-----------|------|------|
| `GET` | 查询（幂等） | `GET /api/v1/registrations/{id}` |
| `POST` | 创建 | `POST /api/v1/registrations` |
| `PUT` | 全量更新 | `PUT /api/v1/registrations/{id}` |
| `PATCH` | 部分更新 / 状态操作 | `PATCH /api/v1/registrations/{id}/cancel` |
| `DELETE` | 删除 | `DELETE /api/v1/registrations/{id}` |

### 9.2 URL 前缀规范

详见 [01-OVERVIEW.md §12.1](./01-OVERVIEW.md) 的接口前缀总表。所有 API 统一前缀 `/api/v1/`。

### 9.3 幂等性

**需要幂等的场景**：支付接口、挂号创建、状态变更操作。

**实现方式**：
- `@Idempotent` 注解（Redis + 幂等 Key 实现）
- 唯一业务键（数据库唯一约束，如 `registration_no`）

### 9.4 限流

**实现方式**：
- `@RateLimiter` 注解
- Redisson 滑动窗口
- Key 通过 `CacheKeyGenerator` 统一生成

### 9.5 参数校验

- 使用 `@Validated` 触发 Bean Validation
- 自定义校验注解放在 `mediask-common`
- 嵌套对象使用 `@Valid` 级联校验

```java
public class CreateRegistrationRequest {
    @NotNull(message = "场次 ID 不能为空")
    private Long sessionId;

    @NotNull(message = "患者 ID 不能为空")
    private Long patientId;
}
```

---

## 10. 数据库规范

### 10.1 命名规范

| 对象 | 规范 | 示例 |
|------|------|------|
| 表名 | `snake_case`，名词/名词短语 | `registration_order`、`clinic_session` |
| 字段名 | `snake_case` | `patient_id`、`created_at` |
| 主键 | `id BIGINT`（雪花 ID，应用层生成） | — |
| 时间字段 | `TIMESTAMPTZ` | `created_at`、`updated_at`、`deleted_at` |
| 状态字段 | `VARCHAR` + `CHECK` 约束 | `status VARCHAR(32) CHECK (status IN (...))` |
| 乐观锁 | `version INT NOT NULL DEFAULT 0` | — |
| 软删除 | `deleted_at TIMESTAMPTZ DEFAULT NULL` | — |
| 金额 | `NUMERIC(10,2)` | `fee`、`amount` |

### 10.2 SQL 文件组织

详见 [07-DATABASE.md](./07-DATABASE.md)，共 58 张表分布在 7 个 SQL 文件中。

### 10.3 敏感数据存储

| 策略 | 说明 |
|------|------|
| 索引/密文分离 | 列表查询只读索引表，查看原文时解密密文表（如 `emr_record` + `emr_record_content`） |
| 独立加密列 | 应用层 AES-256 加密（如 `ai_turn_content.encrypted_content`） |
| PII 隔离 | 高敏感身份信息独立存储于 `user_pii_profile` |
| 访问审计 | 每次访问敏感数据均记录至 `data_access_log` |

---

## 11. 安全规范

### 11.1 认证

- JWT Access Token（30min）+ UUID Refresh Token（7d）
- 登出时 Refresh Token 失效 + Access Token 加入 Redis 黑名单
- `JwtAuthenticationFilter` 验证签名 → 检查黑名单 → 注入 SecurityContext

### 11.2 鉴权

| 层级 | 机制 | 实现 |
|------|------|------|
| 接口级 | RBAC | `@PreAuthorize("hasAuthority('...')")` |
| 数据级 | 数据权限规则 | `data_scope_rules` + MyBatis 拦截器 |
| 字段级 | 敏感字段脱敏 | 序列化时按角色决定 |

### 11.3 AI 安全护栏

详见 [11-AI_GUARDRAILS_PLAN.md](./11-AI_GUARDRAILS_PLAN.md)。输入侧 PII 检测 + 风险分类，输出侧回扫 + 免责声明注入。

---

## 12. 代码审查 Checklist

### 架构与分层
- [ ] 依赖方向正确（Domain 不依赖外层）
- [ ] Domain 层零框架依赖（纯 Java）
- [ ] Controller 只做参数校验 + 调用 UseCase，无业务逻辑
- [ ] UseCase 不包含领域规则（规则在聚合根/领域服务中）
- [ ] 跨聚合通信通过领域事件

### 命名与规范
- [ ] 类命名符合后缀规范（Controller/UseCase/Command/DO/VO）
- [ ] 方法命名清晰表达业务含义
- [ ] 变量无拼音、无缩写
- [ ] 包结构按限界上下文组织

### 领域模型
- [ ] 聚合根封装行为（充血模型），非 setter 式贫血模型
- [ ] 值对象使用 Java record，包含自校验
- [ ] 领域事件过去式命名，通过 EventPublisherPort 发布
- [ ] 外部引用只用 ID 值对象

### 基础设施
- [ ] Redis Key 通过 CacheKeyGenerator 统一生成
- [ ] DO ↔ Domain 转换通过 Converter，非手写赋值
- [ ] 敏感数据加密存储，响应中脱敏

### 接口设计
- [ ] 核心接口实现幂等性保障
- [ ] 高频接口配置限流
- [ ] 接口添加 OpenAPI 注解
- [ ] 异常抛出而非手动构造 `Result.fail(...)`

### 日志与可观测
- [ ] 使用占位符，禁止字符串拼接
- [ ] 关键业务节点有 INFO 日志
- [ ] 包含 requestId 和关键业务参数（如启用 APM，再附带 traceId）
- [ ] 敏感数据（密码、身份证）不出现在日志中

---

## 13. 相关文档

| 文档 | 说明 |
|------|------|
| [01-OVERVIEW.md](./01-OVERVIEW.md) | 系统架构设计（六边形架构、6 模块、技术栈、部署拓扑） |
| [06-DDD_DESIGN.md](./06-DDD_DESIGN.md) | DDD 设计指南（统一语言、聚合根、状态机） |
| [07-DATABASE.md](./07-DATABASE.md) | 数据库设计（V3 全表，58 张表） |
| [19-ERROR_EXCEPTION_RESPONSE_DESIGN.md](./19-ERROR_EXCEPTION_RESPONSE_DESIGN.md) | 错误/异常/响应设计（`Result<T>`、`BizException`、错误码分段） |
| [16-LOGGING_DESIGN/00-INDEX.md](./16-LOGGING_DESIGN/00-INDEX.md) | 日志架构设计 |
| [17-OBSERVABILITY.md](./17-OBSERVABILITY.md) | 可观测性架构（Traces / Metrics / Logs） |
| [15-PERMISSIONS/00-INDEX.md](./15-PERMISSIONS/00-INDEX.md) | 权限体系设计（RBAC + 数据权限） |
