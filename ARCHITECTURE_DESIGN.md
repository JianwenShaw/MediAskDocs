# 智能医疗辅助问诊系统 - 技术选型与架构设计文档

## 1. 系统架构概览 (System Architecture)

本项目采用 **“适度微服务化” (Modular Monolith)** 的架构设计理念。在单体应用的基础上，通过模块化隔离业务逻辑，既保证了毕设开发的便捷性（易于部署、调试），又保留了向微服务演进的能力。

### 1.1 逻辑架构图
```mermaid
flowchart TB
    %% 样式定义
    classDef client fill:#e3f2fd,stroke:#1565c0,stroke-width:2px,color:#000
    classDef gateway fill:#fff8e1,stroke:#ff6f00,stroke-width:2px,color:#000
    classDef app fill:#e8f5e9,stroke:#2e7d32,stroke-width:2px,color:#000
    classDef infra fill:#f3e5f5,stroke:#7b1fa2,stroke-width:2px,color:#000
    classDef external fill:#ffebee,stroke:#c62828,stroke-width:2px,stroke-dasharray: 5 5,color:#000

    User((用户/医生))
    
    subgraph ClientLayer ["客户端层 (Frontend)"]
        Web["Web端 (React SPA)"]:::client
        H5["移动端 (H5)"]:::client
    end

    GW["Nginx 网关 (反向代理/SSL)"]:::gateway

    subgraph BackendLayer ["后端应用层 (Modular Monolith)"]
        direction TB
        API["mediask-api (Web入口)"]:::app
        Worker["mediask-worker (异步任务)"]:::app
        
        subgraph Modules ["核心业务模块 (Domain)"]
            Auth[认证授权]
            Appt[挂号预约]
            EMR[电子病历]
            AI[AI智能服务]
        end
    end

    subgraph InfraLayer ["基础设施与中间件 (Infrastructure)"]
        MySQL["MySQL 8.0<br/>(业务数据)"]:::infra
        Redis["Redis 7<br/>(缓存/锁)"]:::infra
        Milvus["Milvus<br/>(向量库)"]:::infra
        MQ["RocketMQ<br/>(消息队列)"]:::infra
    end

    subgraph StorageLayer ["文件存储 (Strategy Pattern)"]
        RustFS["RustFS<br/>(Dev环境)"]:::infra
        OSS["Aliyun OSS<br/>(Prod环境)"]:::infra
    end

    subgraph ExternalLayer ["外部服务 (3rd Party)"]
        DeepSeek["DeepSeek LLM API"]:::external
    end

    %% 链路关系
    User --> Web & H5
    Web & H5 -- "HTTPS / JSON" --> GW
    GW -- "负载均衡" --> API

    API -- "同步调用" --> Modules
    Worker -- "复用逻辑" --> Modules

    Modules -- "JDBC" --> MySQL
    Modules -- "Jedis" --> Redis
    Modules -- "gRPC" --> Milvus
    
    API -- "生产消息 (事务)" --> MQ
    MQ -- "消费消息" --> Worker

    Modules -.-> RustFS
    Modules -.-> OSS

    AI -- "HTTP / SSE流式" --> DeepSeek
```

## 2. 前端技术选型 (Frontend Stack)

采用目前工业界最主流的 **React 生态**，构建纯客户端渲染 (CSR) 的单页应用 (SPA)，彻底杜绝服务端渲染 (SSR) 可能带来的安全风险 (如 XSS) 和运维复杂度。

> 本项目的**管理员端 & 医生端**统一采用：React + React Router + Ant Design + Tailwind CSS。

### 2.1 多端形态选择（面向毕设：优先保证 AI 核心能力交付）

本系统的亮点与主要工作量在 **AI 能力（对话、RAG、评估、安全）**，因此端侧选型以“**降低前端不确定性、快速跑通闭环**”为第一原则。

**医生端 / 管理员端（Web）**
- 形态：Web SPA
- 技术栈：React + React Router + Ant Design + Tailwind CSS
- 原因：中后台页面复杂（表格/表单/权限），Web 生态成熟，开发效率高。

**患者端（优先：公众号内 H5 Web）**
- 形态：微信公众号菜单/图文入口打开 H5
- 技术栈：同 Web（React）以最大化复用 API SDK、鉴权、组件与工程化能力
- 原因：无需学习小程序体系即可在微信内完成演示与闭环，把主要时间投入到 AI 模块实现与质量。

