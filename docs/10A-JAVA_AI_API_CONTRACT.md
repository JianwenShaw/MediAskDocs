# AI 对外契约与业务承接（Java）

> 状态：Authoritative Browser-Facing Contract
>
> 适用范围：患者 H5、医生 Web、`mediask-api`
>
> 目标：冻结浏览器经 Java 访问 AI 能力时的接口、结构化结果和后续业务承接口径，避免前端直接绑定 Python 内部 DTO。

## 1. 设计原则

- 浏览器只访问 `mediask-api`，不直连 `mediask-ai`
- Java 对外 `JSON` 接口统一使用 `Result<T>`：`{code, msg, data, requestId, timestamp}`
- Java 对外 `JSON` 中涉及业务主键的 `Long/long` 字段统一按字符串返回，前端按字符串处理 `sessionId`、`turnId`、`encounterId`、`chunkId` 等 ID
- Python 内部返回 `risk_level`、`guardrail_action`、`citations` 等执行结果；Java 负责整理成前端可直接消费的业务结果
- AI 结果必须能承接到挂号和医生接诊，而不是停留在一段聊天文本
- 导诊结构化结果采用单真相模型：`chat`、`triage-result`、`registration-handoff` 共享同一份已持久化 run 结果

## 2. P0 必须打通的用户链路

1. 患者发起 AI 问诊
2. 前端接收回答、引用和风险结果；如需流式观感，由上层基于完整回答做伪流式展示
3. 患者查看导诊结果与推荐科室
4. 患者从 AI 结果跳转挂号
5. 医生在接诊页查看 AI 摘要

## 3. 接口清单

| 接口 | 说明 | 调用方 |
|------|------|--------|
| `POST /api/v1/ai/chat` | 非流式问诊 | 患者 H5 / 调试 |
| `GET /api/v1/ai/sessions` | 当前患者 AI 会话列表 | 患者 H5 |
| `GET /api/v1/ai/sessions/{sessionId}` | 会话详情与轮次列表 | 患者 H5 |
| `GET /api/v1/ai/sessions/{sessionId}/triage-result` | 导诊结果、风险结果、引用与推荐科室 | 患者 H5 |
| `POST /api/v1/ai/sessions/{sessionId}/registration-handoff` | 从 AI 结果生成挂号承接参数 | 患者 H5 |
| `GET /api/v1/internal/triage-department-catalogs/{hospitalScope}` | 仅供 Python 拉取可导诊目录 | Python 内部 |
| `GET /api/v1/encounters/{encounterId}/ai-summary` | 医生查看接诊前 AI 摘要 | 医生 Web |

## 4. 问诊请求

### 4.1 `POST /api/v1/ai/chat`

请求体示例：

```json
{
  "sessionId": null,
  "message": "头痛三天，伴有低烧，应该先看什么科？",
  "departmentId": 101,
  "sceneType": "PRE_CONSULTATION",
  "useStream": false
}
```

返回体 `data` 示例：

```json
{
  "sessionId": "90001",
  "turnId": "90011",
  "answer": "建议尽快线下就医，优先考虑神经内科或发热门诊分诊。",
  "triageResult": {
    "triageStage": "READY",
    "riskLevel": "medium",
    "guardrailAction": "caution",
    "nextAction": "VIEW_TRIAGE_RESULT",
    "recommendedDepartments": [
      {
        "departmentId": "101",
        "departmentName": "神经内科",
        "priority": 1,
        "reason": "头痛伴发热，建议优先神经内科评估"
      }
    ],
    "chiefComplaintSummary": "头痛三天伴低烧",
    "careAdvice": "建议尽快线下就医，避免继续自行判断。",
    "citations": [
      {
        "chunkId": "7003001",
        "retrievalRank": 1,
        "fusionScore": 0.82,
        "snippet": "持续头痛伴发热应结合感染风险进行线下评估。"
      }
    ]
  }
}
```

补充说明：

- `READY` 后聊天链路统一先进入结果页，不再从聊天页直接跳挂号页
- `COLLECTING` 阶段的 `triageResult` 需要额外返回 `followUpQuestions`
- `followUpQuestions` 只出现在 `POST /api/v1/ai/chat` 的 `COLLECTING` 场景，不出现在 `GET /triage-result`
- `followUpQuestions` 最多返回 2 个

