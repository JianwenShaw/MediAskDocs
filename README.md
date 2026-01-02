# 技术文档导航

> 智能医疗辅助问诊系统 - 完整技术文档索引

## 📚 文档结构

本项目技术文档已按模块化拆分，便于阅读和维护：

### 核心文档

1. **[系统架构概览](./docs/01-ARCHITECTURE_OVERVIEW.md)**
   - 架构设计理念（Modular Monolith）
   - 前后端技术选型
   - 数据存储方案
   - DDD 分层结构
   - 核心工程化能力

2. **[代码规范与最佳实践](./docs/02-CODE_STANDARDS.md)**
   - 包结构设计
   - 命名规范（强制执行）
   - 分层代码示例（Controller/Service/Mapper）
   - 统一响应体与异常处理
   - MapStruct 对象转换
   - 代码审查 Checklist

3. **[配置管理指南](./docs/03-CONFIGURATION.md)**
   - 多环境配置结构（dev/test/prod）
   - 敏感配置加密（Jasypt）
   - Maven Profile 管理
   - 文件存储策略模式
   - Logback 日志配置

4. **[部署运维手册](./docs/04-DEVOPS.md)**
   - Docker 多阶段构建
   - Docker Compose 本地开发
   - GitHub Actions CI/CD
   - Prometheus + Grafana 监控
   - 零停机蓝绿部署
   - 备份与故障排查

5. **[测试策略](./docs/05-TESTING.md)**
   - 单元测试（JUnit 5 + Mockito）
   - 集成测试（TestContainers）
   - Controller 层测试（MockMvc）
   - 性能测试（JMeter/Gatling）
   - 测试覆盖率要求

6. **[前端快速开始](./docs/07-FRONTEND_QUICKSTART.md)**
   - pnpm workspace + Vite + React 19
   - React Router v7（`react-router`）
   - Ant Design + Tailwind v4（Vite 插件）
   - 启动/构建/部署要点（静态 SPA）

7. **[前端搭建过程回顾（Web 已完成）](./docs/08-FRONTEND_SETUP_HISTORY.md)**
   - 你当前仓库已完成的操作清单（便于复现）
   - 为新增患者端（H5）提供一致的参考路径

### 补充文档

8. **[数据库设计](./DATABASE_DESIGN.md)**
   - ER 图（16 张核心表）
   - DDL 建表语句
   - 索引策略与优化
   - 分库分表方案
   - Redis 缓存设计

9. **[项目规划](./PROJECT_PLAN.md)**
   - 项目背景与意义
   - 功能模块设计
   - 需求分析与系统功能描述（用例/流程/边界/验收）
   - AI 智能核心模块（RAG）
   - 毕设加分项
   - 论文撰写思路

---

## 🚀 快速开始

### 本地开发环境搭建

1. **克隆仓库**
   ```bash
   git clone https://github.com/xxx/MediAsk.git
   cd MediAsk
   ```

2. **启动基础设施**（需先安装 Docker）
   ```bash
   cd mediask-be
   docker-compose up -d
   ```

3. **导入数据库**
   ```bash
   mysql -uroot -proot mediask < DATABASE_DESIGN.md  # 执行建表 SQL
   ```

4. **启动后端**
   ```bash
   mvn spring-boot:run -pl mediask-api
   ```

5. **访问接口文档**
   ```
   http://localhost:8080/swagger-ui.html
   ```

---

## 📖 阅读顺序建议

### 对于新成员
1. [系统架构概览](./docs/01-ARCHITECTURE_OVERVIEW.md) - 了解整体设计
2. [代码规范](./docs/02-CODE_STANDARDS.md) - 熟悉编码规范
3. [数据库设计](./DATABASE_DESIGN.md) - 理解数据模型
4. [配置管理](./docs/03-CONFIGURATION.md) - 配置开发环境

### 对于运维人员
1. [部署运维手册](./docs/04-DEVOPS.md) - 掌握部署流程
2. [配置管理](./docs/03-CONFIGURATION.md) - 了解环境配置
3. [系统架构概览](./docs/01-ARCHITECTURE_OVERVIEW.md) - 理解架构设计

### 对于测试人员
1. [测试策略](./docs/05-TESTING.md) - 了解测试规范
2. [代码规范](./docs/02-CODE_STANDARDS.md) - 理解代码结构
3. [系统架构概览](./docs/01-ARCHITECTURE_OVERVIEW.md) - 掌握业务流程

---

## 🛠️ 技术栈概览

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
| | Prometheus | 2.x |

---

## 📝 文档维护

- **更新频率**：每次重大架构调整后更新
- **维护责任人**：@jianwen
- **文档格式**：Markdown
- **图表工具**：Mermaid

---

## 🔗 相关链接

- [GitHub 仓库](https://github.com/xxx/MediAsk)
- [在线文档](https://mediask-docs.example.com)
- [API 文档](http://localhost:8080/swagger-ui.html)
- [Grafana 监控](http://localhost:3000)

---

## 📧 联系方式

如有问题，请联系：
- 邮箱：xxx@example.com
- 项目组：MediAsk 开发团队
