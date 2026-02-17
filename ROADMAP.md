# 后端 Java 开发路线图（毕设导向）

> 目标：让你后续每一轮开发都“有目的、有产出、可验收”，并和答辩材料直接对齐。
>
> 适用时间：2026-02-14 之后当前学期。
>
> 约束：以当前 `mediask-be` 实现为基线，优先补齐 Java 主链路，再推进 AI 联动。

## 0. 使用方式（建议阅读/执行顺序）

1) 先看“当前基线”，明确你已经有什么、缺什么。
2) 再看“路线总览”，确认当前你在哪个阶段（P0~P4）。
3) 进入对应阶段时，只盯 4 件事：开发目标、学习目标、产出位置、验收标准。
4) 每次改接口，顺手同步 `api-docs/openapi.json` 与 `api-docs/README.md`，避免演示时卡文档。

构建/测试命令约定（按仓库 `AGENTS.md` 平台规则）：
- macOS：`./scripts/m21.sh clean verify`
- 非 macOS：`mvn clean verify`

## 1. 当前基线（你已经有的）

- 架构：模块化单体（`api/service/domain/infra/dal/common/worker`）。
- 已落地主能力：认证授权、医生管理、排班、预约、AI 反馈统计。
- 工程基线：JDK 21、Spring Boot 3.5.8、MyBatis-Plus 3.5.15、JWT、Redis/Redisson。

补充说明（避免答辩时口径被追问）：
- `MediAskDocs` 中出现的 Milvus / Python AI 微服务 / RocketMQ / ELK / SkyWalking 等，很多是规划项；是否“已落地”以当前 Java 代码与 `mediask-dal/src/main/resources/sql/init-dev.sql` 为准。
- 数据库结构以 `init-dev.sql` 为事实来源：在你推进 P1（病历/处方）之前，需要先确认对应表是否已创建并同步数据库文档。

结论：
- 你现在不是“从 0 到 1”，而是“从可运行到可答辩、可展示、可解释”阶段。

## 2. 路线总览（按优先级）

```mermaid
flowchart LR
    A[P0 业务闭环加固] --> B[P1 病历处方补齐]
    B --> C[P2 AI联动集成]
    C --> D[P3 可观测与稳定性]
    D --> E[P4 答辩资产沉淀]
```

## 3. 每阶段要做什么、学什么、产出到哪里（统一结构）

### P0（2-3 周）业务闭环加固：把现有能力做"稳"

#### 工程基线建设

##### 多实例部署迁移

当前项目仍为 Spring Boot 单体多模块架构。为支撑未来多实例部署与水平扩展，需提前预留可扩展空间。

**技术要点**：
- 无状态化设计（会话、缓存外置）
- 分布式锁与幂等设计
- 支持负载均衡与优雅启停

##### 基础设施建设

###### 2.1 日志与链路追踪

当前日志架构存在以下问题：
- 缺乏完整链路追踪能力
- 审计、Debug、上下文查询困难

**技术选型**：

| 能力 | 推荐方案 |
|------|----------|
| 分布式链路追踪 | **SkyWalking** / Zipkin |
| 日志采集与检索 | **ELK Stack**（Elasticsearch + Logstash + Kibana） |
| 日志格式 | JSON 结构化日志，统一字段规范 |

**建设目标**：
- 每条日志携带 `traceId`、`spanId`、`userId`
- 支持请求全链路追踪
- 支持按时间、关键词、日志级别检索

###### 2.2 性能监控

针对以下指标缺乏有效监控：
- 慢 SQL 查询
- QPS 与吞吐
- P99 响应延迟
- JVM 指标（GC、线程、堆内存）

**技术选型**：

| 能力 | 推荐方案 |
|------|----------|
| 指标采集 | **Micrometer**（Spring Boot 原生集成） |
| 时序存储与查询 | **Prometheus** |
| 可视化面板 | **Grafana** |
| 告警 | Prometheus Alertmanager |

**建设目标**：
- 核心接口 QPS、P99 实时监控
- SQL 执行耗时告警（> 100ms）
- 服务可用性告警

##### 中间件封装规范

**封装标准 Checklist**：

