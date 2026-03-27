# 基础设施与可观测性配置

> 本文档详述 MediAsk 系统所有基础设施组件和可观测性栈的配置。
>
> **总纲**请参阅 [03-CONFIGURATION.md](./03-CONFIGURATION.md)。

---

## 1. Docker Compose 编排

### 1.1 文件组织

```
deploy/
├── docker-compose.yml                # 核心服务（应用 + 数据层）
├── docker-compose.dev.yml            # 开发环境覆盖
├── docker-compose.prod.yml           # 生产环境覆盖
├── docker-compose.observability.yml  # 可观测性栈（独立启停）
└── .env.example                      # 环境变量模板
```

**启动命令**：

```bash
# 开发环境：核心服务
docker compose -f docker-compose.yml -f docker-compose.dev.yml up -d

# 开发环境：核心 + 可观测性
docker compose -f docker-compose.yml -f docker-compose.dev.yml \
               -f docker-compose.observability.yml up -d

# 生产环境
docker compose -f docker-compose.yml -f docker-compose.prod.yml \
               -f docker-compose.observability.yml up -d
```

### 1.2 docker-compose.yml（核心服务）

```yaml
version: "3.9"

services:
  # ---- 数据层 ----
  postgres:
    image: pgvector/pgvector:pg17
    container_name: mediask-postgres
    restart: unless-stopped
    ports:
      - "${PG_PORT:-5432}:5432"
    environment:
      POSTGRES_DB: ${PG_DB:-mediask}
      POSTGRES_USER: ${PG_USER:-mediask}
      POSTGRES_PASSWORD: ${PG_PASSWORD:?PG_PASSWORD is required}
      TZ: Asia/Shanghai
    volumes:
      - pg-data:/var/lib/postgresql/data
      - ./initdb:/docker-entrypoint-initdb.d    # 初始化 SQL
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${PG_USER:-mediask}"]
      interval: 10s
      timeout: 5s
      retries: 5
    deploy:
      resources:
        limits:
          memory: 2G

  redis:
    image: redis:7-alpine
    container_name: mediask-redis
    restart: unless-stopped
    ports:
      - "${REDIS_PORT:-6379}:6379"
    command: >
      redis-server
      --requirepass ${REDIS_PASSWORD:?REDIS_PASSWORD is required}
      --maxmemory 512mb
      --maxmemory-policy allkeys-lru
      --appendonly yes
      --appendfsync everysec
    volumes:
      - redis-data:/data
    healthcheck:
      test: ["CMD", "redis-cli", "-a", "${REDIS_PASSWORD}", "ping"]
      interval: 10s
      timeout: 5s
      retries: 5

  # ---- 应用层 ----
  mediask-api:
    build:
      context: ../mediask-be
      dockerfile: Dockerfile
    container_name: mediask-api
    restart: unless-stopped
    ports:
      - "8989:8989"
    environment:
      SPRING_PROFILES_ACTIVE: ${APP_ENV:-dev}
      PG_HOST: postgres
      PG_PORT: 5432
      PG_DB: ${PG_DB:-mediask}
      PG_USER: ${PG_USER:-mediask}
      PG_PASSWORD: ${PG_PASSWORD}
      REDIS_HOST: redis
      REDIS_PORT: 6379
      REDIS_PASSWORD: ${REDIS_PASSWORD}
      MEDIASK_JWT_SECRET: ${MEDIASK_JWT_SECRET:?JWT secret is required}
      MEDIASK_ENCRYPTION_KEY: ${MEDIASK_ENCRYPTION_KEY:?Encryption key is required}
      MEDIASK_AI_BASE_URL: http://mediask-ai:8000
      MEDIASK_AI_API_KEY: ${MEDIASK_AI_API_KEY:?AI API key is required}
      TZ: Asia/Shanghai
    depends_on:
      postgres:
        condition: service_healthy
      redis:
        condition: service_healthy
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8989/actuator/health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 60s

  mediask-worker:
    build:
      context: ../mediask-be
      dockerfile: Dockerfile.worker
    container_name: mediask-worker
    restart: unless-stopped
    environment:
      SPRING_PROFILES_ACTIVE: ${APP_ENV:-dev}
      PG_HOST: postgres
      PG_PORT: 5432
      PG_DB: ${PG_DB:-mediask}
      PG_USER: ${PG_USER:-mediask}
      PG_PASSWORD: ${PG_PASSWORD}
      REDIS_HOST: redis
      REDIS_PORT: 6379
      REDIS_PASSWORD: ${REDIS_PASSWORD}
      TZ: Asia/Shanghai
    depends_on:
      postgres:
        condition: service_healthy
      redis:
        condition: service_healthy

  mediask-ai:
    build:
      context: ../mediask-ai
      dockerfile: Dockerfile
    container_name: mediask-ai
    restart: unless-stopped
    ports:
      - "8000:8000"
    environment:
      APP_ENV: ${APP_ENV:-dev}
      API_KEY: ${MEDIASK_AI_API_KEY}
      PG_HOST: postgres
      PG_PORT: 5432
      PG_DB: ${PG_DB:-mediask}
      PG_USER: ${PG_AI_USER:-mediask_ai}
      PG_PASSWORD: ${PG_AI_PASSWORD:-${PG_PASSWORD}}
      REDIS_HOST: redis
      REDIS_PORT: 6379
      REDIS_PASSWORD: ${REDIS_PASSWORD}
      LLM_MODEL: ${LLM_MODEL:-deepseek-chat}
      LLM_BASE_URL: ${LLM_BASE_URL:-https://api.deepseek.com/v1}
      LLM_API_KEY: ${LLM_API_KEY:?LLM API key is required}
      EMBEDDING_PROVIDER: ${EMBEDDING_PROVIDER:-openai_compatible}
      EMBEDDING_MODEL: ${EMBEDDING_MODEL:-text-embedding-v4}
      EMBEDDING_BASE_URL: ${EMBEDDING_BASE_URL:-}
      EMBEDDING_API_KEY: ${EMBEDDING_API_KEY:-}
      EMBEDDING_DIM: ${EMBEDDING_DIM:-1536}
      GUARDRAIL_MODE: ${GUARDRAIL_MODE:-normal}
      TZ: Asia/Shanghai
    depends_on:
      postgres:
        condition: service_healthy
      redis:
        condition: service_healthy
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8000/health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 30s

  # ---- 接入层 ----
  nginx:
    image: nginx:alpine
    container_name: mediask-nginx
    restart: unless-stopped
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./nginx/nginx.conf:/etc/nginx/nginx.conf:ro
      - ./nginx/conf.d:/etc/nginx/conf.d:ro
      - ./nginx/certs:/etc/nginx/certs:ro          # TLS 证书
      - ./nginx/html:/usr/share/nginx/html:ro       # 前端静态资源
    depends_on:
      - mediask-api
      - mediask-ai

volumes:
  pg-data:
  redis-data:
```

