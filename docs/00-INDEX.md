# MediAsk 文档索引

> 代码为准：本文档用于导航，具体行为请以 `mediask-be` 当前源码为准。

## 文档分类

| 类型 | 文档 | 说明 |
|------|------|------|
| 索引 | [00-INDEX.md](./00-INDEX.md) | 文档导航与快速开始 |
| 架构 | [01-OVERVIEW.md](./01-OVERVIEW.md) | Java 后端当前架构、模块与依赖 |
| 规范 | [02-CODE_STANDARDS.md](./02-CODE_STANDARDS.md) | 分层依赖与编码约定 |
| 配置 | [03-CONFIGURATION.md](./03-CONFIGURATION.md) | 配置文件与环境说明 |
| 运维 | [04-DEVOPS.md](./04-DEVOPS.md) | Docker 与 CI/CD |
| 测试 | [05-TESTING.md](./05-TESTING.md) | 测试策略与门禁 |
| 设计 | [06-DDD_DESIGN.md](./06-DDD_DESIGN.md) | DDD 方法与边界 |
| 数据库 | [07-DATABASE.md](./07-DATABASE.md) | 以 SQL 初始化脚本为准的库表说明 |
| 前端 | [08-FRONTEND.md](./08-FRONTEND.md) | 前端开发指南 |
| AI 规划 | [10-13 系列文档](./10-PYTHON_AI_SERVICE.md) | Python/RAG 相关规划 |
| 评审 | [14-ARCHITECTURE_REVIEW.md](./14-ARCHITECTURE_REVIEW.md) | 架构评审与优化建议 |
| 设计 | [15-PERMISSIONS/00-INDEX.md](./15-PERMISSIONS/00-INDEX.md) | 权限、审计与合规设计 |
| 设计 | [16-LOGGING_DESIGN](./16-LOGGING_DESIGN/00-INDEX.md) | 工业级日志设计规范 |
| 设计 | [18-SCHEDULING_CORE_UPGRADE.md](./18-SCHEDULING_CORE_UPGRADE.md) | 排班核心升级（节假日、方案版本化） |
| 路线图 | [ROADMAP.md](../ROADMAP.md) | 后端 Java 分阶段目标与产出路径 |

## 快速开始

```bash
cd mediask-be
python3 scripts/os_detect.py

# macOS
./scripts/m21.sh clean verify
./scripts/m21.sh spring-boot:run -pl mediask-api

# 非 macOS
# mvn clean verify
# mvn spring-boot:run -pl mediask-api
```

## 本地访问

- 服务端口（默认）：`8989`
- OpenAPI：`http://localhost:8989/v3/api-docs`
- Swagger UI：`http://localhost:8989/swagger-ui/index.html`

## 与代码一致性约定

- 依赖版本以根 `pom.xml` 为准。
- 模块依赖关系以各模块 `pom.xml` 为准。
- 数据库结构以 `mediask-dal/src/main/resources/sql/init-dev.sql` 为准。
- API 以 `mediask-api` controller 与 `api-docs/openapi.json` 为准。