## 5. 伪流式展示

- Python 内部服务收口为 `POST /api/v1/chat`
- Java 或前端如需“边打字边显示”的体验，只允许基于完整 `answer` 做展示层伪流式切片
- 结构化真相仍只来自完整 `triageResult`，不从伪流式文本中反解析推荐科室、风险状态或跳转动作

## 6. 导诊结果与挂号承接

### 6.0 `GET /api/v1/ai/sessions`

用途：返回当前患者的 AI 会话历史列表，用于结果页或历史页选择具体会话后继续查看详情和导诊结果。

当前版本无查询参数，不分页。

`data.items[]` 至少包含：

- `sessionId`
- `sceneType`
- `status`
- `departmentId`
- `chiefComplaintSummary`
- `summary`
- `startedAt`
- `endedAt`

规则：

- 当前实现仅返回当前患者本人的会话
- 列表按 `startedAt DESC` 排序；同一时间按 `sessionId DESC`
- 该接口只返回最小摘要，不返回 `turns`、消息原文或导诊结构化结果
- 详情仍走 `GET /api/v1/ai/sessions/{sessionId}`，导诊结果仍走 `GET /api/v1/ai/sessions/{sessionId}/triage-result`

### 6.1 `GET /api/v1/ai/sessions/{sessionId}`

`data` 至少包含：

- `sessionId`
- `sceneType`
- `status`
- `departmentId`
- `chiefComplaintSummary`
- `summary`
- `startedAt`
- `endedAt`
- `turns`

`turns[]` 至少包含：

- `turnId`
- `turnNo`
- `turnStatus`
- `startedAt`
- `completedAt`
- `errorCode`
- `errorMessage`
- `messages`

`messages[]` 至少包含：

- `role`
- `content`
- `createdAt`

规则：

- 当前实现仅支持患者本人回看自己的 AI 会话
- 医生侧查看 AI 内容仍走后续 `GET /api/v1/encounters/{encounterId}/ai-summary`

### 6.2 `GET /api/v1/ai/sessions/{sessionId}/triage-result`

`data` 至少包含：

- `sessionId`
- `resultStatus`
- `triageStage`
- `riskLevel`
- `guardrailAction`
- `nextAction`
- `finalizedTurnId`
- `finalizedAt`
- `hasActiveCycle`
- `activeCycleTurnNo`
- `chiefComplaintSummary`
- `recommendedDepartments`
- `careAdvice`
- `citations`

补充说明：

- 当前目标设计中，`triage-result` 读取的是 session 最近一次 finalized `ai_model_run.triage_snapshot_json`，再结合 guardrail 与 citations 组装结果
- 如果历史上已有 finalized 结果，而当前新一轮仍处于 `COLLECTING`，`GET /triage-result` 继续返回旧结果
- 此时返回 `resultStatus = UPDATING`，明确表示“当前展示的是上一版 finalized 结果，而不是当前聊天中的最新状态”
- `GET /triage-result` 仅在“从未产出过 finalized snapshot 且当前仍处于 `COLLECTING`”时返回 `409`
- 历史老会话如果对应 run 尚未持久化 `triage_snapshot_json`，可能不存在 `triage-result`
- 前端应以该接口返回的结构化字段作为导诊结果真相，不从聊天文本中自行解析
- Python 内部用于判定 `triageStage` 的 `risk_blockers`、`missing_critical_info`、`follow_up_questions`、`department_recommendation_confidence` 不对浏览器暴露，前端不消费这些内部判定材料

`resultStatus` 固定值：

- `CURRENT`
- `UPDATING`

含义：

- `CURRENT`：当前展示的是最新 finalized 结果，当前没有新的 active cycle 在收集
- `UPDATING`：当前展示的是上一版 finalized 结果，但当前有新的 active cycle 仍在 `COLLECTING`

结果页行为约束：

- `CURRENT`：正常展示 finalized 结果
- `UPDATING`：必须展示“正在重新评估”的提示文案
- `UPDATING` 场景仍允许展示结果页 CTA，但应明确这是“按上一版结果继续”
- `GET /triage-result` 成功返回时，`triageStage` 只允许 `READY` 或 `BLOCKED`

