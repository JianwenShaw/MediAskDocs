CREATE EXTENSION IF NOT EXISTS vector;

CREATE TABLE ai_session (
    id uuid PRIMARY KEY,
    patient_user_id varchar(128) NOT NULL,
    request_id varchar(64),
    scene_code varchar(32) NOT NULL CHECK (scene_code = 'AI_TRIAGE'),
    hospital_scope varchar(64) NOT NULL,
    current_stage varchar(32) NOT NULL CHECK (current_stage IN ('COLLECTING', 'READY', 'BLOCKED', 'CLOSED')),
    current_turn_no integer NOT NULL CHECK (current_turn_no >= 0),
    current_triage_cycle_no integer NOT NULL CHECK (current_triage_cycle_no >= 1),
    closed_at timestamptz,
    created_at timestamptz NOT NULL,
    updated_at timestamptz NOT NULL
);

CREATE INDEX idx_ai_session_stage
    ON ai_session (current_stage, created_at DESC);

CREATE INDEX idx_ai_session_patient_created
    ON ai_session (patient_user_id, created_at DESC);

CREATE TABLE knowledge_base (
    id uuid PRIMARY KEY,
    hospital_scope varchar(64) NOT NULL,
    code varchar(64) NOT NULL,
    name varchar(128) NOT NULL,
    description text,
    default_embedding_model varchar(64) NOT NULL,
    default_embedding_dimension integer NOT NULL CHECK (default_embedding_dimension = 1024),
    retrieval_strategy varchar(64) NOT NULL,
    status varchar(16) NOT NULL CHECK (status IN ('ENABLED', 'DISABLED', 'ARCHIVED')),
    created_at timestamptz NOT NULL,
    updated_at timestamptz NOT NULL,
    CONSTRAINT uq_knowledge_base_scope_code UNIQUE (hospital_scope, code)
);

CREATE INDEX idx_knowledge_base_scope_status
    ON knowledge_base (hospital_scope, status);

CREATE TABLE knowledge_document (
    id uuid PRIMARY KEY,
    kb_id uuid NOT NULL REFERENCES knowledge_base (id),
    title varchar(255) NOT NULL,
    source_type varchar(32) NOT NULL CHECK (source_type IN ('MANUAL', 'MARKDOWN', 'PDF', 'DOCX')),
    source_uri text,
    mime_type varchar(128),
    content_hash varchar(128) NOT NULL,
    owner_ref varchar(128),
    lifecycle_status varchar(16) NOT NULL CHECK (lifecycle_status IN ('DRAFT', 'ENABLED', 'ARCHIVED')),
    deleted_at timestamptz,
    created_at timestamptz NOT NULL,
    updated_at timestamptz NOT NULL
);

CREATE INDEX idx_knowledge_document_kb_status
    ON knowledge_document (kb_id, lifecycle_status);

CREATE UNIQUE INDEX uq_knowledge_document_kb_hash_active
    ON knowledge_document (kb_id, content_hash)
    WHERE deleted_at IS NULL;

CREATE TABLE knowledge_index_version (
    id uuid PRIMARY KEY,
    kb_id uuid NOT NULL REFERENCES knowledge_base (id),
    version_code varchar(64) NOT NULL,
    embedding_model varchar(64) NOT NULL,
    embedding_dimension integer NOT NULL CHECK (embedding_dimension = 1024),
    build_scope varchar(16) NOT NULL CHECK (build_scope IN ('FULL', 'INCREMENTAL')),
    status varchar(16) NOT NULL CHECK (status IN ('BUILDING', 'READY', 'FAILED', 'ARCHIVED')),
    source_document_count integer NOT NULL CHECK (source_document_count >= 0),
    started_at timestamptz NOT NULL,
    finished_at timestamptz,
    created_at timestamptz NOT NULL,
    CONSTRAINT uq_knowledge_index_version_kb_code UNIQUE (kb_id, version_code),
    CONSTRAINT uq_knowledge_index_version_id_kb UNIQUE (id, kb_id)
);

CREATE INDEX idx_knowledge_index_version_kb_status
    ON knowledge_index_version (kb_id, status);

