INSERT INTO roles (id, role_code, role_name, role_type, status, sort_order)
VALUES
    (1001, 'PATIENT', '患者', 'BUSINESS', 'ACTIVE', 10),
    (1002, 'DOCTOR', '医生', 'BUSINESS', 'ACTIVE', 20),
    (1003, 'ADMIN', '管理员', 'SYSTEM', 'ACTIVE', 30)
ON CONFLICT (role_code) DO NOTHING;

INSERT INTO permissions (id, permission_code, permission_name, permission_type, status, sort_order)
VALUES
    (1102, 'registration:create', '创建挂号', 'API', 'ACTIVE', 20),
    (1103, 'encounter:query', '查询接诊', 'API', 'ACTIVE', 30),
    (1104, 'emr:create', '创建病历', 'API', 'ACTIVE', 40),
    (1105, 'emr:read', '查看病历', 'API', 'ACTIVE', 50),
    (1106, 'auth:refresh', '刷新令牌', 'API', 'ACTIVE', 60),
    (1108, 'patient:profile:view:self', '查看本人患者资料', 'API', 'ACTIVE', 80),
    (1109, 'doctor:profile:view:self', '查看本人医生资料', 'API', 'ACTIVE', 90),
    (1110, 'patient:profile:update:self', '更新本人患者资料', 'API', 'ACTIVE', 100),
    (1111, 'doctor:profile:update:self', '更新本人医生资料', 'API', 'ACTIVE', 110),
    (1112, 'admin:patient:list', '后台患者列表', 'API', 'ACTIVE', 120),
    (1113, 'admin:patient:view', '后台患者详情', 'API', 'ACTIVE', 130),
    (1114, 'admin:patient:create', '后台新增患者', 'API', 'ACTIVE', 140),
    (1115, 'admin:patient:update', '后台修改患者', 'API', 'ACTIVE', 150),
    (1116, 'admin:patient:delete', '后台删除患者', 'API', 'ACTIVE', 160),
    (1124, 'encounter:update', '更新接诊状态', 'API', 'ACTIVE', 240),
    (1125, 'prescription:create', '创建处方', 'API', 'ACTIVE', 250),
    (1126, 'prescription:read', '查看处方', 'API', 'ACTIVE', 260),
    (1127, 'admin:triage-catalog:publish', '发布导诊目录', 'API', 'ACTIVE', 270),
    (1128, 'admin:knowledge-base:list', '知识库列表', 'API', 'ACTIVE', 280),
    (1129, 'admin:knowledge-base:create', '创建知识库', 'API', 'ACTIVE', 290),
    (1130, 'admin:knowledge-base:update', '更新知识库', 'API', 'ACTIVE', 300),
    (1131, 'admin:knowledge-base:delete', '删除知识库', 'API', 'ACTIVE', 310),
    (1132, 'admin:knowledge-document:import', '导入知识文档', 'API', 'ACTIVE', 320),
    (1133, 'admin:knowledge-document:list', '知识文档列表', 'API', 'ACTIVE', 330),
    (1134, 'admin:knowledge-document:delete', '删除知识文档', 'API', 'ACTIVE', 340),
    (1135, 'admin:knowledge-ingest-job:view', '查看知识入库任务', 'API', 'ACTIVE', 350),
    (1136, 'admin:knowledge-index-version:list', '知识索引版本列表', 'API', 'ACTIVE', 360),
    (1137, 'admin:knowledge-release:list', '知识发布记录列表', 'API', 'ACTIVE', 370),
    (1138, 'admin:knowledge-release:publish', '发布知识库版本', 'API', 'ACTIVE', 380)
ON CONFLICT (permission_code) DO NOTHING;

INSERT INTO role_permissions (id, role_id, permission_id)
VALUES
    (1202, 1001, 1102),
    (1203, 1002, 1103),
    (1204, 1002, 1104),
    (1205, 1002, 1105),
    (1206, 1001, 1106),
    (1207, 1002, 1106),
    (1208, 1003, 1106),
    (1211, 1001, 1108),
    (1212, 1002, 1109),
    (1213, 1001, 1110),
    (1214, 1002, 1111),
    (1215, 1003, 1112),
    (1216, 1003, 1113),
    (1217, 1003, 1114),
    (1218, 1003, 1115),
    (1219, 1003, 1116),
    (1227, 1001, 1105),
    (1228, 1002, 1124),
    (1229, 1002, 1125),
    (1230, 1002, 1126),
    (1231, 1003, 1127),
    (1232, 1003, 1128),
    (1233, 1003, 1129),
    (1234, 1003, 1130),
    (1235, 1003, 1131),
    (1236, 1003, 1132),
    (1237, 1003, 1133),
    (1238, 1003, 1134),
    (1239, 1003, 1135),
    (1240, 1003, 1136),
    (1241, 1003, 1137),
    (1242, 1003, 1138)
