# MediAsk 文档索引

> 智能医疗辅助问诊系统 - 完整技术文档索引
>
> **文档定位**：本文档是"地图"，代码仓库是"领土"。文档说明规范和模式，具体实现请参考代码仓库。

---

## 文档类型说明

| 类型 | 内容 | 定位 |
|------|------|------|
| **规范类** | 代码规范、DDD 模式、测试策略 | 约束与原则 |
| **架构类** | 系统架构、数据库设计 | 设计与决策 |
| **运维类** | 部署配置、监控告警 | 运行环境 |
| **根目录** | 项目规划、开题报告 | 项目管理 |

---

## 文档结构

| 编号 | 文档 | 类型 | 说明 |
|------|------|------|------|
| **必读（规范）** |
| 00 | 本索引 | 规范 | 文档导航与快速开始 |
| 02 | [代码规范与最佳实践](./02-CODE_STANDARDS.md) | 规范 | 命名规范、分层架构 |
| 06 | [DDD 设计指南](./06-DDD_DESIGN.md) | 规范 | 领域驱动设计模式 |
| **架构设计** |
| 01 | [系统架构概览](./01-OVERVIEW.md) | 架构 | 架构设计、技术选型 |
| 07 | [数据库设计](./07-DATABASE.md) | 架构 | ER 图、DDL、索引策略 |
| **运维与测试** |
| 03 | [配置管理指南](./03-CONFIGURATION.md) | 运维 | 多环境配置、加密 |
| 04 | [部署运维手册](./04-DEVOPS.md) | 运维 | Docker、CI/CD、监控 |
| 05 | [测试策略](./05-TESTING.md) | 规范 | 测试要求与质量标准 |
| **AI（Python 微服务）** |
| 10 | [Python AI 服务设计与落地清单](./10-PYTHON_AI_SERVICE.md) | 架构 | API、配置、目录结构、待办 |
| 11 | [AI 安全护栏方案](./11-AI_GUARDRAILS_PLAN.md) | 规范 | 风险分级、PII 脱敏、审计与降级 |
| 12 | [AI/RAG 核心模块实现计划](./12-AI_RAG_IMPLEMENTATION_PLAN.md) | 规划 | 从 MVP 到可用的分阶段实施路线 |
| **前端** |
| 08 | [前端开发指南](./08-FRONTEND.md) | 运维 | React 快速开始 |
| **根目录文档** |
| [PROJECT_PLAN.md](../PROJECT_PLAN.md) | 管理 | 项目规划与需求分析 |
| [ResearchProposal.md](../ResearchProposal.md) | 管理 | 开题报告 |

---

## 🚀 快速开始

### 本地开发环境搭建

```bash
# 1. 克隆仓库
git clone https://github.com/xxx/MediAsk.git
cd MediAsk/mediask-be

# 2. 启动基础设施
docker-compose up -d

# 3. 导入数据库
mysql -uroot -proot mediask < MediAskDocs/docs/07-DATABASE.md

# 4. 启动后端
mvn spring-boot:run -pl mediask-api

# 5. 访问接口文档
http://localhost:8989/doc.html
```

---

## 📖 阅读顺序

### 新成员

1. [系统架构概览](./01-OVERVIEW.md) - 了解整体设计
2. [代码规范与最佳实践](./02-CODE_STANDARDS.md) - 熟悉编码规范
3. [DDD 设计指南](./06-DDD_DESIGN.md) - 理解领域模型
4. [数据库设计](./07-DATABASE.md) - 理解数据模型
5. [配置管理指南](./03-CONFIGURATION.md) - 配置开发环境

### 运维人员

1. [部署运维手册](./04-DEVOPS.md) - 掌握部署流程
2. [配置管理指南](./03-CONFIGURATION.md) - 了解环境配置
3. [测试策略](./05-TESTING.md) - 了解质量要求

### 测试人员

1. [测试策略](./05-TESTING.md) - 了解测试规范
2. [代码规范与最佳实践](./02-CODE_STANDARDS.md) - 理解代码结构

---

## 🔗 相关链接

- [GitHub 仓库](https://github.com/xxx/MediAsk)
- [API 文档](http://localhost:8989/doc.html)
- [Grafana 监控](http://localhost:3000)
