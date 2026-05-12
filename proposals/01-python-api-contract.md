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
| POST | `/api/v1/admin/query-evaluations` | Admin dry-run 问诊评估，返回 `triage_result + evaluation` |
| GET | `/api/v1/sessions` | 查询当前患者的 AI 会话摘要列表 |
| GET | `/api/v1/sessions/{session_id}` | 查询当前患者的 AI 会话明细 |
| GET | `/api/v1/sessions/{session_id}/triage-result` | 查询当前患者最近一次 finalized 导诊结果 |

不再使用旧 `/api/v1/chat`。

---

## 3. 通用请求头

- `Content-Type: application/json`
- `X-Request-Id: <string>`（由 Java 网关优先传入；若缺失 Python 生成并在响应中回传）
- `X-Patient-User-Id: <string>`（Java 透传当前登录患者的 `users.id`；query 和 sessions 接口都必传）

Admin 接口补充：

- `X-Actor-Id: <string>`（当前操作人；admin 接口必传）
- `X-Hospital-Scope: <string>`（当前管理侧医院作用域；admin 接口必传）

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

## 5B. Admin Dry-Run 问诊评估接口

### 5B.1 `POST /api/v1/admin/query-evaluations`

语义：

- 这是内部 Admin 调试接口，不给患者前台直接调用
- 接口会实时执行一次完整的干跑问诊评估：护栏检查、目录加载、知识检索、模型调用、`triage_result` 组装
- 不创建真实 `session`，不写 `ai_turn`、`query_run`、`ai_model_run`、`query_result_snapshot`、`answer_citation`
- 返回两部分：
  - `triage_result`：这次 dry-run 的真实问诊结果
  - `evaluation`：便于人工抽查效果的评估指标
- 不使用 SSE，固定返回普通 JSON

请求体：

```json
{
  "scene": "AI_TRIAGE",
  "hospital_scope": "default",
  "user_message": "头痛三天，伴有低烧"
}
```

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `scene` | `string` | 是 | 当前固定 `AI_TRIAGE` |
| `hospital_scope` | `string` | 是 | 本次评估命中的医院目录/知识库作用域 |
| `user_message` | `string` | 是 | 用于本次 dry-run 的患者输入原文 |

约束：

- v1 不接收 `session_id`
- v1 不接收历史对话
- v1 固定按“单轮首轮问诊”口径运行
- 调用不会污染正式问诊数据

### 5B.2 成功响应总结构

```json
{
  "request_id": "test-request-id",
  "triage_result": { /* 判别联合，见 §8 */ },
  "evaluation": { /* 评估指标，见 §5B.6 */ }
}
```

顶层字段说明：

| 字段 | 类型 | 说明 |
|------|------|------|
| `request_id` | `string` | 本次请求 ID；用于日志串联和问题排查 |
| `triage_result` | `object` | 本次 dry-run 产出的结构化问诊结果 |
| `evaluation` | `object` | 本次 dry-run 的评估指标集合 |

### 5B.3 `READY` 响应示例

```json
{
  "request_id": "test-request-id",
  "triage_result": {
    "triage_stage": "READY",
    "triage_completion_reason": "SUFFICIENT_INFO",
    "next_action": "VIEW_TRIAGE_RESULT",
    "risk_level": "low",
    "chief_complaint_summary": "头痛三天，伴有低烧",
    "recommended_departments": [
      {
        "department_id": 101,
        "department_name": "神经内科",
        "priority": 1,
        "reason": "头痛相关症状优先考虑神经内科"
      }
    ],
    "care_advice": "建议尽快门诊就诊。",
    "catalog_version": "deptcat-v20260423-01",
    "citations": [
      {
        "citation_order": 1,
        "chunk_id": "33333333-3333-3333-3333-333333333333",
        "snippet": "头痛伴恶心时应先排查神经系统相关疾病。"
      }
    ]
  },
  "evaluation": {
    "finalized": true,
    "triage_stage": "READY",
    "guardrail_blocked": false,
    "follow_up_question_count": 0,
    "risk_level": "low",
    "recommended_department_count": 1,
    "primary_department_id": 101,
    "primary_department_name": "神经内科",
    "citation_count": 1,
    "citation_chunk_ids": [
      "33333333-3333-3333-3333-333333333333"
    ],
    "retrieved_chunk_count": 2,
    "model_invoked": true,
    "input_tokens": 11,
    "output_tokens": 22,
    "total_tokens": 33,
    "duration_ms": 24,
    "catalog_version": "deptcat-v20260423-01",
    "kb_id": "11111111-1111-1111-1111-111111111111",
    "index_version_id": "22222222-2222-2222-2222-222222222222"
  }
}
```