ON CONFLICT (role_id, permission_id) DO NOTHING;

-- admin / admin123
-- doctor_zhang / doctor123
-- doctor_wang / doctor123
-- doctor_chen / doctor123
-- patient_li / patient123
-- patient_wu / patient123
-- patient_zhao / patient123
-- doctor_liu / doctor123
-- doctor_zhao2 / doctor123
-- doctor_yang / doctor123
-- doctor_zhou / doctor123
-- doctor_wu2 / doctor123
-- doctor_sun / doctor123
-- doctor_lin / doctor123
-- doctor_he / doctor123
-- doctor_guo / doctor123
-- doctor_ma / doctor123
-- doctor_tang / doctor123
-- doctor_deng / doctor123
-- doctor_xu / doctor123
-- doctor_feng / doctor123
-- doctor_jiang / doctor123
-- doctor_qin / doctor123
-- doctor_xie / doctor123
-- doctor_shen / doctor123
-- doctor_han / doctor123
-- doctor_yuan / doctor123
-- doctor_su / doctor123
-- patient_chen2 / patient123
-- patient_he2 / patient123
-- patient_guo2 / patient123
INSERT INTO users (id, username, password_hash, display_name, mobile_masked, user_type, account_status)
VALUES
    (2001, 'admin', '$2y$10$XMYeGErQIJ3Wg5Bzlj9B5.lhFhj3JBe1.YZ4j1OxihiNsHL4rIh8e', '系统管理员', '138****0000', 'ADMIN', 'ACTIVE'),
    (2002, 'doctor_zhang', '$2y$10$/0Am2Gpefs87WmCYex4Jr.RNGSOKaVsaLz4qmiB8zKOhKBgz.KUUy', '张医生', '139****0001', 'DOCTOR', 'ACTIVE'),
    (2003, 'patient_li', '$2y$10$xm4nTR2YtFBj9ZWiHbazOu3yq0JedJArylIn5HmdaP7FlLegb8WQe', '李患者', '137****0002', 'PATIENT', 'ACTIVE'),
    (2004, 'doctor_wang', '$2y$10$/0Am2Gpefs87WmCYex4Jr.RNGSOKaVsaLz4qmiB8zKOhKBgz.KUUy', '王医生', '139****0003', 'DOCTOR', 'ACTIVE'),
    (2005, 'doctor_chen', '$2y$10$/0Am2Gpefs87WmCYex4Jr.RNGSOKaVsaLz4qmiB8zKOhKBgz.KUUy', '陈医生', '139****0004', 'DOCTOR', 'ACTIVE'),
    (2006, 'patient_wu', '$2y$10$xm4nTR2YtFBj9ZWiHbazOu3yq0JedJArylIn5HmdaP7FlLegb8WQe', '吴患者', '137****0005', 'PATIENT', 'ACTIVE'),
    (2007, 'patient_zhao', '$2y$10$xm4nTR2YtFBj9ZWiHbazOu3yq0JedJArylIn5HmdaP7FlLegb8WQe', '赵患者', '137****0006', 'PATIENT', 'ACTIVE'),
    (2008, 'doctor_liu', '$2y$10$/0Am2Gpefs87WmCYex4Jr.RNGSOKaVsaLz4qmiB8zKOhKBgz.KUUy', '刘医生', '139****0007', 'DOCTOR', 'ACTIVE'),
    (2009, 'doctor_zhao2', '$2y$10$/0Am2Gpefs87WmCYex4Jr.RNGSOKaVsaLz4qmiB8zKOhKBgz.KUUy', '赵医生', '139****0008', 'DOCTOR', 'ACTIVE'),
    (2010, 'doctor_yang', '$2y$10$/0Am2Gpefs87WmCYex4Jr.RNGSOKaVsaLz4qmiB8zKOhKBgz.KUUy', '杨医生', '139****0009', 'DOCTOR', 'ACTIVE'),
    (2011, 'doctor_zhou', '$2y$10$/0Am2Gpefs87WmCYex4Jr.RNGSOKaVsaLz4qmiB8zKOhKBgz.KUUy', '周医生', '139****0010', 'DOCTOR', 'ACTIVE'),
    (2012, 'doctor_wu2', '$2y$10$/0Am2Gpefs87WmCYex4Jr.RNGSOKaVsaLz4qmiB8zKOhKBgz.KUUy', '吴医生', '139****0011', 'DOCTOR', 'ACTIVE'),
    (2013, 'doctor_sun', '$2y$10$/0Am2Gpefs87WmCYex4Jr.RNGSOKaVsaLz4qmiB8zKOhKBgz.KUUy', '孙医生', '139****0012', 'DOCTOR', 'ACTIVE'),
    (2014, 'doctor_lin', '$2y$10$/0Am2Gpefs87WmCYex4Jr.RNGSOKaVsaLz4qmiB8zKOhKBgz.KUUy', '林医生', '139****0013', 'DOCTOR', 'ACTIVE'),
    (2015, 'doctor_he', '$2y$10$/0Am2Gpefs87WmCYex4Jr.RNGSOKaVsaLz4qmiB8zKOhKBgz.KUUy', '何医生', '139****0014', 'DOCTOR', 'ACTIVE'),
    (2016, 'doctor_guo', '$2y$10$/0Am2Gpefs87WmCYex4Jr.RNGSOKaVsaLz4qmiB8zKOhKBgz.KUUy', '郭医生', '139****0015', 'DOCTOR', 'ACTIVE'),
    (2017, 'doctor_ma', '$2y$10$/0Am2Gpefs87WmCYex4Jr.RNGSOKaVsaLz4qmiB8zKOhKBgz.KUUy', '马医生', '139****0016', 'DOCTOR', 'ACTIVE'),
    (2018, 'doctor_tang', '$2y$10$/0Am2Gpefs87WmCYex4Jr.RNGSOKaVsaLz4qmiB8zKOhKBgz.KUUy', '唐医生', '139****0017', 'DOCTOR', 'ACTIVE'),
    (2019, 'doctor_deng', '$2y$10$/0Am2Gpefs87WmCYex4Jr.RNGSOKaVsaLz4qmiB8zKOhKBgz.KUUy', '邓医生', '139****0018', 'DOCTOR', 'ACTIVE'),
    (2020, 'doctor_xu', '$2y$10$/0Am2Gpefs87WmCYex4Jr.RNGSOKaVsaLz4qmiB8zKOhKBgz.KUUy', '徐医生', '139****0019', 'DOCTOR', 'ACTIVE'),
    (2021, 'doctor_feng', '$2y$10$/0Am2Gpefs87WmCYex4Jr.RNGSOKaVsaLz4qmiB8zKOhKBgz.KUUy', '冯医生', '139****0020', 'DOCTOR', 'ACTIVE'),
    (2022, 'doctor_jiang', '$2y$10$/0Am2Gpefs87WmCYex4Jr.RNGSOKaVsaLz4qmiB8zKOhKBgz.KUUy', '蒋医生', '139****0021', 'DOCTOR', 'ACTIVE'),
    (2023, 'doctor_qin', '$2y$10$/0Am2Gpefs87WmCYex4Jr.RNGSOKaVsaLz4qmiB8zKOhKBgz.KUUy', '秦医生', '139****0022', 'DOCTOR', 'ACTIVE'),
    (2024, 'doctor_xie', '$2y$10$/0Am2Gpefs87WmCYex4Jr.RNGSOKaVsaLz4qmiB8zKOhKBgz.KUUy', '谢医生', '139****0023', 'DOCTOR', 'ACTIVE'),
    (2025, 'doctor_shen', '$2y$10$/0Am2Gpefs87WmCYex4Jr.RNGSOKaVsaLz4qmiB8zKOhKBgz.KUUy', '沈医生', '139****0024', 'DOCTOR', 'ACTIVE'),
    (2026, 'doctor_han', '$2y$10$/0Am2Gpefs87WmCYex4Jr.RNGSOKaVsaLz4qmiB8zKOhKBgz.KUUy', '韩医生', '139****0025', 'DOCTOR', 'ACTIVE'),
    (2027, 'doctor_yuan', '$2y$10$/0Am2Gpefs87WmCYex4Jr.RNGSOKaVsaLz4qmiB8zKOhKBgz.KUUy', '袁医生', '139****0026', 'DOCTOR', 'ACTIVE'),
    (2028, 'doctor_su', '$2y$10$/0Am2Gpefs87WmCYex4Jr.RNGSOKaVsaLz4qmiB8zKOhKBgz.KUUy', '苏医生', '139****0027', 'DOCTOR', 'ACTIVE'),
    (2029, 'patient_chen2', '$2y$10$xm4nTR2YtFBj9ZWiHbazOu3yq0JedJArylIn5HmdaP7FlLegb8WQe', '陈患者', '137****0028', 'PATIENT', 'ACTIVE'),
    (2030, 'patient_he2', '$2y$10$xm4nTR2YtFBj9ZWiHbazOu3yq0JedJArylIn5HmdaP7FlLegb8WQe', '何患者', '137****0029', 'PATIENT', 'ACTIVE'),
    (2031, 'patient_guo2', '$2y$10$xm4nTR2YtFBj9ZWiHbazOu3yq0JedJArylIn5HmdaP7FlLegb8WQe', '郭患者', '137****0030', 'PATIENT', 'ACTIVE')
