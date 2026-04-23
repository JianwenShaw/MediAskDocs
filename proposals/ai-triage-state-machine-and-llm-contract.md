# AI 导诊状态机与 LLM 合同设计

## 1. 文档定位

本文专门回答以下问题：

- AI 问诊什么时候结束追问并进入导诊结果页
- 高风险对话如何从普通导诊链路中阻断
- LLM 应该输出什么，不能输出什么
- Python 如何把 LLM 输出收敛成稳定的业务结果
- Java 如何接收并承接这份结果

本文的核心结论是：

**LLM 不直接决定页面跳转和业务状态，只输出受约束的判定材料；Python 用确定性状态机收口；Java 只消费结构化结果。**

---

## 2. 设计目标

这套设计要同时满足 4 个目标：

1. 问诊不能无限追问，必须有限收口
2. 高风险场景必须优先阻断，而不是继续普通导诊
3. 导诊结果必须结构化，不能依赖自由文本反解析
4. Java 和前端能够稳定承接结果页与挂号链路

---

## 3. DeepSeek 实现前提

这份设计的实现前提必须明确为：

- Python 代码层使用 `OpenAI SDK`
- 实际调用模型使用 `DeepSeek API`
- `base_url` 指向 `https://api.deepseek.com`
- 导诊主模型优先使用 `deepseek-chat`

这意味着这里的落地方案不能假设“模型原生支持严格 JSON Schema 约束解码”，而必须基于 DeepSeek 官方当前公开能力来设计。

### 3.1 DeepSeek 官方已确认能力

根据 DeepSeek 官方文档，当前可直接依赖的能力有：

- OpenAI API 兼容调用
  - 可直接使用 OpenAI SDK
  - 官方文档：
    - https://api-docs.deepseek.com/
- JSON Output
  - 通过 `response_format={"type":"json_object"}` 让模型输出合法 JSON 字符串
  - 官方文档：
    - https://api-docs.deepseek.com/guides/json_mode/
- Streaming
  - `stream=true` 可获得流式响应
  - 高压下会有 keep-alive 注释
  - 官方文档：
    - https://api-docs.deepseek.com/quick_start/rate_limit/

### 3.2 DeepSeek 官方约束

按官方文档，当前设计必须接受这些约束：

- DeepSeek 的 `JSON Output` 重点是“返回合法 JSON 字符串”
- 不能把它等同于“严格遵守你给定的 JSON Schema”
- Prompt 中必须显式包含 `json` 字样
- Prompt 中应给出目标 JSON 示例
- `max_tokens` 要合理设置，避免 JSON 中途截断
- 使用 JSON Output 时，接口可能偶发返回空 `content`

这直接决定了本方案的实现口径：

**模型负责输出 JSON，Python 负责做严格校验和业务收口。**

### 3.3 本文冻结的实现原则

结合你的项目，最终冻结为以下 5 条实现原则：

1. 工作流走预定路径，不让 LLM 自由决定业务流转。
2. DeepSeek 只负责输出 `json_object`，不直接作为最终业务真相。
3. Python 和 Java 之间只传 Python 校验后的结构化结果，不传“靠猜”的文本。
4. 状态机是单一真相，前端只消费状态机结果，不从流式文本反解析。
5. 流式输出和结构化结果分层，只有最终结构化事件能驱动页面跳转。

---

## 4. 设计结论

建议固定三层责任边界：

- `LLM`
  - 负责理解用户表达
  - 负责生成判定材料
  - 不直接决定最终业务状态
- `Python`
  - 负责护栏
  - 负责状态机映射
  - 负责生成最终结构化导诊结果
- `Java`
  - 负责结果持久化
  - 负责结果页承接
  - 负责挂号承接

一句话概括：

**LLM 负责“判断线索”，Python 负责“业务收口”，Java 负责“页面与交易承接”。**

---

## 5. 导诊状态机

建议把导诊业务状态冻结为三态：

- `COLLECTING`
- `READY`
- `BLOCKED`

### 5.1 `COLLECTING`

含义：

- 当前信息仍不足以稳定给出普通导诊结果
- 系统需要继续追问

行为约束：

- 不进入导诊结果页
- 不生成 finalized 导诊结果
- 只返回追问问题

### 5.2 `READY`

含义：

- 当前信息已足够形成可交付的普通导诊结果
- 可以生成推荐科室与建议

行为约束：

- 进入导诊结果页
- 生成 finalized 导诊结果
- 可以进入挂号承接链路

