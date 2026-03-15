# 配置管理总纲

> **设计立场**：本文档为 MediAsk 系统的目标配置管理方案，完全基于最佳实践从零规划。
>
> **架构决策记录**（ADR）贯穿全文，关键决策以 `[ADR-xxx]` 标注。

---

## 1. 配置管理原则

### 1.1 核心原则

| 原则 | 说明 | 落地方式 |
|------|------|----------|
| **环境一致性** | 同一份制品（JAR / Docker Image）运行在所有环境，行为差异仅由配置驱动 | 12-Factor App：配置通过环境变量注入，不烘焙进镜像 |
| **密钥零信任** | 敏感凭证不以明文形式出现在代码仓库、镜像层、日志输出中 | 分级密钥管理（见 §4） |
| **显式优于隐式** | 每个配置项必须有明确的 key 名、类型、默认值、生效范围 | 配置项注册表（见各子文档） |
| **最小权限** | 每个环境/服务只能访问自己需要的配置和密钥 | 环境变量隔离 + 密钥分组 |
| **可审计** | 配置变更可追溯 | Git 版本管理配置模板；生产密钥变更记录在审计日志 |
| **安全降级** | 非必要配置缺失时服务应安全降级而非崩溃 | 定义每个配置项的缺失行为（见 §5） |

### 1.2 配置分类

| 分类 | 定义 | 示例 | 存储方式 |
|------|------|------|---------|
| **静态配置** | 应用启动时加载，运行期不变 | 端口、连接池大小、日志格式 | `application.yml` / `.env` |
| **环境配置** | 不同部署环境取值不同 | DB 连接串、Redis 地址 | 环境变量（生产）/ profile 文件（开发） |
| **密钥配置** | 敏感凭证 | JWT Secret、DB 密码、API Key | 环境变量 + 密钥管理（见 §4） |
| **特性开关** | 运行时可切换的功能标志 | RAG 开关、护栏模式、调试模式 | 环境变量 / 配置文件 |
| **业务规则配置** | 可变的业务参数 | AI 护栏规则、限流阈值 | 数据库 / 配置文件 |

---

## 2. 环境矩阵

### 2.1 环境定义

| 环境 | 标识 | 用途 | 基础设施 |
|------|------|------|---------|
| **本地开发** | `dev` | 开发者本机调试 | Docker Compose 单机 |
| **测试** | `test` | 自动化测试、集成测试 | Docker Compose / CI Runner |
| **预发布** | `staging` | 上线前验证，尽可能模拟生产 | 独立服务器，生产级配置 |
| **生产** | `prod` | 真实业务流量 | 生产服务器集群 |

### 2.2 环境切换机制

| 服务 | 切换方式 | 配置加载顺序（优先级由高到低） |
|------|---------|-------------------------------|
| **Java 后端** | `spring.profiles.active` | 命令行参数 > 环境变量 > `application-{profile}.yml` > `application.yml` |
| **Python AI** | `APP_ENV` 环境变量 | `ENV_FILE`（显式指定） > `.env.{APP_ENV}` > `.env.dev` > `.env` |

```bash
# Java 启动
java -jar mediask-api.jar --spring.profiles.active=prod

# Python 启动
APP_ENV=prod uvicorn app.main:app --host 0.0.0.0 --port 8000
```

### 2.3 环境配置差异矩阵

| 配置维度 | dev | test | staging | prod |
|----------|-----|------|---------|------|
| **数据库** | 本地 PG / Docker | 测试专用 PG | 独立 PG 实例 | 生产 PG（备份+监控） |
| **Redis** | 本地 / Docker | 测试专用 | 独立 Redis | 生产 Redis（持久化+哨兵） |
| **JWT Secret** | 固定测试值 | 固定测试值 | 随机生成 | 高强度随机 + 定期轮换 |
| **LLM API** | DeepSeek 开发账户 | Mock / 低配额 | DeepSeek 测试账户 | DeepSeek 生产账户 |
| **Embedding** | `none`（可选跳过） | Mock | 百炼测试 | 百炼生产 |
| **日志级别** | DEBUG | INFO | INFO | INFO（SQL 日志关闭） |
| **日志格式** | 纯文本 Console | 纯文本 Console | JSON + Console | JSON（Loki 采集） |
| **Swagger UI** | 开启 | 开启 | 开启 | **关闭** |
| **Actuator 端点** | 全量暴露 | 全量暴露 | 限制暴露 | 仅 `health,prometheus` |
| **SQL 输出** | 开启 | 开启 | 关闭 | **关闭** |
| **SkyWalking Agent（P2）** | 可选 | 关闭 | 可选 | 可选 |
| **AI 护栏模式** | `normal` | `normal` | `strict` | **`strict`** |
| **Debug 模式** | `true` | `true` | `false` | **`false`** |

