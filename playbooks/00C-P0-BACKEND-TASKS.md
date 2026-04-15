# P0 后端任务清单

> 状态：Backend Execution Checklist / Current Repo Snapshot
>
> 目标：把 `P0` 主链路拆成后端可直接执行的任务包，并明确当前仓库除了 `RAG` 本身之外还缺哪些后端能力。

判定口径：

- 以当前 `mediask-backend` 仓库中的 Java 代码、SQL、测试和 `qingniao` 脚本为准。
- 已有 schema 不等于业务已交付；接口、UseCase、持久化和联调链路打通后才算任务完成。

## 1. 后端总目标

后端 `P0` 只需要打通一条主线：

`认证 -> AI 问诊 -> RAG 引用 -> 导诊结果 -> 挂号 -> 接诊 -> 病历 -> 处方 -> 权限校验 -> 审计留痕`

## 2. 当前后端完成度速览

| 任务包 | 当前状态 | 说明 |
|------|----------|------|
| Task A：公共协议与请求上下文 | 完成 | `Result<T>`、错误处理、`requestId`、JWT、健康检查、对外 `SSE` 协议与结构化日志基线已完成；当前 `6001` 属于 Java -> Python AI 联调问题，不再归入 Task A |
| Task B：认证、角色、数据范围基线 | 部分完成 | 登录/刷新/登出/当前用户、本人资料、管理员患者管理已完成；对象级授权仍缺资源解析实现 |
| Task C：知识库与 RAG 底座 | 未完成 | 表结构与 Java AI client 骨架已在仓库中，知识导入与索引链路未开始 |
| Task D：AI 问诊主链路 | 未完成 | 没有 AI Controller/UseCase/会话持久化/对外接口 |
| Task E：AI 到挂号承接 | 大体完成 | 场次查询、挂号创建、挂号列表、`registration-handoff` 已完成；AI 来源校验与完整验收仍待补强 |
| Task F：医生接诊、病历、处方 | 部分完成 | 接诊列表已完成；接诊详情、AI 摘要、病历、处方未完成 |
| Task G：审计与敏感访问留痕 | 未完成 | 审计表已建，写入与查询完全未落地 |

## 3. 任务包拆分

## 3.1 Task A：公共协议与请求上下文

### 交付物

- [x] `Result<T>` 统一成功响应
- [x] 统一错误码与全局异常处理
- [x] `X-Request-Id` 生成、透传、回写
- [x] Java `health/readiness/liveness` 端点开放
- [x] Java -> Python 的 `X-Request-Id` 与 `X-API-Key` client 基础设施
- [x] Java `JSON` 接口与 `SSE` 接口口径分离
- [x] Logback 结构化日志 / `request_id` 日志输出

### 关键文件/模块

- `mediask-common`
- `mediask-api`
- `mediask-infra`
- `docs/19-ERROR_EXCEPTION_RESPONSE_DESIGN.md`
- `docs/17A-REQUEST_CONTEXT_IMPLEMENTATION.md`

### 验收标准

- [x] 所有 `JSON` 接口返回 `Result<T>`
- [x] 任意报错都带稳定 `requestId`
- [x] `SSE` 返回 `message / meta / end / error`
- [x] Java 日志中稳定输出 `request_id`

## 3.2 Task B：认证、角色、数据范围基线

### 交付物

- [x] 登录 / 刷新 / 登出 / 当前用户接口
- [x] 患者 / 医生 / 管理员角色识别
- [x] 患者本人资料、医生本人资料查询与更新
- [x] 管理员患者列表 / 详情 / 新增 / 修改 / 删除
- [x] `data_scope_rules` 装载进认证用户
- [x] `ScenarioAuthorization` 场景鉴权骨架
- [ ] `ResourceReferenceAssemblerPort` / `ResourceAccessResolverPort` 实现
- [ ] `EMR_RECORD` / `AI_SESSION` 的对象级授权闭环

### 关键表

- [x] `users`
- [x] `roles`
- [x] `permissions`
- [x] `user_roles`
- [x] `role_permissions`
- [x] `data_scope_rules`

