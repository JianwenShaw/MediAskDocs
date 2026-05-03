# 审计与事件表设计逐表说明（V3）

> 本文对 V3 审计、访问日志、领域事件相关表做逐表说明。
> 重点不是复述 DDL，而是解释为什么审计日志、访问日志、领域事件、Outbox 必须分开，以及每张表在监管、集成和架构演进中的真实作用。
>
> 数据库引擎：PostgreSQL 17+（V3 统一迁移，详见 [07-DATABASE.md](./07-DATABASE.md)）。

## 0. 当前阶段怎么读本文

本文保留审计与事件表的完整演进设计，但当前毕设实现优先级固定为：

| 层级 | 当前要求 |
|------|----------|
| `P0` | `audit_event`、`data_access_log` |
| `P1` | `audit_payload` |
| `P2` | `domain_event_stream`、`outbox_event`、`integration_event_archive` |

如果本文的完整设计描述与 `docs/00A-P0-BASELINE.md`、`docs/07E-DATABASE-PRIORITY.md` 冲突，以后两者为准。

## 1. 设计总原则

- 操作审计、敏感数据访问监管、业务事件、可靠投递是四种不同事实
- 审计索引和高敏载荷必须拆层
- 访问过什么，比修改了什么，在医疗场景里同样重要
- 领域事件应服务于业务编排，不应沦为审计替代品
- Outbox 是工程可靠性机制，不是业务真相表
- 审计监管表物理落在 `audit` schema，业务事件与 Outbox 物理落在 `event` schema，但仍共享同一 PostgreSQL 实例与事务边界
- 权威审计写入必须在业务事务内同步完成；异步监听只用于报表、投影或可选 ES 同步
- `audit_event`、`data_access_log` 采用 append-only + 按月分区，归档与清理基于分区完成

## 2. `audit_event`

### 2.1 这张表回答什么问题

- 谁在什么时间做了什么操作
- 操作的目标资源是什么
- 影响了哪位患者 / 哪次接诊
- 是否成功
- 请求链路 request_id 是什么

### 2.2 为什么必须有审计头表

很多系统喜欢把审计前后值直接塞进一张日志大表，但这会导致：

- 索引字段和高敏 payload 混在一起
- 普通审计查询也要扫大文本
- 查询成本高，权限边界模糊

所以 V3 把审计拆成两层：

- `audit_event`：审计索引头
- `audit_payload`：审计高敏载荷

### 2.3 关键字段

- `request_id`：跨网关、Java、Python、审计排查的主线索
- `trace_id`：P2 启用 APM 时用于额外对齐 SkyWalking / OpenTelemetry
- `actor_type`：当前默认 `USER`，后续可扩展 `SYSTEM`
- `operator_user_id`：明确是谁操作的
- `operator_username`：保留操作时使用的登录名；登录失败时尤其需要它来定位被尝试的账号
- `operator_role_code`：保留操作时的角色视角，避免后续角色变更后回溯困难
- `actor_department_id`：定位操作者当时处于哪个科室/组织视角
- `action_code`：标准化业务动作码，如 `AUTH_LOGIN_SUCCESS`、`REGISTRATION_CREATE`、`EMR_SAVE`、`ROLE_ASSIGN`
- `resource_type` / `resource_id`：形成审计对象索引；`resource_id` 在 P0 固定使用稳定业务键字符串，例如 `encounterId`、`sessionId`
- `patient_user_id`：关联患者主体，支持“最近谁动过这个患者的数据”
- `encounter_id`：关联一次接诊，方便从病历、诊断、处方回溯到诊疗现场
- `success_flag`：便于区分成功与失败操作，支持安全分析
- `client_ip` / `user_agent`：支持基础安全排查
- `reason_text`：导出、高权限变更、二次确认等场景的操作理由；`P0` 当前也用于记录 `AUDIT_QUERY` 的受控查询摘要，字段长度建议至少 `VARCHAR(1024)`

`P0` 不建议把病历原文、AI 原文、证件号、手机号前后值直接塞进 `audit_event`；这类高敏内容如确有需要，后续统一进入 `audit_payload`。

### 2.4 推荐索引

`audit_event` 至少应具备以下查询索引：

- `idx_audit_event_request (request_id)`
- `idx_audit_event_user_time (operator_user_id, occurred_at)`
- `idx_audit_event_resource (resource_type, resource_id, occurred_at)`
- `idx_audit_event_action (action_code, occurred_at)`
- `brin_audit_event_occurred_at (occurred_at)`

