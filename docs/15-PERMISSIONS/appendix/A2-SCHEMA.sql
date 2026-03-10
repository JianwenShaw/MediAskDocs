-- A2. 权限/审计相关表结构草案（已废弃）
--
-- 说明：
-- 1. 本文件保留为早期草案存档，不再作为当前 V3 设计依据。
-- 2. 当前权限/审计事实来源以 docs/07-DATABASE.md、docs/07D-AUDIT-TABLES-V3.md
--    与 docs/15-PERMISSIONS/*.md 为准。
-- 3. 本文件中的表名如 audit_logs 等仍沿用旧版口径，请勿据此继续实现或答辩表述。

-- 角色表（支持继承）
CREATE TABLE roles (
    id BIGINT PRIMARY KEY,
    code VARCHAR(50) NOT NULL UNIQUE COMMENT '角色编码',
    name VARCHAR(50) NOT NULL COMMENT '角色名称',
    parent_id BIGINT COMMENT '父角色ID（支持继承）',
    level INT DEFAULT 0 COMMENT '角色等级（数值越大权限越高）',
    description VARCHAR(255) COMMENT '描述',
    is_system BOOLEAN DEFAULT FALSE COMMENT '是否系统角色',
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME ON UPDATE CURRENT_TIMESTAMP,
    deleted_at DATETIME,
    INDEX idx_roles_parent (parent_id),
    INDEX idx_roles_level (level)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='角色表';

-- 用户角色关联表（支持有效期）
CREATE TABLE user_roles (
    id BIGINT PRIMARY KEY,
    user_id BIGINT NOT NULL,
    role_id BIGINT NOT NULL,
    valid_from DATETIME COMMENT '生效时间',
    valid_until DATETIME COMMENT '失效时间（支持临时角色）',
    grant_reason VARCHAR(255) COMMENT '授权原因',
    grantor_id BIGINT COMMENT '授权人',
    is_emergency BOOLEAN DEFAULT FALSE COMMENT '是否紧急授权',
    status VARCHAR(20) DEFAULT 'ACTIVE' COMMENT 'ACTIVE/PENDING_EXPIRE/EXPIRED',
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    deleted_at DATETIME,
    UNIQUE KEY uk_user_role (user_id, role_id, valid_from),
    INDEX idx_user_roles_user (user_id),
    INDEX idx_user_roles_role (role_id),
    INDEX idx_user_roles_valid (valid_until)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='用户角色关联表';

-- 角色互斥规则表
CREATE TABLE role_mutex_rules (
    id BIGINT PRIMARY KEY,
    role_id1 BIGINT NOT NULL COMMENT '互斥角色1',
    role_id2 BIGINT NOT NULL COMMENT '互斥角色2',
    description VARCHAR(255) COMMENT '互斥说明',
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY uk_role_mutex (role_id1, role_id2)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='角色互斥规则表';

-- 权限表（树形结构）
CREATE TABLE permissions (
    id BIGINT PRIMARY KEY,
    code VARCHAR(100) NOT NULL UNIQUE COMMENT '权限编码',
    name VARCHAR(50) NOT NULL COMMENT '权限名称',
    parent_id BIGINT DEFAULT 0 COMMENT '父权限ID',
    type VARCHAR(20) COMMENT '类型：MENU/BUTTON/API',
    path VARCHAR(255) COMMENT 'API路径',
    method VARCHAR(10) COMMENT 'HTTP方法：GET/POST/PUT/DELETE',
    sort_order INT DEFAULT 0 COMMENT '排序',
    icon VARCHAR(50) COMMENT '菜单图标',
    description VARCHAR(255) COMMENT '描述',
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    deleted_at DATETIME,
    INDEX idx_permissions_parent (parent_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='权限表';

-- 角色权限关联表
CREATE TABLE role_permissions (
    id BIGINT PRIMARY KEY,
    role_id BIGINT NOT NULL,
    permission_id BIGINT NOT NULL,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY uk_role_perm (role_id, permission_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='角色权限关联表';

-- 数据权限范围表
CREATE TABLE data_scope_rules (
    id BIGINT PRIMARY KEY,
    role_id BIGINT NOT NULL COMMENT '角色ID',
    resource_type VARCHAR(50) NOT NULL COMMENT '资源类型',
    scope_type VARCHAR(20) NOT NULL COMMENT '范围类型：ALL/DEPARTMENT/SELF/TEAM/CUSTOM',
    custom_condition TEXT COMMENT '自定义SQL条件（JSON）',
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='数据权限规则表';

-- 黑白名单表
CREATE TABLE access_blacklists (
    id BIGINT PRIMARY KEY,
    type VARCHAR(20) NOT NULL COMMENT '类型：FUNCTION/API/IP/USER',
    target VARCHAR(255) NOT NULL COMMENT '目标值',
    user_id BIGINT COMMENT '针对用户ID',
    valid_from DATETIME COMMENT '生效时间',
    valid_until DATETIME COMMENT '失效时间',
    reason VARCHAR(255) COMMENT '封禁/放行原因',
    operator_id BIGINT COMMENT '操作人',
    status VARCHAR(20) DEFAULT 'ACTIVE' COMMENT 'ACTIVE/EXPIRED/CANCELLED',
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_blacklist_type_target (type, target),
    INDEX idx_blacklist_user (user_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='黑白名单表';

-- 权限审批表
CREATE TABLE permission_approval_orders (
    id BIGINT PRIMARY KEY,
    applicant_id BIGINT NOT NULL COMMENT '申请人',
    target_user_id BIGINT NOT NULL COMMENT '目标用户',
    roles JSON NOT NULL COMMENT '申请的角色ID列表',
    reason VARCHAR(500) NOT NULL COMMENT '申请理由',
    approver_id BIGINT COMMENT '审批人',
    status VARCHAR(20) DEFAULT 'PENDING' COMMENT 'PENDING/APPROVED/REJECTED/CANCELLED',
    approval_comment VARCHAR(500) COMMENT '审批意见',
    approved_at DATETIME COMMENT '审批时间',
    expires_at DATETIME COMMENT '审批有效期',
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_approval_status (status),
    INDEX idx_approval_approver (approver_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='权限审批表';

-- 审计日志表（增强版）
CREATE TABLE audit_logs (
    id BIGINT PRIMARY KEY,
    user_id BIGINT COMMENT '操作用户ID',
    username VARCHAR(50) COMMENT '用户名',
    user_role VARCHAR(50) COMMENT '用户角色',
    user_department BIGINT COMMENT '用户科室',
    action VARCHAR(50) NOT NULL COMMENT '操作类型',
    action_name VARCHAR(50) COMMENT '操作名称',
    resource_type VARCHAR(50) COMMENT '资源类型',
    resource_id VARCHAR(64) COMMENT '资源ID',
    resource_name VARCHAR(255) COMMENT '资源名称',
    client_ip VARCHAR(45) COMMENT '客户端IP',
    user_agent VARCHAR(500) COMMENT 'User-Agent',
    trace_id VARCHAR(64) COMMENT '链路追踪ID',
    old_value TEXT COMMENT '变更前（JSON）',
    new_value TEXT COMMENT '变更后（JSON）',
    request_params TEXT COMMENT '请求参数（JSON脱敏后）',
    success BOOLEAN DEFAULT TRUE COMMENT '是否成功',
    fail_reason VARCHAR(500) COMMENT '失败原因',
    integrity_hash VARCHAR(64) COMMENT '完整性校验哈希',
    previous_hash VARCHAR(64) COMMENT '前一条记录的哈希（链式）',
    timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_audit_user_time (user_id, timestamp),
    INDEX idx_audit_resource (resource_type, resource_id),
    INDEX idx_audit_action (action),
    INDEX idx_audit_timestamp (timestamp),
    INDEX idx_audit_trace (trace_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='审计日志表';
