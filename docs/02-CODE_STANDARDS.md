# 代码规范与工程最佳实践

> 本文档定义项目强制执行的代码规范、分层架构实践和示例代码

## 1. 包结构设计

### 1.1 mediask-dal 模块结构
```
mediask-dal/
├── src/main/java/me/jianwen/mediask/dal/
│   ├── entity/              # 实体类（DO - Data Object）
│   │   ├── UserDO.java
│   │   ├── DoctorDO.java
│   │   └── AppointmentDO.java
│   ├── mapper/              # MyBatis Mapper 接口
│   │   ├── UserMapper.java
│   │   └── DoctorMapper.java
│   ├── enums/               # 枚举类型（状态码、业务类型）
│   │   ├── UserTypeEnum.java
│   │   └── ApptStatusEnum.java
│   └── config/              # 数据源配置
│       └── DataSourceConfig.java
└── src/main/resources/
    └── mapper/              # MyBatis XML 映射文件
        ├── UserMapper.xml
        └── DoctorMapper.xml
```

### 1.2 mediask-application 模块结构
```
mediask-application/
├── service/                 # 业务服务接口
│   ├── UserService.java
│   └── AppointmentService.java
├── service/impl/            # 业务服务实现
│   ├── UserServiceImpl.java
│   └── AppointmentServiceImpl.java
├── dto/                     # 数据传输对象
│   ├── request/
│   │   ├── UserLoginDTO.java
│   │   └── ApptCreateDTO.java
│   └── response/
│       ├── UserInfoVO.java
│       └── ApptDetailVO.java
├── converter/               # 对象转换器 (MapStruct)
│   ├── UserConverter.java
│   └── AppointmentConverter.java
└── event/                   # 领域事件
    └── ApptCreatedEvent.java
```

## 2. 命名规范（强制执行）

### 2.1 类命名规范
| 类型 | 规范 | 示例 |
|------|------|------|
| **Entity (实体)** | `XxxDO` | `UserDO`, `AppointmentDO` |
| **DTO (传输对象)** | `XxxDTO` | `UserLoginDTO`, `ApptCreateDTO` |
| **VO (视图对象)** | `XxxVO` | `UserInfoVO`, `DoctorDetailVO` |
| **Mapper** | `XxxMapper` | `UserMapper`, `DoctorMapper` |
| **Service** | `XxxService` | `UserService`, `ApptService` |
| **ServiceImpl** | `XxxServiceImpl` | `UserServiceImpl` |
| **Controller** | `XxxController` | `UserController`, `ApptController` |
| **枚举** | `XxxEnum` | `UserTypeEnum`, `ApptStatusEnum` |
| **异常** | `XxxException` | `BizException`, `ApptNotFoundException` |
| **工具类** | `XxxUtil` 或 `XxxHelper` | `DateUtil`, `EncryptHelper` |

### 2.2 方法命名规范
```java
// ✅ 正确示例
public UserVO getUserById(Long id);
public List<DoctorVO> listDoctorsByDeptId(Long deptId);
public boolean checkApptAvailable(Long scheduleId);
public void createAppointment(ApptCreateDTO dto);
public void updateApptStatus(Long apptId, ApptStatusEnum status);
public void deleteUserById(Long id); // 物理删除
public void removeUserById(Long id); // 软删除

// ❌ 错误示例
public UserVO get(Long id);           // 不清晰
public List<DoctorVO> doctors();      // 缺少动词
public void save(ApptCreateDTO dto);  // save含义模糊（新增还是更新？）
```

### 2.3 变量命名规范
```java
// ✅ 正确：清晰表达业务含义
private Long userId;
private String realName;
private LocalDateTime createdAt;
private boolean isDeleted;
private int totalSlots;          // 总号源数
private int availableSlots;      // 剩余号源数

// ❌ 错误：缩写或拼音
private Long uid;
private String xm;               // 姓名拼音缩写
private Date ctime;
private boolean del;
private int num;
```

## 3. 分层代码示例

### 3.1 Controller 层（入口层）
```java
@RestController
@RequestMapping("/api/v1/appointments")
@Tag(name = "挂号预约", description = "挂号预约相关接口")
@RequiredArgsConstructor
public class AppointmentController {
    
    private final AppointmentService appointmentService;
    
    /**
     * 创建挂号预约
     * @param dto 预约信息
     * @return 预约单号
     */
    @PostMapping
    @Operation(summary = "创建挂号")
    @PreAuthorize("hasAuthority('appt:create')")
    public R<String> createAppointment(
            @Validated @RequestBody ApptCreateDTO dto) {
        String apptNo = appointmentService.createAppointment(dto);
        return R.ok(apptNo);
    }
    
    /**
     * 分页查询患者挂号记录
     * @param query 查询条件
     * @return 挂号列表
     */
    @GetMapping("/my")
    @Operation(summary = "我的挂号记录")
    public R<PageResult<ApptVO>> listMyAppointments(
            @Validated ApptQueryDTO query) {
        Long patientId = SecurityContextHolder.getUserId();
        PageResult<ApptVO> result = appointmentService
            .listPatientAppointments(patientId, query);
        return R.ok(result);
    }
}
```

