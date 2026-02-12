# 代码规范与工程最佳实践

> 本文档定义项目强制执行的代码规范和分层架构实践。
>
> **注意**：具体代码实现请参考代码仓库，文档仅说明规范和模式。

---

## 1. 包结构设计

### 1.1 模块职责

| 模块 | 职责 | 关键类 |
|------|------|--------|
| `mediask-api` | REST 控制器、JWT 认证、安全配置 | `*Controller`, `*Filter` |
| `mediask-service` | 应用服务、业务编排、用例实现 | `*ApplicationService` |
| `mediask-domain` | 领域实体、值对象、领域服务、仓储接口 | `*`, `*DomainService` |
| `mediask-infra` | 仓储实现、Redis/锁、JWT、事件发布 | `*RepositoryImpl`, `*Converter` |
| `mediask-dal` | DO 实体、MyBatis-Plus Mapper | `*DO`, `*Mapper` |
| `mediask-common` | 工具类、异常、常量、响应包装器 | `R<T>`, `BizException` |
| `mediask-worker` | 定时任务 | `*Scheduler` |

### 1.2 分层依赖规则

```
┌─────────────────────────────────────────┐
│  API Layer (mediask-api)                │ ← 不能直接依赖 Domain
│  Controller, DTO, Assembler             │
└───────────────────┬─────────────────────┘
                    │ 依赖
                    ▼
┌─────────────────────────────────────────┐
│  Service Layer (mediask-service)        │ ← 使用 Repository 接口
│  ApplicationService                     │
└───────────────────┬─────────────────────┘
                    │
          ┌─────────┴─────────┐
          ▼                   ▼
┌───────────────────┐ ┌───────────────────┐
│  Domain Layer     │ │  Infra Layer      │
│  (纯 Java，无 Spring 依赖) │ │  (技术实现)       │
└───────────────────┘ └───────────────────┘
```

**核心规则**：
- Domain 层：不依赖 Infra/DAL；可保留极少量 Spring 依赖用于注解（如 `@Service`）
- Service 层：使用 Repository 接口（定义在 Domain），不直接用 Mapper
- Infra 层：实现 Domain 的仓储接口，提供技术能力

---

## 2. 命名规范

### 2.1 类命名

| 类型 | 后缀规范 | 示例 |
|------|----------|------|
| 数据对象 | `XxxDO` | `UserDO`, `AppointmentDO` |
| 请求 DTO | `XxxRequest` | `LoginRequest`, `CreateScheduleRequest` |
| 响应 DTO | `XxxResponse` | `LoginResponse` |
| 服务 DTO | `XxxDTO` | `LoginResponseDTO` |
| 视图对象 | `XxxVO` | `UserInfoVO` |
| Mapper | `XxxMapper` | `UserMapper` |
| 服务 | `XxxService` | `UserService` |
| 应用服务 | `XxxApplicationService` | `AppointmentApplicationService` |
| 领域服务 | `XxxDomainService` | `AutoScheduleDomainService` |
| 值对象 | `XxxId`, `XxxPeriod` | `DoctorId`, `TimePeriod` |
| 枚举 | `XxxEnum` | `UserTypeEnum` |
| 异常 | `XxxException` | `BizException` |
| 工具类 | `XxxUtils` | `DateUtils` |
| Converter | `XxxConverter` | `AppointmentConverter` |

### 2.2 方法命名

```java
// ✅ 正确：清晰表达业务含义
UserVO getUserById(Long id);
List<DoctorVO> listDoctorsByDeptId(Long deptId);
boolean checkApptAvailable(Long scheduleId);
void createAppointment(CreateAppointmentRequest request);
void updateApptStatus(Long apptId, ApptStatusEnum status);

// ❌ 错误：含义模糊
UserVO get(Long id);
List<DoctorVO> doctors();
void save(ApptCreateDTO dto);
```

### 2.3 变量命名

```java
// ✅ 清晰表达业务含义
private Long userId;
private String realName;
private LocalDateTime createdAt;
private boolean isDeleted;
private int totalSlots;
private int availableSlots;

// ❌ 缩写或拼音
private Long uid;
private String xm;
private Date ctime;
```

---

## 3. 分层代码模式

### 3.1 Controller 层

**职责**：
- 参数校验（`@Validated`）
- 调用 Service
- 返回 `R<T>` 响应

**模式**：
```
Controller → Request → Service → Response → R<T>
```

### 3.2 Service 层

**职责**：
- 业务逻辑编排
- 事务管理（`@Transactional`）
- 发布领域事件

