# AI 导诊目录 Redis 发布方案

## 1. 文档定位

本文单独讨论一个问题：

**当 AI 导诊能力收敛到 Python 服务后，Python 如何知道“当前允许推荐哪些科室”，以及如何把推荐结果稳定回传给 Java 业务系统。**

本文给出的结论是：

- 科室主数据真相仍归 Java / 业务侧
- Python 不维护科室主数据真相
- Java 生成一份“可导诊目录”并发布到 Redis
- Python 只读 Redis 中的导诊目录
- Python 只能从该目录中选择推荐科室
- Java 按相同目录版本校验并承接结果

这不是普通“缓存优化”，而是一份**由 Java 发布、Python 只读消费的导诊目录读模型**。

---

## 2. 设计目标

这个方案要同时解决 3 个问题：

1. Python 如何知道当前有哪些可推荐科室
2. Python 如何在受控候选集中做推荐，而不是自由生成科室名
3. Java 如何稳定接收结构化结果，而不是再从文本里反解析

附加目标：

- 不把“实时拉 Java”放进问诊主链路
- 不把 Python 变成科室主数据拥有者
- 让“显式发布”在导诊目录上也成立

---

## 3. 设计结论

推荐采用以下边界：

- `departments` 及相关业务主数据仍由 Java 维护
- Java 基于业务主数据生成一份“可导诊目录”
- Java 将目录按版本发布到 Redis
- Python 只读取 Redis 中已发布目录
- Python 输出结构化推荐结果：
  - `department_id`
  - `department_name`
  - `reason`
  - `priority`
  - `catalog_version`
- Java 收到后按同一版本校验并承接挂号链路

一句话概括：

**Java 管目录真相与发布，Python 管目录内推荐。**

---

## 4. 为什么选 Redis，而不是 Python 侧建表

如果只看这个场景，Redis 比 Python 自己维护一套目录表更合适，原因很直接：

- 科室目录是高频读、低频写数据
- Python 每次问诊都可能读目录
- 目录变更频率远低于问诊请求频率
- Java 本来就拥有真实主数据和发布权限

因此：

- 不适合让 Python 每次请求时同步调 Java
- 也没必要让 Python 再维护一套长期主数据表

对于当前毕设项目，更合理的方案是：

- Java 负责生成并发布 Redis 目录
- Python 直接读 Redis

这样实现简单，边界清晰，也容易讲解。

---

## 5. Redis 数据模型

建议采用“活动版本指针 + 不可变版本内容”两层结构。

### 5.1 Key 设计

- `triage_catalog:active:{hospital_scope}`
  - 当前激活目录版本
- `triage_catalog:{hospital_scope}:{catalog_version}`
  - 该版本的完整目录 JSON

例如：

- `triage_catalog:active:default`
- `triage_catalog:default:deptcat-v20260423-01`

### 5.2 JSON 结构建议

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

目录里只放导诊推荐所需的最小字段，不放业务无关大字段。

---

## 6. 发布流程

Java 侧发布流程建议固定为：

1. 从业务主数据中生成新的可导诊目录
2. 生成新的 `catalog_version`
3. 写入 `triage_catalog:{hospital_scope}:{catalog_version}`
4. 校验目录内容无误
5. 更新 `triage_catalog:active:{hospital_scope}`

这本质上就是“显式发布”：

- 新版本先写入
- 校验通过后再切换活动指针
- Python 始终只读已发布版本

这样可以避免：

- 目录更新到一半被 Python 读到
- Java 和 Python 两侧看到不同目录

---

## 7. Python 读取流程

Python 侧建议这样使用：

1. 根据 `hospital_scope` 读取 active version
2. 再读取该 version 对应目录 JSON
3. 在目录候选集中做召回与排序
4. 只返回目录内存在的 `department_id`

推荐结果必须是结构化结果，不能只返回自然语言。

例如：

```json
{
  "triage_stage": "READY",
  "recommended_departments": [
    {
      "department_id": 101,
      "department_name": "神经内科",
      "priority": 1,
      "reason": "头痛伴恶心，当前更需要优先评估神经系统相关问题"
    }
  ],
  "catalog_version": "deptcat-v20260423-01"
}
```

