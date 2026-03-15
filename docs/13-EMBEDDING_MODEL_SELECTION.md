# Embedding 选型说明（阿里百炼平台唯一方案）

> 与 `THESIS_OUTLINE.md` 同步：本项目 Embedding 已定为阿里云百炼 `text-embedding-v4`，不再考虑本地部署方案。

## 1. 选型结论

- **唯一选型**：阿里云百炼 `text-embedding-v4`
- **接入方式**：远程 Embedding API（OpenAI 兼容调用方式）
- **应用范围**：知识库入库向量化 + 查询向量化

## 2. 选择理由（与论文口径一致）

- **中文场景适配**：满足医疗中文问答为主的检索语义需求。
- **工程可落地**：无需本地模型部署与运维，降低环境复杂度。
- **成本可控**：利用免费额度（100 万 tokens）支撑毕设阶段开发与演示。
- **架构一致性**：与“Java 后端 + Python AI 服务 + PostgreSQL + pgvector + DeepSeek”路线保持一致。

## 3. 约束与边界

- **不再维护本地 Embedding 分支**：不再对本地开源模型做主线对比与切换策略。
- **输入先脱敏**：发送至 Embedding API 前必须执行 PII 脱敏。
- **最小化审计**：日志记录脱敏文本摘要或哈希，不落原始敏感文本。

## 4. 故障与降级策略

- **Embedding API 不可用**：返回明确错误并提示“知识库暂不可用”。
- **RAG 降级**：允许退化为无检索的保守回答，并保留免责声明。
- **审计必填**：记录 `request_id`、`action`、`latency_ms`、`input_hash`、`output_hash`；`trace_id` 仅在 P2 APM 时补充。

## 5. 配置建议（示例）

```bash
EMBEDDING_PROVIDER=openai_compatible
EMBEDDING_MODEL=text-embedding-v4
EMBEDDING_BASE_URL=<阿里百炼兼容端点>
EMBEDDING_API_KEY=<你的百炼API Key>
```

> 说明：向量维度以实际 API 返回与 PostgreSQL `knowledge_chunk_index` 的 `VECTOR(1536)` 定义保持一致。
