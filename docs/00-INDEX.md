# MediAsk 文档索引

> 文档定位（同步时间：2026-03-11）：本目录已收敛为 MediAsk 重写阶段的设计基线；当前代码不作为架构与数据设计依据。

> 口径同步（2026-02-25）：Embedding 方案已定为阿里云百炼 `text-embedding-v4`（远程 API），不再考虑本地部署分支；详见 `13-EMBEDDING_MODEL_SELECTION.md`。

## 文档分类

| 类型 | 文档 | 说明 |
|------|------|------|
| 索引 | [00-INDEX.md](./00-INDEX.md) | 文档导航与快速开始 |
| 索引 | [00A-P0-BASELINE.md](./00A-P0-BASELINE.md) | 毕设实现范围、P0/P1/P2 与冻结口径 |
| 执行 | [../playbooks/README.md](../playbooks/README.md) | 实施清单、任务拆分、页面流转与 AI 提示词索引 |
| 执行 | [../playbooks/00B-P0-DEVELOPMENT-CHECKLIST.md](../playbooks/00B-P0-DEVELOPMENT-CHECKLIST.md) | P0 开发清单、页面/API/表/用例映射 |
| 执行 | [../playbooks/00C-P0-BACKEND-TASKS.md](../playbooks/00C-P0-BACKEND-TASKS.md) | P0 后端任务拆分与联调顺序 |
| 执行 | [../playbooks/00D-P0-FRONTEND-TASKS.md](../playbooks/00D-P0-FRONTEND-TASKS.md) | P0 前端页面任务拆分与验收标准 |
| 执行 | [../playbooks/00E-P0-BACKEND-ORDER-AND-DTOS.md](../playbooks/00E-P0-BACKEND-ORDER-AND-DTOS.md) | P0 后端表迁移顺序、API 实现顺序与 DTO 清单 |
| 执行 | [../playbooks/00F-P0-FRONTEND-PROTOTYPES-AND-FLOWS.md](../playbooks/00F-P0-FRONTEND-PROTOTYPES-AND-FLOWS.md) | P0 页面原型块清单与状态流转图 |
| 架构 | [01-OVERVIEW.md](./01-OVERVIEW.md) | 重写基线架构、模块与依赖 |
| 规范 | [02-CODE_STANDARDS.md](./02-CODE_STANDARDS.md) | 分层依赖与编码约定 |
| 配置 | [03-CONFIGURATION.md](./03-CONFIGURATION.md) | 配置管理总纲（原则、环境矩阵、密钥管理） |
| 配置 | [03A-JAVA_CONFIG.md](./03A-JAVA_CONFIG.md) | Java 后端配置详解 |
| 配置 | [03B-PYTHON_CONFIG.md](./03B-PYTHON_CONFIG.md) | Python AI 服务配置详解 |
| 配置 | [03C-INFRASTRUCTURE_CONFIG.md](./03C-INFRASTRUCTURE_CONFIG.md) | 基础设施与可观测性配置 |
| 配置 | [03D-BASELINE_DEPLOYMENT_FILES.md](./03D-BASELINE_DEPLOYMENT_FILES.md) | 无 SkyWalking / 无 ES 的基线部署文件模板 |
| 运维 | [04-DEVOPS.md](./04-DEVOPS.md) | Docker 与 CI/CD |
| 测试 | [05-TESTING.md](./05-TESTING.md) | 测试策略与门禁 |
| 设计 | [06-DDD_DESIGN.md](./06-DDD_DESIGN.md) | DDD 方法与边界 |
| 数据库 | [07-DATABASE.md](./07-DATABASE.md) | V3 主数据库设计总览 |
| 设计 | [07A-SCHEDULING-V3.md](./07A-SCHEDULING-V3.md) | 排班规划、发布门诊与挂号边界说明 |
| 设计 | [07B-AI-AUDIT-V3.md](./07B-AI-AUDIT-V3.md) | AI、审计、访问监管与 Python 服务边界说明 |
| 设计 | [07C-AI-TABLES-V3.md](./07C-AI-TABLES-V3.md) | AI 相关表逐表设计说明 |
| 设计 | [07D-AUDIT-TABLES-V3.md](./07D-AUDIT-TABLES-V3.md) | 审计、访问日志、事件表逐表说明 |
| 前端 | [08-FRONTEND.md](./08-FRONTEND.md) | 前端开发指南 |
| AI 规划 | [10-13 系列文档](./10-PYTHON_AI_SERVICE.md) | Python/RAG 相关基线与实现计划 |
| AI 规划 | [10A-JAVA_AI_API_CONTRACT.md](./10A-JAVA_AI_API_CONTRACT.md) | 浏览器经 Java 访问的 AI 外部契约与业务承接 |
| 评审 | [14-ARCHITECTURE_REVIEW.md](./14-ARCHITECTURE_REVIEW.md) | 重写前架构评审与收敛结论 |
| 设计 | [15-PERMISSIONS/00-INDEX.md](./15-PERMISSIONS/00-INDEX.md) | 权限、审计与合规设计 |
| 设计 | [16-LOGGING_DESIGN](./16-LOGGING_DESIGN/00-INDEX.md) | 工业级日志设计规范 |
| 设计 | [17A-REQUEST_CONTEXT_IMPLEMENTATION.md](./17A-REQUEST_CONTEXT_IMPLEMENTATION.md) | 请求上下文、MDC 与 Java/Python 透传实现 |
| 设计 | [18-SCHEDULING_CORE_UPGRADE.md](./18-SCHEDULING_CORE_UPGRADE.md) | 排班核心升级（节假日、方案版本化） |
| 设计 | [19-ERROR_EXCEPTION_RESPONSE_DESIGN.md](./19-ERROR_EXCEPTION_RESPONSE_DESIGN.md) | 错误码、异常与统一响应设计说明 |
| 设计 | [20-RAG_DATABASE_PGVECTOR_DESIGN.md](./20-RAG_DATABASE_PGVECTOR_DESIGN.md) | PostgreSQL + pgvector 的 RAG 数据库设计（已定案，Milvus 不再作为 P0/P1 依赖） |
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

## 重写基线约定

- 当前实施边界、P0/P1/P2 范围以 [00A-P0-BASELINE.md](./00A-P0-BASELINE.md) 与 [07E-DATABASE-PRIORITY.md](./07E-DATABASE-PRIORITY.md) 为准。
- 架构与模块边界以 [01-OVERVIEW.md](./01-OVERVIEW.md) 与 [14-ARCHITECTURE_REVIEW.md](./14-ARCHITECTURE_REVIEW.md) 为准。
- 数据库与 RAG 三层模型以 [07-DATABASE.md](./07-DATABASE.md)、[07B-AI-AUDIT-V3.md](./07B-AI-AUDIT-V3.md)、[20-RAG_DATABASE_PGVECTOR_DESIGN.md](./20-RAG_DATABASE_PGVECTOR_DESIGN.md) 为准。
- AI 服务契约与落地顺序以 [10-PYTHON_AI_SERVICE.md](./10-PYTHON_AI_SERVICE.md) 与 [12-AI_RAG_IMPLEMENTATION_PLAN.md](./12-AI_RAG_IMPLEMENTATION_PLAN.md) 为准。
- 当前代码仅可用于查看历史实现思路，不作为本轮重写的规范来源。
