# 配置管理最佳实践

> 本文档描述项目配置文件结构、多环境隔离策略和敏感配置加密方案

## 1. 配置文件结构

```
src/main/resources/
├── application.yml                    # 公共配置
├── application-dev.yml                # 开发环境
├── application-test.yml               # 测试环境
├── application-prod.yml               # 生产环境
├── logback-spring.xml                 # 日志配置
└── mapper/                            # MyBatis XML
```

## 2. application.yml 公共配置

```yaml
spring:
  application:
    name: mediask-api
  
  profiles:
    active: @spring.profiles.active@  # Maven Profile 注入
  
  # 虚拟线程配置（JDK 21）
  threads:
    virtual:
      enabled: true
  
  # Jackson 配置
  jackson:
    time-zone: GMT+8
    date-format: yyyy-MM-dd HH:mm:ss
    default-property-inclusion: non_null
    serialization:
      write-dates-as-timestamps: false

# MyBatis-Plus 配置
mybatis-plus:
  configuration:
    log-impl: org.apache.ibatis.logging.slf4j.Slf4jImpl
    map-underscore-to-camel-case: true
  global-config:
    db-config:
      logic-delete-field: deletedAt
      logic-delete-value: NOW()
      logic-not-delete-value: 'NULL'

# 接口文档配置
springdoc:
  api-docs:
    enabled: true
    path: /v3/api-docs
  swagger-ui:
    enabled: ${springdoc.swagger-ui.enabled:true}
    path: /swagger-ui.html

# 日志配置
logging:
  level:
    root: INFO
    me.jianwen.mediask: DEBUG
  pattern:
    console: "%d{yyyy-MM-dd HH:mm:ss} [%thread] %-5level [%X{traceId}] %logger{36} - %msg%n"
```

## 3. application-dev.yml 开发环境

```yaml
spring:
  datasource:
    url: jdbc:mysql://localhost:3306/mediask?useUnicode=true&characterEncoding=utf8mb4&serverTimezone=Asia/Shanghai
    username: root
    password: root
    driver-class-name: com.mysql.cj.jdbc.Driver
    hikari:
      maximum-pool-size: 10
      minimum-idle: 5
      connection-timeout: 30000
  
  data:
    redis:
      host: localhost
      port: 6379
      database: 0
      timeout: 3000ms
      lettuce:
        pool:
          max-active: 8
          max-idle: 8
          min-idle: 2

# 文件存储（开发环境使用本地）
file:
  storage:
    type: local
    local-path: /tmp/mediask/upload

# 接口文档（开发环境开启）
springdoc:
  swagger-ui:
    enabled: true

# AI模型配置
ai:
  deepseek:
    api-key: ${DEEPSEEK_API_KEY:sk-xxx}
    base-url: https://api.deepseek.com
    model: deepseek-chat
    timeout: 30s
```

## 4. application-prod.yml 生产环境

```yaml
spring:
  datasource:
    url: jdbc:mysql://${DB_HOST:mysql}:3306/mediask?useSSL=true
    username: ${DB_USER}
    password: ${DB_PASSWORD}
    hikari:
      maximum-pool-size: 50
      minimum-idle: 10
  
  data:
    redis:
      host: ${REDIS_HOST:redis}
      port: 6379
      password: ${REDIS_PASSWORD}

# 文件存储（生产环境使用OSS）
file:
  storage:
    type: oss
    oss:
      endpoint: ${OSS_ENDPOINT}
      access-key-id: ${OSS_ACCESS_KEY}
      access-key-secret: ${OSS_SECRET_KEY}
      bucket-name: mediask-prod

# 接口文档（生产环境关闭）
springdoc:
  swagger-ui:
    enabled: false

# 日志级别调整
logging:
  level:
    me.jianwen.mediask: INFO
```

## 5. 敏感配置加密方案

### 5.1 使用 Jasypt 加密

```xml
<!-- pom.xml 添加依赖 -->
<dependency>
    <groupId>com.github.ulisesbocchio</groupId>
    <artifactId>jasypt-spring-boot-starter</artifactId>
    <version>3.0.5</version>
</dependency>
```

```yaml
# application.yml
jasypt:
  encryptor:
    password: ${JASYPT_PASSWORD}  # 环境变量传入密钥
    algorithm: PBEWithMD5AndDES

# 加密后的配置
spring:
  datasource:
    password: ENC(encryptedPassword)
```