### 3.2 Service 层（业务编排层）
```java
@Service
@RequiredArgsConstructor
@Slf4j
public class AppointmentServiceImpl implements AppointmentService {
    
    private final AppointmentMapper appointmentMapper;
    private final DoctorScheduleMapper scheduleMapper;
    private final RedisTemplate<String, Object> redisTemplate;
    private final ApplicationEventPublisher eventPublisher;
    private final SnowflakeIdWorker idWorker;
    
    @Override
    @Transactional(rollbackFor = Exception.class)
    public String createAppointment(ApptCreateDTO dto) {
        // 1. 参数校验（Service层二次校验关键业务逻辑）
        DoctorScheduleDO schedule = scheduleMapper.selectById(dto.getScheduleId());
        if (schedule == null || schedule.getAvailableSlots() <= 0) {
            throw new BizException(ErrorCode.APPT_NO_SLOTS);
        }
        
        // 2. 分布式锁扣减号源（防止超卖）
        String lockKey = RedisKeyConstant.APPT_LOCK + dto.getScheduleId();
        RLock lock = redissonClient.getLock(lockKey);
        try {
            if (!lock.tryLock(3, 10, TimeUnit.SECONDS)) {
                throw new BizException(ErrorCode.APPT_BUSY);
            }
            
            // 3. 扣减库存（乐观锁 + 数据库约束双重保障）
            int updated = scheduleMapper.decreaseSlots(dto.getScheduleId());
            if (updated == 0) {
                throw new BizException(ErrorCode.APPT_NO_SLOTS);
            }
            
            // 4. 生成预约单
            AppointmentDO appointment = AppointmentConverter.INSTANCE
                .toEntity(dto);
            appointment.setId(idWorker.nextId());
            appointment.setApptNo(generateApptNo());
            appointment.setApptStatus(ApptStatusEnum.UNPAID);
            appointmentMapper.insert(appointment);
            
            // 5. 发布领域事件（异步处理短信通知等）
            eventPublisher.publishEvent(new ApptCreatedEvent(appointment));
            
            log.info("创建挂号成功, apptNo={}, patientId={}", 
                appointment.getApptNo(), appointment.getPatientId());
            
            return appointment.getApptNo();
            
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            throw new SysException(ErrorCode.SYSTEM_ERROR);
        } finally {
            lock.unlock();
        }
    }
    
    /**
     * 生成预约单号：APT + yyyyMMdd + 6位递增序列
     */
    private String generateApptNo() {
        String dateStr = LocalDate.now().format(DateTimeFormatter.BASIC_ISO_DATE);
        String seqKey = RedisKeyConstant.APPT_SEQ + dateStr;
        Long seq = redisTemplate.opsForValue().increment(seqKey);
        if (seq == 1) {
            redisTemplate.expire(seqKey, 1, TimeUnit.DAYS);
        }
        return String.format("APT%s%06d", dateStr, seq);
    }
}
```

### 3.3 Mapper 层（数据访问层）
```java
/**
 * 挂号预约 Mapper
 * @author jianwen
 */
@Mapper
public interface AppointmentMapper extends BaseMapper<AppointmentDO> {
    
    /**
     * 查询患者挂号记录（支持分页）
     * @param patientId 患者ID
     * @param query 查询条件
     * @return 挂号列表
     */
    List<ApptVO> selectPatientAppointments(
        @Param("patientId") Long patientId,
        @Param("query") ApptQueryDTO query
    );
    
    /**
     * 统计医生今日挂号数
     * @param doctorId 医生ID
     * @param date 日期
     * @return 挂号数量
     */
    int countTodayAppointments(
        @Param("doctorId") Long doctorId,
        @Param("date") LocalDate date
    );
}
```

```xml
<!-- AppointmentMapper.xml -->
<mapper namespace="me.jianwen.mediask.dal.mapper.AppointmentMapper">
    
    <select id="selectPatientAppointments" 
            resultType="me.jianwen.mediask.application.dto.ApptVO">
        SELECT 
            a.id,
            a.appt_no,
            a.appt_date,
            a.appt_time,
            a.appt_status,
            d.real_name AS doctor_name,
            dept.dept_name,
            a.appt_fee
        FROM appointments a
        LEFT JOIN doctors doc ON a.doctor_id = doc.id
        LEFT JOIN users d ON doc.user_id = d.id
        LEFT JOIN departments dept ON doc.dept_id = dept.id
        WHERE a.patient_id = #{patientId}
          AND a.deleted_at IS NULL
        <if test="query.status != null">
          AND a.appt_status = #{query.status}
        </if>
        <if test="query.startDate != null">
          AND a.appt_date &gt;= #{query.startDate}
        </if>
        ORDER BY a.created_at DESC
    </select>
    
</mapper>
```

## 4. 统一响应体设计

