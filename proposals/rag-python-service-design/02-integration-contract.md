# RAG Python 服务联调协议冻结版

## 1. 文档定位

本文冻结 Python、Java、前端三方联调口径。

目标是明确：

- Python 对外 HTTP 接口
- Python 流式 SSE 事件
- `triage_result` 结构化业务真相
- Java 承接职责
- 前端跳页规则
- Redis 导诊目录读模型合同

后续联调、DTO、前端页面动作、网关透传都以本文为准。

## 2. 参与方与边界

三方职责固定如下：

- Python
  - 负责 DeepSeek 调用
  - 负责护栏
  - 负责状态机收口
  - 负责生成最终 `triage_result`
- Java
  - 负责业务主数据
  - 负责发布 Redis 导诊目录
  - 负责接收并持久化 finalized 结果
  - 负责导诊结果页和挂号承接
- Frontend
  - 负责展示聊天流和结果页
  - 只根据 `final` 事件或同步响应里的 `triage_result` 跳页

明确禁止：

- Frontend 从流式文本推断业务状态
- Java 从自然语言反解析科室
- Python 在 query 主链路中实时拉取 Java 内部 HTTP 目录接口

## 3. 目录读模型合同

目录读模型由 Java 发布到 Redis，Python 只读。

### 3.1 Redis key

- `triage_catalog:active:{hospital_scope}`
- `triage_catalog:{hospital_scope}:{catalog_version}`

### 3.2 目录 JSON

```json
{
  "hospital_scope": "default",
  "catalog_version": "deptcat-v20260423-01",
  "published_at": "2026-04-23T12:00:00Z",
  "department_candidates": [
    {
      "department_id": 101,
      "department_name": "神经内科",
      "routing_hint": "头痛、头晕、肢体麻木、意识异常相关问题优先考虑",
      "aliases": ["神内", "脑病门诊"],
      "sort_order": 10
    }
  ]
}
```

### 3.3 Python 使用规则

1. 先读 `active` 指针
2. 再读对应版本 JSON
3. 只允许从 `department_candidates` 中选择推荐科室
4. 返回结果必须带 `catalog_version`

### 3.4 Java 校验规则

Java 收到 Python 返回结果后必须校验：

1. `catalog_version` 是否存在
2. `department_id` 是否属于该版本目录
3. `department_name` 是否与该 `department_id` 严格匹配

## 4. 标准 HTTP 接口

P0 只冻结两个 query 接口：

- `POST /api/v1/query`
- `POST /api/v1/query/stream`

不再使用旧 `/api/v1/chat` 口径。

## 5. 通用请求头

所有请求统一使用：

- `Content-Type: application/json`
- `X-Request-Id: <string>`

规则：

- `X-Request-Id` 由 Java 网关优先传入
- 若缺失，Python 生成并在响应中回传

## 6. 请求体

两个接口请求体一致：

```json
{
  "scene": "AI_TRIAGE",
  "session_id": null,
  "hospital_scope": "default",
  "user_message": "我这两天一直头痛，还想吐"
}
```

### 6.1 字段冻结

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `scene` | `string` | 是 | P0 固定为 `AI_TRIAGE` |
| `session_id` | `string \| null` | 是 | 首轮传 `null`，后续轮次传回 Python 返回的会话 id |
| `hospital_scope` | `string` | 是 | 目录作用域 |
| `user_message` | `string` | 是 | 当前轮患者输入原文 |

### 6.2 请求约束

- Python 不要求 Java 传 `catalog_version`
- Python 自己读取 Redis 活动目录版本
- 请求体不承载“预判的导诊状态”
- 请求体不承载“推荐科室候选”

## 7. 同步接口

## 7.1 `POST /api/v1/query`

语义：

- 完整执行一次 query workflow
- 返回最终结构化 `triage_result`

响应格式：