---

## 8. Java 承接流程

Java 收到 Python 返回结果后，不再从文本中猜推荐科室，只做结构化校验和业务承接。

建议固定做以下检查：

1. `catalog_version` 是否存在且是当前可接受版本
2. `department_id` 是否属于该 `catalog_version`
3. `department_name` 是否与该 `department_id` 对应

校验通过后：

- 持久化导诊结果
- 生成结果页展示数据
- 作为挂号承接入口的推荐科室

这样 Java 和 Python 的分工是稳定的：

- Python 负责推荐
- Java 负责验证与业务承接

---

## 9. Redis 存储规模与性能问题

你担心的点是合理的：

**如果把所有科室目录都塞进一个 Redis 字符串，会不会太大，影响性能？**

结论是：

- 对这个项目来说，通常不会成为问题
- 只要目录字段收敛，一个版本一个 JSON 字符串是完全可行的

### 9.1 为什么通常不会太大

医院“可导诊目录”通常不是一个超大集合。

即使按比较保守的估算：

- 每个科室条目只保留 `department_id / department_name / routing_hint / aliases / sort_order`
- 一个条目通常也就是几百字节量级
- 就算有 `100` 个科室，整体往往也只是几十 KB
- 就算扩到 `300` 个科室，通常也还是在几百 KB 内

对于 Redis 来说：

- 这种量级远谈不上“大 key”风险
- 用一次 `GET` 读取完整 JSON 的成本也很低

这个场景真正要避免的不是“几十 KB 的 JSON”，而是：

- 往目录里塞大量无关字段
- 把医生、排班、描述正文、图片链接等重数据一起塞进去
- 把目录做成频繁更新的大杂烩对象

### 9.2 什么情况下才需要担心

只有在以下情况同时出现时，才需要重新设计：

- 目录规模非常大，比如上千到上万条
- 每条目录项字段很多
- 每次请求都跨 scope 读取多个大目录
- Redis 内存本身非常紧张

但这不符合你当前项目的典型场景。

对毕设来说，更现实的结论是：

- `一个 scope 一个 version 一个 JSON` 完全够用
- 不需要一开始就为了所谓“大 key”把结构拆得很复杂

### 9.3 P0 不建议过度优化

P0 阶段不建议一开始就做：

- 按科室逐条拆 key
- Redis Hash 多层嵌套
- 压缩存储
- 二级目录索引
- 复杂预热机制

因为这些复杂度对当前收益很低。

P0 最合理的做法是：

- 保持目录字段极简
- 采用版本化 JSON
- 先跑通发布、读取、校验、承接闭环

---

## 10. 如果未来目录真的变大，怎么演进

如果后续目录规模明显变大，再按下面顺序演进即可：

### 10.1 第一层演进

继续保留 active version 指针，但把完整目录拆成：

- `catalog summary`
- `catalog item by id`

这样 Python 可以先读 summary，再按需读细项。

### 10.2 第二层演进

如果不同场景只需要部分目录，可以按业务 scope 拆更细：

- 医院级 scope
- 院区级 scope
- 场景级 scope

### 10.3 第三层演进

如果 Redis 压力很大，再考虑：

- Python 本地短 TTL 内存缓存
- 发布后主动预热

但这些都不属于当前 P0 必须项。

---

## 11. 推荐最终方案

对当前毕业设计项目，建议直接冻结为以下方案：

- 科室主数据真相：Java
- 导诊目录发布：Java 发布到 Redis
- Python 权限：只读 Redis
- 发布模型：`active key + versioned content`
- 推荐约束：Python 只能从目录候选集中选择
- 结果契约：返回结构化 `recommended_departments`
- Java 承接：按 `catalog_version` 校验并进入挂号链路

Redis 部分的具体建议是：

- 先用单个 versioned JSON 存目录
- 不要过早优化“大 key”
- 只要目录字段控制住，当前规模下不会成为性能瓶颈

---

## 12. 一句话结论

**可以把导诊目录放 Redis，而且应该按“Java 发布、Python 只读、版本化显式发布”的方式设计；对当前项目的科室规模来说，一个版本一个 JSON 字符串通常不会带来实际性能问题。**
