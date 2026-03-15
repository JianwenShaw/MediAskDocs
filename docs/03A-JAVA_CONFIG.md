# Java 后端配置详解

> 本文档详述 MediAsk Java 后端（`mediask-api` / `mediask-worker`）的所有配置项。
>
> **总纲**请参阅 [03-CONFIGURATION.md](./03-CONFIGURATION.md)。
>
> **执行边界说明**：`P0` 阶段优先使用环境变量与 profile 配置启动开发；下文的“配置加密”属于可选增强能力，不应阻塞主链路开发。

---

## 1. 配置文件结构

```
mediask-api/src/main/resources/
├── application.yml              # 公共配置（所有环境共享的不变项）
├── application-dev.yml          # 开发环境覆盖
├── application-test.yml         # 测试环境覆盖
├── application-staging.yml      # 预发布环境覆盖
├── application-prod.yml         # 生产环境覆盖
└── logback-spring.xml           # 日志配置
```

**加载优先级**（由高到低）：
1. 命令行参数（`--server.port=8080`）
2. 操作系统环境变量
3. `application-{profile}.yml`
4. `application.yml`

---

## 2. 配置属性加密

> 当前建议：把本节视为 `P2` 运维增强设计。`P0/P1` 只要做到“敏感配置不提交到仓库、通过环境变量注入”即可满足当前阶段需要。

### 2.1 设计目标

数据库密码、Redis 密码、JWT Secret 等敏感配置**不得以明文形式**出现在 `application*.yml` 中。
采用自定义 `EnvironmentPostProcessor` 方案，在 Spring 容器启动最早期拦截配置加载，对**指定的敏感配置项**自动解密。

> **为什么不用 Jasypt？** Jasypt 功能完善但引入了额外依赖和复杂度。本项目敏感配置项数量有限，自研方案更轻量可控。

### 2.2 加密约定

| 项目 | 说明 |
|------|------|
| 加密算法 | AES-256-GCM（与业务数据加密保持一致） |
| 密文格式 | 纯 Base64 字符串，配置文件中无任何特殊标记 |
| 主密钥来源 | 环境变量 `MEDIASK_CONFIG_MASTER_KEY` 或 JVM 参数 `-Dmediask.config.master-key` |
| 主密钥长度 | 32 字节（Base64 编码后 44 字符） |

**需要解密的配置项**（硬编码在 PostProcessor 中）：

```java
private static final List<String> ENCRYPTED_KEYS = List.of(
    "spring.datasource.password",
    "spring.data.redis.password",
    "mediask.jwt.secret",
    "mediask.encryption.key",
    "mediask.ai.api-key",
    "mediask.redisson.password"
);
```

> 这些 key 就是项目里所有密码/密钥类配置的完整清单，新增敏感配置时同步维护此列表。

**配置文件中的写法**（看起来就是普通 Base64 值）：

```yaml
spring:
  datasource:
    password: U2FsdGVkX1+3bLz0YpKq8g7dR...==
  data:
    redis:
      password: U2FsdGVkX1+7qPmNxV2jf5kA...==

mediask:
  jwt:
    secret: U2FsdGVkX1+9xKfTmB3pW6nY...==
```

### 2.3 实现方案：EncryptedPropertyPostProcessor

```
启动流程：
  SpringApplication.run()
    → EnvironmentPostProcessor（SPI 加载）
      → EncryptedPropertyPostProcessor.postProcessEnvironment()
        → 读取主密钥（环境变量 / JVM 参数）
          → 遍历 ENCRYPTED_KEYS 列表
            → 从 Environment 取值 → AES-256-GCM 解密 → 写回覆盖
              → 后续 Bean 读到的已是明文，业务代码无感知
```

**核心类**：

| 类 | 包路径 | 职责 |
|----|--------|------|
| `EncryptedPropertyPostProcessor` | `me.jianwen.mediask.infrastructure.config` | `EnvironmentPostProcessor` 实现，按 key 列表解密配置 |
| `PropertyDecryptor` | `me.jianwen.mediask.infrastructure.config` | AES-256-GCM 解密工具，接受主密钥 + 密文，返回明文 |

**SPI 注册**（Spring Boot 3.x）：