ON CONFLICT (username) DO NOTHING;

INSERT INTO user_roles (id, user_id, role_id, granted_by)
VALUES
    (2101, 2001, 1003, 2001),
    (2102, 2002, 1002, 2001),
    (2103, 2003, 1001, 2001),
    (2104, 2004, 1002, 2001),
    (2105, 2005, 1002, 2001),
    (2106, 2006, 1001, 2001),
    (2107, 2007, 1001, 2001),
    (2108, 2008, 1002, 2001),
    (2109, 2009, 1002, 2001),
    (2110, 2010, 1002, 2001),
    (2111, 2011, 1002, 2001),
    (2112, 2012, 1002, 2001),
    (2113, 2013, 1002, 2001),
    (2114, 2014, 1002, 2001),
    (2115, 2015, 1002, 2001),
    (2116, 2016, 1002, 2001),
    (2117, 2017, 1002, 2001),
    (2118, 2018, 1002, 2001),
    (2119, 2019, 1002, 2001),
    (2120, 2020, 1002, 2001),
    (2121, 2021, 1002, 2001),
    (2122, 2022, 1002, 2001),
    (2123, 2023, 1002, 2001),
    (2124, 2024, 1002, 2001),
    (2125, 2025, 1002, 2001),
    (2126, 2026, 1002, 2001),
    (2127, 2027, 1002, 2001),
    (2128, 2028, 1002, 2001),
    (2129, 2029, 1001, 2001),
    (2130, 2030, 1001, 2001),
    (2131, 2031, 1001, 2001)