**可选演进（Phase 2）：微信小程序**
- 当需要更强触达/订阅提醒/扫码入口时，可在后端 API 不变的前提下增加小程序端（可选 Taro/React）。

### 2.2 仓库组织建议（两端同仓：Monorepo）

当前已确定患者端采用“公众号内 H5（React）”，且医生/管理员端同为 Web 技术栈，因此建议将两端前端放在**同一个仓库**，以复用 API SDK、鉴权、类型定义与工程化配置，降低毕设实现风险。

推荐目录（示例）：

```text
mediask-fe/
  apps/
    admin-web/        # 医生端 + 管理员端（React + Antd + Tailwind）
    patient-h5/       # 公众号内 H5（React + Tailwind）
  packages/
    shared/           # 共享：API client、types、auth、utils、error codes
```

*   **渲染模式**: **SPA (Single Page Application)**
    *   所有页面渲染逻辑均在浏览器端执行，构建产物为纯静态 HTML/JS/CSS 文件。
    *   部署时直接托管于 **Nginx** 或对象存储，不涉及 Node.js 服务端运行时。
*   **核心框架**: **React 19** (利用 Concurrent Mode 优化体验)
*   **开发语言**: **TypeScript** (强类型约束，减少 Bug，利于后期维护)
*   **构建工具**: **Vite** (极速冷启动，秒级热更新，优于 Webpack)
*   **UI 组件库**: **Ant Design 6.0** (企业级中后台首选，内置大量医疗场景适用的表单/表格组件)
*   **状态管理**: **Zustand** (比 Redux 更轻量、现代，代码量少) 或 **React Query** (专门处理服务端状态，如挂号列表的缓存与自动刷新)
*   **路由管理**: **React Router v6**
*   **HTTP 客户端**: **Axios** (封装拦截器，统一处理 Token 和全局错误)
*   **样式方案**: **Tailwind CSS** (原子化 CSS，开发效率极高) 

## 3. 后端技术选型 (Backend Stack)

基于 **Java 21** 新特性构建高性能后端，摒弃过时技术。

*   **开发语言**: **Java 21** (使用 Record 类简化 DTO，使用 Virtual Threads 提升高并发 I/O 性能)
*   **核心框架**: **Spring Boot 3.2+** (原生支持 AOT 编译，启动更快)
*   **ORM 框架**: **MyBatis-Plus** (简化 CRUD) + **MyBatis-Plus-Join** (连表查询增强)
*   **AI 应用框架**: **Spring AI** 或 **LangChain4j** (统一的大模型接入层，支持流式对话 Streaming)
*   **工具库**: 
    *   **Lombok**: 消除样板代码。
    *   **MapStruct**: 高性能 Bean 属性拷贝 (优于 BeanUtils)。
    *   **Knife4j**: 生成美观的接口文档。 

## 4. 数据存储与中间件 (Data & Middleware)

### 4.1 数据库选型方案 (确切方案)

1.  **业务数据库: MySQL 8.0**
    *   **选型理由**: 
        *   **生态兼容性**: MyBatis-Plus 对 MySQL 的支持最完美，社区资源最丰富，遇到问题最容易解决。
        *   **事务稳定性**: InnoDB 引擎在处理挂号扣减库存等高并发事务时表现稳定，符合医疗系统对数据一致性的严苛要求。
    *   **规范**: 字符集统一使用 `utf8mb4`，主键使用 `Snowflake` 雪花算法生成 (BIGINT)。

2.  **向量数据库: Milvus 2.3+ (Standalone Mode)**
    *   **选型理由**: 
        *   **专业性**: 相比于 PgVector 插件，Milvus 是专为向量检索设计的云原生数据库，支持百亿级向量检索，在答辩时更能体现“架构设计的专业度”。
        *   **解耦**: 将 AI 知识库数据与业务数据物理隔离，互不影响性能。
    *   **部署**: 开发环境使用 Docker Compose 一键部署单机版。

### 4.2 文件存储方案 (环境隔离策略)
采用 **策略模式 (Strategy Pattern)** 实现文件服务的无缝切换。

