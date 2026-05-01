CREATE TABLE ai_triage_result (
    id BIGINT PRIMARY KEY,
    request_id VARCHAR(64) NOT NULL,
    session_id VARCHAR(64) NOT NULL,
    turn_id VARCHAR(64) NOT NULL,
    query_run_id VARCHAR(64) NOT NULL,
    hospital_scope VARCHAR(64) NOT NULL,
    triage_stage VARCHAR(32) NOT NULL,
    triage_completion_reason VARCHAR(64),
    next_action VARCHAR(64) NOT NULL,
    risk_level VARCHAR(16),
    chief_complaint_summary TEXT,
    care_advice TEXT,
    blocked_reason VARCHAR(64),
    catalog_version VARCHAR(64),
    recommended_departments_json JSONB NOT NULL DEFAULT '[]'::jsonb,
    citations_json JSONB NOT NULL DEFAULT '[]'::jsonb,
    version INTEGER NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    deleted_at TIMESTAMPTZ
);

CREATE UNIQUE INDEX uq_ai_triage_result_query_run
    ON ai_triage_result (query_run_id)
    WHERE deleted_at IS NULL;

CREATE INDEX idx_ai_triage_result_session_created
    ON ai_triage_result (session_id, created_at DESC)
    WHERE deleted_at IS NULL;
