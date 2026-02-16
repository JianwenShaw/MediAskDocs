# 配置管理指南（按当前代码）

> 本文档基于 `mediask-api/src/main/resources/application*.yml` 的现状整理。

## 1. 配置文件位置

```text
mediask-api/src/main/resources/
├── application.yml
├── application-dev.yml
├── application-test.yml
└── application-prod.yml
```

## 2. 当前 profile 行为

- `application.yml` 中默认：`spring.profiles.active: dev`
- 未使用 Maven profile 占位符注入。
- 运行时可通过环境变量/启动参数覆盖。

示例：

```bash
java -jar app.jar --spring.profiles.active=prod
```

## 3. application.yml（公共配置）

当前重点配置：

- `server.port: 8989`
- `server.servlet.context-path: /`
- MyBatis-Plus：
  - `mapper-locations: classpath*:mapper/**/*.xml`
  - `type-aliases-package: me.jianwen.mediask.dal.entity`
  - `global-config.db-config.id-type: ASSIGN_ID`
  - 逻辑删除字段：`deletedAt`
- JWT：
  - `security.jwt.secret`
  - `security.jwt.issuer`
  - `security.jwt.expire-seconds`

## 4. application-dev.yml（开发环境）

当前包含：

- 数据源：Druid + MySQL
- Redis：主机、端口、密码、连接池
- 日志级别：`me.jianwen.mediask` 与 MyBatis 调试日志

注意：当前开发配置中包含示例/占位敏感信息，部署前需改为环境变量。

## 5. application-test.yml（测试环境）

当前提供最小化 MySQL/Redis 参数模板，尚未包含完整测试隔离配置。

## 6. application-prod.yml（生产环境）

当前通过环境变量读取 MySQL/Redis 连接参数，并关闭 SQL 输出日志实现类。

## 7. 与文档历史版本差异

以下内容在旧文档中出现，但当前 Java 代码未落地为通用配置：

- Jasypt 加密配置样例
- `file.storage.*`（本地/OSS 策略）
- DeepSeek/Milvus/RocketMQ 等外部配置项
- `logback-spring.xml` 的项目内实现

上述内容若后续落地，应以新增代码与配置为准再补文档。

## 8. 推荐实践（适用于当前项目）

- 敏感配置统一改为环境变量注入。
- `dev/test/prod` 数据源与 Redis 彻底隔离。
- 每次新增配置项时同步更新本文档与对应 `application-*.yml` 注释。

## 9. Redis Key 管理（当前实现）

### 9.1 统一入口

当前 Redis Key 由 `infra` 层统一管理：

- `mediask-infra/src/main/java/me/jianwen/mediask/infra/cache/CacheKeyManager.java`

该类负责定义：
- Key 分隔符（统一 `:`）
- 业务前缀（如 `auth:refresh`、`holiday`、`test:connection`）
- Key/Pattern 生成方法（避免业务代码自行拼接）

### 9.2 使用约束

- 业务代码禁止直接硬编码 Redis Key 前缀。
- 需要新 Key 时，先在 `CacheKeyManager` 增加方法，再由调用方接入。
- 删除或批量删除操作也必须通过统一入口生成 pattern，保证前缀一致。

### 9.3 已接入示例

- Refresh Token：`RefreshTokenStore` 使用 `refreshTokenKey(...)` 与 `refreshTokenPattern(...)`
- 节假日缓存：`HolidayService` 使用 `holidayKey(...)`
- 诊断缓存：`TestConnectionInfraService` 使用 `testConnectionKey(...)`
