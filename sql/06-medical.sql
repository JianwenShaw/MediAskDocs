CREATE TABLE emr_record (
    id BIGINT PRIMARY KEY,
    record_no VARCHAR(64) NOT NULL,
    encounter_id BIGINT NOT NULL,
    patient_id BIGINT NOT NULL,
    doctor_id BIGINT NOT NULL,
    department_id BIGINT NOT NULL,
    record_status VARCHAR(16) NOT NULL DEFAULT 'DRAFT',
    chief_complaint_summary TEXT,
    content_encrypted TEXT,
    content_masked TEXT,
    content_hash VARCHAR(128),
    version INT NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    deleted_at TIMESTAMPTZ DEFAULT NULL,
    CONSTRAINT uk_emr_record_no UNIQUE (record_no),
    CONSTRAINT uk_emr_record_encounter UNIQUE (encounter_id),
    CONSTRAINT uk_emr_record_identity UNIQUE (id, patient_id, doctor_id, department_id),
    CONSTRAINT fk_emr_record_encounter_identity FOREIGN KEY (encounter_id, patient_id, doctor_id, department_id)
        REFERENCES visit_encounter (id, patient_id, doctor_id, department_id),
    CONSTRAINT ck_emr_record_status CHECK (record_status IN ('DRAFT', 'SIGNED', 'AMENDED', 'ARCHIVED'))
);

CREATE TABLE emr_diagnosis (
    id BIGINT PRIMARY KEY,
    record_id BIGINT NOT NULL,
    diagnosis_type VARCHAR(16) NOT NULL,
    diagnosis_code VARCHAR(64),
    diagnosis_name VARCHAR(255) NOT NULL,
    is_primary BOOLEAN NOT NULL DEFAULT FALSE,
    sort_order INT NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_emr_diagnosis_record FOREIGN KEY (record_id) REFERENCES emr_record (id),
    CONSTRAINT ck_emr_diagnosis_type CHECK (diagnosis_type IN ('PRIMARY', 'SECONDARY'))
);

CREATE TABLE prescription_order (
    id BIGINT PRIMARY KEY,
    prescription_no VARCHAR(64) NOT NULL,
    record_id BIGINT NOT NULL,
    encounter_id BIGINT NOT NULL,
    patient_id BIGINT NOT NULL,
    doctor_id BIGINT NOT NULL,
    prescription_status VARCHAR(16) NOT NULL DEFAULT 'DRAFT',
    version INT NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    deleted_at TIMESTAMPTZ DEFAULT NULL,
    CONSTRAINT uk_prescription_order_no UNIQUE (prescription_no),
    CONSTRAINT uk_prescription_order_encounter UNIQUE (encounter_id),
    CONSTRAINT fk_prescription_order_record FOREIGN KEY (record_id) REFERENCES emr_record (id),
    CONSTRAINT fk_prescription_order_encounter FOREIGN KEY (encounter_id) REFERENCES visit_encounter (id),
    CONSTRAINT fk_prescription_order_patient FOREIGN KEY (patient_id) REFERENCES users (id),
    CONSTRAINT fk_prescription_order_doctor FOREIGN KEY (doctor_id) REFERENCES doctors (id),
    CONSTRAINT ck_prescription_order_status CHECK (prescription_status IN ('DRAFT', 'ISSUED', 'CANCELLED'))
);

CREATE TABLE prescription_item (
    id BIGINT PRIMARY KEY,
    prescription_id BIGINT NOT NULL,
    sort_order INT NOT NULL DEFAULT 0,
    drug_name VARCHAR(255) NOT NULL,
    drug_specification VARCHAR(255),
    dosage_text VARCHAR(255),
    frequency_text VARCHAR(255),
    duration_text VARCHAR(255),
    quantity NUMERIC(10,2) NOT NULL DEFAULT 0,
    unit VARCHAR(32),
    route VARCHAR(64),
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_prescription_item_order FOREIGN KEY (prescription_id) REFERENCES prescription_order (id),
    CONSTRAINT ck_prescription_item_quantity CHECK (quantity >= 0)
);

CREATE INDEX idx_emr_record_doctor_created ON emr_record (doctor_id, created_at);
CREATE INDEX idx_emr_record_patient_created ON emr_record (patient_id, created_at);
CREATE INDEX idx_emr_diagnosis_record ON emr_diagnosis (record_id, sort_order);
CREATE INDEX idx_prescription_order_encounter ON prescription_order (encounter_id, created_at);
CREATE INDEX idx_prescription_item_order ON prescription_item (prescription_id, sort_order);
