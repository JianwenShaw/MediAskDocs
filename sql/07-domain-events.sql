CREATE TABLE audit.audit_event (
    id BIGINT PRIMARY KEY,
    request_id VARCHAR(64) NOT NULL,
    trace_id VARCHAR(64),
    operator_user_id BIGINT,
    operator_role_code VARCHAR(64),
    action_code VARCHAR(64) NOT NULL,
    resource_type VARCHAR(64) NOT NULL,
    resource_id BIGINT,
    success_flag BOOLEAN NOT NULL,
    error_code VARCHAR(64),
    error_message VARCHAR(255),
    client_ip INET,
    occurred_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE audit.data_access_log (
    id BIGINT PRIMARY KEY,
    request_id VARCHAR(64) NOT NULL,
    trace_id VARCHAR(64),
    operator_user_id BIGINT,
    operator_role_code VARCHAR(64),
    patient_user_id BIGINT,
    access_purpose VARCHAR(64) NOT NULL,
    resource_type VARCHAR(64) NOT NULL,
    resource_id BIGINT NOT NULL,
    access_result VARCHAR(16) NOT NULL,
    deny_reason VARCHAR(255),
    occurred_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT ck_data_access_log_result CHECK (access_result IN ('ALLOWED', 'DENIED'))
);

CREATE INDEX idx_audit_event_request ON audit.audit_event (request_id);
CREATE INDEX idx_audit_event_user_time ON audit.audit_event (operator_user_id, occurred_at);
CREATE INDEX idx_audit_event_resource ON audit.audit_event (resource_type, resource_id, occurred_at);
CREATE INDEX idx_audit_event_action ON audit.audit_event (action_code, occurred_at);
CREATE INDEX brin_audit_event_occurred_at ON audit.audit_event USING brin (occurred_at);

CREATE INDEX idx_data_access_log_request ON audit.data_access_log (request_id);
CREATE INDEX idx_data_access_log_user_time ON audit.data_access_log (operator_user_id, occurred_at);
CREATE INDEX idx_data_access_log_resource ON audit.data_access_log (resource_type, resource_id, occurred_at);
CREATE INDEX brin_data_access_log_occurred_at ON audit.data_access_log USING brin (occurred_at);