### 1.3 docker-compose.prod.yml（生产覆盖）

```yaml
version: "3.9"

services:
  mediask-api:
    deploy:
      resources:
        limits:
          memory: 2G
          cpus: "2.0"
        reservations:
          memory: 1G
    logging:
      driver: "json-file"
      options:
        max-size: "100m"
        max-file: "5"
    # P0/P1 默认不启用 SkyWalking Agent
    environment:
      JAVA_OPTS: >-
        -XX:MaxRAMPercentage=75.0
    # 如启用 P2 APM，可追加：
    # environment:
    #   JAVA_OPTS: >-
    #     -XX:MaxRAMPercentage=75.0
    #     -javaagent:/opt/skywalking-agent/skywalking-agent.jar
    #     -DSW_AGENT_NAME=mediask-api
    #     -DSW_OAP_SERVER_ADDRESS=skywalking-oap:11800
    # volumes:
    #   - ./skywalking-agent:/opt/skywalking-agent:ro

  mediask-ai:
    deploy:
      resources:
        limits:
          memory: 2G
          cpus: "2.0"
        reservations:
          memory: 512M
    command: >
      uvicorn app.main:app
      --host 0.0.0.0 --port 8000
      --workers 4 --loop uvloop --http httptools

  postgres:
    deploy:
      resources:
        limits:
          memory: 4G
    command: >
      postgres
      -c shared_buffers=1GB
      -c effective_cache_size=3GB
      -c work_mem=16MB
      -c maintenance_work_mem=256MB
      -c max_connections=200
      -c wal_buffers=16MB
      -c checkpoint_completion_target=0.9
      -c random_page_cost=1.1
```

---

## 2. PostgreSQL 配置

### 2.1 参数调优