```json
{
  "request_id": "req_01",
  "session_id": "82f7a4c2-7784-4d31-9c6e-6c8fbbe8c2cd",
  "turn_id": "4b1eaf1f-3e28-479f-9fb5-f259db73507a",
  "query_run_id": "9e86fc63-15f1-44db-9c07-ef2e5911d69c",
  "triage_result": {
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
}
```

## 8. 流式接口

## 8.1 `POST /api/v1/query/stream`

语义：

- 返回标准 `text/event-stream`
- 由 Python 输出真实流式事件

### 8.2 SSE 事件清单

- `start`
- `progress`
- `delta`
- `final`
- `error`
- `done`

### 8.3 事件结构

`start`

```json
{
  "request_id": "req_01",
  "session_id": "82f7a4c2-7784-4d31-9c6e-6c8fbbe8c2cd",
  "turn_id": "4b1eaf1f-3e28-479f-9fb5-f259db73507a",
  "query_run_id": "9e86fc63-15f1-44db-9c07-ef2e5911d69c"
}
```

`progress`

```json
{
  "step": "catalog_loaded"
}
```

P0 允许的 `step`：

- `guardrail_checked`
- `catalog_loaded`
- `triage_materials_ready`
- `finalizing`

`delta`

```json
{
  "text_delta": "根据你提供的信息，当前更建议先到神经内科就诊。"
}
```

`final`

```json
{
  "request_id": "req_01",
  "session_id": "82f7a4c2-7784-4d31-9c6e-6c8fbbe8c2cd",
  "turn_id": "4b1eaf1f-3e28-479f-9fb5-f259db73507a",
  "query_run_id": "9e86fc63-15f1-44db-9c07-ef2e5911d69c",
  "triage_result": {
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
    "citations": []
  }
}
```

`error`

```json
{
  "code": "TRIAGE_MODEL_SCHEMA_INVALID",
  "message": "model response schema invalid"
}
```

`done`

```json
{}
```

### 8.4 流式强约束

- 前端只能根据 `final` 事件跳页
- Java 如果透传 SSE，也只能以 `final` 中的 `triage_result` 作为业务真相
- `delta` 只用于展示自然语言
- Python 必须在服务端完整组装 DeepSeek JSON，再生成 `final`
- Python 不得把 DeepSeek keep-alive 注释直接透给业务端

## 9. `triage_result` 判别联合

`triage_result` 必须是判别联合，不允许一个大而松散的可空对象。

### 9.1 `COLLECTING`

```json
{
  "triage_stage": "COLLECTING",
  "triage_completion_reason": null,
  "next_action": "CONTINUE_TRIAGE",
  "chief_complaint_summary": "近两天持续头痛，伴恶心",
  "follow_up_questions": [
    "请问是否有肢体无力或说话含糊？"
  ]
}
```

字段约束：

- 必须有 `follow_up_questions`
- 不允许有 `recommended_departments`
- 不允许有 `blocked_reason`