其中 `idx_audit_event_action` 是 P1 阶段必须补齐的索引，因为审计平台最常见的问题之一就是：

- 查所有 `AI_REVIEW`
- 查所有 `DELETE`
- 查所有 `EXPORT`

如果只有用户维度和资源维度索引，按动作码筛选会退化成大范围扫描。

## 3. `audit_payload`

### 3.1 这张表回答什么问题

- 请求参数是什么
- 修改前值是什么
- 修改后值是什么

### 3.2 为什么必须独立于 `audit_event`

因为这里天然是高敏区：

- 病历字段
- 处方字段
- AI 原文摘要
- 用户身份信息

如果把这些内容和审计索引头混在一起，后果通常是：

- 任何能查审计表的人都可能顺手看到敏感内容
- 审计检索性能越来越差
- 表膨胀严重

### 3.3 关键字段

- `request_payload_encrypted`：原始请求密文
- `before_payload_encrypted`：变更前值密文
- `after_payload_encrypted`：变更后值密文
- `*_masked`：给普通审计场景提供受控预览，不必每次解密
- `*_hash`：用于完整性校验、对账与差异比对，避免频繁解密大载荷

### 3.4 这张表的真正价值

它让系统能够同时满足两件事：

- 需要时能追溯完整敏感变更内容
- 日常情况下又不会因为审计检索而过度暴露高敏字段

## 4. `data_access_log`

### 4.1 这张表回答什么问题

- 谁查看了哪份病历
- 谁导出了哪张处方
- 谁看了哪段 AI 原文
- 谁查看了患者身份信息
- 谁访问审计密文载荷被允许或拒绝

### 4.2 为什么它不能并入 `audit_event`

因为“访问敏感数据”和“修改业务数据”不是一回事。

例如：

- 医生查看病历正文
- 管理员导出 AI 复核明细
- 审计员查看审计载荷

这些操作可能没有修改任何业务数据，但在医疗系统里仍然必须监管。

所以 `data_access_log` 是一个独立领域：

- 面向合规监管
- 面向隐私审计
- 面向最小权限原则落地

### 4.3 关键字段

- `actor_type`：当前默认 `USER`，后续可扩展 `SYSTEM`
- `actor_department_id`：保留操作者所在科室/组织上下文
- `operator_username`：保留操作者当时的登录名，便于直接排查账号层面的敏感访问
- `access_action`：查看、导出、下载、打印等访问动作
- `access_purpose_code`：为什么看，建议固定为 `TREATMENT`、`SELF_SERVICE`、`ADMIN_OPERATION`、`SECURITY_INVESTIGATION`、`AUDIT_REVIEW`
- `resource_type` / `resource_id`：看了什么；允许与拒绝访问必须使用同一业务键口径，避免追责时出现资源对不上
- `patient_user_id`：如果是患者相关敏感数据，这个字段很关键
- `encounter_id`：如果访问对象归属于一次诊疗，应同步写入
- `access_result` / `deny_reason_code`：不只是记录允许，还要记录拒绝
- `client_ip` / `user_agent`：用于识别异常终端与可疑来源
- `request_id` / `trace_id`：默认靠 `request_id` 对齐；启用 APM 时再补 `trace_id`

`P0` 最少应覆盖：

- 病历正文
- 诊断详情
- 处方详情
- AI 原文 / 完整问诊明细
- 患者身份信息详情
- 审计明细本身

### 4.4 为什么这张表在医疗系统里非常重要

很多真正的风险不是“谁改了病历”，而是“谁看了不该看的病历”。

所以这张表不是辅助功能，而是核心监管能力。

## 5. `domain_event_stream`

> 当前定位：`P2` 保留设计，不作为毕设主链路前置能力。

### 5.1 这张表回答什么问题

- 业务上发生了什么事实
- 例如挂号确认、门诊停诊、病历签署、AI 复核完成

### 5.2 为什么不能用审计日志替代它

审计日志记录的是“谁做了什么操作”。

领域事件记录的是“业务世界里发生了什么变化”。

两者看似接近，但本质不同：

- 审计面向监管
- 事件面向业务编排和异步处理

### 5.3 关键字段

- `event_key`：事件全局唯一键
- `aggregate_type` / `aggregate_id`：事件归属聚合根
- `event_type`：明确是哪种业务事实
- `event_payload_json`：仅承载最小化、脱敏后的事件内容
- `event_payload_encrypted`：需要保留的敏感事件明细密文
- `payload_hash`：用于对账、去重与安全追踪
- `request_id`：便于与业务请求和审计链串联
- `trace_id`：P2 启用 APM 时便于与 Span 链路对齐