| 参数 | dev | prod | 说明 |
|------|-----|------|------|
| `shared_buffers` | 128MB | 1GB（内存的 25%） | 共享内存缓冲区 |
| `effective_cache_size` | 512MB | 3GB（内存的 75%） | 查询优化器的缓存估计 |
| `work_mem` | 4MB | 16MB | 排序/Hash 操作工作内存 |
| `maintenance_work_mem` | 64MB | 256MB | 维护操作内存（VACUUM、CREATE INDEX） |
| `max_connections` | 50 | 200 | 最大连接数 |
| `wal_buffers` | -1 (auto) | 16MB | WAL 缓冲区 |
| `checkpoint_completion_target` | 0.5 | 0.9 | Checkpoint 完成目标 |
| `random_page_cost` | 4.0 | 1.1 | SSD 随机读成本（SSD 调低） |

### 2.2 pgvector 扩展

```sql
-- 初始化脚本（initdb/00-extensions.sql）
CREATE EXTENSION IF NOT EXISTS vector;
CREATE EXTENSION IF NOT EXISTS pg_trgm;    -- 用于模糊搜索

-- HNSW 索引参数
-- m: 每层连接数（越大越精确，越慢）
-- ef_construction: 构建时搜索宽度
CREATE INDEX idx_chunk_embedding ON knowledge_chunk_index
    USING hnsw (embedding vector_cosine_ops)
    WITH (m = 16, ef_construction = 200);

-- 查询时的搜索宽度参数
SET ivfflat.probes = 10;              -- IVFFlat 索引
SET hnsw.ef_search = 100;             -- HNSW 索引
```

### 2.3 用户与权限

```sql
-- Java 应用用户（完整读写权限）
CREATE USER mediask WITH PASSWORD '${PG_PASSWORD}';
GRANT ALL PRIVILEGES ON DATABASE mediask TO mediask;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO mediask;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO mediask;

-- Python AI 用户（受限权限）
CREATE USER mediask_ai WITH PASSWORD '${PG_AI_PASSWORD}';
GRANT CONNECT ON DATABASE mediask TO mediask_ai;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO mediask_ai;
GRANT SELECT, INSERT, UPDATE, DELETE ON knowledge_chunk_index TO mediask_ai;
GRANT SELECT, INSERT, UPDATE, DELETE ON ai_run_citation TO mediask_ai;
GRANT USAGE ON ALL SEQUENCES IN SCHEMA public TO mediask_ai;

-- 未来新表自动授权
ALTER DEFAULT PRIVILEGES IN SCHEMA public
    GRANT SELECT ON TABLES TO mediask_ai;
```

### 2.4 备份策略

| 策略 | 频率 | 保留 | 实现 |
|------|------|------|------|
| **逻辑备份** | 每日 02:00 | 30 天 | `pg_dump --format=custom` |
| **WAL 归档** | 持续 | 7 天 | `archive_mode=on` + `archive_command` |
| **时间点恢复** | 按需 | 依赖 WAL | `pg_restore` + WAL replay |

```bash
# 逻辑备份脚本示例
pg_dump --host=localhost --port=5432 --username=mediask \
        --format=custom --compress=9 \
        --file=/backup/mediask_$(date +%Y%m%d_%H%M%S).dump \
        mediask
```

---

## 3. Redis 配置

### 3.1 Redis Server 参数

| 参数 | dev | prod | 说明 |
|------|-----|------|------|
| `maxmemory` | 128mb | 512mb–1gb | 最大内存 |
| `maxmemory-policy` | `allkeys-lru` | `allkeys-lru` | 内存淘汰策略 |
| `appendonly` | no | yes | AOF 持久化 |
| `appendfsync` | — | everysec | AOF 同步频率 |
| `save` | — | `900 1 300 10 60 10000` | RDB 快照策略 |
| `requirepass` | 可选 | **必须** | 认证密码 |

### 3.2 Key 命名规范

详见 [02-CODE_STANDARDS.md §7](./02-CODE_STANDARDS.md)。所有 Key 通过 `CacheKeyGenerator` 统一生成。

| Key 模式 | 用途 | TTL |
|----------|------|-----|
| `auth:jwt:blacklist:{jti}` | JWT 黑名单 | Access Token 剩余有效期 |
| `auth:refresh:{userId}:{tokenId}` | Refresh Token 存储 | 7 天 |
| `cache:slot:inventory:{sessionId}` | 号源库存热缓存 | 5 分钟 |
| `rate:limit:auth:login:{account}` | 登录限流计数 | 滑动窗口 |
| `rate:limit:registration:create:{userId}` | 挂号限流计数 | 滑动窗口 |
| `lock:registration:{sessionId}` | 挂号分布式锁 | 30 秒 |
| `cache:holiday:{year}` | 节假日缓存 | 24 小时 |

### 3.3 监控指标

通过 Redisson 的 Micrometer 集成暴露以下指标：

