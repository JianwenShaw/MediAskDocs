# 日志格式示例

> 本文档收录日志格式示例与审计事件样例，主文档见 `../00-INDEX.md`

---

## 1. 应用日志（Application Log）

### 1.1 INFO 级别

```json
{"ts":"2026-02-13T22:00:00Z","level":"INFO","service":"mediask-api","env":"prod","request_id":"r-123","request_trace_id":"rt-001","trace_id":"t-abc","logger":"c.m.m.s.appointment.AppointmentService","msg":"预约创建成功","event":"appointment.create","appointment_id":10001,"doctor_id":201}
```

### 1.2 WARN 级别

```json
{"ts":"2026-02-13T22:00:01Z","level":"WARN","service":"mediask-api","env":"prod","request_id":"r-124","request_trace_id":"rt-002","trace_id":"t-def","logger":"c.m.m.i.redis.CacheService","msg":"缓存未命中，查询数据库","event":"cache.miss","cache":{"key_hash":"h:9f1a..."}}
```

### 1.3 ERROR 级别

```json
{"ts":"2026-02-13T22:00:02Z","level":"ERROR","service":"mediask-api","env":"prod","request_id":"r-125","request_trace_id":"rt-003","trace_id":"t-ghi","logger":"c.m.m.s.appointment.AppointmentService","msg":"预约创建失败","event":"appointment.create.fail","appointment_id":10002,"error":{"code":"APPOINTMENT_SLOT_FULL","msg":"该时段预约已满"},"exception.type":"BizException"}
```

---

## 2. 访问日志（Access Log）

```json
{"ts":"2026-02-13T22:00:00Z","level":"INFO","service":"mediask-api","env":"prod","request_id":"r-123","request_trace_id":"rt-001","trace_id":"t-abc","logger":"http.access","msg":"request completed","http":{"method":"GET","path":"/api/v1/schedules","status":200,"latency_ms":34},"client":{"ip":"203.0.113.10","ua":"Mozilla/5.0"},"user":{"id":100,"type":"patient"}}
```

---

## 3. 审计日志（Audit Log）

### 3.1 用户登录

```json
{"ts":"2026-02-13T22:00:00Z","level":"INFO","service":"mediask-api","env":"prod","request_id":"r-123","request_trace_id":"rt-001","trace_id":"t-abc","event":"auth.login","action":"USER_LOGIN","resource":{"type":"USER","id":"100"},"user":{"id":100,"role":"patient","department":"-"},"client":{"ip":"203.0.113.10","ua":"Mozilla/5.0"},"result":"success"}
```

### 3.2 角色分配

```json
{"ts":"2026-02-13T22:00:01Z","level":"INFO","service":"mediask-api","env":"prod","request_id":"r-124","request_trace_id":"rt-002","trace_id":"t-def","event":"audit_log","action":"ROLE_ASSIGN","resource":{"type":"USER","id":"200"},"user":{"id":1,"role":"admin","department":"管理"},"client":{"ip":"203.0.113.10","ua":"Mozilla/5.0"},"result":"success","old_value":"patient","new_value":"doctor"}
```

### 3.3 病历查看（脱敏）

```json
{"ts":"2026-02-13T22:00:02Z","level":"INFO","service":"mediask-api","env":"prod","request_id":"r-125","request_trace_id":"rt-003","trace_id":"t-ghi","event":"record.view","action":"MEDICAL_RECORD_VIEW","resource":{"type":"MEDICAL_RECORD","id":"MR-001"},"user":{"id":201,"role":"doctor","department":"内科"},"client":{"ip":"203.0.113.10","ua":"Mozilla/5.0"},"result":"success","note":"患者姓名、身份证号已脱敏"}
```

---

## 4. 安全日志（Security Log）

### 4.1 登录失败

```json
{"ts":"2026-02-13T22:00:00Z","level":"WARN","service":"mediask-api","env":"prod","request_id":"r-123","request_trace_id":"rt-001","trace_id":"t-abc","event":"auth.login_failed","action":"USER_LOGIN_FAILED","client":{"ip":"203.0.113.10","ua":"Mozilla/5.0"},"security":{"rule_id":"login_rate_limit","decision":"deny","reason":"密码错误（累计失败 3 次）"}}
```

### 4.2 权限不足