CREATE TABLE knowledge_release (
    id uuid PRIMARY KEY,
    kb_id uuid NOT NULL REFERENCES knowledge_base (id),
    release_code varchar(64) NOT NULL,
    release_type varchar(32) NOT NULL CHECK (release_type = 'INDEX_ACTIVATION'),
    target_index_version_id uuid NOT NULL,
    status varchar(16) NOT NULL CHECK (status IN ('DRAFT', 'PUBLISHED', 'REVOKED')),
    published_by varchar(128),
    published_at timestamptz,
    revoked_at timestamptz,
    created_at timestamptz NOT NULL,
    CONSTRAINT uq_knowledge_release_kb_code UNIQUE (kb_id, release_code),
    CONSTRAINT fk_knowledge_release_target_same_kb
        FOREIGN KEY (target_index_version_id, kb_id)
        REFERENCES knowledge_index_version (id, kb_id)
);

CREATE INDEX idx_knowledge_release_kb_status
    ON knowledge_release (kb_id, status);

CREATE INDEX idx_knowledge_release_target
    ON knowledge_release (target_index_version_id);

CREATE UNIQUE INDEX uq_knowledge_release_one_published_per_kb
    ON knowledge_release (kb_id)
    WHERE status = 'PUBLISHED';

CREATE TABLE knowledge_chunk (
    id uuid PRIMARY KEY,
    document_id uuid NOT NULL REFERENCES knowledge_document (id),
    chunk_no integer NOT NULL CHECK (chunk_no >= 1),
    content_text text NOT NULL,
    content_preview text NOT NULL,
    page_no integer,
    section_path varchar(512),
    token_count integer NOT NULL CHECK (token_count >= 0),
    created_at timestamptz NOT NULL,
    CONSTRAINT uq_knowledge_chunk_document_no UNIQUE (document_id, chunk_no)
);

CREATE INDEX idx_knowledge_chunk_document
    ON knowledge_chunk (document_id, chunk_no);

CREATE TABLE ai_turn (
    id uuid PRIMARY KEY,
    session_id uuid NOT NULL REFERENCES ai_session (id),
    turn_no integer NOT NULL CHECK (turn_no >= 1),
    triage_cycle_no integer NOT NULL CHECK (triage_cycle_no >= 1),
    user_message_text text NOT NULL,
    assistant_message_text text,
    stage_before varchar(32) NOT NULL CHECK (stage_before IN ('COLLECTING', 'READY', 'BLOCKED')),
    stage_after varchar(32) CHECK (stage_after IN ('COLLECTING', 'READY', 'BLOCKED')),
    is_finalized boolean NOT NULL,
    created_at timestamptz NOT NULL,
    updated_at timestamptz NOT NULL,
    CONSTRAINT uq_ai_turn_session_no UNIQUE (session_id, turn_no)
);

CREATE INDEX idx_ai_turn_session_no
    ON ai_turn (session_id, turn_no);

CREATE TABLE query_run (
    id uuid PRIMARY KEY,
    request_id varchar(64) NOT NULL,
    session_id uuid NOT NULL REFERENCES ai_session (id),
    turn_id uuid NOT NULL UNIQUE REFERENCES ai_turn (id),
    kb_id uuid REFERENCES knowledge_base (id),
    scene_code varchar(32) NOT NULL CHECK (scene_code = 'AI_TRIAGE'),
    request_text text NOT NULL,
    normalized_query_text text,
    hospital_scope varchar(64) NOT NULL,
    catalog_version varchar(64),
    index_version_id uuid,
    status varchar(16) NOT NULL CHECK (status IN ('RUNNING', 'SUCCEEDED', 'FAILED')),
    started_at timestamptz NOT NULL,
    finished_at timestamptz,
    created_at timestamptz NOT NULL,
    CONSTRAINT chk_query_run_index_requires_kb CHECK (index_version_id IS NULL OR kb_id IS NOT NULL),
    CONSTRAINT fk_query_run_index_same_kb
        FOREIGN KEY (index_version_id, kb_id)
        REFERENCES knowledge_index_version (id, kb_id)
);

CREATE INDEX idx_query_run_session
    ON query_run (session_id, created_at DESC);