| 指标 | 说明 |
|------|------|
| `redis.commands.duration` | 命令执行耗时 |
| `redis.pool.active` | 活跃连接数 |
| `redis.pool.idle` | 空闲连接数 |
| `redis.pool.pending` | 等待连接数 |

### 3.4 MediAsk 缓存架构决策

当前阶段采用 **Redis 单层** 作为唯一业务缓存层，同时承担共享状态与分布式协调的基础设施职责；**暂不落地 `Caffeine + Redis` 二级缓存**。

#### 为什么当前不直接做二级缓存

- 当前项目仍处于 `P0` 主链路优先阶段，多实例刚需首先是共享状态一致性和分布式协调，而不是本地热点缓存极致性能。
- 二级缓存会额外引入本地陈旧读、双层失效、跨实例一致性、观测复杂度等问题，不适合作为当前默认方案。
- 现有 DDD 分层要求缓存能力收敛在 `mediask-infra`，当前先以 Redis 单层落地，更符合“先守住边界，再做优化”的原则。

#### Redis 职责拆分

Redis 在本项目中有且仅有以下三类职责：

| 类别 | 说明 | 当前策略 |
|------|------|----------|
| 共享状态存储 | JWT 黑名单、Refresh Token 等必须跨实例共享的状态 | `Redis-only` |
| 分布式协调 | 分布式锁、限流计数、未来幂等键等协调机制 | `Redis/Redisson-only` |
| 业务读缓存 | 节假日、科室、医生归属、只读查询投影等读多写少数据 | 当前 `Redis-only`，未来可演进为 `L1 + L2` |

明确规则：

- 共享状态存储和分布式协调 **不引入本地 L1**。
- 只有业务读缓存才允许未来升级为 `Caffeine + Redis`。
- `cache:slot:inventory:{sessionId}` 虽然使用 `cache` 前缀，但语义上按“共享热状态 + 并发控制”处理，不按普通二级读缓存设计。

#### 模块职责

缓存实现必须遵守以下边界：

- `mediask-domain` 不定义 `CachePort`、不暴露 Redis/Caffeine/TTL。
- `mediask-application` 不直接使用 `RedisTemplate`、`RedissonClient`，也不编排 L1/L2 读取顺序。
- `mediask-infra` 在 `RepositoryImpl`、`Query Adapter` 或专用适配器内部决定缓存命中、回源、失效。
- `mediask-api` 与 `mediask-worker` 只调用 Application，不直接接触缓存客户端。

#### 当前建议的实现形态

在 `mediask-infra` 内部划分三类适配能力，避免职责混淆：

- `infra.security`：认证状态相关 Redis 适配
- `infra.cache`：业务读缓存
- `infra.lock` 或对应业务上下文适配器：分布式锁与并发协调

对业务代码保持以下约束：

- Domain / Application 面向原有业务 `Repository`、`Port`、`Query` 编程
- 缓存键通过统一入口生成，不在业务类中手写
- 写库成功后由 Infra 执行缓存失效，不采用“只更新缓存不更新数据库”的写法
- 缓存异常应显式暴露，不吞异常、不静默降级

#### 未来平滑引入 Caffeine 的预留方式

当前阶段不建议为了“将来可能用 Caffeine”预先建立通用缓存框架。默认做法是：

- 只保留 `CacheKeyGenerator` 与按业务域分类的 TTL / key 常量
- 由具体 `RepositoryAdapter` / `QueryAdapter` 在内部实现 Redis 命中、回源、回填、失效
- 只有在多个适配器出现稳定、重复的 Redis 访问样板代码时，才向上提炼最小公共 helper

明确不建议当前就新增：

- 通用 `CachePort`
- 通用 `BusinessCache`
- `CacheSpec`
- `CacheValueCodec<T>`
- `TwoLevelBusinessCache`

未来如果人工引入 `Caffeine`，建议采用点状演进，而不是先搭全局框架：

- 先选择一个明确热点的具体读模型试点
- 只在该 `RepositoryAdapter` / `QueryAdapter` 内部把 Redis-only 升级为 `Caffeine + Redis`
- 验证收益和一致性复杂度后，再决定是否复制到其他适配器

该试点的预期行为仍然固定为：

- 读：先 L1，未命中再查 Redis
- 写：业务写库成功后主动失效本地与 Redis
- 不做自动刷新、后台重建、复杂补偿一致性

#### 当前推荐可缓存对象

优先考虑以下读多写少、允许短暂最终一致的对象：