### 5.3 `BLOCKED`

含义：

- 当前对话命中高风险或其他必须阻断普通导诊的场景

行为约束：

- 不进入普通导诊结果链路
- 不进入普通挂号承接
- 进入高风险阻断页或人工支持页

---

## 6. 状态转移规则

为了便于 Python、Java、前端联调，状态机不能只写“定义”，还要明确“怎么转”。

建议把状态转移冻结成下表：

| 当前状态 | 触发条件 | 下一状态 | 是否生成 finalized 结果 |
|----------|----------|----------|--------------------------|
| `COLLECTING` | 命中高风险硬规则 | `BLOCKED` | 是 |
| `COLLECTING` | 关键信息不足，且未到上限 | `COLLECTING` | 否 |
| `COLLECTING` | 信息足够，方向稳定 | `READY` | 是 |
| `COLLECTING` | 到达最大患者回合，且无高风险 | `READY` | 是 |
| `READY` | 用户开始新一轮导诊 cycle | `COLLECTING` | 否 |
| `BLOCKED` | 用户开始新一轮导诊 cycle | `COLLECTING` | 否 |

需要再额外冻结两条规则：

- `READY` 和 `BLOCKED` 都是 finalized 结果状态。
- `COLLECTING` 永远不是 finalized 结果状态。

也就是说：

- Python 只有在状态机收口到 `READY / BLOCKED` 时，才把正式业务结果交给 Java 持久化。
- `COLLECTING` 只是一轮中间态，能展示，但不能冒充“结果页真相”。

---

## 7. 前端动作映射

前端动作不能由 LLM 自由发挥，必须由 Python 按状态机固定映射。

建议固定为：

- `COLLECTING -> CONTINUE_TRIAGE`
- `READY -> VIEW_TRIAGE_RESULT`
- `BLOCKED -> EMERGENCY_OFFLINE` 或 `MANUAL_SUPPORT`

补充约束：

- 聊天页不直接跳挂号页
- `READY` 后统一先进入导诊结果页
- 挂号入口由结果页 CTA 承接

---

## 8. Active Triage Cycle 与强制收口

为了防止无限追问，建议引入 `active triage cycle`。

定义：

- 从 session 开始或最近一次 finalized 结果之后，重新开始一个新的导诊收集周期
- 以患者发言轮次计数

建议固定规则：

- 每个 active triage cycle 最多允许 `5` 个患者回合
- 前 `4` 个患者回合允许返回 `COLLECTING`
- 到第 `5` 个患者回合时，不允许继续 `COLLECTING`
- 第 `5` 个患者回合必须收口为：
  - `BLOCKED`，如果命中高风险
  - 否则 `READY`，输出 best-effort 导诊结果

这样可以保证：

- 不会无限问下去
- 每次问诊最终都能形成可被系统承接的明确结果

---

## 9. 高风险对话处理

高风险场景不能继续走普通导诊链路。

### 9.1 高风险场景示例

至少应包括：

- 自杀、自伤、自残倾向
- 明确伤人风险
- 意识障碍或明显意识改变
- 明显呼吸困难
- 持续或剧烈胸痛
- 大出血
- 抽搐
- 中风样表现
- 严重过敏反应

### 9.2 高风险处理原则

命中高风险后，系统应直接进入 `BLOCKED`。

此时固定行为应为：

- 停止普通追问
- 不推荐普通门诊科室
- 不返回普通挂号承接
- 返回紧急线下就医、人工支持或求助建议

### 9.3 自杀倾向场景

像“我不想活了”“想结束自己”“有自杀计划”这类表达，建议视为高优先级阻断。

系统行为应固定为：

- `triage_stage = BLOCKED`
- `blocked_reason = SELF_HARM_RISK`
- `recommended_departments = []`
- `next_action = EMERGENCY_OFFLINE` 或 `MANUAL_SUPPORT`

也就是说：

**这不是“推荐什么科室”的问题，而是“终止普通导诊”的问题。**

---

## 10. LLM 输出合同

LLM 不应直接输出自由业务结果，而应输出一组受约束的判定材料。

建议最小输出结构如下：

```json
{
  "chief_complaint_summary": "近两天持续头痛，伴恶心",
  "risk_blockers": [],
  "missing_critical_info": ["是否伴随肢体无力"],
  "follow_up_questions": ["请问是否有肢体无力或说话含糊？"],
  "department_recommendation_confidence": "UNSTABLE",
  "recommended_departments": [],
  "care_advice": "如症状明显加重请及时线下就医",
  "triage_completion_reason": null
}
```

