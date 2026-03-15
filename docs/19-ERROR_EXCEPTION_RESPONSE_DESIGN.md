# 错误码、异常与统一响应设计说明

> 状态：Target Design
>
> 适用范围：`mediask-api`、`mediask-common`、`mediask-application`、`mediask-infrastructure`、`mediask-ai`
>
> 目的：冻结 Java 对外协议、Java/Python 服务间错误语义和 `request_id` 串联口径。

## 1. 设计目标

本项目当前阶段最重要的不是做复杂错误治理平台，而是先保证：

1. 前后端看到的是同一套错误语义
2. Java 与 Python 能用同一条 `request_id` 串起来
3. 成功/失败响应格式稳定，便于联调与答辩展示
4. 异常分层清晰，不把所有问题都压成“系统异常”

## 2. 对外统一响应契约（Java）

Java 对浏览器/前端暴露的所有 HTTP 接口，统一使用 `Result<T>`：

```json
{
  "code": 0,
  "msg": "success",
  "data": {},
  "requestId": "req_01hrx6m5q4x5v2f6k4w4x1c7pz",
  "timestamp": 1761234567890
}
```

字段定义：

| 字段 | 类型 | 说明 |
|------|------|------|
| `code` | int | 业务码；`0` 成功，非 `0` 失败 |
| `msg` | string | 人类可读提示 |
| `data` | any | 业务数据；失败时可为 `null` |
| `requestId` | string | 请求标识，必须稳定返回 |
| `timestamp` | long | Unix 毫秒时间戳 |

冻结规则：

- 不再使用 `message` 作为统一字段名
- 不再使用 HTTP `200/500` 作为业务成功/失败码语义
- 前端判断成功与否只看 `code`，不看 `msg`

## 3. HTTP 状态码与业务码的关系

| 场景 | HTTP 状态码 | `code` |
|------|-------------|--------|
| 正常成功 | `200` | `0` |
| 参数错误 | `400` | `1xxx` |
| 未认证 | `401` | `1001` 等认证码 |
| 无权限 | `403` | `1003` 等授权码 |
| 资源不存在 | `404` | 对应业务域错误码 |
| 业务冲突 | `409` | 对应业务域错误码 |
| 系统故障 | `500` | `9xxx` |

结论：**HTTP 状态码表达协议层结果，`code` 表达业务语义。**

## 4. 错误码分段

| 范围 | 领域 |
|------|------|
| `0` | 成功 |
| `1xxx` | 通用/公共（参数、认证、授权、限流等） |
| `2xxx` | 用户上下文 |
| `3xxx` | 门诊挂号上下文 |
| `4xxx` | 诊疗上下文 |
| `5xxx` | 排班上下文 |
| `6xxx` | AI 问诊上下文 |
| `9xxx` | 系统级兜底 |

## 5. 异常分层

### 5.1 Java

| 异常类型 | 用途 | 典型场景 |
|----------|------|----------|
| `BizException` | 可预期的业务失败 | 状态机不允许、资源不存在、重复提交、数据范围不允许 |
| `SysException` | 不可预期的系统故障 | 数据库不可用、Redis/RPC 超时、序列化故障 |
| `GlobalExceptionHandler` | 统一映射异常到 `Result<T>` | 控制器外统一兜底 |

使用原则：

- 业务规则失败抛 `BizException`
- 技术故障抛 `SysException` 或让框架异常统一映射
- Controller 不手写失败响应，统一交给异常处理器

### 5.2 Python AI 服务

Python 是内部服务，不强制成功响应也套 `Result<T>`；但失败响应必须统一字段：

```json
{
  "code": 6001,
  "msg": "AI service unavailable",
  "requestId": "req_01hrx6m5q4x5v2f6k4w4x1c7pz",
  "timestamp": 1761234567890
}
```

冻结规则：

- Java 调 Python 时，优先透传/信任 Python 返回的 `code`、`msg`、`requestId`
- Python 成功响应使用端点专属 DTO，不强制再包一层 `Result<T>`
- Python 失败码固定落在 `6xxx` 或 `9xxx`

## 6. `request_id` 规范

### 6.1 Header 约定

- Header 名固定为 `X-Request-Id`
- 若客户端未传入，网关或应用入口生成
- 兼容旧头 `X-Trace-Id`，但内部统一收敛为 `request_id`

### 6.2 透传规则

| 路径 | 规则 |
|------|------|
| Client -> Java | 读取或生成 `X-Request-Id` |
| Java -> Python | 原值透传 `X-Request-Id` |
| Python -> Java | 响应头回写 `X-Request-Id` |
| Java -> Client | 响应头与响应体都返回 `requestId` |
| Logs / Audit | 统一落 `request_id` |

### 6.3 为什么必须统一

如果入口、日志、响应、审计各自使用不同 ID，会直接导致：

- 流式对话难排障
- Java/Python 故障无法串联
- 审计与业务日志无法对齐

因此 `request_id` 是 P0 必须冻结的基础协议。

## 7. Java 与 Python 的边界约定

### 7.1 Java 对外

- 所有浏览器接口统一使用 `Result<T>`
- AI SSE 也由 Java 对外暴露，再转发 Python 内部流
- 不把 Python 的内部异常原样泄露给前端

### 7.2 Java 调 Python

- 成功：按端点 DTO 解析
- 失败：按统一失败结构解析
- 网络异常、超时、反序列化失败：Java 映射为 `6001/6002/6003/9999` 等统一码

### 7.3 Python 对 Java

- 成功：返回 `answer/citations/risk_level/...` 等端点专属结构
- 失败：返回统一错误结构
- 所有响应头回写 `X-Request-Id`

## 8. 推荐错误码示例

| 场景 | 推荐 code |
|------|-----------|
| 参数非法 | `1002` |
| 未认证 | `1001` |
| 无权限 | `1003` |
| 挂号资源不存在 | `3004` |
| 病历无查看权限 | `4003` |
| AI 服务不可用 | `6001` |
| AI 超时 | `6002` |
| AI 响应异常 | `6003` |
| 系统兜底 | `9999` |

实际枚举值可以继续细化，但分段口径不能再变。

## 9. P0 最少测试场景

1. 无 `X-Request-Id` 时自动生成并回写
2. 有 `X-Request-Id` 时保持原值透传
3. 参数校验失败返回 `400 + 1xxx`
4. 业务异常返回对应业务码，不落入 `9999`
5. Python 超时/故障时，Java 能映射成稳定错误码
6. 401/403 场景响应体仍包含 `requestId`
7. SSE 异常结束时仍能通过 `request_id` 串到日志

## 10. 当前阶段不做什么

以下内容不作为当前优先事项：

- 国际化错误消息平台
- 自动生成错误码注册中心与 CI 校验
- 多语言前端消息模板
- 对每个接口写完整错误码矩阵

这些都可以留到 P1/P2，再做不会影响主链路。

## 11. 一句话结论

当前阶段只需要先把三件事定死：**对外统一 `Result<T>`、成功码固定为 `0`、`request_id` 贯穿 Java/Python/审计。** 这比继续扩充错误治理设计更重要。