*   **接口定义**: `FileStorageService { upload(File), getUrl(path) }`
*   **Dev 环境 (开发)**: 
    *   **实现类**: `RustFSStorageImpl` (模拟/本地)
    *   **方案**: 使用本地磁盘或轻量级文件服务 (RustFS) 存储文件，避免开发阶段消耗云存储费用，且离线可用。
*   **Prod 环境 (生产)**: 
    *   **实现类**: `AliyunOssStorageImpl`
    *   **方案**: 使用 **阿里云 OSS**。利用其 CDN 加速功能，提高病历图片和药品说明书的加载速度，同时保障数据持久性。
*   **实现技术**: 利用 Spring Boot 的 `@Profile("dev")` 和 `@Profile("prod")` 注解自动注入对应的 Bean。

### 4.3 缓存与中间件
*   **Redis 7**: 核心缓存。
    *   **Key 设计规范**: `app:module:id` (如 `mediask:appt:doctor:1001`)。
    *   **分布式锁**: Redisson。
*   **消息队列: RocketMQ 5.0+**
    *   **选型理由**: 
        *   **事务消息**: RocketMQ 独有的事务消息机制，能完美解决“挂号扣库存”与“发送通知”之间的最终一致性问题，比 RabbitMQ 更适合金融/医疗级业务。
        *   **削峰填谷**: 优秀的抗压能力，保护数据库不被瞬间流量打垮。
    *   **核心 Topic**: 
        *   `TOPIC_APPT_CREATE`: 挂号成功消息 (Tag: `SMS`, `STOCK`)。
        *   `TOPIC_RAG_PARSE`: 知识库文档解析任务。

## 5. 关键工程化实践 (Best Engineering Practices)

### 5.1 API 治理与交互规范 (API Governance)
*   **RESTful 设计**: 遵循资源导向设计 (GET/POST/PUT/DELETE)，URL 使用名词复数，版本化管理 (`/api/v1/...`)。
*   **统一响应体**: 封装 `R<T>` 对象，包含 `code` (业务码), `msg` (提示信息), `data` (载荷), `traceId` (全链路追踪ID)。
*   **接口文档**: 集成 **Knife4j 4.0** (OpenAPI 3)，要求所有 Controller/DTO 必须有 `@Schema` 注解，生产环境自动关闭文档以保障安全。

### 5.2 健壮的异常处理体系 (Robust Error Handling)
*   **异常分层**: 定义 `BizException` (业务逻辑错误) 与 `SysException` (系统级错误)。
*   **全局处理器**: 使用 `@RestControllerAdvice` 统一捕获异常。
    *   对于 `BizException`: 返回对应错误码和提示。
    *   对于 `Exception`: 返回 "系统繁忙"，并打印堆栈日志，**隐藏底层细节**防止泄露。
*   **错误码管理**: 使用枚举 `ErrorCode` 统一管理 (如 `USER_001`, `APPT_002`)，拒绝硬编码字符串。

### 5.3 高并发与异步编程 (Concurrency & Async)
*   **虚拟线程 (Virtual Threads)**: 
    *   启用 JDK 21 虚拟线程 (`spring.threads.virtual.enabled=true`) 处理高并发 I/O (特别是 AI 接口的 HTTP 调用)。
    *   **注意**: 确保使用 **MySQL Connector/J 8.0.33+** 驱动，以避免旧版驱动中 `synchronized` 导致的线程钉住 (Pinning) 问题。
*   **领域事件解耦**: 
    *   **进程内解耦**: 使用 **Spring Event** (`ApplicationEventPublisher`) 处理轻量级副作用 (如记录操作日志)。
    *   **跨进程解耦**: 使用 **RocketMQ** 将耗时任务 (如发送短信、RAG 文档解析) 投递给 `mediask-worker` 模块异步执行，确保 Web 接口毫秒级响应。
    *   *场景*: 挂号成功后 -> `rocketMQTemplate.convertAndSend("TOPIC_APPT", msg)` -> Worker 监听消费。
*   **AI 流式响应**: 使用 Spring MVC 标准的 **SseEmitter** 实现 SSE (Server-Sent Events)，配合前端 `fetch-event-source` 库处理断连重试，实现 ChatGPT 式的打字机体验。避免引入 WebFlux 增加技术栈复杂度。