**模式**：
```java
@Service
@RequiredArgsConstructor
@Slf4j
public class XxxApplicationService {

    private final XxxRepository repository;  // 使用接口
    private final DomainEventPublisher eventPublisher;

    @Transactional
    public ResultDTO execute(RequestDTO request) {
        // 1. 领域操作
        DomainEntity entity = repository.findById(id);

        // 2. 业务行为
        entity.doSomething();

        // 3. 持久化
        repository.save(entity);

        // 4. 发布事件
        eventPublisher.publish(new XxxEvent(entity));

        return converter.toDTO(entity);
    }
}
```

### 3.3 Domain 层

**职责**：
- 业务规则
- 领域状态变更
- 领域事件

**模式**：
```java
// 聚合根示例
public class Appointment {

    private AppointmentId id;
    private AppointmentNo appointmentNo;
    private UserId patientId;
    private AppointmentStatus status;

    public void pay() {
        if (!this.status.canPayment()) {
            throw new AppointmentException("当前状态不允许支付");
        }
        this.status = AppointmentStatus.CONFIRMED;
    }
}
```

### 3.4 Infra 层

**职责**：
- 技术实现
- 外部服务调用
- 数据持久化

**模式**：
```java
@Repository
public class AppointmentRepositoryImpl implements AppointmentRepository {

    private final AppointmentMapper mapper;
    private final AppointmentConverter converter;

    @Override
    public void save(Appointment appointment) {
        AppointmentDO dataObject = converter.toDO(appointment);
        mapper.insert(dataObject);
    }
}
```

---

## 4. 统一响应体

```java
// 响应包装器
R.ok(data)
R.fail(ErrorCode.NOT_FOUND)

// 业务异常
throw new BizException(ErrorCode.NOT_FOUND);
```

---

## 5. MapStruct 对象转换

使用 `XxxConverter` 在不同层对象间转换：
- DO ↔ Domain
- DO ↔ DTO/VO
- Request ↔ Domain

---

## 6. 枚举设计

```java
@Getter
@AllArgsConstructor
public enum XxxStatus {
    PENDING("待处理"),
    CONFIRMED("已确认"),
    CANCELLED("已取消");

    private final String description;

    public boolean canConfirm() {
        return this.equals(PENDING);
    }
}
```

---

## 7. 常量管理

```java
// Redis Key 常量
public interface RedisKeyConstant {
    String APPT_LOCK = "mediask:lock:appt:";
    String SCHEDULE_CACHE = "mediask:schedule:doctor:%s:%s";
}
```

---

## 8. 日志规范

```java
// ✅ 正确：结构化日志，关键信息占位符
log.info("创建挂号成功, apptNo={}, patientId={}", apptNo, patientId);
log.warn("库存不足, scheduleId={}", scheduleId);

// ❌ 错误：字符串拼接
log.info("创建成功 apptNo=" + apptNo);
```

---

## 9. 接口设计规范

### 9.1 幂等性

**需要幂等的场景**：
- 支付接口
- 订单创建
- 挂号预约
- 状态变更

**实现方式**：
- `@Idempotent` 注解（Redis 实现）
- 唯一业务键（数据库唯一约束）

### 9.2 限流

**实现方式**：
- `@RateLimiter` 注解
- Redisson 滑动窗口

### 9.3 版本管理

```java
// 路径版本（推荐）
@RequestMapping("/api/v1/appointments")

// 头版本
@GetMapping(value = "/appointments", headers = "API-Version=2.0")
```

### 9.4 接口安全

- 敏感参数加密传输
- 签名校验
- 限流防护

---

## 10. 代码审查 Checklist

### 基础规范
- [ ] 类命名符合规范（DO/DTO/VO 后缀）
- [ ] 方法命名清晰表达业务含义
- [ ] 变量命名无拼音、无缩写
- [ ] Controller 层只做参数校验和调用 Service
- [ ] Service 层包含事务注解
- [ ] 异常处理完整
- [ ] 日志输出包含 traceId 和关键业务参数
- [ ] 敏感数据加密存储

### 接口设计
- [ ] 核心接口实现幂等性保障
- [ ] 对外接口添加签名校验
- [ ] 高频接口配置限流策略
- [ ] 接口添加完整的 OpenAPI 注解
- [ ] 敏感参数加密传输
- [ ] 关键接口添加监控埋点

---

## 11. 参考实现

| 规范 | 参考代码 |
|------|----------|
| Controller 模式 | `mediask-api/src/.../controller/AppointmentController.java` |
| Service 模式 | `mediask-service/src/.../appointment/AppointmentApplicationService.java` |
| Domain 模式 | `mediask-domain/src/.../appointment/Appointment.java` |
| Repository 模式 | `mediask-infra/src/.../appointment/AppointmentRepositoryImpl.java` |
| Converter 模式 | `mediask-infra/src/.../appointment/AppointmentConverter.java` |
| 分布式锁 | `mediask-infra/src/.../lock/` |