- `cache:holiday:{year}`
- 科室列表 / 科室详情
- 医生与科室归属映射
- 只读查询投影

当前不建议进入本地二级缓存的对象：

- `auth:jwt:blacklist:{jti}`
- `auth:refresh:{userId}:{tokenId}`
- `cache:slot:inventory:{sessionId}`
- `lock:registration:{sessionId}`
- 各类限流计数
- 权限敏感正文、AI 原文及其访问控制相关状态

---

## 4. Nginx 配置

### 4.1 主配置（nginx.conf）

```nginx
user nginx;
worker_processes auto;
error_log /var/log/nginx/error.log warn;
pid /var/run/nginx.pid;

events {
    worker_connections 1024;
    multi_accept on;
    use epoll;
}

http {
    include /etc/nginx/mime.types;
    default_type application/octet-stream;

    # ---- 日志格式 ----
    log_format main_json escape=json
        '{'
        '"time":"$time_iso8601",'
        '"remote_addr":"$remote_addr",'
        '"request":"$request",'
        '"status":$status,'
        '"body_bytes_sent":$body_bytes_sent,'
        '"request_time":$request_time,'
        '"upstream_response_time":"$upstream_response_time",'
        '"http_x_request_id":"$http_x_request_id"'
        '}';

    access_log /var/log/nginx/access.log main_json;

    # ---- 性能 ----
    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 65;
    keepalive_requests 100;

    # ---- 安全 ----
    server_tokens off;
    client_max_body_size 50m;           # 文档上传大小限制

    # ---- 压缩 ----
    gzip on;
    gzip_vary on;
    gzip_min_length 1024;
    gzip_types text/plain text/css application/json application/javascript
               text/xml application/xml application/xml+rss text/javascript;

    include /etc/nginx/conf.d/*.conf;
}
```

### 4.2 反向代理规则（conf.d/mediask.conf）

```nginx
upstream java_backend {
    server mediask-api:8989;
    keepalive 32;
}

upstream python_ai {
    server mediask-ai:8000;
    keepalive 16;
}

server {
    listen 80;
    server_name mediask.example.com;

    # ---- 生产环境强制 HTTPS ----
    # return 301 https://$host$request_uri;

    # ---- Request ID 生成 ----
    # 先优先使用 X-Request-Id；若缺失则兼容旧口径 X-Trace-Id；再缺失则由 Nginx 生成
    map $http_x_request_id $request_id_from_header {
        default $http_x_request_id;
        ""      $http_x_trace_id;
    }

    map $request_id_from_header $mediask_request_id {
        default $request_id_from_header;
        ""      $request_id;
    }

    # ---- 静态资源（前端） ----
    location / {
        root /usr/share/nginx/html;
        try_files $uri $uri/ /index.html;

        # 缓存策略
        location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg|woff2?)$ {
            expires 30d;
            add_header Cache-Control "public, immutable";
        }
    }

    # ---- Java API ----
    location /api/ {
        proxy_pass http://java_backend;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header X-Request-Id $mediask_request_id;

        proxy_connect_timeout 10s;
        proxy_send_timeout 30s;
        proxy_read_timeout 30s;

        proxy_http_version 1.1;
        proxy_set_header Connection "";        # 启用 keepalive
    }

    # ---- Actuator（仅内网访问） ----
    location /actuator/ {
        # allow 10.0.0.0/8;
        # allow 172.16.0.0/12;
        # allow 192.168.0.0/16;
        # deny all;
        proxy_pass http://java_backend;
    }

    # ---- Swagger UI（非生产环境） ----
    location /swagger-ui/ {
        proxy_pass http://java_backend;
    }
    location /v3/api-docs {
        proxy_pass http://java_backend;
    }

    # ---- AI SSE 流式接口 ----
    location /api/v1/ai/chat/stream {
        proxy_pass http://java_backend;
        proxy_set_header X-Request-Id $mediask_request_id;

        # SSE 特殊配置
        proxy_buffering off;                   # 关闭缓冲，支持流式输出
        proxy_cache off;
        proxy_read_timeout 300s;               # SSE 长连接超时 5 分钟
        proxy_set_header Connection "";
        proxy_http_version 1.1;

        chunked_transfer_encoding on;
    }

    # ---- 健康检查 ----
    location /health {
        access_log off;
        return 200 '{"status":"ok"}';
        add_header Content-Type application/json;
    }
}

# ---- HTTPS Server（生产环境取消注释） ----
# server {
#     listen 443 ssl http2;
#     server_name mediask.example.com;
#
#     ssl_certificate /etc/nginx/certs/fullchain.pem;
#     ssl_certificate_key /etc/nginx/certs/privkey.pem;
#     ssl_protocols TLSv1.2 TLSv1.3;
#     ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256;
#     ssl_prefer_server_ciphers off;
#     ssl_session_cache shared:SSL:10m;
#     ssl_session_timeout 1d;
#
#     # HSTS
#     add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
#
#     # ... 与 HTTP server 相同的 location 块 ...
# }
```