---

## 3. 配置文件体系

### 3.1 Java 后端配置文件结构

```
mediask-api/src/main/resources/
├── application.yml              # 公共配置（所有环境共享）
├── application-dev.yml          # 开发环境覆盖
├── application-test.yml         # 测试环境覆盖
├── application-staging.yml      # 预发布环境覆盖
├── application-prod.yml         # 生产环境覆盖（敏感值全部引用环境变量）
└── logback-spring.xml           # 日志配置（按 profile 条件化输出）
```

**详见** [03A-JAVA_CONFIG.md](./03A-JAVA_CONFIG.md)。

### 3.2 Python AI 服务配置文件结构

```
mediask-ai/
├── .env                         # 默认 fallback（不提交到 Git）
├── .env.dev                     # 开发环境
├── .env.test                    # 测试环境
├── .env.staging                 # 预发布环境
├── .env.prod                    # 生产环境（敏感值全部引用环境变量）
├── .env.example                 # 配置模板（提交到 Git，无真实密钥）
└── app/core/settings.py         # Pydantic Settings 定义
```

**详见** [03B-PYTHON_CONFIG.md](./03B-PYTHON_CONFIG.md)。

### 3.3 基础设施配置文件结构

```
deploy/
├── docker-compose.yml           # 基础服务编排
├── docker-compose.dev.yml       # 开发环境覆盖
├── docker-compose.prod.yml      # 生产环境覆盖
├── docker-compose.observability.yml  # 可观测性栈
├── nginx/
│   ├── nginx.conf               # Nginx 主配置
│   └── conf.d/
│       └── mediask.conf         # 反向代理规则
├── prometheus/
│   └── prometheus.yml           # Prometheus 抓取配置
├── loki/
│   └── loki-config.yml          # Loki 配置
├── promtail/
│   └── promtail-config.yml      # Promtail 采集配置
└── .env.example                 # Docker Compose 环境变量模板
```

**详见** [03C-INFRASTRUCTURE_CONFIG.md](./03C-INFRASTRUCTURE_CONFIG.md)。

---

## 4. 密钥管理 `[ADR-010]`

### [ADR-010] 分级密钥管理策略

**背景**：系统涉及多类敏感凭证（DB 密码、JWT 密钥、第三方 API Key、加密密钥），需要在安全性和运维复杂度之间取得平衡。

**决策**：采用三级密钥管理策略，随项目成熟度逐步升级。

### 4.1 密钥分级

| 级别 | 定义 | 示例 | 泄露影响 |
|------|------|------|---------|
| **L1 — 关键密钥** | 泄露可直接导致数据泄露或系统被接管 | JWT 签名密钥、AES-256 加密密钥、DB 超级用户密码 | 致命 — 全库数据可被解密/伪造令牌 |
| **L2 — 服务密钥** | 泄露可导致服务间越权或外部 API 滥用 | 服务间 API Key、LLM API Key、Embedding API Key | 严重 — 经济损失 + 服务被冒用 |
| **L3 — 运维密钥** | 泄露影响有限，可快速轮换 | Grafana 管理密码、Redis 密码（内网） | 中等 — 监控数据泄露 |

### 4.2 三阶段演进路径