ON CONFLICT (user_id, role_id) DO NOTHING;

INSERT INTO user_pii_profile (user_id, real_name_encrypted, phone_encrypted, id_no_encrypted, email_encrypted)
VALUES
    (2001, 'enc_admin_name', 'enc_admin_phone', 'enc_admin_id', 'enc_admin_mail'),
    (2002, 'enc_doctor_zhang_name', 'enc_doctor_zhang_phone', 'enc_doctor_zhang_id', 'enc_doctor_zhang_mail'),
    (2003, 'enc_patient_li_name', 'enc_patient_li_phone', 'enc_patient_li_id', 'enc_patient_li_mail'),
    (2004, 'enc_doctor_wang_name', 'enc_doctor_wang_phone', 'enc_doctor_wang_id', 'enc_doctor_wang_mail'),
    (2005, 'enc_doctor_chen_name', 'enc_doctor_chen_phone', 'enc_doctor_chen_id', 'enc_doctor_chen_mail'),
    (2006, 'enc_patient_wu_name', 'enc_patient_wu_phone', 'enc_patient_wu_id', 'enc_patient_wu_mail'),
    (2007, 'enc_patient_zhao_name', 'enc_patient_zhao_phone', 'enc_patient_zhao_id', 'enc_patient_zhao_mail'),
    (2008, 'enc_doctor_liu_name', 'enc_doctor_liu_phone', 'enc_doctor_liu_id', 'enc_doctor_liu_mail'),
    (2009, 'enc_doctor_zhao2_name', 'enc_doctor_zhao2_phone', 'enc_doctor_zhao2_id', 'enc_doctor_zhao2_mail'),
    (2010, 'enc_doctor_yang_name', 'enc_doctor_yang_phone', 'enc_doctor_yang_id', 'enc_doctor_yang_mail'),
    (2011, 'enc_doctor_zhou_name', 'enc_doctor_zhou_phone', 'enc_doctor_zhou_id', 'enc_doctor_zhou_mail'),
    (2012, 'enc_doctor_wu2_name', 'enc_doctor_wu2_phone', 'enc_doctor_wu2_id', 'enc_doctor_wu2_mail'),
    (2013, 'enc_doctor_sun_name', 'enc_doctor_sun_phone', 'enc_doctor_sun_id', 'enc_doctor_sun_mail'),
    (2014, 'enc_doctor_lin_name', 'enc_doctor_lin_phone', 'enc_doctor_lin_id', 'enc_doctor_lin_mail'),
    (2015, 'enc_doctor_he_name', 'enc_doctor_he_phone', 'enc_doctor_he_id', 'enc_doctor_he_mail'),
    (2016, 'enc_doctor_guo_name', 'enc_doctor_guo_phone', 'enc_doctor_guo_id', 'enc_doctor_guo_mail'),
    (2017, 'enc_doctor_ma_name', 'enc_doctor_ma_phone', 'enc_doctor_ma_id', 'enc_doctor_ma_mail'),
    (2018, 'enc_doctor_tang_name', 'enc_doctor_tang_phone', 'enc_doctor_tang_id', 'enc_doctor_tang_mail'),
    (2019, 'enc_doctor_deng_name', 'enc_doctor_deng_phone', 'enc_doctor_deng_id', 'enc_doctor_deng_mail'),
    (2020, 'enc_doctor_xu_name', 'enc_doctor_xu_phone', 'enc_doctor_xu_id', 'enc_doctor_xu_mail'),
    (2021, 'enc_doctor_feng_name', 'enc_doctor_feng_phone', 'enc_doctor_feng_id', 'enc_doctor_feng_mail'),
    (2022, 'enc_doctor_jiang_name', 'enc_doctor_jiang_phone', 'enc_doctor_jiang_id', 'enc_doctor_jiang_mail'),
    (2023, 'enc_doctor_qin_name', 'enc_doctor_qin_phone', 'enc_doctor_qin_id', 'enc_doctor_qin_mail'),
    (2024, 'enc_doctor_xie_name', 'enc_doctor_xie_phone', 'enc_doctor_xie_id', 'enc_doctor_xie_mail'),
    (2025, 'enc_doctor_shen_name', 'enc_doctor_shen_phone', 'enc_doctor_shen_id', 'enc_doctor_shen_mail'),
    (2026, 'enc_doctor_han_name', 'enc_doctor_han_phone', 'enc_doctor_han_id', 'enc_doctor_han_mail'),
    (2027, 'enc_doctor_yuan_name', 'enc_doctor_yuan_phone', 'enc_doctor_yuan_id', 'enc_doctor_yuan_mail'),
    (2028, 'enc_doctor_su_name', 'enc_doctor_su_phone', 'enc_doctor_su_id', 'enc_doctor_su_mail'),
    (2029, 'enc_patient_chen2_name', 'enc_patient_chen2_phone', 'enc_patient_chen2_id', 'enc_patient_chen2_mail'),
    (2030, 'enc_patient_he2_name', 'enc_patient_he2_phone', 'enc_patient_he2_id', 'enc_patient_he2_mail'),
    (2031, 'enc_patient_guo2_name', 'enc_patient_guo2_phone', 'enc_patient_guo2_id', 'enc_patient_guo2_mail')