```
# META-INF/spring/org.springframework.boot.env.EnvironmentPostProcessor.imports
me.jianwen.mediask.infrastructure.config.EncryptedPropertyPostProcessor
```

### 2.4 加密工具 CLI

提供命令行工具用于生成密文，供运维人员在配置文件中填写：

```bash
# 生成主密钥（首次）
java -cp mediask-api.jar \
  me.jianwen.mediask.infrastructure.config.PropertyEncryptorCli generate-key

# 加密一个配置值
java -cp mediask-api.jar \
  me.jianwen.mediask.infrastructure.config.PropertyEncryptorCli encrypt \
  --master-key=<Base64主密钥> \
  --plaintext="my-secret-password"

# 输出：U2FsdGVkX1+3bLz0Yp...==
```

### 2.5 主密钥管理

| 环境 | 主密钥管理方式 | 说明 |
|------|---------------|------|
| dev | 不启用加密 | 本地临时调试可在 `application-dev.yml` 使用明文；默认仍推荐优先走环境变量注入 |
| test | CI/CD 环境变量注入 | GitHub Actions / Jenkins Secret |
| staging | 环境变量 `MEDIASK_CONFIG_MASTER_KEY` | 由运维注入，不落盘 |
| prod | JVM 参数 `-Dmediask.config.master-key` 或 K8s Secret 挂载 | 主密钥与配置文件物理隔离 |

> **安全原则**：主密钥和密文必须分离存储。配置文件中只有密文，主密钥通过运行时注入，两者不在同一存储介质上。

### 2.6 降级策略

- 主密钥未设置 → PostProcessor 跳过解密，配置值原样使用（兼容 dev 环境明文）
- 主密钥已设置 → 对 `ENCRYPTED_KEYS` 中的每个 key 尝试解密；解密失败则启动失败，日志输出具体是哪个 key 解密异常

---

## 3. 公共配置（application.yml）

以下配置项在所有环境中保持一致，不随 profile 变化。

### 3.1 服务器

```yaml
server:
  port: 8989
  servlet:
    context-path: /
  shutdown: graceful                          # 优雅停机
  tomcat:
    threads:
      max: 200                                # Tomcat 最大工作线程
      min-spare: 10                           # Tomcat 最小空闲线程
    max-connections: 8192
    accept-count: 100
    connection-timeout: 20000                 # 连接超时 20s

spring:
  lifecycle:
    timeout-per-shutdown-phase: 30s           # 优雅停机等待时间
```

### 3.2 MyBatis-Plus

```yaml
mybatis-plus:
  mapper-locations: classpath*:mapper/**/*.xml
  type-aliases-package: me.jianwen.mediask.infrastructure.persistence.dataobject
  configuration:
    map-underscore-to-camel-case: true        # 下划线 → 驼峰自动映射
    cache-enabled: false                      # 禁用二级缓存
  global-config:
    db-config:
      id-type: INPUT                          # 雪花 ID 由应用层生成
      logic-delete-field: deletedAt           # 逻辑删除字段
      logic-not-delete-value: "null"          # 未删除：NULL
      logic-delete-value: "now()"             # 已删除：当前时间戳
```

### 3.3 自定义业务配置

```yaml
mediask:
  # ---- JWT / 认证 ----
  jwt:
    secret: ${MEDIASK_JWT_SECRET}                          # [L1] 必填
    issuer: mediask
    access-token-expire-seconds: 1800                      # Access Token 有效期 30 分钟
    refresh-token-expire-days: 7                           # Refresh Token 有效期 7 天

  # ---- AI 服务集成 ----
  ai:
    base-url: ${MEDIASK_AI_BASE_URL:http://localhost:8000} # Python AI 服务地址
    api-key: ${MEDIASK_AI_API_KEY}                         # [L2] 服务间认证
    timeout-seconds: 30                                     # HTTP 调用超时
    retry:
      max-attempts: 2                                       # 最大重试次数
      backoff-millis: 500                                   # 重试退避时间

  # ---- 数据加密 ----
  encryption:
    key: ${MEDIASK_ENCRYPTION_KEY}                         # [L1] AES-256 密钥（Base64）
    algorithm: AES/GCM/NoPadding                           # 加密算法
```

### 3.4 API 文档

