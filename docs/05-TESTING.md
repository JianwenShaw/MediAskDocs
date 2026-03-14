# 测试策略与质量要求（P0 毕设版）

> 本文档只约束当前毕业设计主线的测试范围与质量门禁。
>
> 口径基线以 `01-OVERVIEW.md`、`07E-DATABASE-PRIORITY.md`、`12-AI_RAG_IMPLEMENTATION_PLAN.md`、`17A-REQUEST_CONTEXT_IMPLEMENTATION.md` 为准。

---

## 1. 测试目标

### 1.1 P0 测试目标

| 目标 | 说明 | 优先级 |
|------|------|--------|
| **主链路正确** | 打通 AI 问诊 → 挂号 → 接诊 → 病历 → 处方 | P0 |
| **跨服务可追踪** | Java ↔ Python ↔ 审计能用同一 `request_id` 串起来 | P0 |
| **安全合规** | 对象级授权、数据范围、敏感访问留痕可验证 | P0 |
| **回归稳定** | 核心链路在改动后不被破坏 | P0 |
| **性能基线** | 形成最小可说明的响应时间与降级结果 | P1 |

### 1.2 测试原则

- 左移测试：领域规则、状态机、错误映射优先单测覆盖。
- 主链路优先：优先保障题目主线，不把时间投到非核心工程化压测。
- 自动化优先：能自动化的核心流程不依赖纯手工回归。
- 契约优先：Java ↔ Python 的请求头、错误响应、SSE 事件必须有契约测试。

---

## 2. P0 范围与非目标

### 2.1 本轮必须覆盖的范围

| 模块 | 必测内容 |
|------|---------|
| **AI/RAG** | `knowledge/index`、`knowledge/search`、`chat`、`chat/stream`、引用留痕、降级路径 |
| **医疗闭环** | `clinic_session -> clinic_slot -> registration_order -> visit_encounter -> emr_record -> prescription_order` |
| **权限与审计** | RBAC、数据范围、对象级授权、`data_access_log`、关键业务审计 |
| **请求串联** | `X-Request-Id` 透传、`request_id` 日志字段、跨服务抽样追踪 |
| **AI 安全边界** | 不输出诊断结论、不输出处方建议、护栏命中可留痕 |

### 2.2 本轮不设为硬门禁的内容

- 支付、退款、锁号释放等完整交易治理
- 复杂排班求解器与高并发抢号压测
- SkyWalking / Elasticsearch / 预发布环境级别的重型基础设施验证
- 生产级长稳压测、漏洞扫描、超长留存治理

说明：这些能力可保留为 `P1/P2` 扩展设计，但不应阻塞当前开发启动。

---

## 3. 测试分层策略

### 3.1 分层

| 层级 | 测试对象 | 重点 | 环境 | 执行频率 |
|------|---------|------|------|---------|
| **单元测试** | Domain、UseCase、Guardrail、Mapper/Converter | 状态机、规则、不变量、错误分支 | Mock 依赖 | 每次提交 |
| **集成测试** | Controller、Repository、Python Client、审计写库 | DB 交互、对象级授权、错误映射 | TestContainers / 本地依赖 | 每次提交 |
| **契约测试** | Java ↔ Python HTTP/SSE | `X-Request-Id`、错误响应、`meta/end/error` 事件 | Mock Python / Mock LLM | 每次提交 |
| **端到端测试** | 毕设主链路 | AI 问诊到接诊闭环演示 | 本地联调环境 | 里程碑前 |

### 3.2 测试金字塔

```
        ┌──────────────────────────────┐
        │ E2E 主链路测试               │
        │ AI → 挂号 → 接诊 → 病历处方  │
        └────────────┬─────────────────┘
                     │
        ┌────────────┴─────────────────┐
        │ 集成 / 契约测试              │
        │ DB、权限、Java↔Python 协议   │
        └────────────┬─────────────────┘
                     │
        ┌────────────┴─────────────────┐
        │ 单元测试                     │
        │ 领域规则、状态机、降级逻辑   │
        └──────────────────────────────┘
```

---

## 4. P0 必测场景

### 4.1 AI/RAG 主链路

| 场景 | 断言 |
|------|------|
| 知识索引成功 | `knowledge_chunk_index` 写入成功，Java 才能把 `knowledge_document` 置为 `ACTIVE` |
| 知识索引失败 | 文档不得误标为可用，保留重试入口 |
| 检索成功 | 返回 `chunk_id/score/metadata`，并写 `ai_run_citation` |
| 检索无结果 | 进入保守降级路径，`is_degraded=true` |
| 普通对话 | 返回 `answer/citations/risk_level`，Java 回填 `ai_model_run/ai_turn_content/ai_guardrail_event` |
| 流式对话 | 稳定输出 `message/meta/end/error`，异常时能正确结束 |
| 护栏约束 | 对诊断结论、处方建议、剂量问题进行拒答或谨慎回答 |

### 4.2 医疗业务闭环

| 场景 | 断言 |
|------|------|
| 患者根据导诊建议挂号 | 可创建 `registration_order`，关联正确患者/科室/医生 |
| 医生发起接诊 | 基于挂号记录创建 `visit_encounter` |
| 医生写病历 | `emr_record` 与 `emr_record_content` 成功落库 |
| 医生写诊断与处方 | `emr_diagnosis`、`prescription_order`、`prescription_item` 成功落库 |
| 非法状态流转 | 不允许跳过关键状态或重复落库 |

