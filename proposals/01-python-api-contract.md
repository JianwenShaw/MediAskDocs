# Python API 合同冻结版

## 1. 文档定位

本文冻结 Python RAG 服务对外暴露的 HTTP API 合同，包括：

- 请求与响应格式
- SSE 事件结构
- `triage_result` 判别联合
- Python 状态机收口规则
- 失败契约与错误码

本文是 `00-interface-overview.md` 的子文档。三方职责与通信架构见总纲。

---

## 2. 端点

| 方法 | 路径 | 语义 |
|------|------|------|
| POST | `/api/v1/query` | 同步完整 query，返回 `triage_result` |
| POST | `/api/v1/query/stream` | 流式 SSE，事件驱动 |
| GET | `/api/v1/sessions` | 查询当前患者的 AI 会话摘要列表 |
| GET | `/api/v1/sessions/{session_id}` | 查询当前患者的 AI 会话明细 |
| GET | `/api/v1/sessions/{session_id}/triage-result` | 查询当前患者最近一次 finalized 导诊结果 |

不再使用旧 `/api/v1/chat`。

---

## 3. 通用请求头

- `Content-Type: application/json`
- `X-Request-Id: <string>`（由 Java 网关优先传入；若缺失 Python 生成并在响应中回传）
- `X-Patient-User-Id: <string>`（Java 透传当前登录患者的 `users.id`；query 和 sessions 接口都必传）

---

## 4. 请求体（两个端点一致）

```json
{
  "scene": "AI_TRIAGE",
  "session_id": null,
  "hospital_scope": "default",
  "user_message": "我这两天一直头痛，还想吐"
}
```

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `scene` | `string` | 是 | P0 固定 `AI_TRIAGE` |
| `session_id` | `string \| null` | 是 | 首轮传 `null`，后续轮次传回 Python 返回的 session_id |
| `hospital_scope` | `string` | 是 | 目录作用域 |
| `user_message` | `string` | 是 | 当前轮患者输入原文 |

约束：
- Python 不要求 Java 传 `catalog_version`，Python 自己从 Redis 读取
- 请求体不承载"预判的导诊状态"或"推荐科室候选"

---

## 5. 同步响应体

```json
{
  "request_id": "req_01",
  "session_id": "82f7a4c2-7784-4d31-9c6e-6c8fbbe8c2cd",
  "turn_id": "4b1eaf1f-3e28-479f-9fb5-f259db73507a",
  "query_run_id": "9e86fc63-15f1-44db-9c07-ef2e5911d69c",
  "triage_result": { /* 判别联合，见 §8 */ }
}
```

## 5A. 会话查询接口

### 5A.1 `GET /api/v1/sessions`

语义：

- 返回当前 `X-Patient-User-Id` 对应患者的 AI 会话摘要列表
- 按 `started_at DESC` 排序；同一时间按 `session_id DESC`
- 优先展示最近一次 finalized 结果摘要；若从未 finalized，则回退到最新 collecting snapshot

响应示例：

```json
{
  "items": [
    {
      "session_id": "82f7a4c2-7784-4d31-9c6e-6c8fbbe8c2cd",
      "scene": "AI_TRIAGE",
      "status": "COLLECTING",
      "department_id": 101,
      "chief_complaint_summary": "近两天持续头痛，伴恶心",
      "summary": "建议尽快门诊就诊",
      "started_at": "2026-05-01T09:00:00Z",
      "ended_at": "2026-05-01T09:03:00Z"
    }
  ]
}
```

字段约束：

- `scene` 当前固定 `AI_TRIAGE`
- `status` ∈ {`COLLECTING`, `READY`, `BLOCKED`, `CLOSED`}
- `department_id` 仅在最近一次 finalized 为 `READY` 时返回
- `summary` 优先取最近一次 finalized 的结果摘要；若无 finalized，则回退为最新 collecting 的 `chief_complaint_summary`

### 5A.2 `GET /api/v1/sessions/{session_id}`

语义：

- 返回当前患者的单个 AI 会话详情
- 顶层摘要字段与列表接口口径一致
- `turns[].messages[]` 直接反映 Python 落库的历史消息事实

