# Logback 日志配置

> 本文档收录 Logback 配置片段，用于输出结构化日志并注入 traceId，主文档见 `../00-INDEX.md`

---

## 1. Logback 配置（mediask-api）

文件位置：`mediask-api/src/main/resources/logback-spring.xml`（需要自行创建该文件）

```xml
<?xml version="1.0" encoding="UTF-8"?>
<configuration>
    <!-- 导入 SkyWalking 变量提供者 -->
    <include resource="org/apache/skywalking/apm/toolkit/log/logback/ApplicationVariables.json"/>

    <!-- 控制台输出：包含 traceId -->
    <appender name="CONSOLE" class="ch.qos.logback.core.ConsoleAppender">
        <encoder>
            <pattern>%d{yyyy-MM-dd HH:mm:ss.SSS} [%X{tid:-N/A}] [%thread] %-5level %logger{50} - %msg%n</pattern>
        </encoder>
    </appender>

    <!-- 文件输出：普通文本（便于本地 tail 排障） -->
    <appender name="FILE" class="ch.qos.logback.core.rolling.RollingFileAppender">
        <file>logs/mediask.log</file>
        <rollingPolicy class="ch.qos.logback.core.rolling.SizeAndTimeBasedRollingPolicy">
            <fileNamePattern>logs/mediask.%d{yyyy-MM-dd}.%i.log.gz</fileNamePattern>
            <maxFileSize>100MB</maxFileSize>
            <maxHistory>30</maxHistory>
        </rollingPolicy>
        <encoder>
            <pattern>%d{yyyy-MM-dd HH:mm:ss.SSS} [%X{tid:-N/A}] [%thread] %-5level %logger{50} - %msg%n</pattern>
        </encoder>
    </appender>

    <!-- JSON 格式输出（推荐 Loki 场景） -->
    <appender name="JSON_FILE" class="ch.qos.logback.core.rolling.RollingFileAppender">
        <file>logs/mediask-json.log</file>
        <rollingPolicy class="ch.qos.logback.core.rolling.SizeAndTimeBasedRollingPolicy">
            <fileNamePattern>logs/mediask-json.%d{yyyy-MM-dd}.%i.log.gz</fileNamePattern>
            <maxFileSize>100MB</maxFileSize>
            <maxHistory>30</maxHistory>
        </rollingPolicy>
        <encoder class="net.logstash.logback.encoder.LoggingEventCompositeJsonEncoder">
            <providers>
                <timestamp>
                    <fieldName>ts</fieldName>
                    <timeZone>Asia/Shanghai</timeZone>
                </timestamp>
                <logLevel>
                    <fieldName>level</fieldName>
                </logLevel>
                <loggerName>
                    <fieldName>logger</fieldName>
                </loggerName>
                <threadName>
                    <fieldName>thread</fieldName>
                </threadName>
                <message>
                    <fieldName>msg</fieldName>
                </message>
                <pattern>
                    <pattern>
                        {
                            "service": "${spring.application.name:-mediask-api}",
                            "env": "${spring.profiles.active:-dev}"
                        }
                    </pattern>
                </pattern>
                <!-- 输出 SkyWalking 注入的 tid 到 trace_id（同时保留应用自建 traceId/requestId 便于双链路对齐） -->
                <mdc>
                    <includeMdcKeyName>tid</includeMdcKeyName>
                    <mdcKeyFieldName>tid=trace_id</mdcKeyFieldName>
                    <includeMdcKeyName>traceId</includeMdcKeyName>
                    <mdcKeyFieldName>traceId=request_trace_id</mdcKeyFieldName>
                    <includeMdcKeyName>requestId</includeMdcKeyName>
                    <mdcKeyFieldName>requestId=request_id</mdcKeyFieldName>
                </mdc>
            </providers>
        </encoder>
    </appender>

    <root level="INFO">
        <appender-ref ref="CONSOLE"/>
        <appender-ref ref="FILE"/>
    </root>

    <!-- 生产环境使用 JSON 格式 -->
    <springProfile name="prod">
        <root level="INFO">
            <appender-ref ref="JSON_FILE"/>
            <appender-ref ref="CONSOLE"/>
        </root>
    </springProfile>
</configuration>
```

---

## 2. 依赖配置（mediask-api/pom.xml）

```xml
<!-- SkyWalking Logback 工具包（用于日志注入 traceId） -->
<dependency>
    <groupId>org.apache.skywalking</groupId>
    <artifactId>apm-toolkit-logback-1.x</artifactId>
    <version>9.1.0</version>
</dependency>

<!-- JSON Encoder（用于输出 JSON Lines 结构化日志） -->
<dependency>
    <groupId>net.logstash.logback</groupId>
    <artifactId>logstash-logback-encoder</artifactId>
</dependency>
```

---

## 3. 启动命令（带 SkyWalking Agent）

```bash
# 开发环境
java -javaagent:/path/to/skywalking-agent/skywalking-agent.jar \
     -DSW_AGENT_NAME=mediask-api \
     -DSW_OAP_SERVER_ADDRESS=localhost:11800 \
     -jar mediask-api.jar --spring.profiles.active=dev

# 生产环境
java -javaagent:/path/to/skywalking-agent/skywalking-agent.jar \
     -DSW_AGENT_NAME=mediask-api \
     -DSW_OAP_SERVER_ADDRESS=${SW_OAP_SERVER_ADDRESS} \
     -jar mediask-api.jar --spring.profiles.active=prod
```

---

## 4. 日志输出效果

控制台/文件输出：
```
2026-02-14 10:30:45.123 [http-nio-8989-exec-1] INFO  c.m.m.a.controller.LoginController - 用户登录 TID:3f9a8b7c2d1e
                                                                ↑traceId，自动注入
```

JSON 格式输出：
```json
{"ts":"2026-02-14T10:30:45.123+0800","level":"INFO","service":"mediask-api","env":"prod","trace_id":"3f9a8b7c2d1e","request_trace_id":"t-abc123","request_id":"r-123","logger":"c.m.m.a.controller.LoginController","msg":"用户登录","thread":"http-nio-8989-exec-1"}
```
