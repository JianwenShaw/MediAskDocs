# MdcTaskDecorator 设计文档

## 1. 概述

`MdcTaskDecorator` 是 MediAsk 项目中用于解决 **异步任务日志链路追踪** 的核心组件。

### 核心职责

将父线程的 MDC（Mapped Diagnostic Context）上下文（如 `traceId`、`requestUri`）传播到异步子线程，确保异步任务的日志能够关联到原始请求的链路追踪 ID。

---

## 2. 问题背景

### 2.1 MDC 原理

MDC（Mapped Diagnostic Context）是 SLF4J 提供的一种线程级别的日志上下文机制，基于 `ThreadLocal` 实现：

```
Thread A (主请求线程)
├── MDC {traceId: "abc123", requestUri: "/api/schedule"}
├── 日志输出: [abc123] 用户查询排班
└── 发起异步任务 → Thread B (异步线程)
    ├── MDC {}  ← 空！无法继承父线程上下文
    └── 日志输出: [] 排班结果生成完成  ← 丢失链路信息
```

### 2.2 业务场景

在 MediAsk 项目中，以下场景会产生异步任务：

| 场景 | 线程池 | 异步处理内容 |
|------|--------|--------------|
| 领域事件处理 | `eventTaskExecutor` | 异步发布、处理领域事件 |
| 排班求解计算 | `scheduleSolverExecutor` | 复杂排班算法的异步求解 |

这些异步任务的日志如果无法关联到原始请求的 `traceId`，将严重影响问题排查和链路追踪。

---

## 3. 解决方案

### 3.1 类设计

```java
public class MdcTaskDecorator implements TaskDecorator {

    @Override
    public Runnable decorate(Runnable runnable) {
        // 1. 获取当前线程（父线程）的 MDC 上下文副本
        Map<String, String> contextMap = MDC.getCopyOfContextMap();
        
        // 2. 返回包装后的任务，在子线程中恢复 MDC 上下文
        return () -> {
            try {
                // 3. 将父线程的 MDC 上下文设置到当前线程（子线程）
                if (contextMap != null) {
                    MDC.setContextMap(contextMap);
                }
                // 4. 执行实际任务
                runnable.run();
            } finally {
                // 5. 清理 MDC，避免内存泄漏和上下文污染
                MDC.clear();
            }
        };
    }
}
```

### 3.2 执行流程

```
┌─────────────────────────────────────────────────────────────────┐
│                        主请求线程                                │
│  TraceIdFilter: MDC.put("traceId", "abc123")                   │
│                              │                                  │
│                              ▼                                  │
│  Service 调用异步任务 executor.execute(task)                   │
└─────────────────────────────────────────────────────────────────┘
                               │
                               │ 传入 Runnable
                               ▼
┌─────────────────────────────────────────────────────────────────┐
│                    MdcTaskDecorator.decorate()                  │
│  1. MDC.getCopyOfContextMap() → {traceId: "abc123"}            │
│  2. 返回包装后的 Runnable                                      │
└─────────────────────────────────────────────────────────────────┘
                               │
                               ▼
┌─────────────────────────────────────────────────────────────────┐
│                      异步子线程执行                              │
│  包装Runnable执行:                                              │
│  1. MDC.setContextMap({traceId: "abc123"}) ← 恢复上下文        │
│  2. runnable.run() → 执行业务逻辑                               │
│  3. MDC.clear() → 清理上下文                                    │
└─────────────────────────────────────────────────────────────────┘
```

---

## 4. 配置使用

### 4.1 线程池配置

在 `AsyncConfig` 中为每个线程池配置 `MdcTaskDecorator`：

```java
@Bean(name = "eventTaskExecutor")
public Executor eventTaskExecutor() {
    ThreadPoolTaskExecutor executor = new ThreadPoolTaskExecutor();
    executor.setCorePoolSize(4);
    executor.setMaxPoolSize(8);
    executor.setQueueCapacity(100);
    executor.setThreadNamePrefix("event-");
    executor.setTaskDecorator(new MdcTaskDecorator());  // 关键配置
    executor.initialize();
    return executor;
}
```

### 4.2 配置的线程池

| Bean 名称 | 用途 | 线程名前缀 |
|-----------|------|-----------|
| `eventTaskExecutor` | 领域事件异步处理 | `event-` |
| `scheduleSolverExecutor` | 排班求解异步计算 | `schedule-solver-` |

---

## 5. MDC 上下文内容

### 5.1 上下文键

在 `CommonConstants` 中定义：

```java
public static final String MDC_TRACE_ID = "traceId";      // 链路追踪 ID
public static final String MDC_USER_ID = "userId";        // 用户 ID
public static final String MDC_REQUEST_URI = "requestUri"; // 请求 URI
```

### 5.2 上下文写入

`TraceIdFilter` 在请求入口处写入：

```java
MDC.put(CommonConstants.MDC_TRACE_ID, traceId);
MDC.put(CommonConstants.MDC_REQUEST_URI, request.getRequestURI());
// 可扩展：MDC.put(CommonConstants.MDC_USER_ID, userId);
```

---

## 6. 日志效果对比

### 6.1 未配置 MdcTaskDecorator

```
[http-nio-8080-exec-1] INFO  c.m.s.api.filter.TraceIdFilter   - 收到请求: /api/schedule/generate
[event-1] INFO  c.m.s.d.event.AppointmentEventListener    - 事件处理开始
[event-1] ERROR c.m.s.d.event.AppointmentEventListener    - 处理失败  ← 无法关联到原始请求
```

### 6.2 配置 MdcTaskDecorator 后

```
[http-nio-8080-exec-1] INFO  c.m.s.api.filter.TraceIdFilter   - 收到请求: /api/schedule/generate
[event-1] INFO  c.m.s.d.event.AppointmentEventListener    - [abc123] 事件处理开始
[event-1] ERROR c.m.s.d.event.AppointmentEventListener    - [abc123] 处理失败  ← 成功关联链路
```

---

## 7. 注意事项

### 7.1 必要性

- 任何使用独立线程池（`ThreadPoolTaskExecutor`）的异步任务，都需要配置 `MdcTaskDecorator`
- 使用 Spring `@Async` 注解时，如果使用默认线程池，也需要考虑配置

### 7.2 内存管理

- 在任务执行完毕后调用 `MDC.clear()` 清理上下文，避免：
  - 线程复用时上下文污染
  - 内存泄漏

### 7.3 嵌套异步

- 如果存在嵌套异步任务，`MdcTaskDecorator` 会自动级联传播（每次 `decorate` 都会捕获当前线程的 MDC）

---

## 8. 相关类索引

| 类名 | 职责 |
|------|------|
| `MdcTaskDecorator` | MDC 上下文传播装饰器 |
| `AsyncConfig` | 异步任务线程池配置 |
| `TraceIdFilter` | 请求入口，生成/读取 traceId 写入 MDC |
| `CommonConstants` | MDC 键常量定义 |
| `Result` | 响应封装，从 MDC 获取 traceId 返回 |

---

## 9. 参考资料

- [SLF4J MDC 官方文档](https://www.slf4j.org/manual.html#mdc)
- Spring `TaskDecorator` 接口文档
- `MediAskDocs/docs/16-LOGGING_DESIGN` - 日志设计文档
