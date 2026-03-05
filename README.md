# MediAsk 技术文档

> 基准说明（同步时间：2026-02-25）：Java 相关文档以 `mediask-be` 当前代码为准；AI（10-13）相关文档以 `mediask-ai` 当前代码与方案决策为准。

> 口径同步（2026-02-25）：Embedding 方案已定为阿里云百炼 `text-embedding-v4`（远程 API），不再考虑本地部署分支；详见 `docs/13-EMBEDDING_MODEL_SELECTION.md`。

## 文档结构

| 编号 | 文档 | 说明 |
|------|------|------|
| 00 | [文档索引](./docs/00-INDEX.md) | 文档导航与快速开始 |
| 01 | [系统架构概览](./docs/01-OVERVIEW.md) | 当前后端架构与模块划分 |
| 02 | [代码规范与最佳实践](./docs/02-CODE_STANDARDS.md) | 命名规范、分层规范 |
| 03 | [配置管理指南](./docs/03-CONFIGURATION.md) | `application*.yml` 现状与约定 |
| 04 | [部署运维手册](./docs/04-DEVOPS.md) | 容器化与 CI/CD 说明 |
| 05 | [测试策略](./docs/05-TESTING.md) | 测试目标与执行策略 |
| 06 | [DDD 设计指南](./docs/06-DDD_DESIGN.md) | 领域建模原则 |
| 07 | [数据库设计](./docs/07-DATABASE.md) | 以 `init-dev.sql` 为准的表结构说明 |
| 08 | [前端开发指南](./docs/08-FRONTEND.md) | 前端工程说明 |
| 10 | [Python AI 服务设计与落地清单](./docs/10-PYTHON_AI_SERVICE.md) | Python 侧规划文档（非 Java 已实现能力） |
| 11 | [AI 安全护栏方案](./docs/11-AI_GUARDRAILS_PLAN.md) | 规划文档 |
| 12 | [AI/RAG 实现计划](./docs/12-AI_RAG_IMPLEMENTATION_PLAN.md) | 规划文档 |
| 13 | [Embedding 模型选择](./docs/13-EMBEDDING_MODEL_SELECTION.md) | 规划文档 |
| 14 | [后端 Java 开发路线图](./ROADMAP.md) | 后端阶段目标、学习重点、交付清单 |

## 快速开始（后端）

```bash
# 1) 进入后端项目
cd mediask-be

# 2) 检测平台（按 AGENTS.md 规则选择命令）
python3 scripts/os_detect.py

# 3) 构建/测试
# macOS:
./scripts/m21.sh clean verify
# 非 macOS:
# mvn clean verify

# 4) 启动 API 模块
# macOS:
./scripts/m21.sh spring-boot:run -pl mediask-api
# 非 macOS:
# mvn spring-boot:run -pl mediask-api
```

## 当前技术栈（Java 后端）

| 分类 | 技术 | 版本 |
|------|------|------|
| 语言 | Java | 21 |
| 框架 | Spring Boot | 3.5.8 |
| ORM | MyBatis-Plus | 3.5.15 |
| 数据库驱动 | mysql-connector-j | 8.3.0 |
| 缓存/锁 | Redis + Redisson | 7.x / 3.40.2 |
| 安全 | Spring Security + JJWT | 6.x / 0.12.6 |
| 文档 | springdoc-openapi | 2.6.0 |

## 接口文档访问

- OpenAPI JSON: `http://localhost:8989/v3/api-docs`
- Swagger UI: `http://localhost:8989/swagger-ui/index.html`

> 说明：`MediAskDocs` 中涉及 Milvus/FastAPI/LangChain 的内容，当前主要是规划，不代表 Java 后端已全部落地。
