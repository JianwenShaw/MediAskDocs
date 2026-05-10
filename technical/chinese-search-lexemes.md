# 中文分词与稀疏检索优化说明

## 背景

PostgreSQL `simple` 全文检索不会自动理解中文词边界。直接把用户中文问句交给 `websearch_to_tsquery` 或 `plainto_tsquery` 时，容易出现整句 token、虚词干扰和同义词无法匹配的问题。

本次改动的目标是让 RAG 的 sparse 检索在中文问诊场景下更稳定，同时避免把医学词表、停用词和同义词长期硬编码在 Python 文件中。

## 改动概览

分词规则外置到 `app/resources/search_lexemes/`：

- `jieba_terms.txt`：医学词、症状词、科室名和疾病名。
- `stopwords.txt`：中文问句里的无检索价值词，例如“这个、是不是、应该、什么、还是”。
- `synonyms.tsv`：同义词映射，例如“发烧 -> 发热”“拉肚子 -> 腹泻”。

`app/services/search_lexemes.py` 负责加载这些资源文件，并提供两类输出：

- `build_search_lexemes(text)`：用于知识入库索引，生成清洗后的空格分隔词项。
- `build_search_tsquery(text)`：用于查询时 sparse 检索，生成 PostgreSQL `to_tsquery` 表达式。

## 查询语义

普通词项之间保持 AND 语义，确保查询仍然聚焦用户描述的主要症状。

同义词组内部使用 OR 语义，避免“发烧 发热”被 `plainto_tsquery` 当成必须同时命中的两个词。

例如：

```text
发烧拉肚子
```

会生成类似：

```text
('发烧' | '发热' | '高烧') & ('拉肚子' | '腹泻')
```

这样既保留用户原始表达，也能匹配知识库中的规范医学表达。

## 维护原则

- 新增医学词、停用词、同义词时优先修改资源文件，不要把大段词表写回 Python 代码。
- 词表只覆盖当前导诊和知识库真实需要的高频表达，不做泛化大词典。
- 同义词应保持少量、高置信，避免把医学含义不同的词强行归并。
- 修改分词资源后，需要重新构建并发布知识库索引；旧 `knowledge_chunk_index.search_lexemes/search_tsv` 不会自动更新。

## 验证

相关测试：

```bash
uv run pytest tests/test_retrieval_service.py tests/test_knowledge_repository.py tests/test_knowledge_ingestion.py
```

静态检查：

```bash
uv run ruff check app/services/search_lexemes.py app/services/retrieval.py app/repositories/knowledge.py tests/test_retrieval_service.py tests/test_knowledge_repository.py
```