### 9.2 `READY`

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
  "citations": []
}
```

字段约束：

- `triage_completion_reason` 只允许 `SUFFICIENT_INFO` 或 `MAX_TURNS_REACHED`
- 必须有 `recommended_departments`
- 必须有 `catalog_version`
- `recommended_departments` 最多 3 条

### 9.3 `BLOCKED`

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

## 10. `recommended_departments` 合同

数组项字段固定为：

- `department_id`
- `department_name`
- `priority`
- `reason`

约束固定为：

- 最多 `3` 条
- `priority` 从 `1` 开始递增
- `department_id` 必须存在于当前目录版本
- `department_name` 必须与目录中该 id 严格一致

## 11. `blocked_reason` 合同

P0 固定允许：

- `SELF_HARM_RISK`
- `VIOLENCE_RISK`
- `CHEST_PAIN_RISK`
- `RESPIRATORY_DISTRESS_RISK`
- `STROKE_RISK`
- `SEIZURE_RISK`
- `SEVERE_BLEEDING_RISK`
- `ANAPHYLAXIS_RISK`
- `OTHER_EMERGENCY_RISK`

## 12. Python 状态机收口规则

Python 必须按确定性规则收口，不直接信任模型的业务判断。

固定顺序：

1. 输入护栏检查
2. 读取 Redis 导诊目录
3. 调用 DeepSeek 获取 `triage_materials`
4. 本地 JSON 解析和 schema 校验
5. 目录内科室校验
6. 高风险后处理
7. 最大回合数强制收口
8. 映射为 `COLLECTING / READY / BLOCKED`
9. 组装最终 `triage_result`

强制规则：

- 每个 active triage cycle 最多 `5` 个患者回合
- 第 `5` 个患者回合不得继续返回 `COLLECTING`

## 13. Java 承接规则

### 13.1 同步接口

- `COLLECTING`
  - 不写 finalized snapshot
  - 留在聊天页
- `READY`
  - 写 finalized snapshot
  - 进入导诊结果页
  - 允许挂号承接
- `BLOCKED`
  - 写 blocked snapshot
  - 进入高风险结果页
  - 禁止普通挂号承接

### 13.2 流式接口

- 只消费 `final` 事件里的 `triage_result`
- 不根据 `delta` 或 `progress` 修改业务状态

### 13.3 Java 禁止事项

- 从文本里反解析推荐科室
- 根据推荐科室是否为空猜状态
- 根据 `department_name` 模糊匹配科室 id
- 根据流式文本猜是否进入结果页

## 14. 前端行为冻结

前端动作只由 `triage_result.next_action` 驱动。

固定映射：

- `CONTINUE_TRIAGE`
  - 留在聊天页
- `VIEW_TRIAGE_RESULT`
  - 跳转导诊结果页
- `MANUAL_SUPPORT`
  - 跳转高风险人工支持页
- `EMERGENCY_OFFLINE`
  - 跳转紧急线下就医页

前端禁止事项：

- 从 `delta` 文本猜推荐科室
- 从 `delta` 文本猜高风险等级
- 在未收到 `final` 时提前跳页

## 15. 失败契约

以下情况 Python 直接返回失败，不向 Java 提交脏结果：

- DeepSeek 返回空 `content`
- DeepSeek JSON 无法解析
- DeepSeek JSON 校验失败
- 目录版本不存在
- 推荐科室不在目录中
- 流式 JSON 组装失败

### 15.1 HTTP 错误响应

同步接口错误响应格式：

```json
{
  "request_id": "req_01",
  "error": {
    "code": "TRIAGE_MODEL_SCHEMA_INVALID",
    "message": "model response schema invalid"
  }
}
```

### 15.2 P0 错误码

- `TRIAGE_REQUEST_INVALID`
- `TRIAGE_CATALOG_ACTIVE_VERSION_MISSING`
- `TRIAGE_CATALOG_VERSION_NOT_FOUND`
- `TRIAGE_CATALOG_DEPARTMENT_INVALID`
- `TRIAGE_MODEL_EMPTY_CONTENT`
- `TRIAGE_MODEL_INVALID_JSON`
- `TRIAGE_MODEL_SCHEMA_INVALID`
- `TRIAGE_STREAM_ASSEMBLY_FAILED`
- `TRIAGE_INTERNAL_ERROR`

## 16. 端到端顺序

一次标准流式请求顺序固定为：

1. Java 或前端发起 `/api/v1/query/stream`
2. Python 创建 `session_id`、`turn_id`、`query_run_id`
3. Python 发送 `start`
4. Python 完成输入护栏并发送 `progress`
5. Python 读取 Redis 导诊目录并发送 `progress`
6. Python 调 DeepSeek，完成 `triage_materials`
7. Python 本地校验并做状态机收口
8. Python 发送 `final`
9. Python 发送 `done`
10. Java 根据 `final` 结果持久化并驱动页面流转

## 17. 一句话结论

这份联调协议把三方协作冻结成了唯一链路：

`DeepSeek -> Python 校验与状态机 -> triage_result -> Java 承接 -> Frontend 跳页`

后续任何实现都不得再回到“文本反解析”和“伪流式驱动业务状态”的旧模式。