### 5.4 可观测性与日志 (Observability)
*   **MDC 全链路追踪**: 在 Filter 层生成 `traceId` 放入 MDC (Mapped Diagnostic Context)，所有日志输出自动携带该 ID，串联一次请求的所有日志。
*   **AOP 操作日志**: 自定义 `@Log(module="挂号", action="取消")` 注解，自动记录操作人、IP、耗时、入参出参到数据库，用于审计。

### 5.5 代码质量与规范 (Code Quality)
*   **参数校验**: 严格使用 **JSR-303 (Hibernate Validator)**，配合分组校验 (`@Validated(AddGroup.class)`)，拒绝在 Service 层编写冗余的 `if (obj == null)`。
*   **对象转换**: 强制使用 **MapStruct** 替代 BeanUtils，在编译期生成类型安全的转换代码，性能无损耗。
*   **Git 提交规范**: 遵循 **Conventional Commits** (`feat:`, `fix:`, `docs:`)，保持提交历史清晰。

### 5.6 安全设计落地 (Security Implementation)
1.  **认证与鉴权**: Spring Security 6 + JWT，实现无状态认证与动态权限控制 (`@PreAuthorize`)。
2.  **敏感数据脱敏**: 基于 Jackson 自定义序列化器实现**注解式脱敏** (`@Sensitive(strategy = PHONE)`)，彻底解耦业务代码。
3.  **数据加密**: 密码使用 **BCrypt**，身份证号使用 **AES-128** 加密存储。
4.  **API 防护**: 引入 **Redis Lua 脚本** 实现滑动窗口限流；关键接口引入 `Idempotency-Key` 防止重放攻击。

## 6. 项目目录结构规范 (Maven Multi-Module)

本项目采用 **Maven 多模块 (Multi-Module)** 结构进行管理，遵循 **DDD (领域驱动设计)** 分层思想。

```mermaid
classDiagram
    direction TB
    
    class Root ["mediask-root (父工程)"] {
        +pom.xml : 统一依赖管理
    }

    class API ["mediask-api (接入层)"] {
        +Controller : Web接口
        +Filter : 安全过滤
        <<Deployable>>
    }

    class Worker ["mediask-worker (任务层)"] {
        +Job : 定时任务
        +Consumer : 消息消费
        <<Deployable>>
    }

    class Service ["mediask-service (业务服务层)"] {
        +Service : 业务编排
        +DTO : 数据传输对象
        +Event : 领域事件发布
    }

    class Domain ["mediask-domain (领域层)"] {
        +Entity : 核心实体
        +Repository : 仓储接口
        <<Core>>
    }

    class DAL ["mediask-dal (数据访问层)"] {
        +Mapper : MyBatis实现
        +Redis : 缓存实现
        +AIClient : 大模型客户端
        +FileStore : 文件存储实现
    }

    class Common ["mediask-common (通用层)"] {
        +Utils : 工具类
        +Result : 统一响应
        +Exception : 全局异常
    }

    %% 依赖关系
    Root --* API
    Root --* Worker
    Root --* Service
    Root --* Domain
    Root --* DAL
    Root --* Common

    API ..> Service : 依赖
    Worker ..> Service : 依赖
    Service ..> Domain : 依赖
    DAL ..|> Domain : 实现接口 (依赖倒置)
    DAL ..> Common : 依赖
    Domain ..> Common : 依赖
    Service ..> Common : 依赖
```

### 6.1 模块职责说明
*   **mediask-api**: 系统的**流量入口**，负责参数校验、身份认证，不包含复杂业务逻辑。
*   **mediask-worker**: 系统的**后台工人**，负责异步处理耗时任务，与 Web 流量物理隔离。
*   **mediask-service**: 系统的**大脑**，负责编排业务流程（如：先扣库存，再生成订单，最后发短信）。
*   **mediask-domain**: 系统的**心脏**，包含最纯粹的业务规则，不依赖任何第三方框架（POJO）。
*   **mediask-dal**: 系统的**四肢**，负责具体的技术实现（连数据库、连 Redis、连 AI）。

### 6.2 部署架构优势
*   **Web 模块独立扩展**: 当挂号流量激增时，只需增加 `mediask-api` 的容器实例数量。
*   **Job 模块隔离**: 繁重的定时任务 (如批量生成排班、RAG 知识库全量更新) 运行在独立进程 `mediask-worker` 中，不会阻塞 Web 接口的响应线程。