---

## 5. 可观测性栈配置

### 5.1 docker-compose.observability.yml（P0/P1 基线）

> 如需一套按目录组织好的“基线部署文件清单”，直接参考 `docs/03D-BASELINE_DEPLOYMENT_FILES.md`。

```yaml
version: "3.9"

services:
  # ---- 指标 ----
  prometheus:
    image: prom/prometheus:v2.48.0
    container_name: mediask-prometheus
    restart: unless-stopped
    ports:
      - "9090:9090"
    volumes:
      - ./prometheus/prometheus.yml:/etc/prometheus/prometheus.yml:ro
      - prometheus-data:/prometheus
    command:
      - "--config.file=/etc/prometheus/prometheus.yml"
      - "--storage.tsdb.retention.time=30d"

  grafana:
    image: grafana/grafana:10.2.0
    container_name: mediask-grafana
    restart: unless-stopped
    ports:
      - "3000:3000"
    environment:
      GF_SECURITY_ADMIN_USER: ${GF_ADMIN_USER:-admin}
      GF_SECURITY_ADMIN_PASSWORD: ${GF_ADMIN_PASSWORD:?Grafana admin password is required}
      GF_INSTALL_PLUGINS: ""
    volumes:
      - grafana-data:/var/lib/grafana

  # ---- 日志 ----
  loki:
    image: grafana/loki:2.9.0
    container_name: mediask-loki
    restart: unless-stopped
    ports:
      - "3100:3100"
    volumes:
      - ./loki/loki-config.yml:/etc/loki/loki-config.yml:ro
      - loki-data:/loki
    command: -config.file=/etc/loki/loki-config.yml

  promtail:
    image: grafana/promtail:2.9.0
    container_name: mediask-promtail
    restart: unless-stopped
    volumes:
      - ./promtail/promtail-config.yml:/etc/promtail/promtail-config.yml:ro
      - /var/log:/var/log:ro                        # 宿主机日志
      - promtail-positions:/tmp/positions
    command: -config.file=/etc/promtail/promtail-config.yml
    depends_on:
      - loki

volumes:
  prometheus-data:
  grafana-data:
  loki-data:
  promtail-positions:
```

> 如需 `P2` 链路追踪能力，再额外追加 `skywalking-oap`、`skywalking-ui` 与 `elasticsearch` 服务，不纳入默认基线。

### 5.2 Prometheus 配置

```yaml
# prometheus/prometheus.yml
global:
  scrape_interval: 15s
  evaluation_interval: 15s

scrape_configs:
  # Prometheus 自身
  - job_name: "prometheus"
    static_configs:
      - targets: ["localhost:9090"]

  # Java 后端（Spring Boot Actuator）
  - job_name: "mediask-api"
    metrics_path: /actuator/prometheus
    scrape_interval: 10s
    static_configs:
      - targets: ["mediask-api:8989"]
        labels:
          application: mediask-api
          env: "${APP_ENV:-dev}"

  # Python AI 服务（如有 Prometheus 端点）
  - job_name: "mediask-ai"
    metrics_path: /metrics
    scrape_interval: 15s
    static_configs:
      - targets: ["mediask-ai:8000"]
        labels:
          application: mediask-ai
          env: "${APP_ENV:-dev}"
```

### 5.3 Loki 配置

```yaml
# loki/loki-config.yml
auth_enabled: false

server:
  http_listen_port: 3100
  grpc_listen_port: 9096

common:
  path_prefix: /loki
  storage:
    filesystem:
      chunks_directory: /loki/chunks
      rules_directory: /loki/rules
  replication_factor: 1
  ring:
    instance_addr: 127.0.0.1
    kvstore:
      store: inmemory

schema_config:
  configs:
    - from: 2024-01-01
      store: tsdb
      object_store: filesystem
      schema: v13
      index:
        prefix: index_
        period: 24h

limits_config:
  reject_old_samples: true
  reject_old_samples_max_age: 168h           # 7 天
  max_entries_limit_per_query: 5000
  ingestion_rate_mb: 10
  ingestion_burst_size_mb: 20

chunk_store_config:
  max_look_back_period: 0s

table_manager:
  retention_deletes_enabled: true
  retention_period: 720h                     # 30 天日志保留
```