### 验收标准

- [x] 患者只能访问自己的资料与挂号列表
- [x] 医生接诊列表按本人 `doctorId` 过滤
- [ ] 患者不能读取他人病历与 AI 原文
- [ ] 医生不能读取超出部门范围的病历与 AI 原文
- [ ] 管理员拥有最小审计查询能力

## 3.3 Task C：知识库与 RAG 底座

### 交付物

- [x] 知识库后台管理接口：`GET /api/v1/admin/knowledge-bases`
- [x] 知识库后台管理接口：`POST /api/v1/admin/knowledge-bases`
- [x] 知识库后台管理接口：`PATCH /api/v1/admin/knowledge-bases/{id}`
- [x] 知识库后台管理接口：`DELETE /api/v1/admin/knowledge-bases/{id}`
- [x] Java 侧 AI client / DTO / 错误映射骨架
- [x] 知识文档入库最小后台接口：`POST /api/v1/admin/knowledge-documents/import`（`multipart/form-data` 文件上传）
- [x] 知识文档后台管理接口：`GET /api/v1/admin/knowledge-documents`
- [x] 知识文档后台管理接口：`DELETE /api/v1/admin/knowledge-documents/{id}`
- [x] Java 调 Python 解析原始文档并接收 chunk payload
- [x] `knowledge_document` / `knowledge_chunk` 持久化
- [x] Java 调 Python 建立索引
- [ ] Python 写 `knowledge_chunk_index`

### 关键接口

- [x] Java：`GET /api/v1/admin/knowledge-bases`
- [x] Java：`POST /api/v1/admin/knowledge-bases`
- [x] Java：`PATCH /api/v1/admin/knowledge-bases/{id}`
- [x] Java：`DELETE /api/v1/admin/knowledge-bases/{id}`
- [x] Java：`POST /api/v1/admin/knowledge-documents/import`
- [x] Java：`GET /api/v1/admin/knowledge-documents`
- [x] Java：`DELETE /api/v1/admin/knowledge-documents/{id}`
- [ ] Python：`/api/v1/knowledge/prepare`
- [ ] Python：`/api/v1/knowledge/index`
- [ ] Python：`/api/v1/knowledge/search`

### 验收标准

- [ ] 至少一套知识文档可被检索命中
- [ ] `knowledge_chunk_index` 由 Python 写入

## 3.4 Task D：AI 问诊主链路

### 交付物

- [x] `AiChatPort`、`PythonAiChatPortAdapter`、请求/响应 DTO 契约
- [x] `POST /api/v1/ai/chat`
- [x] `POST /api/v1/ai/chat/stream`
- [x] `GET /api/v1/ai/sessions`
- [x] `GET /api/v1/ai/sessions/{sessionId}`
- [x] `GET /api/v1/ai/sessions/{sessionId}/triage-result`

### 关键表

- [x] `ai_session`
- [x] `ai_turn`
- [x] `ai_turn_content`
- [x] `ai_model_run`
- [x] `ai_guardrail_event`
- [x] `ai_run_citation`

### 实现规则

- [x] Java 预创建 `ai_model_run`
- [x] Java 持久化 `ai_session`、`ai_turn`、`ai_turn_content`
- [x] Java 调 Python 时透传 `model_run_id + request_id`
- [ ] Python 负责检索、生成、护栏、引用写入
- [x] Java 负责会话主事实、对外协议、审计串联

### 验收标准

- [x] 回答可展示引用
- [x] 返回 `riskLevel / guardrailAction / nextAction`
- [x] 高风险分支不继续普通问答

## 3.5 Task E：AI 到挂号承接

### 交付物

- [x] `POST /api/v1/ai/sessions/{sessionId}/registration-handoff`
- [x] `GET /api/v1/clinic-sessions`
- [x] `POST /api/v1/registrations`
- [x] `GET /api/v1/registrations`

### 关键表

- [x] `clinic_session`
- [x] `clinic_slot`
- [x] `registration_order`

### 验收标准

