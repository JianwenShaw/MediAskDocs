# Java 网关 API 合同冻结版

## 1. 文档定位

本文冻结 Frontend → Java 网关的 HTTP API 合同，包括：

- Gateway 端点定义
- 请求与响应格式
- SSE 透传规则
- 前端行为冻结

本文是 `00-interface-overview.md` 的子文档。三方职责与通信架构见总纲。

---

## 2. 端点

| 方法 | 路径 | 语义 | 认证 |
|------|------|------|------|
| POST | `/api/v1/ai/triage/query` | 同步 query | JWT |
| POST | `/api/v1/ai/triage/query/stream` | 流式 SSE 代理 | JWT |

---

## 3. 请求体

```json
{
  "session_id": null,
  "hospital_scope": "default",
  "user_message": "我这两天一直头痛"
}
```

- `scene` 不由前端传，Java 网关固定填 `AI_TRIAGE`

---

## 4. 同步响应

Java 将 Python 返回的 `triage_result` 封装进统一 `Result<T>` 响应。

---

## 5. SSE 流式

Java 透传 Python 的 SSE 事件（`start` / `progress` / `delta` / `final` / `error` / `done`），仅在收到 `final` 事件时执行持久化。

---

## 6. 前端行为冻结

前端动作只由 `triage_result.next_action` 驱动：

| `next_action` | 前端行为 |
|----------------|----------|
| `CONTINUE_TRIAGE` | 留在聊天页 |
| `VIEW_TRIAGE_RESULT` | 跳转导诊结果页 |
| `MANUAL_SUPPORT` | 跳转高风险人工支持页 |
| `EMERGENCY_OFFLINE` | 跳转紧急线下就医页 |

前端禁止：
- 从 `delta` 文本猜推荐科室或风险等级
- 在未收到 `final` 时提前跳页