| 原则 | 说明 | 示例 |
|------|------|------|
| 接口抽象 | 定义业务接口，不暴露底层客户端 | `TokenCacheService` 而非 `RedisTemplate` |
| 配置外置 | 配置抽离到 Properties 类 | `JwtProperties` |
| 异常转换 | 技术异常转为业务异常 | `LockException` |
| 命名业务化 | 方法名反映业务含义 | `storeToken` 而非 `set` |
| Key 统一管理 | Key 前缀、格式统一 | `"token:" + tokenId` |
| 超时/重试 | 明确超时、重试策略 | `@Retryable` |

**当前问题**：

| 组件 | 问题 | 建议 |
|------|------|------|
| **Redis** | 仅封装 `RedisTemplate`，业务层直接注入使用 | 封装 `CacheService`、`RateLimiter` 等业务服务 |
| **MQ** | 领域事件监听与发布功能未实现，RocketMQ 依赖未引入 | 引入 RocketMQ，实现 `EventPublisher` 与 `@RocketMQMessageListener` |

**待封装清单**：

| 组件 | 封装目标 | 优先级 |
|------|----------|--------|
| Redis | `CacheService`（缓存）、`RateLimiter`（限流） | 高 |
| MQ | `EventPublisher`（事件发布）、`EventListener`（事件消费） | 中 |
| 文件存储 | `OssService`（OSS 操作封装） | 低 |

##### 重构目标

- 解决现有实现中存在的问题，避免演化为技术债务（详见 [架构评审与优化建议](./docs/14-ARCHITECTURE_REVIEW.md)）
- 统一异常处理规范，优化异常类设计

#### 业务闭环回归与功能加固

##### 开发目标

- 基于 RBAC 的权限树实现
- 利用Guava缓存（读多写少且数据量小的）数据如
  - 正则编译结果
  - 科室列表(数据库查询结果，1小时刷新一次)
  - 权限规则:RBAC规则树，变更时主动失效
  - 配置对象：从Nacos / Config Center加载的业务配置（当前项目暂未扩展多实例部署，不予实现）
  - RBAC 权限树
- 完成"患者登录 → 查询号源 → 创建预约 → 支付/取消 → 医生就诊标记"全链路回归测试
- 明确并发与一致性边界：
  - 防超卖（号源扣减原子性）
  - 重复预约（幂等设计）
  - 状态流转合法性校验
- 清理 API 文档与实现的偏差，保证接口可正常演示

##### 学习目标

- Spring 事务边界与幂等设计
- DDD 中应用服务与领域服务的分工
- Redis 分布式锁 / Lua 脚本与数据库兜底的配合方案
- Guava Cache: Guava Cache 适合的是读多写少、需要懒加载或自动刷新、数据源在外部的场景。

##### 产出位置（必须落盘）

| 类型 | 位置 |
|------|------|
| 代码 | `mediask-service`、`mediask-domain`、`mediask-api`、`mediask-infra` |
| 测试 | `mediask-domain/src/test/java`、`mediask-api/src/test/java` |
| 接口文档 | `api-docs/openapi.json`、`api-docs/README.md` |
| 过程记录 | 本文件末尾"周报模板"填写一条 |

##### 验收标准

- [ ] 本地构建/测试全通过：
  - macOS：`./scripts/m21.sh clean verify`
  - 非 macOS：`mvn clean verify`
- [ ] 关键链路至少 1 个集成测试或接口回归脚本
- [ ] 演示时可稳定走通预约闭环，无明显状态错误

### P1（2-4 周）病历/处方补齐：完成论文“医疗核心业务”

补充提醒：当前数据库以 `mediask-dal/src/main/resources/sql/init-dev.sql` 为准；如其中尚未创建病历/处方相关表（常见：`medical_records`、`prescriptions` 等），本阶段需要先补齐 DDL，并同步 `MediAskDocs/docs/07-DATABASE.md`。

#### 开发目标

- 补齐病历模块（草稿、提交、归档、版本记录）。
- 补齐处方模块（处方主表、明细、基础校验）。
- 完成医生工作台所需的核心后端接口。

#### 学习目标

- 领域建模（实体、值对象、聚合边界）。
- 医疗业务规则的编码方式（状态机 + 规则校验）。
- MapStruct/Converter 分层转换实践。

#### 产出位置

- 代码：`mediask-domain`、`mediask-service`、`mediask-infra`、`mediask-api`。
- 数据库：`mediask-dal/src/main/resources/sql/init-dev.sql`（如变更表结构必须同步）。
- 文档：`MediAskDocs/docs/07-DATABASE.md`、`api-docs/openapi.json`、`api-docs/README.md`。

