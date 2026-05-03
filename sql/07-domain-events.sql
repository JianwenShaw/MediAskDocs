CREATE TABLE audit.audit_event (
    id BIGINT PRIMARY KEY,
    request_id VARCHAR(64) NOT NULL,
    trace_id VARCHAR(64),
    actor_type VARCHAR(32) NOT NULL DEFAULT 'USER',
    operator_user_id BIGINT,
    operator_username VARCHAR(128),
    operator_role_code VARCHAR(64),
    actor_department_id BIGINT,
    action_code VARCHAR(64) NOT NULL,
    resource_type VARCHAR(64) NOT NULL,
    resource_id VARCHAR(64),
    patient_user_id BIGINT,
    encounter_id BIGINT,
    success_flag BOOLEAN NOT NULL,
    error_code VARCHAR(64),
    error_message VARCHAR(255),
    client_ip INET,
    user_agent VARCHAR(512),
    reason_text VARCHAR(1024),
    occurred_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT ck_audit_event_actor_type CHECK (actor_type IN ('USER', 'SYSTEM'))
);

CREATE TABLE audit.data_access_log (
    id BIGINT PRIMARY KEY,
    request_id VARCHAR(64) NOT NULL,
    trace_id VARCHAR(64),
    actor_type VARCHAR(32) NOT NULL DEFAULT 'USER',
    operator_user_id BIGINT,
    operator_username VARCHAR(128),
    operator_role_code VARCHAR(64),
    actor_department_id BIGINT,
    patient_user_id BIGINT,
    encounter_id BIGINT,
    access_action VARCHAR(16) NOT NULL,
    access_purpose_code VARCHAR(64) NOT NULL,
    resource_type VARCHAR(64) NOT NULL,
    resource_id VARCHAR(64) NOT NULL,
    access_result VARCHAR(16) NOT NULL,
    deny_reason_code VARCHAR(64),
    client_ip INET,
    user_agent VARCHAR(512),
    occurred_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT ck_data_access_log_actor_type CHECK (actor_type IN ('USER', 'SYSTEM')),
    CONSTRAINT ck_data_access_log_action CHECK (access_action IN ('VIEW', 'EXPORT', 'DOWNLOAD', 'PRINT')),
    CONSTRAINT ck_data_access_log_purpose CHECK (
        access_purpose_code IN (
            'TREATMENT',
            'SELF_SERVICE',
            'ADMIN_OPERATION',
            'SECURITY_INVESTIGATION',
            'AUDIT_REVIEW'
        )
    ),
    CONSTRAINT ck_data_access_log_result CHECK (access_result IN ('ALLOWED', 'DENIED'))
);

CREATE INDEX idx_audit_event_request ON audit.audit_event (request_id);
CREATE INDEX idx_audit_event_user_time ON audit.audit_event (operator_user_id, occurred_at);
CREATE INDEX idx_audit_event_resource ON audit.audit_event (resource_type, resource_id, occurred_at);
CREATE INDEX idx_audit_event_action ON audit.audit_event (action_code, occurred_at);
CREATE INDEX idx_audit_event_patient_time ON audit.audit_event (patient_user_id, occurred_at);
CREATE INDEX brin_audit_event_occurred_at ON audit.audit_event USING brin (occurred_at);

CREATE INDEX idx_data_access_log_request ON audit.data_access_log (request_id);
CREATE INDEX idx_data_access_log_user_time ON audit.data_access_log (operator_user_id, occurred_at);
CREATE INDEX idx_data_access_log_resource ON audit.data_access_log (resource_type, resource_id, occurred_at);
CREATE INDEX idx_data_access_log_patient_time ON audit.data_access_log (patient_user_id, occurred_at);
CREATE INDEX brin_data_access_log_occurred_at ON audit.data_access_log USING brin (occurred_at);
