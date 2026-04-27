INSERT INTO knowledge_base (
    id,
    hospital_scope,
    code,
    name,
    description,
    default_embedding_model,
    default_embedding_dimension,
    retrieval_strategy,
    status,
    created_at,
    updated_at
)
VALUES (
    '90000000-0000-0000-0000-000000000001',
    'default',
    'KB_TRIAGE_DEFAULT',
    '默认导诊知识库',
    '用于开发环境的默认 RAG 知识库。',
    'text-embedding-v4',
    1024,
    'DENSE_SPARSE_RRF',
    'ENABLED',
    TIMESTAMPTZ '2026-04-26 18:10:00+08:00',
    TIMESTAMPTZ '2026-04-26 18:10:00+08:00'
)
ON CONFLICT (id) DO NOTHING;