字段职责建议固定为：

- `chief_complaint_summary`
  - 当前主诉摘要
- `risk_blockers`
  - 风险阻断信号列表
- `missing_critical_info`
  - 当前仍缺失的关键信息
- `follow_up_questions`
  - 下一轮允许追问的问题，最多 2 个
- `department_recommendation_confidence`
  - 方向是否稳定，仅供 Python 内部使用
- `recommended_departments`
  - 候选推荐结果，仅允许从目录中选
- `care_advice`
  - 一般性就医建议
- `triage_completion_reason`
  - 导诊收口原因

### 10.1 最重要的合同约束

这里要明确一点：

- LLM 输出的是 `triage_materials`
- 不是最终对 Java 暴露的 `triage_result`

也就是说，LLM 和 Java 之间**不能直连**。

正确链路应当是：

`LLM -> triage_materials -> Python 状态机 -> triage_result -> Java`

这是联调稳定性的关键。

### 10.2 DeepSeek 下的具体实现口径

这里必须明确：

- 本项目不依赖模型原生严格 schema 能力
- 本项目采用 DeepSeek 官方支持的 `JSON Output`
- Python 再做本地严格校验

也就是说，实际链路固定为：

`DeepSeek json_object -> Python parse -> Pydantic/JSON Schema validate -> 状态机收口 -> triage_result -> Java`

建议 Python 请求 DeepSeek 时固定做以下配置：

- 使用 `model="deepseek-chat"`
- 设置 `response_format={"type":"json_object"}`
- system prompt 中显式出现 `json`
- system prompt 中给出目标 JSON 示例
- 合理设置 `max_tokens`
- 流式场景下由 Python 自己拼接完整 JSON，再做解析和校验

这样做的原因很简单：

- Java / Python / 前端 三方联调，最怕字段漂移
- DeepSeek 的 `json_object` 解决的是“合法 JSON”
- 真正的业务可靠性必须靠 Python 本地校验补齐

### 10.3 `triage_materials` 推荐 schema 约束

建议至少冻结以下约束：

- `follow_up_questions`
  - 最多 `2` 条
- `recommended_departments`
  - 最多 `3` 条
- `department_recommendation_confidence`
  - 只允许 `UNSTABLE / STABLE`
- `triage_completion_reason`
  - 只允许 `null / SUFFICIENT_INFO / MAX_TURNS_REACHED / HIGH_RISK_BLOCKED`
- `risk_blockers`
  - 只允许 Python 预定义的 code 列表，不允许自由文本分类名

### 10.4 `triage_materials` 本地校验 schema 草案

下面这版不是直接发给 DeepSeek 的请求参数，而是建议你在 Python 内部先冻结的本地校验 schema。

也就是说：

- Prompt 里给 DeepSeek 的是 JSON 示例
- Python 收到模型返回后，再按下面这版 schema 校验

```json
{
  "type": "object",
  "additionalProperties": false,
  "required": [
    "chief_complaint_summary",
    "risk_blockers",
    "missing_critical_info",
    "follow_up_questions",
    "department_recommendation_confidence",
    "recommended_departments",
    "care_advice",
    "triage_completion_reason"
  ],
  "properties": {
    "chief_complaint_summary": { "type": "string" },
    "risk_blockers": {
      "type": "array",
      "maxItems": 8,
      "items": {
        "type": "string",
        "enum": [
          "SELF_HARM_RISK",
          "VIOLENCE_RISK",
          "CHEST_PAIN_RISK",
          "RESPIRATORY_DISTRESS_RISK",
          "STROKE_RISK",
          "SEIZURE_RISK",
          "SEVERE_BLEEDING_RISK",
          "ANAPHYLAXIS_RISK",
          "OTHER_EMERGENCY_RISK"
        ]
      }
    },
    "missing_critical_info": {
      "type": "array",
      "maxItems": 5,
      "items": { "type": "string" }
    },
    "follow_up_questions": {
      "type": "array",
      "maxItems": 2,
      "items": { "type": "string" }
    },
    "department_recommendation_confidence": {
      "type": "string",
      "enum": ["UNSTABLE", "STABLE"]
    },
    "recommended_departments": {
      "type": "array",
      "maxItems": 3,
      "items": {
        "type": "object",
        "additionalProperties": false,
        "required": ["department_id", "priority", "reason"],
        "properties": {
          "department_id": { "type": "integer", "minimum": 1 },
          "priority": { "type": "integer", "minimum": 1, "maximum": 3 },
          "reason": { "type": "string" }
        }
      }
    },
    "care_advice": { "type": "string" },
    "triage_completion_reason": {
      "anyOf": [
        { "type": "null" },
        {
          "type": "string",
          "enum": [
            "SUFFICIENT_INFO",
            "MAX_TURNS_REACHED",
            "HIGH_RISK_BLOCKED"
          ]
        }
      ]
    }
  }
}
```

