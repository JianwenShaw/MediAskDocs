# 基线部署文件（无 SkyWalking / 无 ES）

> 状态：Authoritative Baseline
>
> 适用阶段：P0 / P1
>
> 目标：给出一套可以直接落地的基线部署文件组织方式，默认只依赖 PostgreSQL、Redis、Prometheus、Grafana、Loki、Promtail。

请求上下文 Header / MDC / 透传命名请同步遵循：`docs/17A-REQUEST_CONTEXT_IMPLEMENTATION.md`。

## 1. 目录建议

```text
deploy/
  compose/
    docker-compose.app.yml
    docker-compose.observability.yml
  nginx/
    mediask.conf
  scripts/
    dev-up.sh
    dev-down.sh
    dev-logs.sh
```

## 2. `docker-compose.app.yml`

```yaml
version: "3.9"

services:
  postgres:
    image: pgvector/pgvector:pg17
    container_name: mediask-postgres
    restart: unless-stopped
    ports:
      - "5432:5432"
    environment:
      POSTGRES_DB: mediask_dev
      POSTGRES_USER: mediask
      POSTGRES_PASSWORD: mediask_dev_password
    volumes:
      - postgres-data:/var/lib/postgresql/data

  redis:
    image: redis:7-alpine
    container_name: mediask-redis
    restart: unless-stopped
    ports:
      - "6379:6379"
    command: ["redis-server", "--appendonly", "yes"]
    volumes:
      - redis-data:/data

  mediask-api:
    image: mediask-api:latest
    container_name: mediask-api
    restart: unless-stopped
    ports:
      - "8989:8989"
    environment:
      SPRING_PROFILES_ACTIVE: dev
      SERVER_PORT: 8989
      PG_HOST: postgres
      PG_PORT: 5432
      PG_DB: mediask_dev
      PG_USER: mediask
      PG_PASSWORD: mediask_dev_password
      REDIS_HOST: redis
      REDIS_PORT: 6379
    volumes:
      - ../../logs/api:/app/logs
    depends_on:
      - postgres
      - redis

  mediask-ai:
    image: mediask-ai:latest
    container_name: mediask-ai
    restart: unless-stopped
    ports:
      - "8000:8000"
    environment:
      APP_ENV: dev
      PG_HOST: postgres
      PG_PORT: 5432
      PG_DB: mediask_dev
      PG_USER: mediask_ai
      PG_PASSWORD: mediask_ai_password
    volumes:
      - ../../logs/ai:/app/logs
    depends_on:
      - postgres

  nginx:
    image: nginx:alpine
    container_name: mediask-nginx
    restart: unless-stopped
    ports:
      - "80:80"
    volumes:
      - ../nginx/mediask.conf:/etc/nginx/conf.d/default.conf:ro
    depends_on:
      - mediask-api
      - mediask-ai

volumes:
  postgres-data:
  redis-data:
```

## 3. `docker-compose.observability.yml`

> `prometheus/prometheus.yml`、`loki/loki-config.yml`、`promtail/promtail-config.yml` 的内容可直接复用 `docs/03C-INFRASTRUCTURE_CONFIG.md` 中的基线配置片段。

```yaml
version: "3.9"

services:
  prometheus:
    image: prom/prometheus:v2.48.0
    container_name: mediask-prometheus
    restart: unless-stopped
    ports:
      - "9090:9090"
    volumes:
      - ./prometheus/prometheus.yml:/etc/prometheus/prometheus.yml:ro
      - prometheus-data:/prometheus

  grafana:
    image: grafana/grafana:10.2.0
    container_name: mediask-grafana
    restart: unless-stopped
    ports:
      - "3000:3000"
    environment:
      GF_SECURITY_ADMIN_USER: admin
      GF_SECURITY_ADMIN_PASSWORD: admin123
    volumes:
      - grafana-data:/var/lib/grafana

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
      - ../../logs:/var/log/mediask:ro
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

## 4. `nginx/mediask.conf`

```nginx
upstream java_backend {
    server mediask-api:8989;
    keepalive 32;
}

upstream python_ai {
    server mediask-ai:8000;
    keepalive 16;
}

map $http_x_request_id $mediask_request_id {
    default $http_x_request_id;
    ""      $request_id;
}

server {
    listen 80;
    server_name _;

    location /api/ {
        proxy_pass http://java_backend;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header X-Request-Id $mediask_request_id;
    }

    location /health {
        return 200 '{"status":"ok"}';
        add_header Content-Type application/json;
    }
}
```

## 5. 启停脚本示例

### 5.1 `scripts/dev-up.sh`

```bash
#!/usr/bin/env bash
set -euo pipefail

docker compose -f ../compose/docker-compose.observability.yml up -d
docker compose -f ../compose/docker-compose.app.yml up -d
```

### 5.2 `scripts/dev-down.sh`

```bash
#!/usr/bin/env bash
set -euo pipefail

docker compose -f ../compose/docker-compose.app.yml down
docker compose -f ../compose/docker-compose.observability.yml down
```

### 5.3 `scripts/dev-logs.sh`

```bash
#!/usr/bin/env bash
set -euo pipefail

docker compose -f ../compose/docker-compose.app.yml logs -f mediask-api mediask-ai nginx
```

## 6. 启动顺序

1. 启动 `docker-compose.observability.yml`
2. 启动 `docker-compose.app.yml`
3. 访问 `http://localhost:3000` 查看 Grafana
4. 访问 `http://localhost:9090` 查看 Prometheus
5. 访问 `http://localhost:3100` 查看 Loki
6. 访问 `http://localhost/health` 验证 Nginx 入口

## 7. P2 扩展位

如后续确实需要 APM，再额外追加：

- `skywalking-oap`
- `skywalking-ui`
- `elasticsearch`

但这些都不属于本轮默认部署文件集合。
