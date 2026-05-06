CREATE TABLE departments (
    id BIGINT PRIMARY KEY,
    hospital_id BIGINT NOT NULL,
    dept_code VARCHAR(64) NOT NULL,
    name VARCHAR(128) NOT NULL,
    dept_type VARCHAR(32) NOT NULL,
    status VARCHAR(16) NOT NULL DEFAULT 'ACTIVE',
    sort_order INT NOT NULL DEFAULT 0,
    version INT NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    deleted_at TIMESTAMPTZ DEFAULT NULL,
    CONSTRAINT uk_departments_code UNIQUE (hospital_id, dept_code),
    CONSTRAINT ck_departments_status CHECK (status IN ('ACTIVE', 'DISABLED')),
    CONSTRAINT ck_departments_type CHECK (dept_type IN ('CLINICAL', 'TECHNICAL', 'MANAGEMENT'))
);

CREATE TABLE doctors (
    id BIGINT PRIMARY KEY,
    user_id BIGINT NOT NULL,
    hospital_id BIGINT NOT NULL,
    doctor_code VARCHAR(64) NOT NULL,
    professional_title VARCHAR(64),
    introduction_masked TEXT,
    status VARCHAR(16) NOT NULL DEFAULT 'ACTIVE',
    version INT NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    deleted_at TIMESTAMPTZ DEFAULT NULL,
    CONSTRAINT uk_doctors_user UNIQUE (user_id),
    CONSTRAINT uk_doctors_code UNIQUE (doctor_code),
    CONSTRAINT fk_doctors_user FOREIGN KEY (user_id) REFERENCES users (id),
    CONSTRAINT ck_doctors_status CHECK (status IN ('ACTIVE', 'DISABLED'))
);

CREATE TABLE doctor_department_rel (
    id BIGINT PRIMARY KEY,
    doctor_id BIGINT NOT NULL,
    department_id BIGINT NOT NULL,
    is_primary BOOLEAN NOT NULL DEFAULT FALSE,
    relation_status VARCHAR(16) NOT NULL DEFAULT 'ACTIVE',
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uk_doctor_department_rel UNIQUE (doctor_id, department_id),
    CONSTRAINT fk_doctor_department_rel_doctor FOREIGN KEY (doctor_id) REFERENCES doctors (id),
    CONSTRAINT fk_doctor_department_rel_department FOREIGN KEY (department_id) REFERENCES departments (id),
    CONSTRAINT ck_doctor_department_rel_status CHECK (relation_status IN ('ACTIVE', 'DISABLED'))
);

CREATE INDEX idx_departments_hospital ON departments (hospital_id, status);
CREATE INDEX idx_doctors_hospital ON doctors (hospital_id, status);
CREATE INDEX idx_doctor_department_rel_department ON doctor_department_rel (department_id, relation_status);
CREATE UNIQUE INDEX uk_doctor_primary_department_active
    ON doctor_department_rel (doctor_id)
    WHERE is_primary = TRUE AND relation_status = 'ACTIVE';
