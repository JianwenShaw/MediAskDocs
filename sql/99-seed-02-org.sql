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
    (3109, 3001, 'ORTHO', '骨科', 'CLINICAL', 'ACTIVE', 90),
    (3110, 3001, 'ENDO', '内分泌科', 'CLINICAL', 'ACTIVE', 100),
    (3111, 3001, 'NEPH', '肾内科', 'CLINICAL', 'ACTIVE', 110),
    (3112, 3001, 'HEMA', '血液内科', 'CLINICAL', 'ACTIVE', 120),
    (3113, 3001, 'GENSUR', '普通外科', 'CLINICAL', 'ACTIVE', 130),
    (3114, 3001, 'URO', '泌尿外科', 'CLINICAL', 'ACTIVE', 140),
    (3115, 3001, 'THORAC', '心胸外科', 'CLINICAL', 'ACTIVE', 150),
    (3116, 3001, 'NEUROSUR', '神经外科', 'CLINICAL', 'ACTIVE', 160),
    (3117, 3001, 'BURN', '烧伤科', 'CLINICAL', 'ACTIVE', 170),
    (3118, 3001, 'OPHTH', '眼科', 'CLINICAL', 'ACTIVE', 180),
    (3119, 3001, 'ENT', '耳鼻喉科', 'CLINICAL', 'ACTIVE', 190),
    (3120, 3001, 'STOMA', '口腔科', 'CLINICAL', 'ACTIVE', 200),
    (3121, 3001, 'ONCO', '肿瘤科', 'CLINICAL', 'ACTIVE', 210),
    (3122, 3001, 'TCM', '中医科', 'CLINICAL', 'ACTIVE', 220),
    (3123, 3001, 'EMERG', '急诊科', 'CLINICAL', 'ACTIVE', 230),
    (3124, 3001, 'INFECT', '感染科', 'CLINICAL', 'ACTIVE', 240),
    (3125, 3001, 'PSYCH', '精神心理科', 'CLINICAL', 'ACTIVE', 250),
    (3126, 3001, 'REHAB', '康复科', 'CLINICAL', 'ACTIVE', 260),
    (3127, 3001, 'OBGYN', '妇产科', 'CLINICAL', 'ACTIVE', 270),
    (3128, 3001, 'BREAST', '甲乳外科', 'CLINICAL', 'ACTIVE', 280)
ON CONFLICT (hospital_id, dept_code) DO NOTHING;

