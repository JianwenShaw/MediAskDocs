# 请求上下文与 MDC 落地设计

> 状态：Authoritative Baseline
>
> 适用阶段：P0 / P1
>
> 目标：统一 Java、Python、Nginx、日志、审计中的请求上下文命名与透传规则，避免 `traceId/requestTraceId/trace_id` 混用。

## 1. 定案

本轮重写把请求上下文命名收敛为一套更工程化的口径：

| 层 | 名称 | 说明 |
|----|------|------|
| HTTP Header | `X-Request-Id` | 唯一且标准的请求串联头，网关生成/透传，Java 与 Python 统一使用 |
| HTTP Header（兼容） | `X-Trace-Id` | 仅作为迁移期兼容别名；新实现不再主动发送 |
| 日志字段 | `request_id` | P0/P1 的主串联字段，所有 access/app/security/audit 日志都必须有 |
| 日志字段（P2） | `trace_id` | 仅在启用 APM 时使用，例如 SkyWalking `tid` |
| 日志字段（P2） | `span_id` | 仅在启用 APM 时使用 |
| MDC Key | `requestId` | 对应 `request_id` |
| MDC Key（P2） | `traceId` | 对应 `trace_id` |
| 响应头 | `X-Request-Id` | 对外回写，便于前端和测试环境定位 |
| 响应体字段 | `requestId` | 统一响应体中的请求标识 |

结论：

- `request_id` 是默认主键
- `trace_id` 不是默认主键，只是 P2 APM 扩展位
- `request_trace_id` 这个命名不再使用

## 2. 为什么这样收敛

- `request_id` 已经足够覆盖单体多实例 + Java ↔ Python 的链路串联
- 当前阶段不上 APM，继续把“应用侧串联 ID”命名成 `trace_id` 容易和真正的 tracing 系统混淆
- `request_trace_id` 语义模糊，既不像标准请求 ID，又不像真正的 trace ID，工程上最容易越用越乱

## 3. 请求上下文规则

### 3.1 入站 HTTP

入口网关或应用按如下优先级处理：

1. 如果存在 `X-Request-Id`，直接沿用
2. 如果不存在 `X-Request-Id`，但存在兼容头 `X-Trace-Id`，则把其值规范化为 `request_id`
3. 如果两者都不存在，生成新的 UUID/ULID 作为 `request_id`

同时：

- 回写响应头 `X-Request-Id`
- 写入 MDC：`requestId`
- 审计写库时写入 `request_id`

### 3.2 Java -> Python

Java 调 Python 时只透传：

- `X-Request-Id`
- `X-API-Key`

不再主动透传 `X-Trace-Id`。

### 3.3 Python -> Java

Python 响应头同样回写：

- `X-Request-Id`

### 3.4 P2 APM 扩展

如果后续启用 SkyWalking：

- `request_id` 仍保留并继续作为业务/审计串联主键
- `trace_id` 只用于 APM UI、Span、性能分析
- 日志中可以同时出现 `request_id` + `trace_id`

## 4. 推荐类名

| 场景 | 推荐类名 |
|------|---------|
| Servlet Filter | `RequestContextFilter` |
| 请求上下文常量 | `RequestContextConstants` |
| 出站 HTTP 透传 | `RequestContextPropagationInterceptor` |
| 线程池 MDC 传播 | `MdcTaskDecorator` |
| Python 中间件 | `RequestContextMiddleware` |

不再建议：

- `TraceIdFilter`
- `trace.py`
- `request_trace_id`

## 5. Nginx 入口示例

```nginx
map $http_x_request_id $request_id_header {
    default $http_x_request_id;
    ""      $http_x_trace_id;
}

map $request_id_header $mediask_request_id {
    default $request_id_header;
    ""      $request_id;
}

server {
    listen 80;

    location /api/ {
        proxy_pass http://java_backend;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header X-Request-Id $mediask_request_id;
    }
}
```

这意味着网关仍能兼容历史客户端传来的 `X-Trace-Id`，但新链路不再继续下游转发它。

## 6. Java Filter 示例

```java
@Component
public class RequestContextFilter extends OncePerRequestFilter {

    @Override
    protected void doFilterInternal(HttpServletRequest request,
                                    HttpServletResponse response,
                                    FilterChain filterChain)
            throws ServletException, IOException {

        String requestId = firstNonBlank(
                request.getHeader("X-Request-Id"),
                request.getHeader("X-Trace-Id"), // deprecated alias
                UUID.randomUUID().toString().replace("-", "")
        );

        MDC.put("requestId", requestId);
        MDC.put("requestUri", request.getRequestURI());

        response.setHeader("X-Request-Id", requestId);

        try {
            filterChain.doFilter(request, response);
        } finally {
            MDC.clear();
        }
    }

    private String firstNonBlank(String... values) {
        for (String value : values) {
            if (value != null && !value.isBlank()) {
                return value;
            }
        }
        return null;
    }
}
```

## 7. Java -> Python 透传示例

```java
@Component
public class RequestContextPropagationInterceptor implements ClientHttpRequestInterceptor {

    @Override
    public ClientHttpResponse intercept(HttpRequest request,
                                        byte[] body,
                                        ClientHttpRequestExecution execution) throws IOException {
        String requestId = MDC.get("requestId");
        if (requestId != null && !requestId.isBlank()) {
            request.getHeaders().set("X-Request-Id", requestId);
        }
        return execution.execute(request, body);
    }
}
```

## 8. 异步线程池 MDC 传播

```java
public class MdcTaskDecorator implements TaskDecorator {

    @Override
    public Runnable decorate(Runnable runnable) {
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

异步任务至少应保留：

- `requestId`
- `requestUri`（如有）
- `userId`（如已认证）

## 9. Python Middleware 示例

```python
from uuid import uuid4
from starlette.middleware.base import BaseHTTPMiddleware


class RequestContextMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request, call_next):
        request_id = (
            request.headers.get("X-Request-Id")
            or request.headers.get("X-Trace-Id")  # deprecated alias
            or uuid4().hex
        )

        request.state.request_id = request_id

        response = await call_next(request)
        response.headers["X-Request-Id"] = request_id
        return response
```

Python 结构化日志至少输出：

- `request_id`
- `service`
- `event`
- `latency_ms`

## 10. 响应体口径

统一响应体使用：

```json
{
  "code": 0,
  "msg": "success",
  "data": {},
  "requestId": "req_01hrx6m5q4x5v2f6k4w4x1c7pz",
  "timestamp": 1761234567890
}
```

说明：

- 对外返回 `requestId`，便于前端、测试与运维定位问题
- 不把 `trace_id` 当作 API 主契约字段

## 11. 迁移策略

### 11.1 兼容期

- 入站请求仍接受 `X-Trace-Id`
- Java / Python 内部统一归一化为 `request_id`
- 新代码、日志、文档不再生成 `request_trace_id`

### 11.2 完成期

- 所有内部调用统一只发 `X-Request-Id`
- 文档和代码中的 `TraceIdFilter` 全部替换为 `RequestContextFilter`
- `trace_id` 仅保留给 P2 APM

## 12. 一句话结论

P0/P1 只需要把 `X-Request-Id` / `request_id` 这一条主线打通，`trace_id` 留给以后真正的 APM。
