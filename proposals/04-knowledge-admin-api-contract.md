# 知识库后台管理 API 合同冻结版

## 1. 文档定位

本文冻结知识库后台管理场景下的职责边界和 Java → Python API 合同。

结论固定为：

**前端仍然只访问 Java；Java 负责认证、授权、审计和网关转发；Python 拥有知识库治理、文档入库、索引版本和发布事实。**

Java 不得通过数据库读取或拼接 Python 的 `knowledge_*`、`ingest_job`、`knowledge_release`、`retrieval_hit`、`answer_citation` 数据。

## 2. 调用链路

```text
Frontend
  |
  | JWT, /api/v1/admin/knowledge-*
  v
Java Spring Boot
  |
  | X-Request-Id
  | X-Actor-Id
  | X-Hospital-Scope
  v
Python FastAPI
  |
  v
PostgreSQL / Object Storage / Worker
```

## 3. Java 在中间的职责

Java 不是知识库领域事实的拥有者，但它必须承担后台入口职责：

- 校验 JWT 登录态
- 校验 RBAC 权限，例如知识库列表、创建、更新、删除、文档导入、发布权限
- 根据当前用户解析可访问的 `hospital_scope`
- 生成并透传 `X-Request-Id`
- 向 Python 传递可信用户上下文
- 记录后台操作审计
- 将 Python 响应封装为前端统一 `Result<T>`
- 将 Python 错误映射为 Java 侧统一错误响应
  - Python 4xx 保持 Java 对外 4xx 语义：404 映射为资源不存在，其他 4xx 映射为参数错误
  - Python 5xx、网络不可用或响应解析异常按 AI 集成系统错误处理

Java 不做：

- 直接查询 Python 数据库
- 维护 `knowledge_base`、`knowledge_document`、`ingest_job`、`knowledge_index_version`、`knowledge_release` 的状态机
- 自己解析文档、切 chunk、生成 embedding、写索引
- 从 Python 内部表拼接知识库页面

## 4. Python 的职责

Python 负责知识库后台管理的事实与流程：

- 创建、更新、归档知识库
- 接收文档导入请求并创建 `knowledge_document`
- 创建和更新 `ingest_job`
- 由 worker 执行解析、切块、embedding、索引写入
- 创建 `knowledge_index_version`
- 创建或撤销 `knowledge_release`
- 提供后台页面需要的列表、详情、作业状态和发布状态 API

## 5. Java → Python 通用请求头

Java 调 Python 时统一传：

| Header | 必填 | 说明 |
|--------|------|------|
| `Content-Type` | 是 | JSON 请求为 `application/json`；上传文档为 `multipart/form-data` |
| `X-Request-Id` | 是 | Java 生成的链路追踪 ID |
| `X-Actor-Id` | 是 | Java 从登录态解析出的后台用户 ID |
| `X-Hospital-Scope` | 是 | Java 授权后确认的院区/医院作用域 |

Python 只信任 Java 传入的这些上下文，不从前端请求体读取操作者身份。

## 6. API 清单

### 6.1 知识库

| 方法 | Python 路径 | 语义 |
|------|-------------|------|
| GET | `/api/v1/admin/knowledge-bases` | 分页查询知识库 |
| POST | `/api/v1/admin/knowledge-bases` | 创建知识库 |
| PATCH | `/api/v1/admin/knowledge-bases/{knowledge_base_id}` | 更新知识库治理字段或状态 |
| DELETE | `/api/v1/admin/knowledge-bases/{knowledge_base_id}` | 归档知识库 |

### 6.2 文档与入库任务

| 方法 | Python 路径 | 语义 |
|------|-------------|------|
| POST | `/api/v1/admin/knowledge-documents/import` | 上传文档并创建入库任务 |
| GET | `/api/v1/admin/knowledge-documents` | 按知识库分页查询文档 |
| DELETE | `/api/v1/admin/knowledge-documents/{document_id}` | 删除文档并触发索引重建或发布撤销 |
| GET | `/api/v1/admin/ingest-jobs/{job_id}` | 查询入库任务状态 |

### 6.3 索引与发布

| 方法 | Python 路径 | 语义 |
|------|-------------|------|
| GET | `/api/v1/admin/knowledge-index-versions` | 查询知识库索引版本 |
| GET | `/api/v1/admin/knowledge-releases` | 查询知识库发布记录 |
| POST | `/api/v1/admin/knowledge-releases` | 发布一个 READY 索引版本 |

## 7. 接口细节

### 7.1 `GET /api/v1/admin/knowledge-bases`

查询参数：

| 参数 | 必填 | 说明 |
|------|------|------|
| `keyword` | 否 | 按 `code` 或 `name` 搜索 |
| `page_num` | 否 | 默认 `1` |
| `page_size` | 否 | 默认 `20` |

响应：

```json
{
  "items": [
    {
      "id": "8e68e3a0-f8d5-4e33-a4a5-f287d9b29a7f",
      "hospital_scope": "default",
      "code": "triage-general",
      "name": "导诊通用知识库",
      "description": "门诊导诊常用知识",
      "retrieval_strategy": "HYBRID_RRF",
      "status": "ENABLED",
      "document_count": 12,
      "published_release_id": "0fc19e80-e04d-4d2b-9949-b6790af931c4"
    }
  ],
  "page_num": 1,
  "page_size": 20,
  "total": 1,
  "total_pages": 1,
  "has_next": false
}
```

### 7.2 `POST /api/v1/admin/knowledge-bases`

请求：