响应示例：

```json
{
  "session_id": "82f7a4c2-7784-4d31-9c6e-6c8fbbe8c2cd",
  "scene": "AI_TRIAGE",
  "status": "COLLECTING",
  "department_id": 101,
  "chief_complaint_summary": "近两天持续头痛，伴恶心",
  "summary": "建议尽快门诊就诊",
  "started_at": "2026-05-01T09:00:00Z",
  "ended_at": "2026-05-01T09:03:00Z",
  "turns": [
    {
      "turn_id": "4b1eaf1f-3e28-479f-9fb5-f259db73507a",
      "turn_no": 1,
      "turn_status": "COLLECTING",
      "started_at": "2026-05-01T09:00:00Z",
      "completed_at": "2026-05-01T09:00:05Z",
      "error_code": null,
      "error_message": null,
      "messages": [
        {
          "role": "user",
          "content": "我这两天一直头痛，还想吐",
          "created_at": "2026-05-01T09:00:00Z"
        },
        {
          "role": "assistant",
          "content": "请问是否有肢体无力或说话含糊？",
          "created_at": "2026-05-01T09:00:05Z"
        }
      ]
    }
  ]
}
```

字段约束：

- `turn_status` 取该 turn 的最终阶段；若尚未写入 `stage_after`，则回退为 `stage_before`
- `messages[].role` 只允许 `user` 或 `assistant`
- 当前实现每轮最多返回 2 条消息：1 条用户消息 + 1 条助手消息
- `assistant` 消息规则：
  - `COLLECTING`：为本轮 follow-up questions 拼接后的历史文本
  - `READY`：为推荐结果提示 + `care_advice`
  - `BLOCKED`：为阻断提示 + `care_advice`

### 5A.3 `GET /api/v1/sessions/{session_id}/triage-result`

语义：

- 返回当前患者最近一次 finalized 导诊结果
- 若当前已有新一轮 cycle 在 `COLLECTING`，继续返回上一版 finalized 结果，并标记 `result_status = UPDATING`

响应示例：

```json
{
  "session_id": "82f7a4c2-7784-4d31-9c6e-6c8fbbe8c2cd",
  "result_status": "UPDATING",
  "triage_stage": "READY",
  "risk_level": "low",
  "guardrail_action": "allow",
  "next_action": "VIEW_TRIAGE_RESULT",
  "finalized_turn_id": "4b1eaf1f-3e28-479f-9fb5-f259db73507a",
  "finalized_at": "2026-05-01T09:03:00Z",
  "has_active_cycle": true,
  "active_cycle_turn_no": 1,
  "chief_complaint_summary": "近两天持续头痛，伴恶心",
  "recommended_departments": [
    {
      "department_id": 101,
      "department_name": "神经内科",
      "priority": 1,
      "reason": "头痛伴恶心，优先考虑神经系统相关问题"
    }
  ],
  "care_advice": "建议尽快门诊就诊",
  "citations": [
    {
      "citation_order": 1,
      "chunk_id": "0aa7d1af-b4f9-4409-920d-31e81b1bb6ce",
      "snippet": "头痛伴恶心时应先排查神经系统相关疾病。"
    }
  ],
  "blocked_reason": null,
  "catalog_version": "deptcat-v20260423-01"
}
```

字段约束：

- `result_status` ∈ {`CURRENT`, `UPDATING`}
- `triage_stage` 成功返回时只允许 `READY` 或 `BLOCKED`
- `guardrail_action` 当前实现只返回：
  - `allow`：`READY`
  - `refuse`：`BLOCKED`
- `active_cycle_turn_no` 仅在 `has_active_cycle = true` 时非空
- `blocked_reason` 仅在 `BLOCKED` 时非空
- `catalog_version` 仅在 `READY` 时非空

---

## 6. SSE 事件清单

| 事件 | 数据字段 | 说明 |
|------|----------|------|
| `start` | `request_id`, `session_id`, `turn_id`, `query_run_id` | 流开始 |
| `progress` | `step` | step ∈ {`guardrail_checked`, `catalog_loaded`, `triage_materials_ready`, `finalizing`} |
| `delta` | `text_delta` | 自然语言增量（仅用于展示，不可驱动业务状态） |
| `final` | `request_id`, `session_id`, `turn_id`, `query_run_id`, `triage_result` | **业务真相，唯一可驱动跳页** |
| `error` | `code`, `message` | 错误事件 |
| `done` | `{}` | 流结束 |

