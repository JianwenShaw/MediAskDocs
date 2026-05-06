CREATE TABLE users (
    id BIGINT PRIMARY KEY,
    username VARCHAR(64) NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    display_name VARCHAR(128) NOT NULL,
    mobile_masked VARCHAR(32),
    user_type VARCHAR(16) NOT NULL,
    account_status VARCHAR(16) NOT NULL DEFAULT 'ACTIVE',
    last_login_at TIMESTAMPTZ,
    version INT NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    deleted_at TIMESTAMPTZ DEFAULT NULL,
    CONSTRAINT uk_users_username UNIQUE (username),
    CONSTRAINT ck_users_user_type CHECK (user_type IN ('PATIENT', 'DOCTOR', 'ADMIN')),
    CONSTRAINT ck_users_account_status CHECK (account_status IN ('ACTIVE', 'DISABLED', 'LOCKED'))
);

CREATE TABLE patient_profile (
    id BIGINT PRIMARY KEY,
    user_id BIGINT NOT NULL,
    patient_no VARCHAR(64) NOT NULL,
    gender VARCHAR(16),
    birth_date DATE,
    blood_type VARCHAR(8),
    allergy_summary TEXT,
    version INT NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    deleted_at TIMESTAMPTZ DEFAULT NULL,
    CONSTRAINT uk_patient_profile_user UNIQUE (user_id),
    CONSTRAINT uk_patient_profile_no UNIQUE (patient_no),
    CONSTRAINT fk_patient_profile_user FOREIGN KEY (user_id) REFERENCES users (id),
    CONSTRAINT ck_patient_profile_gender CHECK (gender IS NULL OR gender IN ('MALE', 'FEMALE', 'OTHER'))
);

CREATE TABLE roles (
    id BIGINT PRIMARY KEY,
    role_code VARCHAR(64) NOT NULL,
    role_name VARCHAR(128) NOT NULL,
    role_type VARCHAR(32) NOT NULL,
    status VARCHAR(16) NOT NULL DEFAULT 'ACTIVE',
    sort_order INT NOT NULL DEFAULT 0,
    version INT NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    deleted_at TIMESTAMPTZ DEFAULT NULL,
    CONSTRAINT uk_roles_code UNIQUE (role_code),
    CONSTRAINT ck_roles_status CHECK (status IN ('ACTIVE', 'DISABLED'))
);

CREATE TABLE permissions (
    id BIGINT PRIMARY KEY,
    permission_code VARCHAR(128) NOT NULL,
    permission_name VARCHAR(128) NOT NULL,
    permission_type VARCHAR(16) NOT NULL,
    parent_id BIGINT,
    resource_path VARCHAR(255),
    http_method VARCHAR(16),
    status VARCHAR(16) NOT NULL DEFAULT 'ACTIVE',
    sort_order INT NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    deleted_at TIMESTAMPTZ DEFAULT NULL,
    CONSTRAINT uk_permissions_code UNIQUE (permission_code),
    CONSTRAINT fk_permissions_parent FOREIGN KEY (parent_id) REFERENCES permissions (id),
    CONSTRAINT ck_permissions_type CHECK (permission_type IN ('MENU', 'API', 'ACTION')),
    CONSTRAINT ck_permissions_status CHECK (status IN ('ACTIVE', 'DISABLED'))
);

CREATE TABLE user_roles (
    id BIGINT PRIMARY KEY,
    user_id BIGINT NOT NULL,
    role_id BIGINT NOT NULL,
    granted_by BIGINT,
    granted_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    expires_at TIMESTAMPTZ,
    active_flag BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uk_user_roles_user_role UNIQUE (user_id, role_id),
    CONSTRAINT fk_user_roles_user FOREIGN KEY (user_id) REFERENCES users (id),
    CONSTRAINT fk_user_roles_role FOREIGN KEY (role_id) REFERENCES roles (id),
    CONSTRAINT fk_user_roles_granted_by FOREIGN KEY (granted_by) REFERENCES users (id)
);

CREATE TABLE role_permissions (
    id BIGINT PRIMARY KEY,
    role_id BIGINT NOT NULL,
    permission_id BIGINT NOT NULL,
    granted_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uk_role_permissions UNIQUE (role_id, permission_id),
    CONSTRAINT fk_role_permissions_role FOREIGN KEY (role_id) REFERENCES roles (id),
    CONSTRAINT fk_role_permissions_permission FOREIGN KEY (permission_id) REFERENCES permissions (id)
);

CREATE TABLE data_scope_rules (
    id BIGINT PRIMARY KEY,
    role_id BIGINT NOT NULL,
    resource_type VARCHAR(64) NOT NULL,
    scope_type VARCHAR(16) NOT NULL,
    scope_dept_id BIGINT,
    conditions_json JSONB,
    status VARCHAR(16) NOT NULL DEFAULT 'ACTIVE',
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_data_scope_rules_role FOREIGN KEY (role_id) REFERENCES roles (id),
    CONSTRAINT ck_data_scope_rules_scope_type CHECK (scope_type IN ('SELF', 'DEPARTMENT', 'ALL', 'CUSTOM')),
    CONSTRAINT ck_data_scope_rules_status CHECK (status IN ('ACTIVE', 'DISABLED'))
);

CREATE INDEX idx_user_roles_user ON user_roles (user_id, active_flag);
CREATE INDEX idx_role_permissions_role ON role_permissions (role_id);
CREATE INDEX idx_data_scope_rules_role_resource ON data_scope_rules (role_id, resource_type);