#### 验收标准

- 病历与处方至少形成最小闭环（创建 -> 查询 -> 状态流转）。
- 医疗关键规则有单元测试覆盖。
- 接口文档与代码一致。

### P2（2-3 周）AI 联动集成：Java 侧打通外部 AI 服务

#### 开发目标

- 在 Java 侧增加 AI 调用门面（超时、重试、降级、错误映射）。
- 打通 AI 预问诊入口与结果回写（会话、消息、摘要）。
- 与 Python AI 服务形成稳定契约（请求/响应、SSE、trace_id）。

#### 学习目标

- 外部服务适配层设计（Anti-Corruption Layer）。
- 异常分层与降级策略。
- SSE/流式接口在后端网关中的处理方式。

#### 产出位置

- Java 代码：`mediask-infra`（client/adapter）、`mediask-service`（编排）、`mediask-api`（接口）。
- 协议文档：`api-docs/openapi.json`、`MediAskDocs/docs/10-12` 相关章节同步。
- 可观测字段：日志中统一 `traceId`、`sessionId`。

#### 验收标准

- AI 服务异常时，Java 接口可给出稳定可解释的降级响应。
- 至少完成 1 条“问诊到摘要入库”的可演示链路。

### P3（1-2 周）可观测性与稳定性：让系统“像工程”

#### 开发目标

- 统一关键业务日志字段（用户、请求、耗时、结果码）。
- 对关键路径增加指标统计（预约成功率、AI 调用失败率）。
- 完成配置治理（敏感配置环境变量化、dev/test/prod 明确隔离）。

#### 学习目标

- 面向生产的日志与指标设计。
- 配置与密钥管理基础实践。
- CI 质量门禁思路（测试、覆盖率、契约校验）。

#### 产出位置

- 配置：`mediask-api/src/main/resources/application*.yml`。
- 文档：`MediAskDocs/docs/03-CONFIGURATION.md`、`MediAskDocs/docs/04-DEVOPS.md`。
- CI：`.github/workflows/ci.yml`（如调整门禁）。

#### 验收标准

- 关键接口问题可通过日志快速定位。
- 新增配置项有文档同步，且不把敏感值硬编码进仓库。

### P4（1 周）答辩资产沉淀：把“做了什么”转成“可证明”

#### 开发目标

- 准备 3 条可复现演示脚本：预约闭环、病历处方闭环、AI 辅助闭环。
- 固化答辩证据：接口文档、测试报告、关键日志截图、架构图。
- 对照论文目标做一次“已完成/未完成/风险”清单。

#### 学习目标

- 工程结果表达能力（不仅是写代码）。
- 以验收视角组织项目材料。

#### 产出位置

- 文档：`MediAskDocs/THESIS_OUTLINE.md`、`MediAskDocs/PROJECT_PLAN.md`、本文件。
- API 证据：`api-docs/openapi.json`。
- 测试证据：`**/target/surefire-reports`、`**/target/site/jacoco`（运行后生成）。

#### 验收标准

- 任意一次演示可在 10 分钟内稳定完成。
- 每条主链路都能说清楚“业务价值 + 技术实现 + 风险控制”。

## 4. 每周执行模板（建议固定节奏）

每周固定 1 次复盘，记录在本文件末尾或单独周报：

1. 本周目标（最多 3 项）
2. 实际完成（对照代码提交/文档更新）
3. 遇到问题（技术债/业务不清）
4. 下周计划（继续、调整、砍掉）

## 5. 你的“优先开发清单”（从明天就能做）

1. 为预约主链路补一组端到端回归用例（创建、支付、取消、就诊标记）。
2. 开始病历模块最小闭环（先草稿/提交，不要一上来做全量复杂规则）。
3. 给 AI 接口定义 Java 侧统一错误码和降级返回结构。
4. 每次改接口强制同步 `api-docs/openapi.json` 与 `api-docs/README.md`。

## 6. 成功标准（毕设视角）

当满足以下条件时，你的后端部分就达到了“高质量毕设交付线”：

- 有 3 条稳定可演示业务闭环（预约、病历处方、AI 辅助）。
- 代码分层清晰、关键规则有测试、接口文档与实现一致。
- 遇到外部依赖异常（AI/Redis/DB）时系统可降级，不是直接崩溃。
- 你能解释每个关键设计取舍（为什么这样做，而不是那样做）。
