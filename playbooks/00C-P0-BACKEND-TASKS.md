# P0 后端任务清单

> 状态：Backend Execution Checklist
>
> 目标：把 `P0` 主链路拆成后端可直接执行的任务包，覆盖 Java API、Python AI、数据库、权限与审计联调。

## 1. 后端总目标

后端 `P0` 只需要打通一条主线：

`认证 -> AI 问诊 -> RAG 引用 -> 导诊结果 -> 挂号 -> 接诊 -> 病历 -> 处方 -> 权限校验 -> 审计留痕`

## 2. 任务包拆分

## 2.1 Task A：公共协议与请求上下文

### 交付物

- [ ] `Result<T>` 统一成功响应
- [ ] 统一错误码与全局异常处理
- [ ] `X-Request-Id` 生成、透传、回写
- [ ] Java `JSON` 接口与 `SSE` 接口口径分离

### 关键文件/模块

- `mediask-common`
- `mediask-api`
- `docs/19-ERROR_EXCEPTION_RESPONSE_DESIGN.md`
- `docs/17A-REQUEST_CONTEXT_IMPLEMENTATION.md`

### 验收标准

- [ ] 所有 `JSON` 接口返回 `Result<T>`
- [ ] `SSE` 返回 `message / meta / end / error`
- [ ] 任意报错都带稳定 `requestId`

## 2.2 Task B：认证、角色、数据范围基线

### 交付物

- [ ] 登录/当前用户接口
- [ ] 患者 / 医生 / 管理员角色识别
- [ ] `data_scope_rules` 生效骨架
- [ ] 对象级授权拦截约定

### 关键表

- [ ] `users`
- [ ] `roles`
- [ ] `permissions`
- [ ] `user_roles`
- [ ] `role_permissions`
- [ ] `data_scope_rules`

### 验收标准

- [ ] 患者只能访问自己的数据
- [ ] 医生不能直接读取非职责范围病历
- [ ] 管理员拥有最小审计查询能力

## 2.3 Task C：知识库与 RAG 底座

### 交付物

- [ ] 知识文档入库接口或脚本
- [ ] `knowledge_document` / `knowledge_chunk` 持久化
- [ ] Java 调 Python 建立索引
- [ ] Python 写 `knowledge_chunk_index`

### 关键接口

- [ ] Java：知识导入最小接口或初始化脚本入口
- [ ] Python：`/api/v1/knowledge/index`
- [ ] Python：`/api/v1/knowledge/search`

### 验收标准

- [ ] 至少一套知识文档可被检索命中
- [ ] `knowledge_chunk_index` 由 Python 写入

## 2.4 Task D：AI 问诊主链路

### 交付物

- [ ] `POST /api/v1/ai/chat`
- [ ] `POST /api/v1/ai/chat/stream`
- [ ] `GET /api/v1/ai/sessions/{sessionId}`
- [ ] `GET /api/v1/ai/sessions/{sessionId}/triage-result`

### 关键表

- [ ] `ai_session`
- [ ] `ai_turn`
- [ ] `ai_turn_content`
- [ ] `ai_model_run`
- [ ] `ai_guardrail_event`
- [ ] `ai_run_citation`

### 实现规则

- [ ] Java 预创建 `ai_model_run`
- [ ] Java 调 Python 时透传 `model_run_id + request_id`
- [ ] Python 负责检索、生成、护栏、引用写入
- [ ] Java 负责会话主事实、对外协议、审计串联

### 验收标准

- [ ] 回答可展示引用
- [ ] 返回 `riskLevel / guardrailAction / nextAction`
- [ ] 高风险分支不继续普通问答

## 2.5 Task E：AI 到挂号承接

### 交付物

- [ ] `POST /api/v1/ai/sessions/{sessionId}/registration-handoff`
- [ ] `GET /api/v1/clinic-sessions`
- [ ] `POST /api/v1/registrations`
- [ ] `GET /api/v1/registrations`

### 关键表

- [ ] `clinic_session`
- [ ] `clinic_slot`
- [ ] `registration_order`

### 验收标准

- [ ] AI 推荐科室可转成挂号查询条件
- [ ] `registration_order.source_ai_session_id` 可追溯

## 2.6 Task F：医生接诊、病历、处方

### 交付物

- [ ] `GET /api/v1/encounters`
- [ ] `GET /api/v1/encounters/{encounterId}`
- [ ] `GET /api/v1/encounters/{encounterId}/ai-summary`
- [ ] `POST /api/v1/emr`
- [ ] `GET /api/v1/emr/{encounterId}`
- [ ] `POST /api/v1/prescriptions`
- [ ] `GET /api/v1/prescriptions/{encounterId}`

### 关键表

- [ ] `visit_encounter`
- [ ] `emr_record`
- [ ] `emr_record_content`
- [ ] `emr_diagnosis`
- [ ] `prescription_order`
- [ ] `prescription_item`

### 验收标准

- [ ] 医生默认只看 AI 摘要，不直接看原文
- [ ] 接诊后可形成病历、诊断、处方闭环

## 2.7 Task G：审计与敏感访问留痕

### 交付物

- [ ] `audit_event` 写入链路
- [ ] `data_access_log` 写入链路
- [ ] 审计最小查询接口

### 关键表

- [ ] `audit_event`
- [ ] `data_access_log`

### 强约束

- [ ] 查看病历正文要写 `data_access_log`
- [ ] 查看 AI 原文要写 `data_access_log`
- [ ] 登录、挂号、病历保存、处方保存、权限变更要写 `audit_event`

## 3. Java / Python 分工

| 能力 | Java | Python |
|------|------|--------|
| 认证与权限 | 负责 | 不负责 |
| 会话主事实 | 负责 | 不负责 |
| RAG 检索 | 调用与整合 | 负责执行 |
| 护栏输出 | 映射 `nextAction` | 输出 `risk_level` 与 `guardrail_action` |
| 浏览器协议 | 负责 | 不负责 |
| `knowledge_chunk_index` | 不写 | 负责 |
| `ai_run_citation` | 不写 | 负责 |
| 审计/访问日志 | 负责 | 不负责 |

## 4. 联调顺序

1. Java 公共协议 + 认证
2. Python 健康检查 + 内部接口骨架
3. RAG 检索闭环
4. AI 问诊 `JSON` 闭环
5. AI `SSE` 闭环
6. 导诊结果 -> 挂号
7. 接诊 -> 病历 -> 处方
8. 对象级授权与审计

## 5. 一句话结论

后端 `P0` 的重点不是把所有基础设施先铺满，而是把 Java/Python/数据库三者之间的权责边界做稳，再把主链路逐段打通。

## 6. 进一步细化

- 表迁移顺序、API 实现顺序、DTO 字段清单见 [00E-P0-BACKEND-ORDER-AND-DTOS.md](./00E-P0-BACKEND-ORDER-AND-DTOS.md)
