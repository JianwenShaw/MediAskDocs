# 审计与事件表设计逐表说明（V3）

> 本文对 `mediask-dal/src/main/resources/sql/07-domain-events.sql` 中的每张表做逐表说明。
> 重点不是复述 DDL，而是解释为什么审计日志、访问日志、领域事件、Outbox 必须分开，以及每张表在监管、集成和架构演进中的真实作用。

## 1. 设计总原则

- 操作审计、敏感数据访问监管、业务事件、可靠投递是四种不同事实
- 审计索引和高敏载荷必须拆层
- 访问过什么，比修改了什么，在医疗场景里同样重要
- 领域事件应服务于业务编排，不应沦为审计替代品
- Outbox 是工程可靠性机制，不是业务真相表

## 2. `audit_event`

### 2.1 这张表回答什么问题

- 谁在什么时间做了什么操作
- 操作的目标资源是什么
- 是否成功
- 请求链路 trace_id 是什么

### 2.2 为什么必须有审计头表

很多系统喜欢把审计前后值直接塞进一张日志大表，但这会导致：

- 索引字段和高敏 payload 混在一起
- 普通审计查询也要扫大文本
- 查询成本高，权限边界模糊

所以 V3 把审计拆成两层：

- `audit_event`：审计索引头
- `audit_payload`：审计高敏载荷

### 2.3 关键字段

- `trace_id`：跨 Java、Python、异步任务排查的主线索
- `operator_user_id`：明确是谁操作的
- `operator_role_code`：保留操作时的角色视角，避免后续角色变更后回溯困难
- `action_code`：标准化操作类型，如 CREATE、UPDATE、EXPORT、AI_REVIEW
- `resource_type` / `resource_id`：形成审计对象索引
- `success_flag`：便于区分成功与失败操作，支持安全分析

### 2.4 推荐索引

`audit_event` 至少应具备以下查询索引：

- `idx_audit_event_trace (trace_id)`
- `idx_audit_event_user_time (operator_user_id, occurred_at)`
- `idx_audit_event_resource (resource_type, resource_id, occurred_at)`
- `idx_audit_event_action (action_code, occurred_at)`

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

### 3.4 这张表的真正价值

它让系统能够同时满足两件事：

- 需要时能追溯完整敏感变更内容
- 日常情况下又不会因为审计检索而过度暴露高敏字段

## 4. `data_access_log`

### 4.1 这张表回答什么问题

- 谁查看了哪份病历
- 谁导出了哪张处方
- 谁看了哪段 AI 原文
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

- `access_purpose`：为什么看，是查看、导出、打印、调试还是复核
- `resource_type` / `resource_id`：看了什么
- `patient_user_id`：如果是患者相关敏感数据，这个字段很关键
- `access_result` / `deny_reason`：不只是记录允许，还要记录拒绝

### 4.4 为什么这张表在医疗系统里非常重要

很多真正的风险不是“谁改了病历”，而是“谁看了不该看的病历”。

所以这张表不是辅助功能，而是核心监管能力。

## 5. `domain_event_stream`

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
- `trace_id`：便于与调用链串联

## 6. `outbox_event`

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

解决的是：

- 业务事实如何表达
- 事件如何可靠投递
- 投递后如何归档

## 9. 典型场景串起来怎么理解

比如医生完成 AI 复核：

- Java 写 `audit_event`
  - 表示“某医生执行了 AI 复核操作”
- 如果有敏感前后值，写 `audit_payload`
- 如果有人查看 AI 原文，再写 `data_access_log`
- 同时业务上发生“AI 复核已完成”，写 `domain_event_stream`
- 如果这个事件要通知别的系统，再写 `outbox_event`
- 投递完成后写 `integration_event_archive`

这才是完整闭环。

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