---

## 11. LLM 禁止事项

Prompt 和后处理都应明确禁止以下行为：

- 输出诊断结论
- 输出处方建议
- 输出目录外科室 ID
- 编造科室名称
- 在 `COLLECTING` 阶段输出 finalized 业务结果
- 高风险时继续普通追问
- 超过追问上限后继续追问

补充一条 DeepSeek 特定约束：

- 不要假设模型一定严格服从字段必填、字段枚举、数组上限
- 这些都必须由 Python 本地校验

---

## 12. Python 的确定性映射规则

Python 不应直接信任 LLM 的业务结论，而是按规则收口。

建议固定映射逻辑：

1. 如果命中高风险硬规则
   - 输出 `BLOCKED`
2. 否则，如果仍缺失关键信息，且未达到上限
   - 输出 `COLLECTING`
3. 否则
   - 输出 `READY`

建议更具体地冻结为：

- `BLOCKED`
  - `risk_blockers` 非空，或命中输入护栏高风险规则
- `COLLECTING`
  - `risk_blockers` 为空
  - 且 `missing_critical_info` 非空或 `follow_up_questions` 非空
  - 且当前未触发 `force_finalize`
- `READY`
  - `triage_completion_reason = SUFFICIENT_INFO`
  - 或 `triage_completion_reason = MAX_TURNS_REACHED`

### 12.1 推荐的收口执行顺序

Python 建议按下面固定顺序执行：

1. 输入护栏检查
2. 导诊目录加载
3. LLM 生成 `triage_materials`
4. schema 校验
5. 目录内科室校验
6. 高风险规则后处理
7. 最大回合数强制收口
8. 状态机映射为 `COLLECTING / READY / BLOCKED`
9. 组装最终 `triage_result`

这个顺序不能乱，原因是：

- 高风险和目录合法性不能依赖模型自觉
- 状态机映射必须发生在 schema 校验之后
- 最终返回给 Java 的只能是 Python 重新组装后的结果

### 12.2 DeepSeek 异常响应处理

针对 DeepSeek 官方文档里已经明确的行为，Python 必须显式处理以下情况：

- 返回空 `content`
- 返回的 JSON 可解析但字段不合法
- 返回的 JSON 被 `max_tokens` 截断
- 流式响应里夹杂 keep-alive 注释

建议固定处理策略：

- 空 `content`
  - 本轮直接判失败，不把结果交给 Java
- JSON 解析失败
  - 本轮直接判失败
- JSON 校验失败
  - 本轮直接判失败
- 流式拼接未形成完整 JSON
  - 本轮直接判失败

对当前毕设项目，不建议在 P0 阶段把这里做成复杂重试编排。

最简单可靠的口径是：

- 失败就让本轮问诊失败
- 不写 finalized snapshot
- 不把脏结果扩散到 Java 和前端

### 12.3 什么时候正式把结果交给 Java

这里冻结一个非常关键的联调口径：

- `COLLECTING`
  - Python 只返回中间态结果
  - Java 不写 finalized snapshot
  - 前端不进入结果页
- `READY`
  - Python 返回 finalized 普通导诊结果
  - Java 写 finalized snapshot
  - 前端进入结果页
- `BLOCKED`
  - Python 返回 finalized 阻断结果
  - Java 写 blocked snapshot
  - 前端进入高风险页

也就是说：

**不是 LLM 说“可以结束了”，而是 Python 状态机判定“已经到达 finalized 状态”，才把正式结果交给 Java。**

---

## 13. 导诊完成原因

建议固定 `triage_completion_reason` 的取值：

- `SUFFICIENT_INFO`
- `MAX_TURNS_REACHED`
- `HIGH_RISK_BLOCKED`

语义固定为：

- `SUFFICIENT_INFO`
  - 当前信息已足够形成普通导诊结果
