# DevOps 实践（当前仓库状态）

> 本文档描述仓库中已存在的容器化与 CI/CD 配置；与未来规划分开标注。

## 1. 容器化

仓库当前包含：

- `Dockerfile.api`
- `Dockerfile.worker`

`Dockerfile.api` 采用多阶段构建（Maven 构建 + JRE 运行）。

注意：Java 服务默认端口来自 `application.yml`，当前为 `8989`。若沿用现有 Dockerfile 的 `8080` 健康检查，需要在部署时显式覆盖端口或同步修正 Dockerfile。

## 2. CI 工作流（已落地）

当前 `.github/workflows/` 主要文件：

- `ci.yml`：JDK 21 + `mvn -B -U verify`
- `release.yml`：依赖 CI，通过后构建并推送镜像（默认 API 镜像）
- `notify.yml`：通知复用工作流（可由其他流程调用）
- `auto-tag-on-merge.yml`：合并后自动打标签

## 3. 质量门禁（当前）

- PR/Push 会执行 `verify`。
- 构建产物包含测试报告与 JaCoCo 报告上传。
- Release 依赖 CI 成功后才执行。

## 4. 本地运维建议

- 当前仓库未提供根目录 `docker-compose.yml`。
- 如需一套可直接落地的 P0/P1 基线文件，请参考 `docs/03D-BASELINE_DEPLOYMENT_FILES.md`。
- 该基线默认只包含 PostgreSQL、Redis、Prometheus、Grafana、Loki、Promtail、Nginx、API、AI，不引入 SkyWalking 或 Elasticsearch。
- 启动命令遵循 AGENTS 平台规则：

## 5. 规划项（未在 Java 后端完全落地）

以下内容可保留在专项文档继续推进，但不视为当前后端已实现：

- pgvector / RAG 在线链路
- Python AI 微服务全链路联调