```json
{"ts":"2026-02-13T22:00:01Z","level":"WARN","service":"mediask-api","env":"prod","request_id":"r-124","request_trace_id":"rt-002","trace_id":"t-def","event":"authz.deny","action":"PATIENT_VIEW_ALL_RECORDS","resource":{"type":"MEDICAL_RECORD","id":"*"},"user":{"id":100,"role":"patient"},"client":{"ip":"203.0.113.10","ua":"Mozilla/5.0"},"security":{"rule_id":"rbac_deny","decision":"deny","reason":"患者角色无权限查看所有病历"}}
```

### 4.3 限流触发

```json
{"ts":"2026-02-13T22:00:02Z","level":"WARN","service":"mediask-api","env":"prod","request_id":"r-125","request_trace_id":"rt-003","trace_id":"t-ghi","event":"rate_limit.hit","action":"API_QUERY","resource":{"type":"API","path":"/api/v1/records"},"client":{"ip":"203.0.113.10","ua":"Python-urllib/3.10"},"security":{"rule_id":"api_rate_limit","decision":"deny","reason":"请求频率超限（> 100 req/min）"}}
```

---

## 5. MDC 上下文传播示例（口径示意）

> 说明：
> - `trace_id`：优先使用 SkyWalking 注入的 `tid`（启用 Agent 时自动存在）
> - `request_id/request_trace_id`：应用侧生成/透传，用于把 Java ↔ Python AI 服务等“非同一套 APM”的日志串起来

### 5.1 Controller 层（入口）

```java
@RestController
@RequestMapping("/api/v1/appointments")
public class AppointmentController {

    private static final Logger log = LoggerFactory.getLogger(AppointmentController.class);

    @PostMapping
    public R<AppointmentResponse> createAppointment(
            @RequestBody CreateAppointmentRequest request,
            @RequestHeader(value = "X-Request-Id", required = false) String requestId,
            @RequestHeader(value = "X-Trace-Id", required = false) String requestTraceId) {

        // MDC 已由 Filter 初始化（tid/traceId/requestId 等），此处直接使用
        log.info("创建预约请求，appointmentId={}", request.getAppointmentId());

        // 业务调用
        AppointmentResultDTO result = appointmentService.createAppointment(request);

        return R.ok(result);
    }
}
```

### 5.2 Filter 层（请求上下文初始化）

```java
@Component
public class RequestContextFilter extends OncePerRequestFilter {

    @Override
    protected void doFilterInternal(HttpServletRequest request,
                                    HttpServletResponse response,
                                    FilterChain filterChain) throws ServletException, IOException {

        // request_id：每个 HTTP 请求都要有（排障/审计用）
        String requestId = request.getHeader("X-Request-Id");
        if (requestId == null || requestId.isEmpty()) {
            requestId = UUID.randomUUID().toString().replace("-", "");
        }

        // request_trace_id：用于跨系统（如 Python AI 服务）对齐日志
        String requestTraceId = request.getHeader("X-Trace-Id");
        if (requestTraceId == null || requestTraceId.isEmpty()) {
            requestTraceId = "rt-" + requestId;
        }

        // 设置到 MDC
        MDC.put("requestId", requestId);
        MDC.put("traceId", requestTraceId);

        // 设置到响应头
        response.setHeader("X-Request-Id", requestId);
        response.setHeader("X-Trace-Id", requestTraceId);

        try {
            filterChain.doFilter(request, response);
        } finally {
            // 清理 MDC
            MDC.clear();
        }
    }
}
```

### 5.3 异步任务（MDC 传播）

```java
@Configuration
public class AsyncConfig implements AsyncConfigurer {

    @Override
    @Bean(name = "taskExecutor")
    public Executor getAsyncExecutor() {
        ThreadPoolTaskExecutor executor = new ThreadPoolTaskExecutor();
        executor.setCorePoolSize(4);
        executor.setMaxPoolSize(8);
        executor.setQueueCapacity(100);
        executor.setThreadNamePrefix("mediask-async-");
        // 设置 TaskDecorator 实现 MDC 传播
        executor.setTaskDecorator(new MdcTaskDecorator());
        executor.initialize();
        return executor;
    }
}

/**
 * MDC 传播装饰器
 */
public class MdcTaskDecorator implements TaskDecorator {

    @Override
    public Runnable decorate(Runnable runnable) {
        // 捕获当前线程的 MDC 上下文
        Map<String, String> contextMap = MDC.getCopyOfContextMap();

        return () -> {
            Map<String, String> previous = MDC.getCopyOfContextMap();
            try {
                if (contextMap != null) {
                    MDC.setContextMap(contextMap);
                }
                runnable.run();
            } finally {
                if (previous != null) {
                    MDC.setContextMap(previous);
                } else {
                    MDC.clear();
                }
            }
        };
    }
}
```