- `MAX_TURNS_REACHED`
  - 达到收集上限，被迫输出 best-effort 结果
- `HIGH_RISK_BLOCKED`
  - 命中高风险，阻断普通导诊

补充约束：

- `COLLECTING` 时，`triage_completion_reason` 必须为 `null`

---

## 14. 导诊结果结构化契约

最终导诊结果必须结构化，不允许 Java 或前端从自然语言文本反解析。

### 14.1 推荐采用判别联合结构

最终对 Java 暴露的 `triage_result` 应按 `triage_stage` 做判别联合，而不是一个大而松散的对象。

原因是：

- `COLLECTING` 和 `READY / BLOCKED` 的字段天然不同
- 如果所有字段都做可空，Java 和前端会很难消费
- 判别联合更适合 Python 本地严格校验后的 DTO 输出

建议固定三种结构：

- `CollectingTriageResult`
- `ReadyTriageResult`
- `BlockedTriageResult`

### 14.2 `triage_result` 判别联合实现建议

如果你后续用 Pydantic 或 Zod，实现上建议分别建 3 个模型，再用 `triage_stage` 做 discriminator。

不要用一个“所有字段都可空”的大模型去兼容三种状态，那样 Java 和前端消费时会很痛苦。

### 14.3 `READY` 结果示例

```json
{
  "triage_stage": "READY",
  "triage_completion_reason": "SUFFICIENT_INFO",
  "risk_level": "low",
  "recommended_departments": [
    {
      "department_id": 101,
      "department_name": "神经内科",
      "priority": 1,
      "reason": "头痛伴恶心，优先考虑神经系统相关问题"
    }
  ],
  "care_advice": "建议尽快门诊就诊",
  "catalog_version": "deptcat-v20260423-01"
}
```

### 14.4 `BLOCKED` 结果示例

```json
{
  "triage_stage": "BLOCKED",
  "triage_completion_reason": "HIGH_RISK_BLOCKED",
  "risk_level": "high",
  "recommended_departments": [],
  "care_advice": "请立即寻求线下紧急帮助或联系人工支持",
  "blocked_reason": "SELF_HARM_RISK"
}
```

### 14.5 `COLLECTING` 结果示例

```json
{
  "triage_stage": "COLLECTING",
  "triage_completion_reason": null,
  "follow_up_questions": [
    "请问是否有肢体无力或说话含糊？"
  ]
}
```

### 14.6 推荐最终字段清单

建议 Python 返回给 Java 的最终字段冻结为：

- `session_id`
- `turn_id`
- `query_run_id`
- `triage_stage`
- `triage_completion_reason`
- `risk_level`
- `next_action`
- `chief_complaint_summary`
- `follow_up_questions`
- `recommended_departments`
- `care_advice`
- `blocked_reason`
- `catalog_version`
- `citations`

其中字段约束建议固定为：

- `COLLECTING`
  - 必须有 `follow_up_questions`
  - 不允许有 `recommended_departments`
- `READY`
  - 必须有 `recommended_departments`
  - 必须有 `catalog_version`
- `BLOCKED`
  - 必须有 `blocked_reason`
  - `recommended_departments` 固定为空数组

### 14.7 `recommended_departments` 合同

`recommended_departments[]` 建议固定为：

- `department_id`
- `department_name`
- `priority`
- `reason`

约束建议：

- 最多 `3` 个
- `priority` 从 `1` 开始递增
- `department_id` 必须属于当前导诊目录版本
- `department_name` 必须与目录中的该 ID 严格一致

### 14.8 `blocked_reason` 合同

建议不要让 `blocked_reason` 变成自由文本，固定成枚举。

P0 可先收敛为：

- `SELF_HARM_RISK`
- `VIOLENCE_RISK`
- `CHEST_PAIN_RISK`
- `RESPIRATORY_DISTRESS_RISK`
- `STROKE_RISK`
- `SEIZURE_RISK`
- `SEVERE_BLEEDING_RISK`
- `ANAPHYLAXIS_RISK`
- `OTHER_EMERGENCY_RISK`

这样 Java 和前端才能稳定做页面分流与文案映射。

---

## 15. 流式联调契约

既然你前面已经明确要做标准流式接口，这里必须把“流式文本”和“结构化真相”分开。

建议 SSE 事件固定为：

- `start`
  - 返回 `session_id`、`turn_id`、`query_run_id`
- `progress`
  - 返回当前工作流阶段，如 `guardrail_checked`、`catalog_loaded`、`triage_materials_ready`