| 阶段 | 适用时期 | L1 密钥 | L2 密钥 | L3 密钥 |
|------|---------|---------|---------|---------|
| **Phase 1 — 环境变量** | MVP / 初期上线 | 操作系统环境变量 + `.env` 文件（不入 Git） | 环境变量 + `.env` 文件 | 环境变量 + `.env` 文件 |
| **Phase 2 — Docker Secrets** | 容器化稳定后 | Docker Secrets / Docker Compose secrets | Docker Secrets | 环境变量 |
| **Phase 3 — Vault** | 规模化运维 | HashiCorp Vault + 自动轮换 | Vault | Docker Secrets / 环境变量 |

**当前目标**：Phase 1，但代码架构预留 Phase 2/3 的升级路径。

### 4.3 密钥清单

| 密钥 | 级别 | 使用方 | 环境变量名 | 轮换频率 |
|------|------|--------|-----------|---------|
| JWT 签名密钥 | L1 | Java 后端 | `MEDIASK_JWT_SECRET` | 90 天 |
| AES-256 加密密钥（EMR/审计） | L1 | Java 后端 | `MEDIASK_ENCRYPTION_KEY` | 年度 + 事件触发 |
| PostgreSQL 密码 | L1 | Java + Python | `PG_PASSWORD` | 90 天 |
| Redis 密码 | L3 | Java + Python | `REDIS_PASSWORD` | 180 天 |
| 服务间 API Key | L2 | Java → Python | `MEDIASK_AI_API_KEY` | 90 天 |
| DeepSeek API Key | L2 | Python AI | `LLM_API_KEY` | 按供应商策略 |
| 百炼 Embedding API Key | L2 | Python AI | `EMBEDDING_API_KEY` | 按供应商策略 |
| Grafana 管理密码 | L3 | 运维 | `GF_SECURITY_ADMIN_PASSWORD` | 180 天 |

### 4.4 密钥使用规则

| 规则 | 说明 |
|------|------|
| **禁止明文入库** | `.env`、`*-prod.yml` 等包含真实密钥的文件**必须**在 `.gitignore` 中 |
| **模板文件入库** | `.env.example`、`application-prod.yml`（引用环境变量占位符）入库 |
| **日志脱敏** | 密钥、密码、Token 禁止出现在任何日志输出中 |
| **镜像层安全** | Docker 构建时不通过 `COPY` 或 `ENV` 写入密钥，使用运行时挂载 |
| **最小暴露** | 每个服务只注入自己需要的密钥，不共享全量 `.env` |

---

## 5. 特性开关与降级策略

### 5.1 特性开关清单

| 开关 | 环境变量 / 配置项 | 默认值 | 影响范围 |
|------|------------------|--------|---------|
| **RAG 开关** | `EMBEDDING_PROVIDER` | `openai_compatible` | `none` 时禁用向量检索，退化为纯 LLM 对话 |
| **AI 护栏模式** | `GUARDRAIL_MODE` | `normal` | `strict` 时提高 PII 检测灵敏度，拒绝更多高风险输入 |
| **调试模式** | `DEBUG` | `false` | `true` 时开启详细日志、错误堆栈、Swagger UI |
| **Swagger UI** | `springdoc.swagger-ui.enabled` | `true` | 生产环境**必须**设为 `false` |
| **SQL 日志** | `logging.level.me.jianwen.mediask.infrastructure.persistence` | `INFO` | `DEBUG` 时输出完整 SQL（仅 dev/test） |
| **SkyWalking（P2）** | JVM Agent 挂载 | 无 Agent 时自动跳过 | 无 Agent 时 `tid` MDC 字段为空，不影响业务 |

### 5.2 降级行为定义

| 依赖项 | 不可用时的行为 | 标记 |
|--------|---------------|------|
| **Embedding API** | Python 返回无 RAG 的纯 LLM 响应 | `ai_model_run.is_degraded = true` |
| **Redis** | Java 后端启动失败（Redis 为必需依赖） | 启动检查失败，拒绝启动 |
| **PostgreSQL** | 所有服务启动失败 | 启动检查失败，拒绝启动 |
| **Python AI 服务** | Java 后端返回 AI 服务不可用错误（ErrorCode 6001） | 业务降级，非 AI 功能正常 |
| **SkyWalking OAP（P2）** | 追踪数据丢失，业务不受影响 | 日志中 `tid` 字段为空 |
| **Loki / Prometheus** | 日志/指标采集中断，业务不受影响 | 运维告警 |