---

## 7. 代码规范与工程实践 (Code Standards & Best Practices)

### 7.1 包结构设计（以 mediask-dal 为例）

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

### 7.2 命名规范（强制执行）

#### 7.2.1 类命名规范
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

#### 7.2.2 方法命名规范
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

#### 7.2.3 变量命名规范
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

### 7.3 分层代码示例（典型CRUD流程）

#### 7.3.1 Controller 层（入口层）
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

#### 7.3.2 Service 层（业务编排层）
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

#### 7.3.3 Mapper 层（数据访问层）
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
<mapper namespace="me.jianwen.mediask.infrastructure.mapper.AppointmentMapper">
    
    <select id="selectPatientAppointments" resultType="me.jianwen.mediask.application.dto.ApptVO">
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

### 7.4 统一响应体设计
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

### 7.5 全局异常处理器
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

---

## 8. 配置管理最佳实践 (Configuration Management)

### 8.1 多环境配置结构
```
src/main/resources/
├── application.yml                    # 公共配置
├── application-dev.yml                # 开发环境
├── application-test.yml               # 测试环境
├── application-prod.yml               # 生产环境
├── logback-spring.xml                 # 日志配置
└── mapper/                            # MyBatis XML
```

### 8.2 application.yml 公共配置
```yaml
spring:
  application:
    name: mediask-api
  
  profiles:
    active: @spring.profiles.active@  # Maven Profile 注入
  
  # 虚拟线程配置（JDK 21）
  threads:
    virtual:
      enabled: true
  
  # Jackson 配置
  jackson:
    time-zone: GMT+8
    date-format: yyyy-MM-dd HH:mm:ss
    default-property-inclusion: non_null
    serialization:
      write-dates-as-timestamps: false

# MyBatis-Plus 配置
mybatis-plus:
  configuration:
    log-impl: org.apache.ibatis.logging.slf4j.Slf4jImpl
    map-underscore-to-camel-case: true
  global-config:
    db-config:
      logic-delete-field: deletedAt
      logic-delete-value: NOW()
      logic-not-delete-value: 'NULL'

# 接口文档配置
springdoc:
  api-docs:
    enabled: true
    path: /v3/api-docs
  swagger-ui:
    enabled: ${springdoc.swagger-ui.enabled:true}
    path: /swagger-ui.html

# 日志配置
logging:
  level:
    root: INFO
    me.jianwen.mediask: DEBUG
  pattern:
    console: "%d{yyyy-MM-dd HH:mm:ss} [%thread] %-5level [%X{traceId}] %logger{36} - %msg%n"
```

### 8.3 application-dev.yml 开发环境
```yaml
spring:
  datasource:
    url: jdbc:mysql://localhost:3306/mediask?useUnicode=true&characterEncoding=utf8mb4&serverTimezone=Asia/Shanghai
    username: root
    password: root
    driver-class-name: com.mysql.cj.jdbc.Driver
    hikari:
      maximum-pool-size: 10
      minimum-idle: 5
      connection-timeout: 30000
  
  data:
    redis:
      host: localhost
      port: 6379
      database: 0
      timeout: 3000ms
      lettuce:
        pool:
          max-active: 8
          max-idle: 8
          min-idle: 2

# 文件存储（开发环境使用本地）
file:
  storage:
    type: local
    local-path: /tmp/mediask/upload

# 接口文档（开发环境开启）
springdoc:
  swagger-ui:
    enabled: true

# AI模型配置
ai:
  deepseek:
    api-key: ${DEEPSEEK_API_KEY:sk-xxx}
    base-url: https://api.deepseek.com
    model: deepseek-chat
    timeout: 30s
```

### 8.4 application-prod.yml 生产环境
```yaml
spring:
  datasource:
    url: jdbc:mysql://${DB_HOST:mysql}:3306/mediask?useSSL=true
    username: ${DB_USER}
    password: ${DB_PASSWORD}
    hikari:
      maximum-pool-size: 50
      minimum-idle: 10
  
  data:
    redis:
      host: ${REDIS_HOST:redis}
      port: 6379
      password: ${REDIS_PASSWORD}

# 文件存储（生产环境使用OSS）
file:
  storage:
    type: oss
    oss:
      endpoint: ${OSS_ENDPOINT}
      access-key-id: ${OSS_ACCESS_KEY}
      access-key-secret: ${OSS_SECRET_KEY}
      bucket-name: mediask-prod

# 接口文档（生产环境关闭）
springdoc:
  swagger-ui:
    enabled: false

# 日志级别调整
logging:
  level:
    me.jianwen.mediask: INFO
```