- `delta`
  - 返回自然语言增量文本
- `final`
  - 返回完整 `triage_result`
- `error`
  - 返回错误码和错误信息
- `done`
  - 表示流结束

关键约束：

- 前端只能根据 `final` 事件里的 `triage_result` 跳页
- 不允许从 `delta` 文本里猜推荐科室、风险等级、页面动作
- Java 如果作为网关，也只能透传 `final` 里的结构化结果作为业务真相
- Python 必须先在服务端完整拼出 DeepSeek 返回内容，再产出 `final`

对 DeepSeek 流式实现，再补两条明确约束：

- Python 不能把模型流式 token 原样当作业务 JSON 直接转发给前端
- DeepSeek keep-alive 注释只能在 Python 内部消费，不能污染业务事件流

---

## 16. Java 承接规则

Java 不再根据自然语言猜测导诊状态，只消费结构化字段。

建议至少消费以下字段：

- `triage_stage`
- `triage_completion_reason`
- `recommended_departments`
- `care_advice`
- `catalog_version`
- 可选：`blocked_reason`

固定承接逻辑：

- `COLLECTING`
  - 留在聊天页
  - 不生成结果页真相
- `READY`
  - 持久化 finalized snapshot
  - 进入导诊结果页
  - 允许挂号承接
- `BLOCKED`
  - 持久化 blocked snapshot
  - 进入高风险结果页
  - 禁止普通挂号承接

### 16.1 对 Java 的强约束

Java 不应再做以下事情：

- 从 `answer` 文本里反解析科室
- 根据推荐科室是否为空来猜 `READY / BLOCKED`
- 根据聊天流式文本自己判断是否进入结果页
- 根据 `department_name` 模糊匹配科室 ID

Java 只认 Python 给出的结构化字段。

---

## 17. LLM 约束的三层机制

不能只依赖 prompt，需要三层一起收口。

### 17.1 第一层：Prompt 合同

- 最多问 2 个高信息增益问题
- 不输出诊断
- 不输出处方
- 推荐科室只能从目录中选
- 高风险时停止普通追问

### 17.2 第二层：结构化输出校验

- 使用 Pydantic 或 JSON Schema 做 Python 本地校验
- 字段缺失、类型错误、目录外科室都直接判失败
- 不能把 DeepSeek 的 `json_object` 直接视为业务上“已可信”

### 17.3 第三层：规则后处理

- Python 内部状态机最终定稿
- 高风险阻断与强制收口不交给模型自由决定

---

## 18. 面向当前毕设的具体落地方案

如果直接结合你现在的项目，我建议冻结为以下实现口径：

1. Python 用 OpenAI SDK 调 DeepSeek `deepseek-chat`
2. 通过 `response_format={"type":"json_object"}` 让 DeepSeek 输出 JSON
3. Prompt 中强制包含 `json` 字样和 JSON 示例
4. Python 对返回内容做严格本地校验，得到 `triage_materials`
5. Python 内部维护显式状态机：`COLLECTING / READY / BLOCKED`
6. Python 只在 `READY / BLOCKED` 时生成 finalized `triage_result`
7. Python 流式接口只在 `final` 事件中输出业务真相
8. Java 只消费 `triage_result`，不消费中间自然语言
9. 前端只根据 `next_action + triage_stage` 驱动页面切换
10. 高风险如自杀倾向直接 `BLOCKED + MANUAL_SUPPORT`
11. 推荐科室只能来自 Java 发布、Python 只读的导诊目录版本

这套设计的优点是：

- 联调口径非常稳定
- 前后端职责边界清楚
- 高风险分流明确
- 结果页真相唯一
- 后续论文答辩时也容易说明“为什么系统是可控的”

---

## 19. 推荐最终方案

对当前毕业设计项目，建议冻结为以下口径：

- 状态机固定为 `COLLECTING / READY / BLOCKED`
- active triage cycle 最多 `5` 个患者回合
- 高风险对话直接进入 `BLOCKED`
- LLM 只输出判定材料，不直接决定页面流转
- Python 负责状态机与最终结构化结果
- Java 只消费结构化结果并承接页面与挂号

---

## 20. 一句话结论

**AI 导诊不能让 LLM 自己决定什么时候“结束并跳页”，而应当由 LLM 提供判定材料、Python 用状态机强制收口、Java 消费结构化结果；高风险场景必须从普通导诊链路中显式阻断。**