---

## 6. 跨服务配置协调

### 6.1 Java ↔ Python 共享配置

以下配置项必须在 Java 和 Python 两侧保持一致：

| 配置项 | Java 侧 | Python 侧 | 一致性保障 |
|--------|---------|-----------|-----------|
| **服务间 API Key** | `mediask.ai.api-key` | `API_KEY` | 同一 `.env` 文件或同一密钥源 |
| **PostgreSQL 连接** | `spring.datasource.*` | `PG_HOST/PORT/DB/USER/PASSWORD` | 指向同一数据库实例 |
| **Redis 连接** | `spring.data.redis.*` | `REDIS_HOST/PORT/PASSWORD` | 指向同一 Redis 实例 |
| **Request ID Header** | `X-Request-Id`（硬编码） | `X-Request-Id`（硬编码） | 协议约定，不可配置化；`X-Trace-Id` 仅兼容旧口径 |
| **Java 对外响应** | `Result<T>` | 前端只依赖 Java 对外协议：`{code, msg, data, requestId, timestamp}` | 协议约定，详见 [19-ERROR_EXCEPTION_RESPONSE_DESIGN.md](./19-ERROR_EXCEPTION_RESPONSE_DESIGN.md) |
| **Python 失败响应** | Java 按统一错误结构解析 | Python 失败体固定为 `{code, msg, requestId, timestamp}`；成功体保持端点 DTO | 协议约定，详见 [19-ERROR_EXCEPTION_RESPONSE_DESIGN.md](./19-ERROR_EXCEPTION_RESPONSE_DESIGN.md) |

### 6.2 数据库写入边界

详见 [01-OVERVIEW.md §7.2](./01-OVERVIEW.md)。配置层面需确保：
- Java 侧 DB 用户拥有业务表的完整读写权限
- Python 侧 DB 用户**仅**拥有 `knowledge_chunk_index` 和 `ai_run_citation` 的写权限 + 所有表的读权限

---

## 7. 配置项命名规范

### 7.1 Java 侧（Spring Boot）

```yaml
# 自定义配置项统一使用 mediask 前缀
mediask:
  jwt:
    secret: ${MEDIASK_JWT_SECRET}
    issuer: mediask
    access-token-expire-seconds: 1800
    refresh-token-expire-days: 7
  ai:
    base-url: ${MEDIASK_AI_BASE_URL:http://localhost:8000}
    api-key: ${MEDIASK_AI_API_KEY}
    timeout-seconds: 30
  encryption:
    key: ${MEDIASK_ENCRYPTION_KEY}
    algorithm: AES/GCM/NoPadding
```

**命名规则**：
- 自定义配置使用 `mediask.*` 前缀，与 Spring 内置配置区分
- kebab-case（`access-token-expire-seconds`），Spring Boot 自动绑定 camelCase
- 敏感值使用 `${ENV_VAR}` 占位符，可选提供非敏感默认值 `${ENV_VAR:default}`

### 7.2 Python 侧（Pydantic Settings）

```python
# 环境变量统一使用 SCREAMING_SNAKE_CASE
# 应用前缀：无（直接使用语义化名称）
PG_HOST=localhost
PG_PORT=5432
LLM_API_KEY=sk-xxx
EMBEDDING_PROVIDER=openai_compatible
GUARDRAIL_MODE=normal
```

**命名规则**：
- `SCREAMING_SNAKE_CASE`
- 布尔值使用 `true` / `false`（小写）
- 枚举值使用小写 + 下划线（`openai_compatible`、`strict`）

### 7.3 Docker Compose 环境变量

```bash
# 所有 Docker Compose 环境变量统一使用以下前缀分组
# 数据库
PG_HOST=postgres
PG_PORT=5432
PG_DB=mediask
PG_USER=mediask
PG_PASSWORD=changeme

# Redis
REDIS_HOST=redis
REDIS_PORT=6379
REDIS_PASSWORD=changeme

# Java 应用
MEDIASK_JWT_SECRET=changeme
MEDIASK_ENCRYPTION_KEY=changeme
MEDIASK_AI_API_KEY=changeme
MEDIASK_AI_BASE_URL=http://mediask-ai:8000

# Python AI
LLM_API_KEY=sk-xxx
LLM_MODEL=deepseek-chat
EMBEDDING_API_KEY=sk-xxx
```

