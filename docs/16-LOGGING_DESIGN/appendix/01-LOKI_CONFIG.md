# Loki 日志采集配置

> 本文档收录 Loki + Promtail 的 Docker Compose 配置，主文档见 `../00-INDEX.md`

---

## 1. Docker Compose 配置

```yaml
# docker-compose.loki.yml
version: '3'

services:
  loki:
    image: grafana/loki:2.9.0
    container_name: loki
    ports:
      - "3100:3100"
    volumes:
      - ./loki/loki-config.yml:/etc/loki/loki-config.yml
      - loki-data:/loki
    command: -config.file=/etc/loki/loki-config.yml
    networks:
      - observability-network

  promtail:
    image: grafana/promtail:2.9.0
    container_name: promtail
    volumes:
      - ./promtail-local-config.yaml:/etc/promtail/promtail-config.yaml
      - ./logs:/var/log/mediask:ro
    command: -config.file=/etc/promtail/promtail-config.yaml
    depends_on:
      - loki
    networks:
      - observability-network

volumes:
  loki-data:

networks:
  observability-network:
    driver: bridge
```

---

## 2. Loki 配置

```yaml
# loki/loki-config.yml
auth_enabled: false

server:
  http_listen_port: 3100
  grpc_listen_port: 9096

ingester:
  lifecycler:
    address: 127.0.0.1
    ring:
      kv_store:
        store: inmemory
      replication_factor: 1
  chunk_idle_period: 15m
  chunk_retain_period: 30s
  max_transfer_retries: 0

schema_config:
  configs:
    - from: 2020-10-01
      store: boltdb
      object_store: filesystem
      schema: v11
      index:
        prefix: index_
        period: 24h

storage_config:
  boltdb:
    directory: /loki/index
  filesystem:
    directory: /loki/chunks

limits_config:
  enforce_metric_name: false
  reject_old_samples: true
  reject_old_samples_max_age: 168h

chunk_store_config:
  max_look_back_period: 0

table_manager:
  retention_deletes_enabled: false
  retention_period: 0
```

---

## 3. Promtail 配置

```yaml
# promtail-local-config.yaml
server:
  http_listen_port: 9080
  grpc_listen_port: 0

positions:
  filename: /tmp/promtail/positions.yaml

clients:
  - url: http://loki:3100/loki/api/v1/push

scrape_configs:
  - job_name: mediask-logs
    static_configs:
      - targets:
          - localhost
        labels:
          job: mediask
          service: mediask-api
          # 宿主机挂载：./logs -> 容器内 /var/log/mediask
          __path__: /var/log/mediask/*.log
    pipeline_stages:
      - json:
          expressions:
            ts: ts
            level: level
            msg: msg
            request_id: request_id
            trace_id: trace_id
            env: env
            service: service
            http_status: http.status
            http_latency_ms: http.latency_ms
      - labels:
          level:
          service:
          env:
          trace_id:
```

---

## 4. 启动命令

```bash
# 启动 Loki + Promtail
docker-compose -f docker-compose.loki.yml up -d
```

---

## 5. Grafana LogQL 查询示例

```logql
# 查询特定服务的所有日志
{job="mediask", service="mediask-api"}

# 查询某个 request_id 在各类日志中的串联（排障常用）
{job="mediask"} | json | request_id="r-123"

# 启用 P2 APM 后，可按 trace_id 过滤
{job="mediask"} | json | trace_id="t-abc123"

# 查询 ERROR 级别日志
{job="mediask", level="ERROR"}

# 查询最近 5 分钟的慢请求（耗时 > 100ms）
{job="mediask"} | json | unwrap http_latency_ms | http_latency_ms > 100

# 按错误统计 TOP 10
topk(10, sum(rate({job="mediask"} |= "ERROR"[5m])) by (service))
```
