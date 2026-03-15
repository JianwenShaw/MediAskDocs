# P0 前端任务清单

> 状态：Frontend Execution Checklist
>
> 目标：把 `P0` 主链路拆成患者 H5、医生 Web、管理员最小审计页三部分的可执行任务清单。

## 1. 前端总目标

前端 `P0` 的目标不是先完成完整中后台，而是支撑毕设演示主链路：

`患者登录 -> AI 问诊 -> 导诊结果 -> 挂号 -> 医生接诊 -> 病历 -> 处方 -> 审计查询`

## 2. 患者 H5

## 2.1 Page A：登录/身份确认

### 页面目标

- [ ] 完成登录
- [ ] 获取当前用户身份
- [ ] 进入 AI 问诊入口

### 依赖接口

- [ ] `/api/v1/auth/login`
- [ ] `/api/v1/auth/me`

## 2.2 Page B：AI 问诊页

### 页面目标

- [ ] 输入症状描述
- [ ] 展示流式回答
- [ ] 展示引用片段
- [ ] 展示风险提示与下一步动作

### 依赖接口

- [ ] `/api/v1/ai/chat`
- [ ] `/api/v1/ai/chat/stream`

### 页面规则

- [ ] 不从聊天文本里猜推荐科室
- [ ] 一切结构化结果以 `meta.triageResult` 为准
- [ ] 断流或报错时保留 `requestId` 以便排障

## 2.3 Page C：导诊结果页

### 页面目标

- [ ] 展示推荐科室
- [ ] 展示 `careAdvice`
- [ ] 展示引用来源
- [ ] 展示是否可继续挂号

### 依赖接口

- [ ] `/api/v1/ai/sessions/{sessionId}/triage-result`
- [ ] `/api/v1/ai/sessions/{sessionId}/registration-handoff`

### 页面规则

- [ ] `VIEW_TRIAGE_RESULT`：正常展示结果
- [ ] `GO_REGISTRATION`：展示挂号入口
- [ ] `EMERGENCY_OFFLINE` / `MANUAL_SUPPORT`：跳转高风险提示页

## 2.4 Page D：高风险提示页

### 页面目标

- [ ] 展示紧急就医提示
- [ ] 展示人工求助提示或热线信息占位
- [ ] 不继续普通 AI 问诊交互

### 页面规则

- [ ] 不展示会被误解为诊断结论的文案
- [ ] 优先给出明确下一步动作

## 2.5 Page E：挂号提交页

### 页面目标

- [ ] 根据推荐科室筛选门诊
- [ ] 选择 `clinic_session` / `clinic_slot`
- [ ] 提交挂号

### 依赖接口

- [ ] `/api/v1/clinic-sessions`
- [ ] `/api/v1/registrations`

## 2.6 Page F：我的挂号

### 页面目标

- [ ] 查看挂号记录
- [ ] 能看出来源于哪次 AI 会话

### 依赖接口

- [ ] `/api/v1/registrations`

## 3. 医生 Web

## 3.1 Page G：工作台首页

### 页面目标

- [ ] 展示待接诊列表入口
- [ ] 展示最小导航：接诊、病历、处方

## 3.2 Page H：接诊列表/详情

### 页面目标

- [ ] 查看挂号信息
- [ ] 查看接诊详情
- [ ] 查看 AI 摘要

### 依赖接口

- [ ] `/api/v1/encounters`
- [ ] `/api/v1/encounters/{encounterId}`
- [ ] `/api/v1/encounters/{encounterId}/ai-summary`

### 页面规则

- [ ] 默认只展示 AI 摘要，不直接展示 AI 原文
- [ ] 若后续加“查看原文”按钮，必须对应后端授权与访问留痕

## 3.3 Page I：病历编辑页

### 页面目标

- [ ] 录入病历正文
- [ ] 录入诊断结果

### 依赖接口

- [ ] `/api/v1/emr`
- [ ] `/api/v1/emr/{encounterId}`

## 3.4 Page J：处方编辑页

### 页面目标

- [ ] 创建处方头
- [ ] 录入处方项

### 依赖接口

- [ ] `/api/v1/prescriptions`
- [ ] `/api/v1/prescriptions/{encounterId}`

## 4. 管理员最小审计页

## 4.1 Page K：审计查询页

### 页面目标

- [ ] 查询 `audit_event`
- [ ] 查询 `data_access_log`
- [ ] 按时间、用户、资源类型做最小筛选

### 依赖接口

- [ ] `/api/v1/audit/events`
- [ ] `/api/v1/audit/data-access`

## 5. 前端公共任务

### 状态管理

- [ ] 登录态、用户信息、UI 状态放前端状态
- [ ] AI 会话、导诊结果、挂号、接诊记录放服务端状态

### 错误处理

- [ ] 统一按 `code` 判断成功失败
- [ ] 页面能展示 `msg`
- [ ] 保留 `requestId` 用于问题排查

### 路由建议

- [ ] `/login`
- [ ] `/ai/session/:sessionId`
- [ ] `/triage/result/:sessionId`
- [ ] `/triage/high-risk/:sessionId`
- [ ] `/registrations/new`
- [ ] `/registrations`
- [ ] `/workbench`
- [ ] `/encounters`
- [ ] `/encounters/:id`
- [ ] `/emr/:encounterId`
- [ ] `/prescriptions/:encounterId`
- [ ] `/audit`

## 6. 页面联调顺序

1. 登录页
2. AI 问诊页
3. 导诊结果页
4. 高风险提示页
5. 挂号提交页
6. 我的挂号页
7. 医生工作台与接诊详情
8. 病历编辑页
9. 处方编辑页
10. 审计查询页

## 7. 页面验收标准

- [ ] AI 问诊页能稳定显示流式回答和结构化结果
- [ ] 导诊结果页能正确处理三种 `nextAction`
- [ ] 患者能从 AI 结果进入挂号
- [ ] 医生能看到 AI 摘要并完成病历/处方录入
- [ ] 页面报错时可看到 `requestId`

## 8. 一句话结论

前端 `P0` 的重点不是先做完整平台壳，而是把患者链路和医生链路串起来，让老师能一眼看到“AI 问诊结果如何进入真实医疗流程”。