CREATE INDEX idx_query_run_request
    ON query_run (request_id);

CREATE INDEX idx_query_run_status
    ON query_run (status, created_at DESC);

CREATE TABLE query_result_snapshot (
    query_run_id uuid PRIMARY KEY REFERENCES query_run (id),
    triage_stage varchar(32) NOT NULL CHECK (triage_stage IN ('COLLECTING', 'READY', 'BLOCKED')),
    triage_completion_reason varchar(32) CHECK (triage_completion_reason IN ('SUFFICIENT_INFO', 'MAX_TURNS_REACHED', 'HIGH_RISK_BLOCKED')),
    next_action varchar(32) NOT NULL CHECK (next_action IN ('CONTINUE_TRIAGE', 'VIEW_TRIAGE_RESULT', 'MANUAL_SUPPORT', 'EMERGENCY_OFFLINE')),
    risk_level varchar(16) CHECK (risk_level IN ('low', 'medium', 'high')),
    chief_complaint_summary text NOT NULL,
    follow_up_questions_json jsonb NOT NULL DEFAULT '[]'::jsonb,
    recommended_departments_json jsonb NOT NULL DEFAULT '[]'::jsonb,
    catalog_version varchar(64),
    care_advice text,
    blocked_reason varchar(64) CHECK (blocked_reason IN (
        'SELF_HARM_RISK',
        'VIOLENCE_RISK',
        'CHEST_PAIN_RISK',
        'RESPIRATORY_DISTRESS_RISK',
        'STROKE_RISK',
        'SEIZURE_RISK',
        'SEVERE_BLEEDING_RISK',
        'ANAPHYLAXIS_RISK',
        'OTHER_EMERGENCY_RISK'
    )),
    created_at timestamptz NOT NULL,
    CONSTRAINT chk_query_result_union CHECK (
        (
            triage_stage = 'COLLECTING' AND
            triage_completion_reason IS NULL AND
            next_action = 'CONTINUE_TRIAGE' AND
            risk_level IS NULL AND
            jsonb_array_length(follow_up_questions_json) BETWEEN 1 AND 2 AND
            jsonb_array_length(recommended_departments_json) = 0 AND
            catalog_version IS NULL AND
            care_advice IS NULL AND
            blocked_reason IS NULL
        ) OR (
            triage_stage = 'READY' AND
            triage_completion_reason IN ('SUFFICIENT_INFO', 'MAX_TURNS_REACHED') AND
            next_action = 'VIEW_TRIAGE_RESULT' AND
            risk_level IN ('low', 'medium', 'high') AND
            jsonb_array_length(follow_up_questions_json) = 0 AND
            jsonb_array_length(recommended_departments_json) BETWEEN 1 AND 3 AND
            catalog_version IS NOT NULL AND
            care_advice IS NOT NULL AND
            blocked_reason IS NULL
        ) OR (
            triage_stage = 'BLOCKED' AND
            triage_completion_reason = 'HIGH_RISK_BLOCKED' AND
            next_action IN ('MANUAL_SUPPORT', 'EMERGENCY_OFFLINE') AND
            risk_level = 'high' AND
            jsonb_array_length(follow_up_questions_json) = 0 AND
            jsonb_array_length(recommended_departments_json) = 0 AND
            catalog_version IS NULL AND
            care_advice IS NOT NULL AND
            blocked_reason IS NOT NULL
        )
    ),
    CONSTRAINT uq_query_result_snapshot_stage UNIQUE (query_run_id, triage_stage)
);

CREATE TABLE ai_model_run (
    id uuid PRIMARY KEY,
    query_run_id uuid NOT NULL REFERENCES query_run (id),
    provider varchar(32) NOT NULL CHECK (provider = 'DEEPSEEK'),
    model varchar(64) NOT NULL,
    run_type varchar(32) NOT NULL CHECK (run_type IN ('TRIAGE_MATERIALS', 'RAG_ANSWER')),
    stream_mode varchar(16) NOT NULL CHECK (stream_mode IN ('SYNC', 'SSE')),
    status varchar(16) NOT NULL CHECK (status IN ('RUNNING', 'SUCCEEDED', 'FAILED')),
    input_tokens integer,
    output_tokens integer,
    started_at timestamptz NOT NULL,
    finished_at timestamptz,
    error_code varchar(64),
    created_at timestamptz NOT NULL
);