### 5B.4 `COLLECTING` 响应示例

```json
{
  "request_id": "test-request-id",
  "triage_result": {
    "triage_stage": "COLLECTING",
    "triage_completion_reason": null,
    "next_action": "CONTINUE_TRIAGE",
    "chief_complaint_summary": "头痛三天，伴有低烧",
    "follow_up_questions": [
      "请问是否发热？",
      "请问头痛是否持续加重？"
    ]
  },
  "evaluation": {
    "finalized": false,
    "triage_stage": "COLLECTING",
    "guardrail_blocked": false,
    "follow_up_question_count": 2,
    "risk_level": null,
    "recommended_department_count": 0,
    "primary_department_id": null,
    "primary_department_name": null,
    "citation_count": 0,
    "citation_chunk_ids": [],
    "retrieved_chunk_count": 2,
    "model_invoked": true,
    "input_tokens": 11,
    "output_tokens": 22,
    "total_tokens": 33,
    "duration_ms": 24,
    "catalog_version": "deptcat-v20260423-01",
    "kb_id": "11111111-1111-1111-1111-111111111111",
    "index_version_id": "22222222-2222-2222-2222-222222222222"
  }
}
```

### 5B.5 `BLOCKED` 响应示例

```json
{
  "request_id": "test-request-id",
  "triage_result": {
    "triage_stage": "BLOCKED",
    "triage_completion_reason": "HIGH_RISK_BLOCKED",
    "next_action": "EMERGENCY_OFFLINE",
    "risk_level": "high",
    "chief_complaint_summary": "我胸痛得厉害，喘不上气",
    "recommended_departments": [],
    "care_advice": "请立即寻求线下紧急帮助或联系人工支持",
    "blocked_reason": "CHEST_PAIN_RISK",
    "citations": []
  },
  "evaluation": {
    "finalized": true,
    "triage_stage": "BLOCKED",
    "guardrail_blocked": true,
    "follow_up_question_count": 0,
    "risk_level": "high",
    "recommended_department_count": 0,
    "primary_department_id": null,
    "primary_department_name": null,
    "citation_count": 0,
    "citation_chunk_ids": [],
    "retrieved_chunk_count": 0,
    "model_invoked": false,
    "input_tokens": null,
    "output_tokens": null,
    "total_tokens": null,
    "duration_ms": 3,
    "catalog_version": null,
    "kb_id": null,
    "index_version_id": null
  }
}
```

### 5B.6 `evaluation` 字段合同

