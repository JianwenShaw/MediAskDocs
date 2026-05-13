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
| GET | `/api/v1/ai/sessions` | 当前患者 AI 会话列表 | JWT |
| GET | `/api/v1/ai/sessions/{sessionId}` | 当前患者 AI 会话明细 | JWT |
| GET | `/api/v1/ai/sessions/{sessionId}/triage-result` | 当前患者最近一次 finalized 导诊结果 | JWT |
| POST | `/api/v1/admin/query-evaluations` | Admin dry-run 问诊评估 | JWT + `admin:triage-catalog:publish` |

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

### 4.1 `GET /api/v1/ai/sessions`

响应示例：

```json
{
  "code": 0,
  "msg": "ok",
  "timestamp": 1777612345678,
  "data": {
    "items": [
      {
        "sessionId": "82f7a4c2-7784-4d31-9c6e-6c8fbbe8c2cd",
        "sceneType": "AI_TRIAGE",
        "status": "COLLECTING",
        "departmentId": 101,
        "chiefComplaintSummary": "近两天持续头痛，伴恶心",
        "summary": "建议尽快门诊就诊",
        "startedAt": "2026-05-01T09:00:00Z",
        "endedAt": "2026-05-01T09:03:00Z"
      }
    ]
  }
}
```

### 4.2 `GET /api/v1/ai/sessions/{sessionId}`

响应示例：

```json
{
  "code": 0,
  "msg": "ok",
  "timestamp": 1777612345678,
  "data": {
    "sessionId": "82f7a4c2-7784-4d31-9c6e-6c8fbbe8c2cd",
    "sceneType": "AI_TRIAGE",
    "status": "COLLECTING",
    "departmentId": 101,
    "chiefComplaintSummary": "近两天持续头痛，伴恶心",
    "summary": "建议尽快门诊就诊",
    "startedAt": "2026-05-01T09:00:00Z",
    "endedAt": "2026-05-01T09:03:00Z",
    "turns": [
      {
        "turnId": "4b1eaf1f-3e28-479f-9fb5-f259db73507a",
        "turnNo": 1,
        "turnStatus": "COLLECTING",
        "startedAt": "2026-05-01T09:00:00Z",
        "completedAt": "2026-05-01T09:00:05Z",
        "errorCode": null,
        "errorMessage": null,
        "messages": [
          {
            "role": "user",
            "content": "我这两天一直头痛，还想吐",
            "createdAt": "2026-05-01T09:00:00Z"
          },
          {
            "role": "assistant",
            "content": "请问是否有肢体无力或说话含糊？",
            "createdAt": "2026-05-01T09:00:05Z"
          }
        ]
      }
    ]
  }
}
```

### 4.3 `GET /api/v1/ai/sessions/{sessionId}/triage-result`

响应示例：

```json
{
  "code": 0,
  "msg": "ok",
  "timestamp": 1777612345678,
  "data": {
    "sessionId": "82f7a4c2-7784-4d31-9c6e-6c8fbbe8c2cd",
    "resultStatus": "UPDATING",
    "triageStage": "READY",
    "riskLevel": "low",
    "guardrailAction": "allow",
    "nextAction": "VIEW_TRIAGE_RESULT",
    "finalizedTurnId": "4b1eaf1f-3e28-479f-9fb5-f259db73507a",
    "finalizedAt": "2026-05-01T09:03:00Z",
    "hasActiveCycle": true,
    "activeCycleTurnNo": 1,
    "chiefComplaintSummary": "近两天持续头痛，伴恶心",
    "recommendedDepartments": [
      {
        "departmentId": 101,
        "departmentName": "神经内科",
        "priority": 1,
        "reason": "头痛伴恶心，优先考虑神经系统相关问题"
      }
    ],
    "careAdvice": "建议尽快门诊就诊",
    "citations": [
      {
        "citationOrder": 1,
        "chunkId": "0aa7d1af-b4f9-4409-920d-31e81b1bb6ce",
        "snippet": "头痛伴恶心时应先排查神经系统相关疾病。"
      }
    ]
  }
}
```

补充约定：

- Java 继续负责把 Python snake_case DTO 映射为对前端暴露的 camelCase DTO
- `GET /api/v1/ai/sessions` 和 `GET /api/v1/ai/sessions/{sessionId}` 的摘要字段口径与 Python 保持一致：
  - 优先展示最近一次 finalized 结果摘要
  - 若从未 finalized，则回退到最新 collecting 摘要
- `GET /api/v1/ai/sessions/{sessionId}` 的 `messages[]` 直接反映 Python 持久化的历史消息

### 4.4 `POST /api/v1/admin/query-evaluations`

请求示例：

```json
{
  "hospitalScope": "default",
  "userMessage": "头痛三天，伴有低烧"
}
```

响应示例：

```json
{
  "code": 0,
  "msg": "ok",
  "timestamp": 1777612345678,
  "data": {
    "requestId": "req_01",
    "triageResult": {
      "triageStage": "READY",
      "triageCompletionReason": "SUFFICIENT_INFO",
      "nextAction": "VIEW_TRIAGE_RESULT",
      "riskLevel": "low",
      "chiefComplaintSummary": "头痛三天，伴有低烧",
      "recommendedDepartments": [
        {
          "departmentId": "101",
          "departmentName": "神经内科",
          "priority": 1,
          "reason": "头痛相关症状优先考虑神经内科"
        }
      ],
      "careAdvice": "建议尽快门诊就诊。",
      "catalogVersion": "deptcat-v20260423-01",
      "citations": []
    },
    "evaluation": {
      "finalized": true,
      "triageStage": "READY",
      "guardrailBlocked": false,
      "followUpQuestionCount": 0,
      "riskLevel": "low",
      "recommendedDepartmentCount": 1,
      "primaryDepartmentId": "101",
      "primaryDepartmentName": "神经内科",
      "citationCount": 0,
      "citationChunkIds": [],
      "retrievedChunkCount": 2,
      "modelInvoked": true,
      "inputTokens": 11,
      "outputTokens": 22,
      "totalTokens": 33,
      "durationMs": 24,
      "catalogVersion": "deptcat-v20260423-01",
      "kbId": "11111111-1111-1111-1111-111111111111",
      "indexVersionId": "22222222-2222-2222-2222-222222222222"
    }
  }
}
```

补充约定：

- 该接口只给管理端调试使用，不给患者前台直接调用。
- 前端不传 `scene`；Java 固定填 `AI_TRIAGE`。
- 前端和 Java 之间使用 camelCase；Java 与 Python 之间使用 snake_case。
- 该接口不创建真实 `session`，不写 `ai_turn`、`query_run`、`query_result_snapshot`。
- `evaluation` 是评估视图，不替代 `triageResult` 业务真相。
- 内部 triage 应用错误对前端统一返回 `6007`。

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
