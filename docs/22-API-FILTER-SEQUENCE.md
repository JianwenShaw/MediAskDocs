# 接口 Filter 与统一处理简化时序图

> 本图用于论文“接口与服务交互设计”小节，简化描述前端请求进入 Java 后端后，经过请求编号、跨域与认证、安全上下文、业务接口、统一响应和异常处理的大致流程。

```mermaid
sequenceDiagram
    autonumber
    participant FE as 前端
    participant F as Filter 链
    participant S as 安全上下文
    participant CTRL as Controller
    participant U as UseCase
    participant H as 统一响应/异常处理

    FE->>F: 发送 HTTP 请求
    F->>F: 读取或生成 requestId

    alt CORS 预检请求 OPTIONS
        F-->>FE: 直接返回预检响应
    else 普通业务请求
        F->>F: JWT 认证过滤器解析 Token

        alt 未登录或 Token 无效
            F->>H: 生成认证失败结果
            H-->>FE: 返回 401 + 统一错误响应
        else Token 有效
            F->>S: 写入当前用户身份
            S->>CTRL: 放行到业务接口
            CTRL->>U: 调用业务用例

            alt 业务处理成功
                U-->>CTRL: 返回业务数据
                CTRL->>H: 统一包装 Result
                H-->>FE: 返回成功响应
            else 无权限或业务异常
                U->>H: 抛出异常
                H-->>FE: 返回统一错误响应
            end
        end
    end

    F->>F: 记录请求状态和耗时
```

## 说明

- Filter 链中主要包含请求编号处理、CORS 处理和 JWT 认证处理。
- requestId 会写入请求上下文、日志上下文和响应头，便于定位一次完整请求。
- JWT 认证成功后，当前用户身份会写入 Spring Security 上下文。
- 控制器只负责接收请求和调用业务用例，统一响应和异常转换由全局处理机制完成。
- 未登录、无权限、参数错误和业务异常都会返回统一格式的 JSON 结果。
