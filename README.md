# MediAsk 技术文档

> 智能医疗辅助问诊系统 - 完整技术文档索引

## 📚 文档结构

所有技术文档已按模块化拆分到 `docs/` 目录：

| 编号 | 文档 | 说明 |
|------|------|------|
| 00 | [文档索引](./docs/00-INDEX.md) | 完整文档导航与快速开始 |
| 01 | [系统架构概览](./docs/01-OVERVIEW.md) | 架构设计、技术选型、模块划分 |
| 02 | [代码规范与最佳实践](./docs/02-CODE_STANDARDS.md) | 命名规范、分层架构、代码示例 |
| 03 | [配置管理指南](./docs/03-CONFIGURATION.md) | 多环境配置、Jasypt 加密 |
| 04 | [部署运维手册](./docs/04-DEVOPS.md) | Docker、CI/CD、监控告警 |
| 05 | [测试策略](./docs/05-TESTING.md) | 单元测试、集成测试、性能测试 |
| 06 | [DDD 设计指南](./docs/06-DDD_DESIGN.md) | 领域驱动设计理念与实践 |
| 07 | [数据库设计](./docs/07-DATABASE.md) | ER 图、DDL、索引策略 |
| 08 | [前端开发指南](./docs/08-FRONTEND.md) | React 快速开始、工程搭建 |

## 📁 根目录文档

| 文档 | 说明 |
|------|------|
| [PROJECT_PLAN.md](./PROJECT_PLAN.md) | 项目规划与需求分析（功能模块、用例、流程） |
| [ResearchProposal.md](./ResearchProposal.md) | 开题报告（研究目的、意义、技术方案、进度安排） |

---

## 🚀 快速开始

### 本地开发环境搭建

```bash
# 1. 克隆仓库
git clone https://github.com/xxx/MediAsk.git
cd MediAsk

# 2. 启动基础设施
cd mediask-be
docker-compose up -d

# 3. 导入数据库
mysql -uroot -proot mediask < MediAskDocs/docs/07-DATABASE.md

# 4. 启动后端
mvn spring-boot:run -pl mediask-api

# 5. 访问接口文档
http://localhost:8080/swagger-ui.html
```

---

## 📖 阅读顺序建议

### 新成员
1. [系统架构概览](./docs/01-OVERVIEW.md) - 了解整体设计
2. [代码规范](./docs/02-CODE_STANDARDS.md) - 熟悉编码规范
3. [数据库设计](./docs/07-DATABASE.md) - 理解数据模型
4. [配置管理](./docs/03-CONFIGURATION.md) - 配置开发环境

### 运维人员
1. [部署运维手册](./docs/04-DEVOPS.md) - 掌握部署流程
2. [配置管理](./docs/03-CONFIGURATION.md) - 了解环境配置
3. [系统架构概览](./docs/01-OVERVIEW.md) - 理解架构设计

### 测试人员
1. [测试策略](./docs/05-TESTING.md) - 了解测试规范
2. [代码规范](./docs/02-CODE_STANDARDS.md) - 理解代码结构
3. [系统架构概览](./docs/01-OVERVIEW.md) - 掌握业务流程

---

## 📝 技术栈概览

| 分类 | 技术 | 版本 |
|------|------|------|
| **后端** | Java | 21 |
| | Spring Boot | 3.3.3 |
| | MyBatis-Plus | 3.5.5 |
| **数据库** | MySQL | 8.0.33+ |
| | Redis | 7.x |
| | Milvus | 2.3+ |
| **消息队列** | RocketMQ | 5.0+ |
| **前端** | React | 19 |
| | TypeScript | 5.x |
| | Ant Design | 6.0 |
| **DevOps** | Docker | 24.x |
| | GitHub Actions | - |