### 8.5 敏感配置加密方案
使用 **Jasypt** 加密敏感配置：

```yaml
# pom.xml 添加依赖
<dependency>
    <groupId>com.github.ulisesbocchio</groupId>
    <artifactId>jasypt-spring-boot-starter</artifactId>
    <version>3.0.5</version>
</dependency>

# application.yml
jasypt:
  encryptor:
    password: ${JASYPT_PASSWORD}  # 环境变量传入密钥
    algorithm: PBEWithMD5AndDES

# 加密后的配置
spring:
  datasource:
    password: ENC(encryptedPassword)
```

---

## 9. DevOps 实践 (持续集成与部署)

### 9.1 Docker 部署方案

#### Dockerfile（多阶段构建优化镜像大小）
```dockerfile
# 构建阶段
FROM maven:3.9-eclipse-temurin-21 AS builder
WORKDIR /app
COPY pom.xml .
COPY mediask-*/pom.xml mediask-*/
RUN mvn dependency:go-offline

COPY . .
RUN mvn clean package -DskipTests -Pprod

# 运行阶段
FROM eclipse-temurin:21-jre-alpine
WORKDIR /app

# 创建非root用户
RUN addgroup -S spring && adduser -S spring -G spring
USER spring:spring

# 复制构建产物
COPY --from=builder /app/mediask-api/target/mediask-api.jar app.jar

# 健康检查
HEALTHCHECK --interval=30s --timeout=3s --retries=3 \
  CMD wget -q --spider http://localhost:8080/actuator/health || exit 1

EXPOSE 8080
ENTRYPOINT ["java", \
  "-Xms512m", "-Xmx1024m", \
  "-XX:+UseZGC", \
  "-Dspring.profiles.active=prod", \
  "-jar", "app.jar"]
```

#### docker-compose.yml（本地开发环境）
```yaml
version: '3.8'

services:
  mysql:
    image: mysql:8.0
    environment:
      MYSQL_ROOT_PASSWORD: root
      MYSQL_DATABASE: mediask
    ports:
      - "3306:3306"
    volumes:
      - mysql-data:/var/lib/mysql
      - ./init.sql:/docker-entrypoint-initdb.d/init.sql
    command: --default-authentication-plugin=mysql_native_password

  redis:
    image: redis:7-alpine
    ports:
      - "6379:6379"
    volumes:
      - redis-data:/data

  milvus:
    image: milvusdb/milvus:v2.3.3
    ports:
      - "19530:19530"
    environment:
      ETCD_ENDPOINTS: etcd:2379
      MINIO_ADDRESS: minio:9000
    depends_on:
      - etcd
      - minio

  mediask-api:
    build: .
    ports:
      - "8080:8080"
    environment:
      SPRING_PROFILES_ACTIVE: dev
      DB_HOST: mysql
      REDIS_HOST: redis
    depends_on:
      - mysql
      - redis

volumes:
  mysql-data:
  redis-data:
```

### 9.2 CI/CD 流程（GitHub Actions）

```yaml
# .github/workflows/deploy.yml
name: Deploy to Production

on:
  push:
    branches: [ main ]

jobs:
  build-and-deploy:
    runs-on: ubuntu-latest
    
    steps:
      - uses: actions/checkout@v3
      
      - name: Set up JDK 21
        uses: actions/setup-java@v3
        with:
          java-version: '21'
          distribution: 'temurin'
          cache: 'maven'
      
      - name: Run Tests
        run: mvn test
      
      - name: Build with Maven
        run: mvn clean package -DskipTests -Pprod
      
      - name: Build Docker Image
        run: |
          docker build -t mediask-api:${{ github.sha }} .
          docker tag mediask-api:${{ github.sha }} mediask-api:latest
      
      - name: Push to Registry
        run: |
          echo ${{ secrets.DOCKER_PASSWORD }} | docker login -u ${{ secrets.DOCKER_USERNAME }} --password-stdin
          docker push mediask-api:latest
      
      - name: Deploy to Server
        uses: appleboy/ssh-action@master
        with:
          host: ${{ secrets.SERVER_HOST }}
          username: ${{ secrets.SERVER_USER }}
          key: ${{ secrets.SSH_PRIVATE_KEY }}
          script: |
            cd /app/mediask
            docker-compose pull
            docker-compose up -d --force-recreate
```