## 6. `outbox_event`

> 当前定位：`P2` 保留设计，不作为当前实现重点。

### 6.1 这张表回答什么问题

- 哪些领域事件需要可靠投递给外部系统或异步消费者
- 当前发布状态如何
- 是否需要重试

### 6.2 为什么它不能和 `domain_event_stream` 合并

因为两者职责不同：

- `domain_event_stream` 是业务真相
- `outbox_event` 是投递机制

一个领域事件可能：

- 不需要对外发
- 需要发多个下游
- 因为网络问题多次重试

如果把这些工程状态和业务事实混在一起，事件表会变得又脏又难维护。

### 6.3 关键字段

- `publish_status`：投递状态
- `retry_count`：重试次数
- `next_retry_at`：调度重试时间
- `published_at`：最终成功时间
- `domain_event_id`：明确来源于哪条业务事件，保证 outbox 不是脱离业务真相的孤立投递记录
- `payload_json` / `payload_encrypted` / `payload_hash`：同样采用“最小明文 + 可选密文 + 哈希”分层，避免把病历、AI 原文、处方详情直接扩散到消息链路

这些字段都明显属于“投递系统”，不是领域本身。

## 7. `integration_event_archive`

> 当前定位：`P2` 保留设计，仅在事件可靠投递体系成立后再引入。

### 7.1 这张表回答什么问题

- 哪些 outbox 事件已经完成归档
- 归档时间是什么

### 7.2 为什么不直接只靠 `outbox_event.publish_status`

因为投递完成后的事件和仍在活动中的 outbox 事件，生命周期不同。

归档表的价值在于：

- 主 outbox 表可以保持相对轻量
- 历史成功事件可单独保留
- 未来做归档、冷热分层会更方便

## 8. 这 6 张表之间的关系

可以把这 6 张表理解为两大块：

### 8.1 监管块

- `audit_event`
- `audit_payload`
- `data_access_log`

解决的是：

- 谁做了什么
- 谁看了什么
- 敏感载荷如何受控留痕

### 8.2 事件块

- `domain_event_stream`
- `outbox_event`
- `integration_event_archive`

这些表在当前阶段属于后续增强设计，不应反向驱动 `P0` 的实现顺序。

解决的是：

- 业务事实如何表达
- 事件如何可靠投递
- 投递后如何归档

### 8.3 物理落库策略

- `audit.audit_event`
- `audit.audit_payload`
- `audit.data_access_log`
- `event.domain_event_stream`
- `event.outbox_event`
- `event.integration_event_archive`

这样做的原因是：

- 不引入独立数据库，就能获得清晰的权限边界与备份治理边界
- 审计写入仍可与业务写入保持同事务提交，不产生跨库双写问题
- 未来如果要做 Elasticsearch 审计索引，也应从 `audit.audit_event` 异步投影，而不是把 ES 变成权威写入链路的一部分

## 9. 典型场景串起来怎么理解

比如医生完成 AI 复核：

- `P0`：Java 写 `audit_event`
  - 表示“某医生执行了 AI 复核操作”，并与业务事务同提交
- `P0`：如果有人查看 AI 原文，再写 `data_access_log`
- `P1`：如果确有敏感前后值留存需求，再写 `audit_payload`
- `P2`：如果要把“AI 复核已完成”作为独立业务事件，再写 `domain_event_stream`
- `P2`：如果这个事件要通知别的系统，再写 `outbox_event`
- `P2`：投递完成后再写 `integration_event_archive`

这就是“先监管闭环，再工程化事件体系”的分阶段闭环。

## 10. 为什么这套设计比 V2 稳定

V2 的问题在于：

- `audit_logs` 既想做索引，又想做 payload 容器
- `domain_events` 又想包业务事件，又容易被误用成审计替代品

V3 的改进点是把职责彻底拆开：

- 审计只管操作留痕
- 访问日志只管敏感数据访问监管
- 领域事件只管业务事实
- Outbox 只管可靠投递

这样后面不管是做：

- 合规监管
- 运营追查
- 安全审计
- 事件驱动集成

都不会互相打架。

## 11. 一句话总结

`07-domain-events.sql` 的设计本质上是在把“谁做了什么”“谁看了什么”“业务发生了什么”“事件怎么发出去”这四件事拆开。

只有拆开，审计才不会污染业务，事件才不会污染监管，系统才能长期演进。