| 字段 | 类型 | 说明 |
|------|------|------|
| `finalized` | `boolean` | 本次结果是否已经收口。`READY` / `BLOCKED` 为 `true`，`COLLECTING` 为 `false` |
| `triage_stage` | `string` | 评估视角下的阶段镜像；与 `triage_result.triage_stage` 一致 |
| `guardrail_blocked` | `boolean` | 是否在输入护栏阶段直接阻断。为 `true` 时，后续不会调用检索与模型 |
| `follow_up_question_count` | `int` | 追问条数。只有 `COLLECTING` 可能大于 0，当前最多 2 |
| `risk_level` | `string \| null` | 风险等级镜像。`READY` / `BLOCKED` 返回实际风险级别，`COLLECTING` 返回 `null` |
| `recommended_department_count` | `int` | 推荐科室数量。`READY` 时通常为 1~3，其它阶段为 0 |
| `primary_department_id` | `int \| null` | 首推科室 ID，取 `recommended_departments[0]`；仅 `READY` 时非空 |
| `primary_department_name` | `string \| null` | 首推科室名称，取 `recommended_departments[0]`；仅 `READY` 时非空 |
| `citation_count` | `int` | 引用条数。当前只统计实际进入 `triage_result.citations` 的引用 |
| `citation_chunk_ids` | `string[]` | 引用来源 chunk ID 列表。顺序与 `triage_result.citations` 一致 |
| `retrieved_chunk_count` | `int` | 检索后进入模型上下文的 chunk 数量；不是数据库总命中数 |
| `model_invoked` | `boolean` | 是否实际调用了 LLM。护栏直接阻断时为 `false` |
| `input_tokens` | `int \| null` | 模型输入 token 数；未调模型时为 `null` |
| `output_tokens` | `int \| null` | 模型输出 token 数；未调模型时为 `null` |
| `total_tokens` | `int \| null` | `input_tokens + output_tokens`；任一不存在时按当前实现求和或返回 `null` |
| `duration_ms` | `int` | 本次 dry-run 总耗时，单位毫秒；从进入接口到响应组装完成 |
| `catalog_version` | `string \| null` | 本次使用的导诊目录版本。护栏直接阻断时为 `null` |
| `kb_id` | `string \| null` | 本次使用的知识库 ID。护栏直接阻断时为 `null` |
| `index_version_id` | `string \| null` | 本次使用的知识索引版本 ID。护栏直接阻断时为 `null` |

补充规则：

- `evaluation` 是评估视图，不是新的业务真相；业务真相仍然是 `triage_result`
- `evaluation` 中的多个字段是为了方便 UI 或人工审查直接读取，不需要前端自己再从 `triage_result` 反算
- `primary_department_*`、`risk_level`、`citation_chunk_ids` 都与 `triage_result` 保持一致，不引入第二套含义

### 5B.7 UI 使用建议

- 列表或卡片摘要优先读：
  - `evaluation.triage_stage`
  - `evaluation.risk_level`
  - `evaluation.primary_department_name`
  - `evaluation.citation_count`
  - `evaluation.duration_ms`
- 若要展示“模型有没有真正参与”：
  - 直接使用 `evaluation.model_invoked`
  - 不要用 `input_tokens != null` 自己推断
- 若要区分“未收口”与“已收口”：
  - 用 `evaluation.finalized`
  - 不要只看 `citation_count` 或 `recommended_department_count`
- 若要展示追问强度：
  - 用 `evaluation.follow_up_question_count`
  - 需要展示文案时再读 `triage_result.follow_up_questions`
- 若要支持人工抽查引用：
  - 先看 `evaluation.citation_chunk_ids`
  - 需要展示原文时再读 `triage_result.citations`
- 若要高亮“护栏直接阻断”：
  - 读 `evaluation.guardrail_blocked`
  - 这种情况下 `model_invoked = false`、`retrieved_chunk_count = 0`、`catalog_version = null`

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
- `delta` 应在 Python 消费模型流时实时向下游发出，而不是等完整响应组装后一次性发送
- Python 必须在服务端完整组装 DeepSeek JSON 后再生成 `final`
- Python 不得把 DeepSeek keep-alive 注释直接透给业务端
- SSE 响应应关闭缓冲，至少包含 `Cache-Control: no-cache`、`Connection: keep-alive`、`X-Accel-Buffering: no`

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

### 12.4 Admin dry-run 评估接口补充错误

`POST /api/v1/admin/query-evaluations`：

- 请求体非法：返回 `400`
- 目录缺失、知识库发布缺失、模型返回非法内容等内部 triage 错误：返回 `5xx`

注意：

- 这个接口不是 query path，所以错误响应格式不是 `{ request_id, error }`
- 它沿用 admin 统一错误格式：

```json
{
  "code": 6007,
  "msg": "published knowledge release is missing",
  "requestId": "req_01",
  "timestamp": 1777612345678
}
```

- `code = 6007` 代表 triage 类应用错误包装
- 更细粒度 triage 错误码（如 `TRIAGE_KNOWLEDGE_RELEASE_MISSING`）当前不会作为独立顶层字段返回，只体现在日志中
