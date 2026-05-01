# AI Triage Gateway Contract

> 状态：Authoritative Browser-Facing Contract
>
> 适用范围：患者 H5、`mediask-api`
>
> 本文件只描述当前 Java 已实现的最小 AI triage 网关契约。更高层的三方边界与 Python 合同以 `docs/proposals/` 为准。

## 1. 固定原则

- 浏览器只访问 `mediask-api`，不直连 Python。
- Java 对外同步接口统一返回 `Result<T>`。
- Java 对外 chat 入口固定为：
  - `POST /api/v1/ai/triage/query`
  - `POST /api/v1/ai/triage/query/stream`
- Java 固定向 Python 发送 `scene=AI_TRIAGE`，前端不传 `scene`。
- Java 调 Python 使用：
  - `POST /api/v1/query`
  - `POST /api/v1/query/stream`
- 业务真相只来自完整 `triage_result`。
- SSE 场景下，只有 `final` 事件可驱动业务状态；`delta` 只用于展示。
- Java 当前只保存 finalized 业务快照 `ai_triage_result`，不维护完整聊天历史主事实。

## 2. 当前已实现接口

| 接口 | 说明 | 认证 |
|------|------|------|
| `POST /api/v1/ai/triage/query` | 同步 triage query | 已登录 + `PATIENT` |
| `POST /api/v1/ai/triage/query/stream` | SSE 代理 | 已登录 + `PATIENT` |

当前未实现：

- `POST /api/v1/ai/chat`
- `GET /api/v1/ai/sessions`
- `GET /api/v1/ai/sessions/{sessionId}`
- `GET /api/v1/ai/sessions/{sessionId}/triage-result`
- `POST /api/v1/ai/sessions/{sessionId}/registration-handoff`
- `GET /api/v1/encounters/{encounterId}/ai-summary`

说明：

- Python 侧当前已经提供 `/api/v1/sessions*` 读取接口
- Java 网关后续可直接基于这些 Python 会话接口补齐浏览器侧 `/api/v1/ai/sessions*`
- 在 Java 网关补齐之前，本文件仍以当前 Java 已实现接口为准

## 3. 同步 Query

### 3.1 请求

`POST /api/v1/ai/triage/query`

请求体：

```json
{
  "sessionId": null,
  "hospitalScope": "default",
  "userMessage": "我这两天一直头痛，还想吐"
}
```

规则：

- `userMessage` 必填，空白时返回 `400 + 1002`
- `hospitalScope` 为空时，Java 默认使用 `"default"`
- `sessionId` 首轮传 `null`，后续透传上一轮返回的 `sessionId`

### 3.2 响应

响应包裹仍是 `Result<T>`，其中 `data` 为：

```json
{
  "requestId": "req_01",
  "sessionId": "82f7a4c2-7784-4d31-9c6e-6c8fbbe8c2cd",
  "turnId": "4b1eaf1f-3e28-479f-9fb5-f259db73507a",
  "queryRunId": "9e86fc63-15f1-44db-9c07-ef2e5911d69c",
  "triageResult": {
    "triageStage": "READY",
    "triageCompletionReason": "SUFFICIENT_INFO",
    "nextAction": "VIEW_TRIAGE_RESULT",
    "riskLevel": "low",
    "chiefComplaintSummary": "近两天持续头痛，伴恶心",
    "recommendedDepartments": [
      {
        "departmentId": "3101",
        "departmentName": "神经内科",
        "priority": 1,
        "reason": "头痛伴恶心，优先考虑神经系统相关问题"
      }
    ],
    "careAdvice": "建议尽快门诊就诊",
    "catalogVersion": "deptcat-v20260501-01",
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

说明：

- `requestId` 在 `Result` 包裹层和 `data.requestId` 中都会出现，二者一致
- `sessionId`、`turnId`、`queryRunId`、`departmentId`、`chunkId` 都按字符串返回
- 当前响应 DTO 不包含旧 `answer` 字段

## 4. `triageResult` 三态

### 4.1 `COLLECTING`

```json
{
  "triageStage": "COLLECTING",
  "triageCompletionReason": null,
  "nextAction": "CONTINUE_TRIAGE",
  "chiefComplaintSummary": "近两天持续头痛，伴恶心",
  "followUpQuestions": ["请问是否有肢体无力或说话含糊？"]
}
```

规则：

- `followUpQuestions` 最多 2 条
- 不返回 `recommendedDepartments`
- 不返回 `blockedReason`
- 不落 Java finalized 快照

### 4.2 `READY`

规则：

- `nextAction = VIEW_TRIAGE_RESULT`
- 必须有 `recommendedDepartments`
- 必须有 `catalogVersion`
- Java 会用已发布目录校验 `catalogVersion + departmentId + departmentName`
- 校验通过后写入 `ai_triage_result`

### 4.3 `BLOCKED`

规则：

- `riskLevel = high`
- 必须有 `blockedReason`
- `recommendedDepartments = []`
- Java 校验通过后写入 `ai_triage_result`

## 5. SSE Query

### 5.1 接口

`POST /api/v1/ai/triage/query/stream`

请求体与同步接口一致。

### 5.2 事件

Java 当前对外输出这些事件名：

- `start`
- `progress`
- `delta`
- `final`
- `error`
- `done`

### 5.3 Java 行为

- Java 从 Python 接收 `snake_case` 事件数据，但对前端统一输出 `camelCase`
- `start` 输出：`requestId`、`sessionId`、`turnId`、`queryRunId`
- `progress` 输出：`step`
- `delta` 输出：`textDelta`
- `final` 输出：与同步 query 的 `data` 结构一致，字段全部为 `camelCase`
- `error` 输出：`code`、`message`
- `done` 输出：`{}`
- 只有 `final` 事件可驱动业务状态；`delta` 只用于展示
- `final`：Java 先解析、校验、必要时落库，再向前端输出
- 如果 `final` 解析失败、目录校验失败或落库失败，Java 发出 `error` 事件并结束当前流

## 6. 持久化边界

Java 当前只保存 finalized 业务快照表 `ai_triage_result`，字段包括：

- `request_id`
- `session_id`
- `turn_id`
- `query_run_id`
- `hospital_scope`
- `triage_stage`
- `triage_completion_reason`
- `next_action`
- `risk_level`
- `chief_complaint_summary`
- `care_advice`
- `blocked_reason`
- `catalog_version`
- `recommended_departments_json`
- `citations_json`

当前不保存：

- 完整聊天消息历史
- Python 内部 `ai_session` / `ai_turn` / `query_run` 明细

## 7. 错误语义

- 未登录：`401 + 1001`
- 非患者角色：`403 + 2008`
- 请求参数非法：`400 + 1002`
- Python 不可用或本地缺少 `mediask.ai.base-url` / `mediask.ai.api-key`：`6001`
- Python 超时：`6002`
- Python 返回体、`final` 事件或目录校验不合法：`6003`

## 8. 一句话结论

当前 Java 已实现的是最小 AI triage 网关：同步 query + SSE proxy + finalized 快照承接，严格跟随 `docs/proposals` 的 `/query` 口径，不再走旧 `/api/v1/ai/chat` 模型。 
