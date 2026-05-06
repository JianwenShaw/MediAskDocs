CREATE TABLE clinic_session (
    id BIGINT PRIMARY KEY,
    hospital_id BIGINT NOT NULL,
    department_id BIGINT NOT NULL,
    doctor_id BIGINT NOT NULL,
    session_date DATE NOT NULL,
    period_code VARCHAR(16) NOT NULL,
    clinic_type VARCHAR(16) NOT NULL,
    session_status VARCHAR(16) NOT NULL DEFAULT 'PUBLISHED',
    capacity INT NOT NULL,
    remaining_count INT NOT NULL,
    fee NUMERIC(10,2) NOT NULL DEFAULT 0,
    source_type VARCHAR(16) NOT NULL DEFAULT 'MANUAL',
    version INT NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    deleted_at TIMESTAMPTZ DEFAULT NULL,
    CONSTRAINT uk_clinic_session_doctor_period UNIQUE (doctor_id, session_date, period_code),
    CONSTRAINT uk_clinic_session_identity UNIQUE (id, doctor_id, department_id),
    CONSTRAINT fk_clinic_session_department FOREIGN KEY (department_id) REFERENCES departments (id),
    CONSTRAINT fk_clinic_session_doctor FOREIGN KEY (doctor_id) REFERENCES doctors (id),
    CONSTRAINT ck_clinic_session_period_code CHECK (period_code IN ('MORNING', 'AFTERNOON', 'EVENING')),
    CONSTRAINT ck_clinic_session_type CHECK (clinic_type IN ('GENERAL', 'SPECIALIST', 'EXPERT')),
    CONSTRAINT ck_clinic_session_status CHECK (session_status IN ('DRAFT', 'PUBLISHED', 'OPEN', 'CLOSED', 'CANCELLED')),
    CONSTRAINT ck_clinic_session_capacity CHECK (capacity >= 0),
    CONSTRAINT ck_clinic_session_remaining CHECK (remaining_count >= 0 AND remaining_count <= capacity),
    CONSTRAINT ck_clinic_session_fee CHECK (fee >= 0)
);

CREATE TABLE clinic_slot (
    id BIGINT PRIMARY KEY,
    session_id BIGINT NOT NULL,
    slot_seq INT NOT NULL,
    slot_start_time TIMESTAMPTZ NOT NULL,
    slot_end_time TIMESTAMPTZ NOT NULL,
    slot_status VARCHAR(16) NOT NULL DEFAULT 'AVAILABLE',
    capacity INT NOT NULL DEFAULT 1,
    remaining_count INT NOT NULL DEFAULT 1,
    version INT NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    deleted_at TIMESTAMPTZ DEFAULT NULL,
    CONSTRAINT uk_clinic_slot_seq UNIQUE (session_id, slot_seq),
    CONSTRAINT uk_clinic_slot_session_ref UNIQUE (id, session_id),
    CONSTRAINT fk_clinic_slot_session FOREIGN KEY (session_id) REFERENCES clinic_session (id),
    CONSTRAINT ck_clinic_slot_seq CHECK (slot_seq > 0),
    CONSTRAINT ck_clinic_slot_status CHECK (slot_status IN ('AVAILABLE', 'BOOKED', 'CANCELLED')),
    CONSTRAINT ck_clinic_slot_time CHECK (slot_start_time < slot_end_time),
    CONSTRAINT ck_clinic_slot_capacity CHECK (capacity >= 0),
    CONSTRAINT ck_clinic_slot_remaining CHECK (remaining_count >= 0 AND remaining_count <= capacity)
);

CREATE TABLE registration_order (
    id BIGINT PRIMARY KEY,
    order_no VARCHAR(64) NOT NULL,
    patient_id BIGINT NOT NULL,
    doctor_id BIGINT NOT NULL,
    department_id BIGINT NOT NULL,
    session_id BIGINT NOT NULL,
    slot_id BIGINT NOT NULL,
    source_ai_session_id VARCHAR(64),
    order_status VARCHAR(16) NOT NULL DEFAULT 'CONFIRMED',
    fee NUMERIC(10,2) NOT NULL DEFAULT 0,
    paid_at TIMESTAMPTZ,
    cancelled_at TIMESTAMPTZ,
    cancellation_reason VARCHAR(255),
    version INT NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    deleted_at TIMESTAMPTZ DEFAULT NULL,
    CONSTRAINT uk_registration_order_no UNIQUE (order_no),
    CONSTRAINT uk_registration_order_identity UNIQUE (id, patient_id, doctor_id, department_id),
    CONSTRAINT fk_registration_order_patient FOREIGN KEY (patient_id) REFERENCES users (id),
    CONSTRAINT fk_registration_order_session_doctor_department FOREIGN KEY (session_id, doctor_id, department_id)
        REFERENCES clinic_session (id, doctor_id, department_id),
    CONSTRAINT fk_registration_order_slot_session FOREIGN KEY (slot_id, session_id)
        REFERENCES clinic_slot (id, session_id),
    CONSTRAINT ck_registration_order_status CHECK (order_status IN ('CONFIRMED', 'CANCELLED', 'COMPLETED')),
    CONSTRAINT ck_registration_order_fee CHECK (fee >= 0)
);

CREATE TABLE visit_encounter (
    id BIGINT PRIMARY KEY,
    order_id BIGINT NOT NULL,
    patient_id BIGINT NOT NULL,
    doctor_id BIGINT NOT NULL,
    department_id BIGINT NOT NULL,
    encounter_status VARCHAR(16) NOT NULL DEFAULT 'SCHEDULED',
    started_at TIMESTAMPTZ,
    ended_at TIMESTAMPTZ,
    summary TEXT,
    version INT NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    deleted_at TIMESTAMPTZ DEFAULT NULL,
    CONSTRAINT uk_visit_encounter_order UNIQUE (order_id),
    CONSTRAINT uk_visit_encounter_identity UNIQUE (id, patient_id, doctor_id, department_id),
    CONSTRAINT fk_visit_encounter_order_identity FOREIGN KEY (order_id, patient_id, doctor_id, department_id)
        REFERENCES registration_order (id, patient_id, doctor_id, department_id),
    CONSTRAINT ck_visit_encounter_status CHECK (encounter_status IN ('SCHEDULED', 'IN_PROGRESS', 'COMPLETED', 'CANCELLED'))
);

CREATE INDEX idx_clinic_session_department_date ON clinic_session (department_id, session_date, session_status);
CREATE INDEX idx_registration_order_doctor_created ON registration_order (doctor_id, created_at);
CREATE INDEX idx_registration_order_patient_created ON registration_order (patient_id, created_at);
CREATE INDEX idx_visit_encounter_doctor_created ON visit_encounter (doctor_id, created_at);