### 6.1 流式强约束

- 前端只能根据 `final` 事件跳页
- Java 透传 SSE 时，只以 `final` 中的 `triage_result` 作为业务真相
- `delta` 只用于展示自然语言
- Python 必须在服务端完整组装 DeepSeek JSON 后再生成 `final`
- Python 不得把 DeepSeek keep-alive 注释直接透给业务端

---

## 7. Java 承接规则

### 7.1 同步接口

| `triage_stage` | Java 行为 |
|----------------|-----------|
| `COLLECTING` | 不写 finalized snapshot，留在聊天页 |
| `READY` | 写 finalized snapshot，进入导诊结果页，允许挂号承接 |
| `BLOCKED` | 写 blocked snapshot，进入高风险结果页，禁止普通挂号承接 |

### 7.2 流式接口

- 只消费 `final` 事件里的 `triage_result`
- 不根据 `delta` 或 `progress` 修改业务状态

---

## 8. `triage_result` 判别联合

`triage_result` 必须是判别联合，不允许一个大而松散的可空对象。

### 8.1 `COLLECTING`

```json
{
  "triage_stage": "COLLECTING",
  "triage_completion_reason": null,
  "next_action": "CONTINUE_TRIAGE",
  "chief_complaint_summary": "近两天持续头痛，伴恶心",
  "follow_up_questions": ["请问是否有肢体无力或说话含糊？"]
}
```

字段约束：
- 必须有 `follow_up_questions`（最多 2 条）
- 不允许有 `recommended_departments`
- 不允许有 `blocked_reason`
- 不允许有 `care_advice`

### 8.2 `READY`

```json
{
  "triage_stage": "READY",
  "triage_completion_reason": "SUFFICIENT_INFO",
  "next_action": "VIEW_TRIAGE_RESULT",
  "risk_level": "low",
  "chief_complaint_summary": "近两天持续头痛，伴恶心",
  "recommended_departments": [
    {
      "department_id": 101,
      "department_name": "神经内科",
      "priority": 1,
      "reason": "头痛伴恶心，优先考虑神经系统相关问题"
    }
  ],
  "care_advice": "建议尽快门诊就诊",
  "catalog_version": "deptcat-v20260423-01",
  "citations": [
    {
      "citation_order": 1,
      "chunk_id": "0aa7d1af-b4f9-4409-920d-31e81b1bb6ce",
      "snippet": "头痛伴恶心时应先排查神经系统相关疾病。"
    }
  ]
}
```

字段约束：
- `triage_completion_reason` ∈ {`SUFFICIENT_INFO`, `MAX_TURNS_REACHED`}
- 必须有 `recommended_departments`（最多 3 条）
- 必须有 `catalog_version`

### 8.3 `BLOCKED`

```json
{
  "triage_stage": "BLOCKED",
  "triage_completion_reason": "HIGH_RISK_BLOCKED",
  "next_action": "MANUAL_SUPPORT",
  "risk_level": "high",
  "chief_complaint_summary": "患者表达明确自杀倾向",
  "recommended_departments": [],
  "care_advice": "请立即寻求线下紧急帮助或联系人工支持",
  "blocked_reason": "SELF_HARM_RISK",
  "citations": []
}
```

字段约束：
- 必须有 `blocked_reason`
- `recommended_departments` 固定为空数组
- 不要求 `catalog_version`

---

## 9. `recommended_departments` 合同

数组项字段固定为：

| 字段 | 类型 | 说明 |
|------|------|------|
| `department_id` | `int` | 科室 ID，必须存在于当前目录版本 |
| `department_name` | `string` | 科室名称，必须与目录中该 ID 严格一致 |
| `priority` | `int` | 优先级，从 1 开始递增 |
| `reason` | `string` | 推荐理由 |

约束：
- 最多 3 条
- `department_id` 必须属于当前 `catalog_version` 对应的目录
- `department_name` 必须与目录中该 `department_id` 严格匹配