CREATE INDEX idx_ai_model_run_query
    ON ai_model_run (query_run_id, started_at DESC);

CREATE TABLE ai_guardrail_event (
    id uuid PRIMARY KEY,
    query_run_id uuid NOT NULL REFERENCES query_run (id),
    phase varchar(16) NOT NULL CHECK (phase IN ('INPUT', 'OUTPUT')),
    risk_code varchar(64) NOT NULL CHECK (risk_code IN (
        'SELF_HARM_RISK',
        'VIOLENCE_RISK',
        'CHEST_PAIN_RISK',
        'RESPIRATORY_DISTRESS_RISK',
        'STROKE_RISK',
        'SEIZURE_RISK',
        'SEVERE_BLEEDING_RISK',
        'ANAPHYLAXIS_RISK',
        'OTHER_EMERGENCY_RISK'
    )),
    action varchar(16) NOT NULL CHECK (action IN ('ALLOW', 'FLAG', 'BLOCK')),
    detail_json jsonb,
    created_at timestamptz NOT NULL
);

CREATE INDEX idx_ai_guardrail_query
    ON ai_guardrail_event (query_run_id, created_at);

CREATE INDEX idx_ai_guardrail_risk
    ON ai_guardrail_event (risk_code, created_at DESC);

CREATE TABLE ingest_job (
    id uuid PRIMARY KEY,
    kb_id uuid NOT NULL REFERENCES knowledge_base (id),
    document_id uuid REFERENCES knowledge_document (id),
    target_index_version_id uuid,
    job_type varchar(32) NOT NULL CHECK (job_type IN ('INGEST_DOCUMENT', 'REINDEX_DOCUMENT', 'REBUILD_KB')),
    status varchar(16) NOT NULL CHECK (status IN ('PENDING', 'RUNNING', 'SUCCEEDED', 'FAILED')),
    current_stage varchar(16) NOT NULL CHECK (current_stage IN ('PARSE', 'CHUNK', 'EMBED', 'INDEX', 'ACTIVATE')),
    error_code varchar(64),
    error_message text,
    started_at timestamptz,
    finished_at timestamptz,
    created_at timestamptz NOT NULL,
    CONSTRAINT fk_ingest_job_target_same_kb
        FOREIGN KEY (target_index_version_id, kb_id)
        REFERENCES knowledge_index_version (id, kb_id)
);

CREATE INDEX idx_ingest_job_status
    ON ingest_job (status, created_at);

CREATE INDEX idx_ingest_job_document
    ON ingest_job (document_id, created_at DESC);

CREATE TABLE knowledge_chunk_index (
    chunk_id uuid NOT NULL REFERENCES knowledge_chunk (id),
    index_version_id uuid NOT NULL REFERENCES knowledge_index_version (id),
    embedding vector(1024) NOT NULL,
    search_lexemes text NOT NULL,
    search_tsv tsvector GENERATED ALWAYS AS (to_tsvector('simple', search_lexemes)) STORED,
    indexed_at timestamptz NOT NULL,
    PRIMARY KEY (chunk_id, index_version_id)
);

CREATE INDEX idx_kci_index_version
    ON knowledge_chunk_index (index_version_id);

CREATE INDEX idx_kci_search_tsv
    ON knowledge_chunk_index
    USING gin (search_tsv);

CREATE INDEX idx_kci_embedding
    ON knowledge_chunk_index
    USING hnsw (embedding vector_cosine_ops)
    WITH (m = 16, ef_construction = 64);

CREATE TABLE answer_citation (
    query_run_id uuid NOT NULL REFERENCES query_run (id),
    citation_order integer NOT NULL CHECK (citation_order >= 1),
    chunk_id uuid NOT NULL,
    snippet text NOT NULL,
    created_at timestamptz NOT NULL,
    PRIMARY KEY (query_run_id, citation_order)
);

CREATE INDEX idx_answer_citation_chunk
    ON answer_citation (chunk_id);