```java
/**
 * 统一响应体
 * @param <T> 数据类型
 */
@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class R<T> implements Serializable {
    
    /** 业务码（0表示成功） */
    private Integer code;
    
    /** 提示信息 */
    private String msg;
    
    /** 响应数据 */
    private T data;
    
    /** 全链路追踪ID */
    private String traceId;
    
    /** 时间戳 */
    private Long timestamp;
    
    public static <T> R<T> ok(T data) {
        return R.<T>builder()
            .code(0)
            .msg("success")
            .data(data)
            .traceId(MDC.get("traceId"))
            .timestamp(System.currentTimeMillis())
            .build();
    }
    
    public static <T> R<T> fail(ErrorCode errorCode) {
        return R.<T>builder()
            .code(errorCode.getCode())
            .msg(errorCode.getMsg())
            .traceId(MDC.get("traceId"))
            .timestamp(System.currentTimeMillis())
            .build();
    }
}
```

## 5. 全局异常处理器

```java
@RestControllerAdvice
@Slf4j
public class GlobalExceptionHandler {
    
    /**
     * 业务异常
     */
    @ExceptionHandler(BizException.class)
    public R<Void> handleBizException(BizException e) {
        log.warn("业务异常: code={}, msg={}", e.getCode(), e.getMessage());
        return R.fail(e.getErrorCode());
    }
    
    /**
     * 参数校验异常
     */
    @ExceptionHandler(MethodArgumentNotValidException.class)
    public R<Void> handleValidException(MethodArgumentNotValidException e) {
        String errorMsg = e.getBindingResult().getFieldErrors().stream()
            .map(DefaultMessageSourceResolvable::getDefaultMessage)
            .collect(Collectors.joining(", "));
        log.warn("参数校验失败: {}", errorMsg);
        return R.<Void>builder()
            .code(ErrorCode.PARAM_ERROR.getCode())
            .msg(errorMsg)
            .build();
    }
    
    /**
     * 系统异常（隐藏细节）
     */
    @ExceptionHandler(Exception.class)
    public R<Void> handleException(Exception e) {
        log.error("系统异常", e);
        return R.fail(ErrorCode.SYSTEM_ERROR);
    }
}
```

## 6. MapStruct 对象转换

```java
@Mapper(componentModel = "spring")
public interface AppointmentConverter {
    
    AppointmentConverter INSTANCE = Mappers.getMapper(AppointmentConverter.class);
    
    /**
     * DTO -> Entity
     */
    @Mapping(target = "id", ignore = true)
    @Mapping(target = "createdAt", ignore = true)
    AppointmentDO toEntity(ApptCreateDTO dto);
    
    /**
     * Entity -> VO
     */
    @Mapping(source = "doctor.realName", target = "doctorName")
    ApptVO toVO(AppointmentDO entity);
}
```

## 7. 枚举设计规范

```java
@Getter
@AllArgsConstructor
public enum ApptStatusEnum {
    
    UNPAID(1, "待支付"),
    CONFIRMED(2, "已预约"),
    VISITED(3, "已就诊"),
    CANCELLED(4, "已取消"),
    ABSENT(5, "爽约");
    
    private final Integer code;
    private final String desc;
    
    public static ApptStatusEnum fromCode(Integer code) {
        return Arrays.stream(values())
            .filter(e -> e.getCode().equals(code))
            .findFirst()
            .orElseThrow(() -> new IllegalArgumentException("无效的状态码: " + code));
    }
}
```

## 8. 常量管理

```java
public interface RedisKeyConstant {
    
    /** 挂号分布式锁 */
    String APPT_LOCK = "mediask:lock:appt:";
    
    /** 挂号序列号 */
    String APPT_SEQ = "mediask:seq:appt:";
    
    /** 医生排班缓存 */
    String SCHEDULE_CACHE = "mediask:schedule:doctor:%s:%s";
    
    /** 过期时间 */
    long CACHE_EXPIRE_DAYS = 1;
}
```

## 9. 日志规范

```java
// ✅ 正确：结构化日志，关键信息占位符
log.info("创建挂号成功, apptNo={}, patientId={}, doctorId={}", 
    apptNo, patientId, doctorId);

log.warn("库存不足, scheduleId={}, availableSlots={}", 
    scheduleId, slots);

// ❌ 错误：字符串拼接，性能差
log.info("创建挂号成功, apptNo=" + apptNo + ", patientId=" + patientId);

// ❌ 错误：缺少上下文
log.info("创建成功");
```

## 10. 代码审查 Checklist

- [ ] 所有类命名符合规范（DO/DTO/VO后缀）
- [ ] 方法命名清晰表达业务含义
- [ ] 变量命名无拼音、无缩写
- [ ] Controller 层只做参数校验和调用 Service
- [ ] Service 层包含事务注解 `@Transactional`
- [ ] 异常处理完整（捕获并转换为业务异常）
- [ ] 日志输出包含 traceId 和关键业务参数
- [ ] 敏感数据（密码、身份证）加密存储
- [ ] 数据库查询使用索引字段
- [ ] 分页查询设置最大条数限制