### 6.3 `POST /api/v1/ai/sessions/{sessionId}/registration-handoff`

用途：把 AI 结果转换成挂号页可直接消费的查询条件与展示摘要。

`data` 示例：

```json
{
  "sessionId": "90001",
  "recommendedDepartmentId": "101",
  "recommendedDepartmentName": "神经内科",
  "chiefComplaintSummary": "头痛三天伴低烧",
  "suggestedVisitType": "OUTPATIENT",
  "blockedReason": null,
  "registrationQuery": {
    "departmentId": "101",
    "dateFrom": "2026-03-15",
    "dateTo": "2026-03-21"
  }
}
```

规则：

- 该接口只做承接信息生成，不直接创建 `registration_order`
- 该接口只消费已持久化的 run 结果，不依赖聊天文本，也不依赖单独 finalize 结果
- 该接口只从结果页触发，不再作为聊天页 `nextAction` 的直接跳转目标
- `suggestedVisitType` 当前固定为 `OUTPATIENT`，仅表达普通门诊承接类型，不等同于线下场次里的 `clinicType`
- 默认返回未来 7 天的挂号查询窗口：`dateFrom = 今天`，`dateTo = 今天 + 6 天`
- 如果 `riskLevel = high`，则返回 `blockedReason = EMERGENCY_OFFLINE`，不生成普通挂号承接参数；此时 `suggestedVisitType`、`registrationQuery`、推荐挂号科室字段返回 `null`

### 6.4 `GET /api/v1/internal/triage-department-catalogs/{hospitalScope}`

用途：供 Python 拉取当前医院范围下的可导诊目录。

规则：

- 该接口仅供内部调用，需携带 `X-API-Key`
- 该接口直接返回 raw JSON，不包 `Result<T>`
- 字段名固定为 snake_case
- 对外暴露的是“可导诊目录”语义，不等于 `departments` 全量
- 本轮目录由 Java 基于现有 `departments` 做受控投影生成，不新增独立目录表

## 7. 医生接诊摘要承接

### 7.1 `GET /api/v1/encounters/{encounterId}/ai-summary`

用途：医生在接诊页快速看到患者 AI 预问诊摘要，而不是查看全部聊天原文。

`data` 至少包含：

- `encounterId`
- `sessionId`
- `chiefComplaintSummary`
- `structuredSummary`
- `riskLevel`
- `recommendedDepartments`
- `latestCitations`

规则：

- 默认只返回摘要与引用，不默认返回 `ai_turn_content` 原文
- 若医生查看原文，必须触发对象级授权与 `data_access_log`

## 8. 高风险分支

| 内部结果 | Java 对外 `nextAction` | 前端表现 |
|----------|------------------------|----------|
| `collecting` | `CONTINUE_TRIAGE` | 继续问诊，不进入结果页 |
| `ready` | `VIEW_TRIAGE_RESULT` | 统一进入结果页，由结果页决定是否展示挂号 CTA |
| `high + refuse` | `EMERGENCY_OFFLINE` 或 `MANUAL_SUPPORT` | 不继续普通问诊，展示紧急就医/人工求助提示 |

约束：

- 高风险场景不输出会被误解为诊断结论的文本
- 高风险场景由 Java 负责把内部护栏结果映射成明确的下一步动作
- 前端只依据 `nextAction` 做聊天结束后的跳转和交互，不自行解释规则命中细节
- 是否出现挂号入口由结果页根据 finalized snapshot 决定，而不是由聊天态 `nextAction` 直接决定

## 9. 与内部 Python 契约的关系

- Python 内部契约见 [10-PYTHON_AI_SERVICE.md](./10-PYTHON_AI_SERVICE.md)
- Python 负责执行、检索和引用；Java 负责鉴权、审计、会话主事实和前端对外协议
- 前端不直接依赖 Python 的 `model_run_id`、`provider_run_id`、`risk_level` 原始字段组合

## 10. 一句话结论

AI 文档不能只定义 Java 和 Python 怎么通，还必须定义浏览器最终拿到什么、下一步怎么走；否则主链路会停在“能聊天”，而不是“能导诊并承接到挂号和接诊”。