ON CONFLICT (user_id) DO NOTHING;

INSERT INTO patient_profile (id, user_id, patient_no, gender, birth_date, blood_type, allergy_summary)
VALUES
    (2201, 2003, 'P20260001', 'FEMALE', DATE '1995-03-12', 'A', '青霉素过敏'),
    (2202, 2006, 'P20260002', 'MALE', DATE '1988-07-01', 'O', '无'),
    (2203, 2007, 'P20260003', 'FEMALE', DATE '2001-11-20', 'B', '海鲜轻度过敏'),
    (2204, 2029, 'P20260004', 'MALE', DATE '1975-06-15', 'AB', '磺胺类药物过敏'),
    (2205, 2030, 'P20260005', 'FEMALE', DATE '1990-02-28', 'O', '无'),
    (2206, 2031, 'P20260006', 'MALE', DATE '1983-09-08', 'A', '花粉过敏')
ON CONFLICT (user_id) DO NOTHING;

INSERT INTO data_scope_rules (id, role_id, resource_type, scope_type, status)
VALUES
    (3401, 1001, 'EMR_RECORD', 'SELF', 'ACTIVE'),
    (3402, 1002, 'EMR_RECORD', 'DEPARTMENT', 'ACTIVE'),
    (3403, 1003, 'AUDIT_EVENT', 'ALL', 'ACTIVE')
ON CONFLICT DO NOTHING;