### 5.2 加密命令

```bash
# 加密密码
java -cp jasypt-1.9.3.jar org.jasypt.intf.cli.JasyptPBEStringEncryptionCLI \
  input="mysecretpassword" \
  password="$JASYPT_PASSWORD" \
  algorithm=PBEWithMD5AndDES

# 输出: ENC(encryptedPassword)
```

## 6. Maven Profile 配置

```xml
<!-- pom.xml -->
<profiles>
    <profile>
        <id>dev</id>
        <activation>
            <activeByDefault>true</activeByDefault>
        </activation>
        <properties>
            <spring.profiles.active>dev</spring.profiles.active>
        </properties>
    </profile>
    
    <profile>
        <id>prod</id>
        <properties>
            <spring.profiles.active>prod</spring.profiles.active>
        </properties>
    </profile>
</profiles>
```

```bash
# 打包时指定环境
mvn clean package -Pprod
```

## 7. 配置类示例

### 7.1 文件存储策略模式

```java
public interface FileStorageService {
    String upload(MultipartFile file);
    String getUrl(String path);
}

@Service
@Profile("dev")
public class LocalFileStorageService implements FileStorageService {
    @Value("${file.storage.local-path}")
    private String localPath;
    
    @Override
    public String upload(MultipartFile file) {
        // 本地磁盘存储
    }
}

@Service
@Profile("prod")
public class OssFileStorageService implements FileStorageService {
    @Value("${file.storage.oss.endpoint}")
    private String endpoint;
    
    @Override
    public String upload(MultipartFile file) {
        // 阿里云 OSS 存储
    }
}
```

### 7.2 数据源配置

```java
@Configuration
public class DataSourceConfig {
    
    @Bean
    @ConfigurationProperties(prefix = "spring.datasource.hikari")
    public HikariConfig hikariConfig() {
        HikariConfig config = new HikariConfig();
        config.setPoolName("MediAskHikariPool");
        config.setConnectionTestQuery("SELECT 1");
        config.setLeakDetectionThreshold(60000);
        return config;
    }
}
```

## 8. Logback 配置

```xml
<!-- logback-spring.xml -->
<configuration>
    <springProperty scope="context" name="APP_NAME" source="spring.application.name"/>
    
    <!-- 开发环境：控制台彩色输出 -->
    <springProfile name="dev">
        <appender name="CONSOLE" class="ch.qos.logback.core.ConsoleAppender">
            <encoder>
                <pattern>%d{yyyy-MM-dd HH:mm:ss} [%thread] %highlight(%-5level) [%X{traceId}] %logger{36} - %msg%n</pattern>
            </encoder>
        </appender>
        <root level="DEBUG">
            <appender-ref ref="CONSOLE"/>
        </root>
    </springProfile>
    
    <!-- 生产环境：JSON格式日志 -->
    <springProfile name="prod">
        <appender name="FILE" class="ch.qos.logback.core.rolling.RollingFileAppender">
            <file>/var/log/${APP_NAME}/${APP_NAME}.log</file>
            <rollingPolicy class="ch.qos.logback.core.rolling.TimeBasedRollingPolicy">
                <fileNamePattern>/var/log/${APP_NAME}/${APP_NAME}.%d{yyyy-MM-dd}.log</fileNamePattern>
                <maxHistory>30</maxHistory>
            </rollingPolicy>
            <encoder class="net.logstash.logback.encoder.LogstashEncoder"/>
        </appender>
        <root level="INFO">
            <appender-ref ref="FILE"/>
        </root>
    </springProfile>
</configuration>
```

## 9. 配置优先级

从高到低：
1. 命令行参数：`java -jar app.jar --server.port=8081`
2. 环境变量：`export DB_HOST=mysql-prod`
3. `application-{profile}.yml`
4. `application.yml`
5. 代码中的 `@Value` 默认值

## 10. 最佳实践

### ✅ 推荐
- 敏感配置通过环境变量注入
- 使用 `@ConfigurationProperties` 批量绑定配置
- 开发/生产环境完全隔离
- 配置文件加密存储在 Git

### ❌ 禁止
- 硬编码数据库密码
- 生产环境开启 Swagger
- 将密钥提交到代码仓库
- 使用默认的加密密钥
