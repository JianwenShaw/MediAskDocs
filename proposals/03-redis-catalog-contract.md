# Redis 导诊目录合同冻结版

## 1. 文档定位

本文冻结 Redis 导诊目录的 key 模式、JSON schema、发布规则与读取规则。

本文是 `00-interface-overview.md` 的子文档。三方职责与通信架构见总纲。

---

## 2. Key 模式

| Key | 类型 | 说明 |
|-----|------|------|
| `triage_catalog:active:{hospital_scope}` | STRING | 当前激活目录版本号 |
| `triage_catalog:{hospital_scope}:{catalog_version}` | STRING | 完整目录 JSON |

示例：
- `triage_catalog:active:default` → `"deptcat-v20260423-01"`
- `triage_catalog:default:deptcat-v20260423-01` → 目录 JSON

---

## 3. 目录 JSON Schema

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

---

## 4. 版本语义

- `catalog_version` 格式：`deptcat-v{YYYYMMDD}-{seq}`
- 每个 `hospital_scope` 同时只有一个 active 版本
- 旧版本不删除，供 Java 校验历史结果

---

## 5. 发布规则（Java）

1. 写入 `triage_catalog:{scope}:{version}`（新内容）
2. 原子更新 `triage_catalog:active:{scope}`（切换指针）

---

## 6. 读取规则（Python）

1. 读 `active` 指针获得当前版本号
2. 读对应版本 JSON
3. 只允许从 `department_candidates` 中选择推荐科室
4. 返回结果必须携带 `catalog_version`

---

## 7. 校验规则（Java 收到 Python 结果后）

1. `catalog_version` 必须存在于 Redis
2. `department_id` 必须属于该版本目录
3. `department_name` 必须与该 `department_id` 严格匹配