```yaml
springdoc:
  api-docs:
    path: /v3/api-docs
    enabled: true                              # 生产环境覆盖为 false
  swagger-ui:
    path: /swagger-ui/index.html
    enabled: true                              # 生产环境覆盖为 false
  default-produces-media-type: application/json
```

### 3.5 Spring Actuator

```yaml
management:
  endpoints:
    web:
      exposure:
        include: health,info,prometheus,metrics  # 生产环境仅暴露必要端点
      base-path: /actuator
  endpoint:
    health:
      show-details: when-authorized              # 认证后才显示详情
      probes:
        enabled: true                            # 开启 readiness/liveness 端点
  metrics:
    export:
      prometheus:
        enabled: true
    tags:
      application: mediask-api                    # 指标全局标签
```

---

## 4. 数据源配置

### 4.1 PostgreSQL + HikariCP

重写基线统一使用 Spring Boot 默认的 `HikariCP`。

原因：

1. Spring Boot 原生支持最好，配置与运维复杂度最低
2. 与 Micrometer / Prometheus / Actuator 集成最直接
3. 连接池职责应保持单一，不把 SQL 防火墙、监控页面等能力耦合进 JDBC 连接池
4. 对本项目的 PostgreSQL 主库与 pgvector 场景，HikariCP 已足够稳定

```yaml
spring:
  datasource:
    driver-class-name: org.postgresql.Driver
    url: jdbc:postgresql://${PG_HOST:localhost}:${PG_PORT:5432}/${PG_DB:mediask}
    username: ${PG_USER:mediask}
    password: ${PG_PASSWORD}                          # 加密存储，由 PostProcessor 解密
    hikari:
      pool-name: MediAskHikariPool
      minimum-idle: 5
      maximum-pool-size: 20
      idle-timeout: 600000                            # 10 分钟
      max-lifetime: 1800000                           # 30 分钟
      connection-timeout: 30000                       # 30 秒
      validation-timeout: 5000
      keepalive-time: 300000                          # 5 分钟
      leak-detection-threshold: 60000                 # 60 秒，仅开发/联调环境建议开启
```

### 4.2 连接池调优建议

| 参数 | dev | staging/prod | 说明 |
|------|-----|-------------|------|
| `minimum-idle` | 2 | 5–10 | 开发环境减少资源占用 |
| `maximum-pool-size` | 5 | 20–50 | 结合 CPU、数据库连接上限和压测结果调优 |
| `connection-timeout` | 10000 | 30000 | 开发环境更快速失败 |
| `max-lifetime` | 900000 | 1800000 | 应小于数据库端连接生命周期 |
| `leak-detection-threshold` | 30000 | 0 或按需开启 | 生产环境默认关闭，定位问题时临时启用 |

### 4.3 为什么不选 Druid 作为重写基线

`Druid` 并非不能用，但不作为本项目重写基线，原因如下：

1. 连接池、SQL 防火墙、监控页面耦合度较高，不利于职责清晰
2. Spring Boot 3 + Micrometer + Prometheus 体系下，HikariCP 的指标链路更自然
3. 本项目已采用参数化 SQL、MyBatis-Plus、统一日志与可观测方案，没必要再把一套重型监控/防火墙能力塞进连接池
4. 毕设与重写阶段更看重稳定、简单、低维护成本，而不是功能堆叠

---

## 5. Redis 配置

### 5.1 Spring Data Redis

```yaml
spring:
  data:
    redis:
      host: ${REDIS_HOST:localhost}
      port: ${REDIS_PORT:6379}
      password: ${REDIS_PASSWORD}                 # [L3] 必填
      database: 0
      timeout: 3000                               # 命令超时 3 秒
      lettuce:
        pool:
          max-active: 16                          # 最大活跃连接
          max-idle: 8                             # 最大空闲连接
          min-idle: 2                             # 最小空闲连接
          max-wait: 3000                          # 获取连接最大等待 3 秒
```

### 5.2 Redisson（分布式锁）

```yaml
mediask:
  redisson:
    address: redis://${REDIS_HOST:localhost}:${REDIS_PORT:6379}
    password: ${REDIS_PASSWORD}
    database: 0
    connection-pool-size: 16
    connection-minimum-idle-size: 4
    timeout: 3000
    retry-attempts: 3
    retry-interval: 1500
```

### 5.3 Redis 用途分离