---

## 10. `blocked_reason` 合同

P0 固定枚举：

- `SELF_HARM_RISK`
- `VIOLENCE_RISK`
- `CHEST_PAIN_RISK`
- `RESPIRATORY_DISTRESS_RISK`
- `STROKE_RISK`
- `SEIZURE_RISK`
- `SEVERE_BLEEDING_RISK`
- `ANAPHYLAXIS_RISK`
- `OTHER_EMERGENCY_RISK`

---

## 11. Python 状态机收口规则

### 11.1 执行顺序（固定）

1. 输入护栏检查
2. 读取 Redis 导诊目录
3. 调用 DeepSeek 获取 `triage_materials`
4. 本地 JSON 解析和 schema 校验
5. 目录内科室校验
6. 高风险后处理
7. 最大回合数强制收口
8. 映射为 `COLLECTING` / `READY` / `BLOCKED`
9. 组装最终 `triage_result`

### 11.2 状态转移规则

| 当前状态 | 触发条件 | 下一状态 | 是否 finalized |
|----------|----------|----------|----------------|
| `COLLECTING` | 命中高风险硬规则 | `BLOCKED` | 是 |
| `COLLECTING` | 关键信息不足，且未到上限 | `COLLECTING` | 否 |
| `COLLECTING` | 信息足够，方向稳定 | `READY` | 是 |
| `COLLECTING` | 到达最大患者回合，且无高风险 | `READY` | 是 |
| `READY` | 用户开始新一轮导诊 cycle | `COLLECTING` | 否 |
| `BLOCKED` | 用户开始新一轮导诊 cycle | `COLLECTING` | 否 |

### 11.3 强制规则

- 每个 active triage cycle 最多 5 个患者回合
- 第 5 个患者回合不得继续返回 `COLLECTING`
- 第 5 轮必须收口为 `BLOCKED`（高风险）或 `READY`（best-effort）

### 11.4 `triage_completion_reason` 语义

| 值 | 语义 |
|----|------|
| `SUFFICIENT_INFO` | 信息足够，正常收口 |
| `MAX_TURNS_REACHED` | 达到收集上限，被迫输出 best-effort |
| `HIGH_RISK_BLOCKED` | 命中高风险，阻断普通导诊 |

`COLLECTING` 时 `triage_completion_reason` 必须为 `null`。

---

## 12. 失败契约

以下情况 Python 直接返回失败，不向 Java 提交脏结果：

- DeepSeek 返回空 `content`
- DeepSeek JSON 无法解析
- DeepSeek JSON 校验失败
- 目录版本不存在
- 推荐科室不在目录中
- 流式 JSON 组装失败

### 12.1 HTTP 错误响应

```json
{
  "request_id": "req_01",
  "error": {
    "code": "TRIAGE_MODEL_SCHEMA_INVALID",
    "message": "model response schema invalid"
  }
}
```

### 12.2 P0 错误码

- `TRIAGE_REQUEST_INVALID`
- `TRIAGE_CATALOG_ACTIVE_VERSION_MISSING`
- `TRIAGE_CATALOG_VERSION_NOT_FOUND`
- `TRIAGE_CATALOG_DEPARTMENT_INVALID`
- `TRIAGE_MODEL_EMPTY_CONTENT`
- `TRIAGE_MODEL_INVALID_JSON`
- `TRIAGE_MODEL_SCHEMA_INVALID`
- `TRIAGE_STREAM_ASSEMBLY_FAILED`
- `TRIAGE_INTERNAL_ERROR`

### 12.3 会话查询接口补充错误

`GET /api/v1/sessions/{session_id}`：

- 当前患者无权访问该会话，或该会话不存在：返回 `404`

`GET /api/v1/sessions/{session_id}/triage-result`：

- 当前患者无权访问该会话，或该会话不存在：返回 `404`
- 从未产出过 finalized 结果：返回 `409`

无 finalized 结果时的错误响应示例：

```json
{
  "code": 6021,
  "msg": "triage result not ready",
  "requestId": "req_01",
  "timestamp": 1777612345678
}
```