```json
{
  "code": "triage-general",
  "name": "导诊通用知识库",
  "description": "门诊导诊常用知识",
  "default_embedding_model": "text-embedding-v4",
  "default_embedding_dimension": 1024,
  "retrieval_strategy": "HYBRID_RRF"
}
```

响应返回创建后的知识库对象。`hospital_scope` 来自 `X-Hospital-Scope`，`status` 固定为 `ENABLED`。

### 7.3 `PATCH /api/v1/admin/knowledge-bases/{knowledge_base_id}`

请求：

```json
{
  "name": "导诊通用知识库",
  "description": "门诊导诊常用知识",
  "status": "ENABLED"
}
```

只允许更新治理字段和状态，不允许修改 `code`。

### 7.4 `DELETE /api/v1/admin/knowledge-bases/{knowledge_base_id}`

语义：

- 将知识库状态置为 `ARCHIVED`
- 不物理删除历史 query、citation、release 追溯数据
- 已发布版本不再进入后续 query 的可选知识库范围

成功响应 `204 No Content`。

### 7.5 `POST /api/v1/admin/knowledge-documents/import`

请求格式：`multipart/form-data`

| 表单字段 | 必填 | 说明 |
|----------|------|------|
| `knowledge_base_id` | 是 | 目标知识库 UUID |
| `file` | 是 | 上传文件 |

响应：

```json
{
  "document_id": "9e2b6c37-7957-4e54-b0af-898b4f197d76",
  "job_id": "90e68871-8615-4c64-8f8d-c53114e8ea8e",
  "lifecycle_status": "DRAFT",
  "job_status": "PENDING"
}
```

使用规则：

1. Java 接收前端上传并完成权限校验。
2. Java 将文件和 `knowledge_base_id` 转发给 Python。
3. Python 保存原始文件，创建 `knowledge_document` 和 `ingest_job`。
4. 前端用返回的 `job_id` 轮询任务状态。

### 7.6 `GET /api/v1/admin/knowledge-documents`

查询参数：

| 参数 | 必填 | 说明 |
|------|------|------|
| `knowledge_base_id` | 是 | 知识库 UUID |
| `page_num` | 否 | 默认 `1` |
| `page_size` | 否 | 默认 `20` |

响应：

```json
{
  "items": [
    {
      "id": "9e2b6c37-7957-4e54-b0af-898b4f197d76",
      "title": "门诊导诊手册",
      "source_type": "PDF",
      "lifecycle_status": "ENABLED",
      "latest_job_status": "SUCCEEDED",
      "chunk_count": 42
    }
  ],
  "page_num": 1,
  "page_size": 20,
  "total": 1,
  "total_pages": 1,
  "has_next": false
}
```

### 7.7 `DELETE /api/v1/admin/knowledge-documents/{document_id}`

语义：

- 删除文档及其 chunk/index 投影
- 如果知识库仍有可用文档，Python 重建并发布新索引版本
- 如果知识库没有可用文档，Python 撤销当前发布版本

成功响应 `204 No Content`。

### 7.8 `GET /api/v1/admin/ingest-jobs/{job_id}`

响应：

```json
{
  "id": "90e68871-8615-4c64-8f8d-c53114e8ea8e",
  "knowledge_base_id": "8e68e3a0-f8d5-4e33-a4a5-f287d9b29a7f",
  "document_id": "9e2b6c37-7957-4e54-b0af-898b4f197d76",
  "job_type": "INGEST_DOCUMENT",
  "status": "RUNNING",
  "current_stage": "EMBED",
  "error_code": null,
  "error_message": null,
  "started_at": "2026-04-28T10:00:00Z",
  "finished_at": null,
  "created_at": "2026-04-28T09:59:58Z"
}
```

### 7.9 `GET /api/v1/admin/knowledge-index-versions`

查询参数：

| 参数 | 必填 | 说明 |
|------|------|------|
| `knowledge_base_id` | 是 | 知识库 UUID |

返回该知识库的索引版本列表，供后台展示构建状态和发布目标。

### 7.10 `GET /api/v1/admin/knowledge-releases`

查询参数：

| 参数 | 必填 | 说明 |
|------|------|------|
| `knowledge_base_id` | 是 | 知识库 UUID |

返回该知识库的发布记录。一个知识库同一时间最多一条 `PUBLISHED` 发布。

### 7.11 `POST /api/v1/admin/knowledge-releases`

请求：

```json
{
  "knowledge_base_id": "8e68e3a0-f8d5-4e33-a4a5-f287d9b29a7f",
  "target_index_version_id": "21b77544-2b55-4139-8155-f5e0d1de1dc6"
}
```

语义：

- 只能发布 `READY` 状态的索引版本
- 发布成功后，旧的 `PUBLISHED` release 变为 `REVOKED`
- Python 使用 `X-Actor-Id` 写入 `published_by`

## 8. 前端使用规则

前端只调用 Java 暴露的同名后台接口，不直接访问 Python：

```text
Frontend -> Java /api/v1/admin/knowledge-*
Java -> Python /api/v1/admin/knowledge-*
```

前端不传：

- `X-Actor-Id`
- `X-Hospital-Scope`
- Python 内部状态字段
- 数据库表名或内部查询条件

前端页面只使用 Java 返回的 DTO 字段。

## 9. 最终口径

知识库管理链路固定为：

`Frontend -> Java 认证授权审计网关 -> Python 知识库 API -> Python 自有数据库`

Java 可以是薄网关，但必须承担认证、授权、审计和统一前端协议；Python 才是知识库、入库任务、索引版本和发布状态的事实拥有者。