| 用途 | Database | 说明 |
|------|----------|------|
| 会话缓存 + JWT 黑名单 | `db 0` | 认证相关 |
| 业务缓存（号源库存等） | `db 1` | 业务热数据 |
| 限流计数器 | `db 2` | 滑动窗口限流 |
| 分布式锁 | `db 0` | Redisson 锁（与 Lettuce 共享 db） |

> **注意**：Redis Database 分离是逻辑隔离，非安全隔离。如需强隔离，使用独立 Redis 实例。

---

## 6. 安全配置

### 6.1 Spring Security

```yaml
# application.yml（公共）
spring:
  security:
    filter:
      order: -100                                 # Security 过滤器链优先级

# 自定义安全配置在 Java 代码中（SecurityConfig.java）
# - JWT 过滤器链
# - CORS 配置
# - 公开端点白名单
# - RBAC 权限检查
```

### 6.2 CORS 配置

```yaml
mediask:
  cors:
    allowed-origins:
      - http://localhost:3000                     # 前端开发服务器
      - http://localhost:5173                     # Vite 开发服务器
    allowed-methods: GET,POST,PUT,PATCH,DELETE,OPTIONS
    allowed-headers: "*"
    allow-credentials: true
    max-age: 3600
```

**生产环境**应将 `allowed-origins` 限制为实际部署域名。

### 6.3 安全端点白名单

以下端点不需要 JWT 认证：

```
POST   /api/v1/auth/login
POST   /api/v1/auth/register
POST   /api/v1/auth/refresh
GET    /actuator/health
GET    /actuator/health/readiness
GET    /v3/api-docs/**              # 仅 dev/test/staging
GET    /swagger-ui/**               # 仅 dev/test/staging
```

---

## 7. 日志配置

### 7.1 logback-spring.xml 概要

```xml
<configuration>
    <!-- ===== 属性定义 ===== -->
    <property name="LOG_PATH" value="logs" />
    <property name="APP_NAME" value="mediask" />

    <!-- ===== Console Appender（所有环境） ===== -->
    <appender name="CONSOLE" class="ch.qos.logback.core.ConsoleAppender">
        <encoder>
            <pattern>%d{yyyy-MM-dd HH:mm:ss.SSS} [%thread] %-5level %logger{36}
                     [requestId=%X{requestId},traceId=%X{traceId:-N/A}] - %msg%n</pattern>
        </encoder>
    </appender>

    <!-- ===== File Appender（纯文本，dev/test） ===== -->
    <springProfile name="dev,test">
        <appender name="FILE" class="ch.qos.logback.core.rolling.RollingFileAppender">
            <file>${LOG_PATH}/${APP_NAME}.log</file>
            <rollingPolicy class="ch.qos.logback.core.rolling.SizeAndTimeBasedRollingPolicy">
                <fileNamePattern>${LOG_PATH}/${APP_NAME}.%d{yyyy-MM-dd}.%i.log.gz</fileNamePattern>
                <maxFileSize>100MB</maxFileSize>
                <maxHistory>30</maxHistory>
                <totalSizeCap>1GB</totalSizeCap>
            </rollingPolicy>
        </appender>
    </springProfile>

    <!-- ===== JSON Appender（Loki 采集，staging/prod） ===== -->
    <springProfile name="staging,prod">
        <appender name="JSON_FILE" class="ch.qos.logback.core.rolling.RollingFileAppender">
            <file>${LOG_PATH}/${APP_NAME}-json.log</file>
            <encoder class="net.logstash.logback.encoder.LogstashEncoder">
                <includeMdcKeyName>requestId</includeMdcKeyName>
                <includeMdcKeyName>traceId</includeMdcKeyName>
                <includeMdcKeyName>userId</includeMdcKeyName>
                <includeMdcKeyName>requestUri</includeMdcKeyName>
            </encoder>
            <!-- 同样的 Rolling 策略 -->
        </appender>
    </springProfile>

    <!-- ===== Root Logger ===== -->
    <root level="INFO">
        <appender-ref ref="CONSOLE" />
    </root>

    <springProfile name="dev,test">
        <root level="INFO">
            <appender-ref ref="FILE" />
        </root>
    </springProfile>

    <springProfile name="staging,prod">
        <root level="INFO">
            <appender-ref ref="JSON_FILE" />
        </root>
    </springProfile>
</configuration>
```