### 5.4 Promtail 配置

```yaml
# promtail/promtail-config.yml
server:
  http_listen_port: 9080
  grpc_listen_port: 0

positions:
  filename: /tmp/positions/positions.yaml

clients:
  - url: http://loki:3100/loki/api/v1/push

scrape_configs:
  # Java 应用 JSON 日志
  - job_name: mediask-api
    static_configs:
      - targets:
          - localhost
        labels:
          job: mediask-api
          __path__: /var/log/mediask/*-json.log
    pipeline_stages:
      - json:
          expressions:
            timestamp: "@timestamp"
            level: level
            message: message
            request_id: requestId
            trace_id: traceId
            user_id: userId
            logger: logger_name
      - labels:
          level:
          request_id:
          trace_id:
      - timestamp:
          source: timestamp
          format: "2006-01-02T15:04:05.000Z07:00"

  # Python AI 服务 JSON 日志
  - job_name: mediask-ai
    static_configs:
      - targets:
          - localhost
        labels:
          job: mediask-ai
          __path__: /var/log/mediask-ai/*.log
    pipeline_stages:
      - json:
          expressions:
            timestamp: timestamp
            level: level
            message: event
            request_id: request_id
            trace_id: trace_id
      - labels:
          level:
          request_id:
          trace_id:
```

---

## 6. Elasticsearch 审计投影配置（P2 可选）

> 仅在 `audit` schema 的月分区、索引和汇总查询已不足以满足复杂聚合、长留存报表或高频跨维检索时启用。
>
> Elasticsearch 只接收来自 PostgreSQL 权威审计表的异步投影，不参与 P0/P1 审计写入主链路。

### 6.1 索引模板

```json
{
  "index_patterns": ["mediask-audit-*"],
  "template": {
    "settings": {
      "number_of_shards": 1,
      "number_of_replicas": 0,
      "index.lifecycle.name": "mediask-audit-ilm",
      "index.lifecycle.rollover_alias": "mediask-audit"
    },
    "mappings": {
      "properties": {
        "event_id": { "type": "keyword" },
        "event_type": { "type": "keyword" },
        "actor_id": { "type": "keyword" },
        "actor_type": { "type": "keyword" },
        "target_type": { "type": "keyword" },
        "target_id": { "type": "keyword" },
        "action": { "type": "keyword" },
        "occurred_at": { "type": "date" },
        "trace_id": { "type": "keyword" },
        "ip_address": { "type": "ip" },
        "summary": { "type": "text" }
      }
    }
  }
}
```

### 6.2 ILM 策略

```json
{
  "policy": {
    "phases": {
      "hot": {
        "min_age": "0ms",
        "actions": {
          "rollover": {
            "max_primary_shard_size": "5gb",
            "max_age": "30d"
          }
        }
      },
      "warm": {
        "min_age": "30d",
        "actions": {
          "shrink": { "number_of_shards": 1 },
          "forcemerge": { "max_num_segments": 1 }
        }
      },
      "cold": {
        "min_age": "90d",
        "actions": {
          "readonly": {}
        }
      },
      "delete": {
        "min_age": "365d",
        "actions": {
          "delete": {}
        }
      }
    }
  }
}
```

**审计投影保留策略**：

| 阶段 | 时间 | 存储 | 说明 |
|------|------|------|------|
| Hot | 0–30 天 | SSD | 活跃查询 |
| Warm | 30–90 天 | HDD | 压缩存储，偶尔查询 |
| Cold | 90–365 天 | HDD | 只读，合规保留 |
| Delete | >365 天 | — | 自动清理（或按合规延长） |

---

## 7. Dockerfile 规范

### 7.1 Java 后端（多阶段构建）

```dockerfile
# ---- Build Stage ----
FROM eclipse-temurin:21-jdk-alpine AS builder
WORKDIR /build
COPY pom.xml .
COPY mediask-*/pom.xml ./
# 利用 Docker 缓存层：先下载依赖
RUN mvn dependency:go-offline -B
COPY . .
RUN mvn package -DskipTests -B

# ---- Runtime Stage ----
FROM eclipse-temurin:21-jre-alpine
WORKDIR /app

# 安全：非 root 用户运行
RUN addgroup -S mediask && adduser -S mediask -G mediask
USER mediask

COPY --from=builder /build/mediask-api/target/mediask-api.jar app.jar

EXPOSE 8989

HEALTHCHECK --interval=30s --timeout=10s --retries=3 --start-period=60s \
    CMD curl -f http://localhost:8989/actuator/health || exit 1

ENTRYPOINT ["java", \
    "-XX:+UseZGC", \
    "-XX:MaxRAMPercentage=75.0", \
    "-Djava.security.egd=file:/dev/./urandom", \
    "-jar", "app.jar"]
```

