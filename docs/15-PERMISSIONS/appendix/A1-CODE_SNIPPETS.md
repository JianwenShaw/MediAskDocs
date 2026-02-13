# A1. 参考代码片段（示意）

> 说明：本文件是“概念到工程”的参考片段，用于沟通实现方向。代码不保证可直接编译运行，具体实现请以项目实际代码结构为准。

## 1. 角色继承

```java
public class Role {
    Long id;
    String code;
    Long parentId;
}

public boolean hasPermission(Long userId, String permissionCode) {
    // 伪代码：从用户角色出发，递归合并继承链权限
    return loadEffectivePermissionCodes(userId).contains(permissionCode);
}
```

## 2. 角色互斥校验

```java
public void checkRoleMutex(Long userId, Long newRoleId) {
    // 伪代码：查询 userId 现有角色，与互斥规则表比对
    // 若存在互斥冲突则拒绝并审计
}
```

## 3. 用户角色有效期

```java
public boolean isRoleEffective(UserRole ur, LocalDateTime now) {
    return (ur.getValidFrom() == null || !now.isBefore(ur.getValidFrom()))
        && (ur.getValidUntil() == null || !now.isAfter(ur.getValidUntil()));
}
```

## 4. 患者侧对象级授权

```java
public MedicalRecord findMyRecord(Long patientId, Long recordId) {
    MedicalRecord record = medicalRecordRepository.findById(recordId);
    if (record == null || !record.getPatientId().equals(patientId)) {
        throw new BizException(ErrorCode.FORBIDDEN, "无权查看该病历");
    }
    return record;
}
```

## 5. AI 对话数据权限（示意）

```java
public List<AiConversation> listAccessibleConversations(Long userId, String userType) {
    return switch (userType) {
        case "PATIENT", "DOCTOR" -> conversationRepo.findByUserId(userId);
        case "REVIEWER" -> conversationRepo.findAllAssignedTo(userId);
        case "ADMIN" -> conversationRepo.findAll();
        default -> List.of();
    };
}
```

## 6. 二次确认注解（示意）

```java
@Target(ElementType.METHOD)
@Retention(RetentionPolicy.RUNTIME)
public @interface RequireConfirm {
    ConfirmType type();
    int timeoutSeconds() default 300;
}

public enum ConfirmType { PASSWORD, SMS_CODE, REASON, APPROVAL }
```

## 7. 紧急授权（break-glass）要点

```java
public void grantEmergencyAccess(Long targetUserId, Long roleId, String reason) {
    // 强制 reason
    // 严格有效期 validUntil
    // 标记 is_emergency
    // 强制审计
}
```

## 8. 黑白名单与限流（示意）

```java
public void checkBlacklist(Long userId, String apiPath, String clientIp) {
    // 按 USER / API / IP 维度检查有效期内黑名单
}

public boolean checkRateLimit(Long userId, String apiKey, Duration window, long limit) {
    // 伪代码：Redis 自增 + TTL
    return true;
}
```

## 9. 对象级授权（防 BOLA/IDOR）

```java
public void checkObjectAccess(Long userId, String resourceType, Long resourceId) {
    // 强制按资源归属/科室/临时授权判断，而不是只看 role
}
```

## 10. 审计 AOP（示意）

```java
@Target(ElementType.METHOD)
@Retention(RetentionPolicy.RUNTIME)
public @interface Auditable {
    String action();
    String resourceType();
    boolean recordParams() default false;
}
```

## 11. 审计脱敏与完整性（示意）

```java
public AuditLog mask(AuditLog log) {
    // 按 action 配置脱敏字段规则
    return log;
}

public void calculateIntegrity(AuditLog log, String prevHash) {
    // integrity_hash = sha256(content + secret)
    // previous_hash = prevHash
}
```