### 7.2 日志级别配置

```yaml
# application.yml（公共）
logging:
  level:
    root: INFO
    me.jianwen.mediask: INFO

# application-dev.yml
logging:
  level:
    me.jianwen.mediask: DEBUG
    me.jianwen.mediask.infrastructure.persistence: DEBUG    # SQL 输出
    org.springframework.security: DEBUG

# application-prod.yml
logging:
  level:
    me.jianwen.mediask: INFO
    me.jianwen.mediask.infrastructure.persistence: WARN     # 关闭 SQL
    org.springframework.security: WARN
    org.apache.ibatis: WARN
```

### 7.3 MDC 上下文

| MDC Key | 来源 | 说明 |
|---------|------|------|
| `requestId` | `RequestContextFilter` 从 `X-Request-Id` 读取或生成，兼容旧头 `X-Trace-Id` | P0/P1 请求串联主键 |
| `traceId` | SkyWalking / OpenTelemetry 注入（P2 可选） | APM 追踪 ID |
| `userId` | `SecurityContext` 中提取 | 当前认证用户 ID |
| `requestUri` | `RequestContextFilter` 提取 | 请求路径 |
| `tid` | SkyWalking Agent 注入 | APM 原始上下文（仅 Agent 存在时自动注入） |

---

## 8. SkyWalking Agent 配置（P2 可选）

> P0/P1 默认不启用 SkyWalking。只有在需要 APM 拓扑、端到端 Span 分析或答辩展示增强时再启用。

```bash
# JVM 启动参数
java -javaagent:/opt/skywalking-agent/skywalking-agent.jar \
     -DSW_AGENT_NAME=mediask-api \
     -DSW_OAP_SERVER_ADDRESS=${SW_OAP_ADDRESS:localhost:11800} \
     -jar mediask-api.jar --spring.profiles.active=prod
```

| 参数 | 说明 | 默认值 |
|------|------|--------|
| `SW_AGENT_NAME` | 服务名（在 SkyWalking UI 中显示） | — |
| `SW_OAP_SERVER_ADDRESS` | OAP Server gRPC 地址 | `localhost:11800` |
| `SW_AGENT_SAMPLE_RATE` | 采样率（0–10000，10000 = 100%） | `10000` |

---

## 9. Profile 覆盖示例

### 9.1 application-dev.yml

```yaml
spring:
  datasource:
    url: jdbc:postgresql://localhost:5432/mediask_dev
    username: mediask
    password: dev_password
    hikari:
      minimum-idle: 2
      maximum-pool-size: 5
      leak-detection-threshold: 30000

  data:
    redis:
      host: localhost
      port: 6379
      password: ""

mediask:
  jwt:
    secret: dev-only-jwt-secret-do-not-use-in-production-at-least-64-characters-long
  encryption:
    key: dev-only-encryption-key-base64-encoded==
  ai:
    base-url: http://localhost:8000
    api-key: dev-api-key
  cors:
    allowed-origins:
      - http://localhost:3000
      - http://localhost:5173

logging:
  level:
    me.jianwen.mediask: DEBUG
    me.jianwen.mediask.infrastructure.persistence: DEBUG

springdoc:
  swagger-ui:
    enabled: true
```

### 9.2 application-prod.yml

```yaml
spring:
  datasource:
    url: jdbc:postgresql://${PG_HOST}:${PG_PORT:5432}/${PG_DB:mediask}
    username: ${PG_USER}
    password: ${PG_PASSWORD}
    hikari:
      minimum-idle: 10
      maximum-pool-size: 30

  data:
    redis:
      host: ${REDIS_HOST}
      port: ${REDIS_PORT:6379}
      password: ${REDIS_PASSWORD}

mediask:
  jwt:
    secret: ${MEDIASK_JWT_SECRET}
  encryption:
    key: ${MEDIASK_ENCRYPTION_KEY}
  ai:
    base-url: ${MEDIASK_AI_BASE_URL}
    api-key: ${MEDIASK_AI_API_KEY}
  cors:
    allowed-origins:
      - https://mediask.example.com               # 替换为实际域名

logging:
  level:
    me.jianwen.mediask: INFO
    me.jianwen.mediask.infrastructure.persistence: WARN

springdoc:
  api-docs:
    enabled: false
  swagger-ui:
    enabled: false

management:
  endpoints:
    web:
      exposure:
        include: health,prometheus                 # 生产仅暴露健康检查和指标
```