- [x] 患者可基于现有门诊场次完成挂号
- [x] 挂号成功后预创建 `visit_encounter`
- [x] `registration_order.source_ai_session_id` 字段已预留
- [x] AI 推荐科室可转成挂号查询条件
- [x] `registration_order.source_ai_session_id` 已具备现有入参与落库追溯能力，后续仅补强校验与验收

## 3.6 Task F：医生接诊、病历、处方

### 交付物

- [x] `GET /api/v1/encounters`
- [ ] `GET /api/v1/encounters/{encounterId}`
- [ ] `GET /api/v1/encounters/{encounterId}/ai-summary`
- [ ] `POST /api/v1/emr`
- [ ] `GET /api/v1/emr/{encounterId}`
- [ ] `POST /api/v1/prescriptions`
- [ ] `GET /api/v1/prescriptions/{encounterId}`

### 关键表

- [x] `visit_encounter`
- [x] `emr_record`
- [x] `emr_record_content`
- [x] `emr_diagnosis`
- [x] `prescription_order`
- [x] `prescription_item`

### 验收标准

- [x] 医生可查看本人接诊列表
- [ ] 医生默认只看 AI 摘要，不直接看原文
- [ ] 接诊后可形成病历、诊断、处方闭环

## 3.7 Task G：审计与敏感访问留痕

### 交付物

- [x] `audit_event` / `data_access_log` schema
- [x] `ScenarioCode` 已预留 `EMR_RECORD_*`、`AI_SESSION_*` 场景码
- [ ] `audit_event` 写入链路
- [ ] `data_access_log` 写入链路
- [ ] 审计最小查询接口

### 关键表

- [x] `audit_event`
- [x] `data_access_log`

### 强约束

- [ ] 查看病历正文要写 `data_access_log`
- [ ] 查看 AI 原文要写 `data_access_log`
- [ ] 登录、挂号、病历保存、处方保存、权限变更要写 `audit_event`

## 4. Java / Python 分工

| 能力 | Java | Python | 当前状态 |
|------|------|--------|----------|
| 认证与权限 | 负责 | 不负责 | Java 基础认证已完成，对象级授权未闭环 |
| 会话主事实 | 负责 | 不负责 | 未开始 |
| RAG 检索 | 调用与整合 | 负责执行 | Java client 骨架已完成，实际链路未开始 |
| 护栏输出 | 映射 `nextAction` | 输出 `risk_level` 与 `guardrail_action` | 未开始 |
| 浏览器协议 | 负责 | 不负责 | Java 对外 AI 接口未开始 |
| `knowledge_chunk_index` | 不写 | 负责 | 未开始 |
| `ai_run_citation` | 不写 | 负责 | 未开始 |
| 审计 / 访问日志 | 负责 | 不负责 | schema 已有，写入未开始 |

## 5. 后续联调顺序

当前仓库已完成的前置能力是：认证、门诊场次查询、挂号、接诊列表、`requestId` 基线。

在此基础上，剩余后端工作建议按下面顺序推进：

1. Java 落地 `ai_session` / `ai_turn` / `ai_model_run` 与 `POST /api/v1/ai/chat`
2. Python 落地 `/health`、`/ready`、`/api/v1/chat`、`/api/v1/knowledge/*`
3. 打通 RAG 索引与检索闭环
4. 补 Java 对外 `SSE` 转发与 `triage-result`
5. 完成 `registration-handoff`
6. 完成接诊详情、AI 摘要、病历、处方
7. 完成对象级授权、`audit_event`、`data_access_log`
8. 补结构化日志与 `request_id` 全链路可观测性

## 6. 一句话结论

除了 `RAG` 本身，当前后端还缺的是：`AI 对外主链接口`、`AI -> 挂号承接`、`病历/处方闭环`、`对象级授权与审计留痕`、`SSE` 和 `request_id` 可观测性闭环。

## 7. 进一步细化

- 表迁移顺序、API 实现顺序、DTO 字段清单见 [00E-P0-BACKEND-ORDER-AND-DTOS.md](./00E-P0-BACKEND-ORDER-AND-DTOS.md)