### 9.3 监控与日志

#### 9.3.1 Spring Boot Actuator 配置
```yaml
management:
  endpoints:
    web:
      exposure:
        include: health,info,metrics,prometheus
  endpoint:
    health:
      show-details: always
  metrics:
    tags:
      application: ${spring.application.name}
```

#### 9.3.2 Prometheus 监控指标暴露
```yaml
# docker-compose.yml 增加 Prometheus
prometheus:
  image: prom/prometheus
  ports:
    - "9090:9090"
  volumes:
    - ./prometheus.yml:/etc/prometheus/prometheus.yml

# prometheus.yml
scrape_configs:
  - job_name: 'mediask-api'
    metrics_path: '/actuator/prometheus'
    static_configs:
      - targets: ['mediask-api:8080']
```

---

## 10. 测试策略 (Testing Strategy)

### 10.1 单元测试（JUnit 5 + Mockito）
```java
@ExtendWith(MockitoExtension.class)
class AppointmentServiceTest {
    
    @Mock
    private AppointmentMapper appointmentMapper;
    
    @Mock
    private DoctorScheduleMapper scheduleMapper;
    
    @InjectMocks
    private AppointmentServiceImpl appointmentService;
    
    @Test
    @DisplayName("创建挂号成功")
    void testCreateAppointment_Success() {
        // Given
        ApptCreateDTO dto = new ApptCreateDTO();
        dto.setScheduleId(1L);
        dto.setPatientId(100L);
        
        DoctorScheduleDO schedule = new DoctorScheduleDO();
        schedule.setAvailableSlots(10);
        when(scheduleMapper.selectById(1L)).thenReturn(schedule);
        when(scheduleMapper.decreaseSlots(1L)).thenReturn(1);
        
        // When
        String apptNo = appointmentService.createAppointment(dto);
        
        // Then
        assertNotNull(apptNo);
        assertTrue(apptNo.startsWith("APT"));
        verify(appointmentMapper, times(1)).insert(any());
    }
    
    @Test
    @DisplayName("号源不足抛出异常")
    void testCreateAppointment_NoSlots() {
        // Given
        ApptCreateDTO dto = new ApptCreateDTO();
        dto.setScheduleId(1L);
        
        DoctorScheduleDO schedule = new DoctorScheduleDO();
        schedule.setAvailableSlots(0);
        when(scheduleMapper.selectById(1L)).thenReturn(schedule);
        
        // When & Then
        assertThrows(BizException.class, 
            () -> appointmentService.createAppointment(dto));
    }
}
```

### 10.2 集成测试（TestContainers）
```java
@SpringBootTest
@Testcontainers
class AppointmentIntegrationTest {
    
    @Container
    static MySQLContainer<?> mysql = new MySQLContainer<>("mysql:8.0")
        .withDatabaseName("mediask_test")
        .withUsername("test")
        .withPassword("test");
    
    @Autowired
    private AppointmentService appointmentService;
    
    @Test
    void testCreateAndQueryAppointment() {
        // 创建挂号
        ApptCreateDTO dto = new ApptCreateDTO();
        String apptNo = appointmentService.createAppointment(dto);
        
        // 查询验证
        ApptVO appt = appointmentService.getByApptNo(apptNo);
        assertEquals(apptNo, appt.getApptNo());
    }
}
```

### 10.3 性能测试（JMeter 压测计划）
```xml
<!-- 挂号接口压测：1000并发，持续5分钟 -->
<ThreadGroup>
  <stringProp name="ThreadGroup.num_threads">1000</stringProp>
  <stringProp name="ThreadGroup.ramp_time">60</stringProp>
  <stringProp name="ThreadGroup.duration">300</stringProp>
</ThreadGroup>
```

**预期指标**：
- **TPS**: ≥ 500/s
- **响应时间**: P99 < 500ms
- **错误率**: < 0.1%