INSERT INTO doctors (id, user_id, hospital_id, doctor_code, professional_title, introduction_masked, status)
VALUES
    (3201, 2002, 3001, 'DOC_ZHANG', 'ATTENDING', '擅长常见内科问题接诊', 'ACTIVE'),
    (3202, 2004, 3001, 'DOC_WANG', 'ASSOCIATE_CHIEF', '擅长头痛头晕和神经系统常见病', 'ACTIVE'),
    (3203, 2005, 3001, 'DOC_CHEN', 'ATTENDING', '擅长发热与呼吸道感染评估', 'ACTIVE'),
    (3204, 2008, 3001, 'DOC_LIU', 'CHIEF_PHYSICIAN', '擅长糖尿病、甲状腺疾病及代谢综合征的诊治', 'ACTIVE'),
    (3205, 2009, 3001, 'DOC_ZHAO', 'ASSOCIATE_CHIEF', '擅长胃肠道疾病及消化内镜诊疗', 'ACTIVE'),
    (3206, 2010, 3001, 'DOC_YANG', 'CHIEF_PHYSICIAN', '擅长高血压、冠心病及心力衰竭的诊治', 'ACTIVE'),
    (3207, 2011, 3001, 'DOC_ZHOU', 'ATTENDING', '擅长骨折创伤及关节置换手术', 'ACTIVE'),
    (3208, 2012, 3001, 'DOC_WU', 'ASSOCIATE_CHIEF', '擅长上腹部及肝胆外科手术', 'ACTIVE'),
    (3209, 2013, 3001, 'DOC_SUN', 'CHIEF_PHYSICIAN', '擅长妇科肿瘤及微创手术', 'ACTIVE'),
    (3210, 2014, 3001, 'DOC_LIN', 'ATTENDING', '擅长白内障及青光眼手术治疗', 'ACTIVE'),
    (3211, 2015, 3001, 'DOC_HE', 'ASSOCIATE_CHIEF', '擅长鼻窦炎、中耳炎及咽喉疾病诊治', 'ACTIVE'),
    (3212, 2016, 3001, 'DOC_GUO', 'CHIEF_PHYSICIAN', '擅长肺癌及消化道肿瘤的综合治疗', 'ACTIVE'),
    (3213, 2017, 3001, 'DOC_MA', 'CHIEF_PHYSICIAN', '擅长中医内科、脾胃调理及慢性病管理', 'ACTIVE'),
    (3214, 2018, 3001, 'DOC_TANG', 'ATTENDING', '擅长急危重症抢救及创伤急救', 'ACTIVE'),
    (3215, 2019, 3001, 'DOC_DENG', 'ASSOCIATE_CHIEF', '擅长肝炎、结核及感染性疾病诊治', 'ACTIVE'),
    (3216, 2020, 3001, 'DOC_XU', 'ATTENDING', '擅长泌尿系结石及前列腺疾病手术', 'ACTIVE'),
    (3217, 2021, 3001, 'DOC_FENG', 'ASSOCIATE_CHIEF', '擅长冠脉搭桥及心脏瓣膜手术', 'ACTIVE'),
    (3218, 2022, 3001, 'DOC_JIANG', 'CHIEF_PHYSICIAN', '擅长脑肿瘤及脑血管病手术治疗', 'ACTIVE'),
    (3219, 2023, 3001, 'DOC_QIN', 'ATTENDING', '擅长肾病综合征及血液透析治疗', 'ACTIVE'),
    (3220, 2024, 3001, 'DOC_XIE', 'ASSOCIATE_CHIEF', '擅长贫血、白血病及血液系统疾病诊治', 'ACTIVE'),
    (3221, 2025, 3001, 'DOC_SHEN', 'CHIEF_PHYSICIAN', '擅长甲状腺及乳腺肿瘤手术', 'ACTIVE'),
    (3222, 2026, 3001, 'DOC_HAN', 'ATTENDING', '擅长口腔种植及牙周病治疗', 'ACTIVE'),
    (3223, 2027, 3001, 'DOC_YUAN', 'ATTENDING', '擅长脑血管病后遗症及运动损伤康复', 'ACTIVE'),
    (3224, 2028, 3001, 'DOC_SU', 'ASSOCIATE_CHIEF', '擅长抑郁症、焦虑症及睡眠障碍治疗', 'ACTIVE')
ON CONFLICT (doctor_code) DO NOTHING;

INSERT INTO doctor_department_rel (id, doctor_id, department_id, is_primary, relation_status)
VALUES
    (3301, 3201, 3103, TRUE, 'ACTIVE'),
    (3302, 3201, 3104, FALSE, 'ACTIVE'),
    (3303, 3202, 3101, TRUE, 'ACTIVE'),
    (3304, 3203, 3102, TRUE, 'ACTIVE'),
    (3305, 3204, 3110, TRUE, 'ACTIVE'),
    (3306, 3205, 3107, TRUE, 'ACTIVE'),
    (3307, 3206, 3105, TRUE, 'ACTIVE'),
    (3308, 3207, 3109, TRUE, 'ACTIVE'),
    (3309, 3208, 3113, TRUE, 'ACTIVE'),
    (3310, 3209, 3127, TRUE, 'ACTIVE'),
    (3311, 3210, 3118, TRUE, 'ACTIVE'),
    (3312, 3211, 3119, TRUE, 'ACTIVE'),
    (3313, 3212, 3121, TRUE, 'ACTIVE'),
    (3314, 3213, 3122, TRUE, 'ACTIVE'),
    (3315, 3214, 3123, TRUE, 'ACTIVE'),
    (3316, 3215, 3124, TRUE, 'ACTIVE'),
    (3317, 3216, 3114, TRUE, 'ACTIVE'),
    (3318, 3217, 3115, TRUE, 'ACTIVE'),
    (3319, 3218, 3116, TRUE, 'ACTIVE'),
    (3320, 3219, 3111, TRUE, 'ACTIVE'),
    (3321, 3220, 3112, TRUE, 'ACTIVE'),
    (3322, 3221, 3128, TRUE, 'ACTIVE'),
    (3323, 3222, 3120, TRUE, 'ACTIVE'),
    (3324, 3223, 3126, TRUE, 'ACTIVE'),
    (3325, 3224, 3125, TRUE, 'ACTIVE')
ON CONFLICT (doctor_id, department_id) DO NOTHING;