---

## 8. 配置变更流程

### 8.1 变更分类

| 类型 | 影响 | 流程 |
|------|------|------|
| **新增配置项** | 需同步模板文件和文档 | PR → Code Review → 更新 `.env.example` + 文档 → 合并 |
| **修改默认值** | 可能影响所有环境 | PR → Review → 验证影响范围 → 合并 |
| **密钥轮换** | 需要协调多服务 | 生成新密钥 → 更新所有引用方 → 验证 → 废弃旧密钥 |
| **特性开关切换** | 影响运行时行为 | 修改环境变量 → 重启服务 → 验证 |

### 8.2 配置验证

每次配置变更后，执行以下检查：

1. **启动检查**：服务能否正常启动（DB/Redis 连通性）
2. **健康检查**：`/actuator/health` 与 `/actuator/health/readiness`（Java）、`/health` 与 `/ready`（Python）返回 200
3. **功能验证**：核心业务流程可用
4. **跨服务验证**：Java ↔ Python 通信正常（`X-Request-Id` 透传、API Key 认证）

---

## 9. `.env.example` 模板规范

每个服务仓库**必须**提供 `.env.example` 文件，遵循以下规范：

```bash
# ============================================================
# MediAsk 配置模板
# 复制为 .env 后填入实际值
# ============================================================

# ---- 数据库 ----
PG_HOST=localhost
PG_PORT=5432
PG_DB=mediask
PG_USER=mediask
PG_PASSWORD=                    # [L1] 必填，不可使用默认值

# ---- Redis ----
REDIS_HOST=localhost
REDIS_PORT=6379
REDIS_PASSWORD=                 # [L3] 必填

# ---- 安全 ----
MEDIASK_JWT_SECRET=             # [L1] 必填，至少 64 字符随机字符串
MEDIASK_ENCRYPTION_KEY=         # [L1] 必填，AES-256 密钥（Base64 编码）
MEDIASK_AI_API_KEY=             # [L2] 必填，服务间认证

# ---- LLM ----
LLM_API_KEY=                    # [L2] 必填
LLM_MODEL=deepseek-chat
LLM_BASE_URL=https://api.deepseek.com/v1

# ---- Embedding ----
EMBEDDING_PROVIDER=openai_compatible   # 可选值: openai_compatible | none
EMBEDDING_API_KEY=              # [L2] EMBEDDING_PROVIDER=openai_compatible 时必填
EMBEDDING_MODEL=text-embedding-v4
EMBEDDING_DIM=1536
```

**标注说明**：
- `[L1]`、`[L2]`、`[L3]` 标注密钥级别
- 空值表示**必须**由开发者/运维人员填入
- 有默认值的项可以不修改

---

## 10. 相关文档

| 文档 | 说明 |
|------|------|
| [03A-JAVA_CONFIG.md](./03A-JAVA_CONFIG.md) | Java 后端配置详解（Spring Boot Profiles、数据源、缓存、安全、ORM） |
| [03B-PYTHON_CONFIG.md](./03B-PYTHON_CONFIG.md) | Python AI 服务配置详解（Pydantic Settings、LLM/Embedding、RAG、护栏） |
| [03C-INFRASTRUCTURE_CONFIG.md](./03C-INFRASTRUCTURE_CONFIG.md) | 基础设施配置（PostgreSQL、Redis、Nginx、Docker Compose、可观测性栈） |
| [01-OVERVIEW.md](./01-OVERVIEW.md) | 系统架构设计 |
| [04-DEVOPS.md](./04-DEVOPS.md) | 部署运维手册 |
| [17-OBSERVABILITY.md](./17-OBSERVABILITY.md) | 可观测性架构 |
| [19-ERROR_EXCEPTION_RESPONSE_DESIGN.md](./19-ERROR_EXCEPTION_RESPONSE_DESIGN.md) | 错误/异常/响应设计 |