### 7.2 Python AI 服务

```dockerfile
FROM python:3.11-slim

WORKDIR /app

# 安全：非 root 用户
RUN groupadd -r mediask && useradd -r -g mediask mediask

# 安装系统依赖
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    && rm -rf /var/lib/apt/lists/*

# 安装 uv
COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /bin/

# 先安装依赖（利用缓存层）
COPY pyproject.toml uv.lock ./
RUN uv sync --frozen --no-dev

COPY . .

USER mediask

EXPOSE 8000

HEALTHCHECK --interval=30s --timeout=10s --retries=3 --start-period=30s \
    CMD curl -f http://localhost:8000/health || exit 1

CMD ["uv", "run", "uvicorn", "app.main:app", \
     "--host", "0.0.0.0", "--port", "8000", \
     "--workers", "4", "--loop", "uvloop"]
```

### 7.3 Dockerfile 安全规则

| 规则 | 说明 |
|------|------|
| **非 root 运行** | 创建专用用户，`USER mediask` |
| **最小化基础镜像** | Alpine（Java）/ slim（Python） |
| **多阶段构建** | 构建工具不进入最终镜像 |
| **无密钥烘焙** | 不通过 `COPY` 或 `ENV` 写入密钥 |
| **固定镜像版本** | 使用具体版本号，不使用 `latest` |
| **.dockerignore** | 排除 `.env`、`.git`、`node_modules`、`__pycache__` |

---

## 8. 环境变量完整清单（Docker Compose）

### 8.1 .env.example（Docker Compose 根目录）

```bash
# ============================================================
# MediAsk Docker Compose 环境变量模板
# 复制为 .env 后填入实际值
# ============================================================

# ---- 环境标识 ----
APP_ENV=dev

# ---- PostgreSQL ----
PG_PORT=5432
PG_DB=mediask
PG_USER=mediask
PG_PASSWORD=                           # [L1] 必填
PG_AI_USER=mediask_ai                  # Python AI 服务专用 DB 用户
PG_AI_PASSWORD=                        # [L1] 必填

# ---- Redis ----
REDIS_PORT=6379
REDIS_PASSWORD=                        # [L3] 必填

# ---- Java 应用密钥 ----
MEDIASK_JWT_SECRET=                    # [L1] 必填，至少 64 字符
MEDIASK_ENCRYPTION_KEY=                # [L1] 必填，AES-256 密钥 Base64
MEDIASK_AI_API_KEY=                    # [L2] 必填，与 Python 侧 API_KEY 一致

# ---- Python AI 服务 ----
LLM_MODEL=deepseek-chat
LLM_BASE_URL=https://api.deepseek.com/v1
LLM_API_KEY=                           # [L2] 必填
EMBEDDING_PROVIDER=openai_compatible
EMBEDDING_MODEL=text-embedding-v4
EMBEDDING_BASE_URL=
EMBEDDING_API_KEY=                     # [L2] provider=openai_compatible 时必填
EMBEDDING_DIM=1536
GUARDRAIL_MODE=normal

# ---- 可观测性 ----
GF_ADMIN_USER=admin
GF_ADMIN_PASSWORD=                     # [L3] 必填
```

---

## 9. 相关文档

| 文档 | 说明 |
|------|------|
| [03-CONFIGURATION.md](./03-CONFIGURATION.md) | 配置管理总纲 |
| [03A-JAVA_CONFIG.md](./03A-JAVA_CONFIG.md) | Java 后端配置 |
| [03B-PYTHON_CONFIG.md](./03B-PYTHON_CONFIG.md) | Python AI 服务配置 |
| [01-OVERVIEW.md](./01-OVERVIEW.md) | 系统架构设计（部署拓扑 §11） |
| [04-DEVOPS.md](./04-DEVOPS.md) | 部署运维手册 |
| [07-DATABASE.md](./07-DATABASE.md) | 数据库设计 |
| [17-OBSERVABILITY.md](./17-OBSERVABILITY.md) | 可观测性架构 |
| [16-LOGGING_DESIGN/00-INDEX.md](./16-LOGGING_DESIGN/00-INDEX.md) | 日志架构设计 |