---

## 10. 配置项完整注册表

### 10.1 服务器与框架

| 配置项 | 类型 | 默认值 | 必填 | 说明 |
|--------|------|--------|------|------|
| `server.port` | int | `8989` | — | HTTP 端口 |
| `server.shutdown` | string | `graceful` | — | 停机模式 |
| `spring.lifecycle.timeout-per-shutdown-phase` | duration | `30s` | — | 优雅停机超时 |
| `spring.profiles.active` | string | `dev` | — | 激活的 Profile |

### 10.2 数据源

| 配置项 | 类型 | 默认值 | 必填 | 密钥级别 |
|--------|------|--------|------|---------|
| `PG_HOST` | string | `localhost` | prod 必填 | — |
| `PG_PORT` | int | `5432` | — | — |
| `PG_DB` | string | `mediask` | — | — |
| `PG_USER` | string | `mediask` | — | — |
| `PG_PASSWORD` | string | — | **是** | L1 |

### 10.3 Redis

| 配置项 | 类型 | 默认值 | 必填 | 密钥级别 |
|--------|------|--------|------|---------|
| `REDIS_HOST` | string | `localhost` | prod 必填 | — |
| `REDIS_PORT` | int | `6379` | — | — |
| `REDIS_PASSWORD` | string | — | **是** | L3 |

### 10.4 业务配置

| 配置项 | 类型 | 默认值 | 必填 | 密钥级别 |
|--------|------|--------|------|---------|
| `MEDIASK_JWT_SECRET` | string | — | **是** | L1 |
| `mediask.jwt.issuer` | string | `mediask` | — | — |
| `mediask.jwt.access-token-expire-seconds` | int | `1800` | — | — |
| `mediask.jwt.refresh-token-expire-days` | int | `7` | — | — |
| `MEDIASK_ENCRYPTION_KEY` | string | — | **是** | L1 |
| `mediask.encryption.algorithm` | string | `AES/GCM/NoPadding` | — | — |
| `MEDIASK_AI_BASE_URL` | string | `http://localhost:8000` | prod 必填 | — |
| `MEDIASK_AI_API_KEY` | string | — | **是** | L2 |
| `mediask.ai.timeout-seconds` | int | `30` | — | — |
| `mediask.ai.retry.max-attempts` | int | `2` | — | — |
| `mediask.ai.retry.backoff-millis` | int | `500` | — | — |

### 10.5 可观测性

| 配置项 | 类型 | 默认值 | 必填 | 说明 |
|--------|------|--------|------|------|
| `management.endpoints.web.exposure.include` | string | `health,info,prometheus,metrics` | — | Actuator 暴露端点 |
| `management.metrics.export.prometheus.enabled` | boolean | `true` | — | Prometheus 指标导出 |
| `management.metrics.tags.application` | string | `mediask-api` | — | 指标全局标签 |
| `SW_AGENT_NAME` | string | — | staging/prod | SkyWalking 服务名 |
| `SW_OAP_SERVER_ADDRESS` | string | `localhost:11800` | staging/prod | SkyWalking OAP 地址 |

---

## 11. 相关文档

| 文档 | 说明 |
|------|------|
| [03-CONFIGURATION.md](./03-CONFIGURATION.md) | 配置管理总纲 |
| [03B-PYTHON_CONFIG.md](./03B-PYTHON_CONFIG.md) | Python AI 服务配置 |
| [03C-INFRASTRUCTURE_CONFIG.md](./03C-INFRASTRUCTURE_CONFIG.md) | 基础设施配置 |
| [16-LOGGING_DESIGN/00-INDEX.md](./16-LOGGING_DESIGN/00-INDEX.md) | 日志架构设计 |
| [17-OBSERVABILITY.md](./17-OBSERVABILITY.md) | 可观测性架构 |
| [19-ERROR_EXCEPTION_RESPONSE_DESIGN.md](./19-ERROR_EXCEPTION_RESPONSE_DESIGN.md) | 错误/异常/响应设计 |
