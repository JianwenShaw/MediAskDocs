INSERT INTO hospitals (id, hospital_code, name, hospital_level, status)
VALUES
    (3001, 'HOSP_MAIN', 'MediAsk Teaching Hospital', '3A', 'ACTIVE')
ON CONFLICT (hospital_code) DO NOTHING;

INSERT INTO departments (id, hospital_id, dept_code, name, dept_type, status, sort_order)
VALUES
    (3101, 3001, 'NEURO', '神经内科', 'CLINICAL', 'ACTIVE', 10),
    (3102, 3001, 'FEVER', '发热门诊', 'CLINICAL', 'ACTIVE', 20),
    (3103, 3001, 'GENMED', '普通内科', 'CLINICAL', 'ACTIVE', 30),
    (3104, 3001, 'PEDI', '儿科', 'CLINICAL', 'ACTIVE', 40),
    (3105, 3001, 'CARDIO', '心内科', 'CLINICAL', 'ACTIVE', 50),
    (3106, 3001, 'RESP', '呼吸内科', 'CLINICAL', 'ACTIVE', 60),
    (3107, 3001, 'GASTRO', '消化内科', 'CLINICAL', 'ACTIVE', 70),
    (3108, 3001, 'DERM', '皮肤科', 'CLINICAL', 'ACTIVE', 80),
    (3109, 3001, 'ORTHO', '骨科', 'CLINICAL', 'ACTIVE', 90)
ON CONFLICT (hospital_id, dept_code) DO NOTHING;

INSERT INTO doctors (id, user_id, hospital_id, doctor_code, professional_title, introduction_masked, status)
VALUES
    (3201, 2002, 3001, 'DOC_ZHANG', 'ATTENDING', '擅长常见内科问题接诊', 'ACTIVE'),
    (3202, 2004, 3001, 'DOC_WANG', 'ASSOCIATE_CHIEF', '擅长头痛头晕和神经系统常见病', 'ACTIVE'),
    (3203, 2005, 3001, 'DOC_CHEN', 'ATTENDING', '擅长发热与呼吸道感染评估', 'ACTIVE')
ON CONFLICT (doctor_code) DO NOTHING;

INSERT INTO doctor_department_rel (id, doctor_id, department_id, is_primary, relation_status)
VALUES
    (3301, 3201, 3103, TRUE, 'ACTIVE'),
    (3302, 3201, 3104, FALSE, 'ACTIVE'),
    (3303, 3202, 3101, TRUE, 'ACTIVE'),
    (3304, 3203, 3102, TRUE, 'ACTIVE')
ON CONFLICT (doctor_id, department_id) DO NOTHING;