### 4.3 权限、审计与请求上下文

| 场景 | 断言 |
|------|------|
| 非授权医生查看他人病历 | 返回 `403/404`，且不泄露资源存在性细节 |
| 患者查看非本人数据 | 返回拒绝，不能越权读取 AI 会话/病历/处方 |
| 查看病历正文或 AI 原文 | 写入 `data_access_log` |
| 关键业务动作 | 写入 `audit_event` |
| 透传 `X-Request-Id` | Java、Python、审计记录共享同一 `request_id` |
| 未传 `X-Request-Id` | 自动生成并回写响应头 |
| Python 异常 | 统一映射为 `code/msg/requestId/timestamp`，Java Client 可识别 |

### 4.4 异常场景最小集合

- 参数校验异常：空值、格式错误、枚举非法。
- 业务规则异常：状态不合法、重复创建、权限不足。
- 外部依赖故障：数据库异常、Redis 异常、Python HTTP 超时、LLM 不可用。
- 流式异常：中途失败仍能输出 `error` 事件并结束。

---

## 5. 覆盖率与质量门禁

### 5.1 覆盖率基线

| 模块类型 | 行覆盖率 | 分支覆盖率 |
|---------|---------|-----------|
| **Domain / Guardrail** | ≥ 85% | ≥ 80% |
| **Application / UseCase** | ≥ 80% | ≥ 75% |
| **Controller / Client / Adapter** | ≥ 70% | ≥ 60% |
| **新增代码整体** | ≥ 80% | ≥ 70% |

### 5.2 P0 提交门禁

| 检查项 | 要求 |
|--------|------|
| 单元测试 | 100% 通过 |
| 集成/契约测试 | 100% 通过 |
| 新增代码覆盖率 | 达到基线 |
| 关键主链路用例 | 至少一条自动化通过 |
| 代码规范检查 | 0 错误 |

### 5.3 P0 演示门禁

以下 6 项全部通过，才算“可答辩演示”：

1. AI 问诊可以返回引用或明确降级结果。
2. AI 结果可以进入挂号与接诊链路。
3. 医生可以完成病历、诊断、处方落库。
4. 非授权访问会被拒绝。
5. 敏感正文读取会留下访问日志。
6. 能按同一 `request_id` 展示 Java、Python、审计三处记录。

---

## 6. 测试环境与工具

### 6.1 环境

| 环境 | 用途 | 数据来源 |
|------|------|---------|
| **本地开发** | 单测、集成测试、联调自测 | Mock 数据 / 固定夹具 |
| **CI 环境** | 自动化回归 | TestContainers + Mock 外部依赖 |
| **演示环境** | 答辩前联调与录屏 | 脱敏演示数据 |

说明：`P0` 不要求先建立预发布环境和生产副本数据链路。

### 6.2 工具

| 测试类型 | 工具/框架 |
|---------|---------|
| **Java 单元测试** | JUnit 5 + Mockito |
| **Java 集成测试** | Spring Boot Test + TestContainers |
| **HTTP 契约测试** | MockMvc / RestAssured / WireMock |
| **Python 接口测试** | `httpx.AsyncClient` |
| **覆盖率统计** | JaCoCo / pytest-cov |

### 6.3 Mock 策略

| 依赖类型 | 策略 |
|---------|------|
| PostgreSQL / Redis | 单测 Mock，集成测试尽量真实 |
| Python AI 服务 | Java 侧使用 Mock Server 或 WireMock |
| LLM / Embedding | 固定响应或 Fake Provider，避免测试不稳定 |
| 审计 / 访问日志 | 以真实写库断言为主，不只校验方法被调用 |

---

## 7. 测试规范

### 7.1 命名示例

单元测试：

```text
方法名_场景描述_期望结果

示例：createRegistration_WhenSlotUnavailable_ThrowException
示例：guardrail_WhenPrescriptionRequested_ReturnRefusal
```

集成测试：

```text
业务流程描述

示例：testP0Flow_AiTriageToEncounterAndEmr
示例：testDoctorCannotReadOtherDoctorsEmr
```

### 7.2 AAA 模式

```java
// Arrange: 准备测试数据和依赖
// Act: 执行业务动作
// Assert: 断言状态、日志、审计、副作用
```

### 7.3 禁止项

- 测试之间相互依赖。
- 只验证返回码，不验证审计/访问日志副作用。
- 只测“有权限”路径，不测“越权失败”路径。
- 让真实 LLM 结果决定测试是否通过。

---

## 8. P1/P2 后置测试

以下内容保留为后续增强，不作为当前开发启动阻塞项：

- 高并发抢号压测与锁号释放演练
- 长稳压测、故障注入、容量规划
- 重型安全扫描与供应链治理
- SkyWalking / Elasticsearch / 多节点拓扑级验证

---

**关联文档**：
- [系统架构概览](./01-OVERVIEW.md)
- [数据库优先级重排（V3 毕设主线版）](./07E-DATABASE-PRIORITY.md)
- [AI/RAG 核心模块实现计划（P0 基线版）](./12-AI_RAG_IMPLEMENTATION_PLAN.md)
- [请求上下文实现口径](./17A-REQUEST_CONTEXT_IMPLEMENTATION.md)
