# DevOps 实践 - 持续集成与部署

> 本文档描述项目的 Docker 容器化、CI/CD 流水线和监控告警方案

## 1. Docker 部署方案

### 1.1 Dockerfile（多阶段构建）

```dockerfile
# 构建阶段
FROM maven:3.9-eclipse-temurin-21 AS builder
WORKDIR /app
COPY pom.xml .
COPY mediask-*/pom.xml mediask-*/
RUN mvn dependency:go-offline

COPY . .
RUN mvn clean package -DskipTests -Pprod

# 运行阶段
FROM eclipse-temurin:21-jre-alpine
WORKDIR /app

# 创建非root用户
RUN addgroup -S spring && adduser -S spring -G spring
USER spring:spring

# 复制构建产物
COPY --from=builder /app/mediask-api/target/mediask-api.jar app.jar

# 健康检查
HEALTHCHECK --interval=30s --timeout=3s --retries=3 \
  CMD wget -q --spider http://localhost:8080/actuator/health || exit 1

EXPOSE 8080
ENTRYPOINT ["java", \
  "-Xms512m", "-Xmx1024m", \
  "-XX:+UseZGC", \
  "-Dspring.profiles.active=prod", \
  "-jar", "app.jar"]
```

### 1.2 .dockerignore

```
target/
.git/
.idea/
*.iml
node_modules/
.env
```

## 2. Docker Compose（本地开发）

> AI 服务本地开发可选用 Milvus Lite（`MILVUS_MODE=lite`），无需启动完整 Milvus/etcd/minio 容器；生产或演示环境再使用标准 Milvus 服务。

```yaml
version: '3.8'

services:
  mysql:
    image: mysql:8.0
    environment:
      MYSQL_ROOT_PASSWORD: root
      MYSQL_DATABASE: mediask
    ports:
      - "3306:3306"
    volumes:
      - mysql-data:/var/lib/mysql
      - ./init.sql:/docker-entrypoint-initdb.d/init.sql
    command: --default-authentication-plugin=mysql_native_password

  redis:
    image: redis:7-alpine
    ports:
      - "6379:6379"
    volumes:
      - redis-data:/data

  milvus:
    image: milvusdb/milvus:v2.3.3
    ports:
      - "19530:19530"
    environment:
      ETCD_ENDPOINTS: etcd:2379
      MINIO_ADDRESS: minio:9000
    depends_on:
      - etcd
      - minio

  etcd:
    image: quay.io/coreos/etcd:v3.5.5
    environment:
      - ETCD_AUTO_COMPACTION_MODE=revision
      - ETCD_AUTO_COMPACTION_RETENTION=1000

  minio:
    image: minio/minio:latest
    environment:
      MINIO_ACCESS_KEY: minioadmin
      MINIO_SECRET_KEY: minioadmin
    command: minio server /minio_data

  mediask-api:
    build: .
    ports:
      - "8080:8080"
    environment:
      SPRING_PROFILES_ACTIVE: dev
      DB_HOST: mysql
      REDIS_HOST: redis
    depends_on:
      - mysql
      - redis

volumes:
  mysql-data:
  redis-data:
```

```bash
# 启动所有服务
docker-compose up -d

# 查看日志
docker-compose logs -f mediask-api

# 停止服务
docker-compose down
```

## 3. CI/CD 流程（GitHub Actions）

### 3.1 .github/workflows/ci.yml

```yaml
name: CI Pipeline

on:
  pull_request:
    branches: [ main, develop ]
  push:
    branches: [ develop ]

jobs:
  test:
    runs-on: ubuntu-latest
    
    steps:
      - uses: actions/checkout@v3
      
      - name: Set up JDK 21
        uses: actions/setup-java@v3
        with:
          java-version: '21'
          distribution: 'temurin'
          cache: 'maven'
      
      - name: Run Unit Tests
        run: mvn test
      
      - name: Run Integration Tests
        run: mvn verify -P integration-test
      
      - name: Upload Coverage
        uses: codecov/codecov-action@v3
        with:
          files: ./target/site/jacoco/jacoco.xml
```

### 3.2 .github/workflows/deploy.yml

```yaml
name: Deploy to Production

on:
  push:
    branches: [ main ]

jobs:
  build-and-deploy:
    runs-on: ubuntu-latest
    
    steps:
      - uses: actions/checkout@v3
      
      - name: Set up JDK 21
        uses: actions/setup-java@v3
        with:
          java-version: '21'
          distribution: 'temurin'
          cache: 'maven'
      
      - name: Run Tests
        run: mvn test
      
      - name: Build with Maven
        run: mvn clean package -DskipTests -Pprod
      
      - name: Build Docker Image
        run: |
          docker build -t mediask-api:${{ github.sha }} .
          docker tag mediask-api:${{ github.sha }} mediask-api:latest
      
      - name: Push to Registry
        run: |
          echo ${{ secrets.DOCKER_PASSWORD }} | docker login -u ${{ secrets.DOCKER_USERNAME }} --password-stdin
          docker push mediask-api:latest
      
      - name: Deploy to Server
        uses: appleboy/ssh-action@master
        with:
          host: ${{ secrets.SERVER_HOST }}
          username: ${{ secrets.SERVER_USER }}
          key: ${{ secrets.SSH_PRIVATE_KEY }}
          script: |
            cd /app/mediask
            docker-compose pull
            docker-compose up -d --force-recreate
```

## 4. 监控与日志

### 4.1 Spring Boot Actuator 配置

```yaml
management:
  endpoints:
    web:
      exposure:
        include: health,info,metrics,prometheus
  endpoint:
    health:
      show-details: always
  metrics:
    tags:
      application: ${spring.application.name}
```

### 4.2 Prometheus 监控

```yaml
# docker-compose.yml 增加 Prometheus
prometheus:
  image: prom/prometheus
  ports:
    - "9090:9090"
  volumes:
    - ./prometheus.yml:/etc/prometheus/prometheus.yml

grafana:
  image: grafana/grafana
  ports:
    - "3000:3000"
  environment:
    - GF_SECURITY_ADMIN_PASSWORD=admin
```

```yaml
# prometheus.yml
scrape_configs:
  - job_name: 'mediask-api'
    metrics_path: '/actuator/prometheus'
    static_configs:
      - targets: ['mediask-api:8080']
```

### 4.3 关键指标

| 指标类型 | 指标名称 | 说明 |
|---------|---------|------|
| **系统指标** | `jvm_memory_used_bytes` | JVM 内存使用 |
| | `system_cpu_usage` | CPU 使用率 |
| **业务指标** | `appt_create_total` | 挂号创建总数 |
| | `appt_create_duration` | 挂号创建耗时 |
| **数据库指标** | `hikaricp_connections_active` | 活跃连接数 |
| | `hikaricp_connections_timeout_total` | 连接超时次数 |

### 4.4 自定义业务指标

```java
@Component
@RequiredArgsConstructor
public class AppointmentMetrics {
    
    private final MeterRegistry meterRegistry;
    
    public void recordApptCreated(String deptName) {
        Counter.builder("appt_create_total")
            .tag("dept", deptName)
            .register(meterRegistry)
            .increment();
    }
    
    public void recordApptDuration(long duration) {
        Timer.builder("appt_create_duration")
            .register(meterRegistry)
            .record(duration, TimeUnit.MILLISECONDS);
    }
}
```

## 5. 日志聚合（ELK）

```yaml
# docker-compose.yml
elasticsearch:
  image: elasticsearch:8.10.0
  environment:
    - discovery.type=single-node
  ports:
    - "9200:9200"

logstash:
  image: logstash:8.10.0
  volumes:
    - ./logstash.conf:/usr/share/logstash/pipeline/logstash.conf
  depends_on:
    - elasticsearch

kibana:
  image: kibana:8.10.0
  ports:
    - "5601:5601"
  depends_on:
    - elasticsearch
```

## 6. 生产环境部署清单

### 6.1 服务器配置
- CPU: 4 核
- 内存: 8GB
- 磁盘: 100GB SSD
- 操作系统: Ubuntu 22.04 LTS

### 6.2 环境变量设置

```bash
# 在服务器上设置环境变量
export DB_HOST=mysql-prod.example.com
export DB_USER=mediask_user
export DB_PASSWORD=xxxxx
export REDIS_HOST=redis-prod.example.com
export REDIS_PASSWORD=xxxxx
export JASYPT_PASSWORD=xxxxx
export DEEPSEEK_API_KEY=sk-xxxxx
```

### 6.3 部署命令

```bash
# 1. 拉取代码
git clone https://github.com/xxx/mediask.git
cd mediask

# 2. 构建镜像
docker build -t mediask-api:latest .

# 3. 启动服务
docker-compose -f docker-compose-prod.yml up -d

# 4. 查看日志
docker logs -f mediask-api

# 5. 健康检查
curl http://localhost:8080/actuator/health
```

## 7. 零停机部署（蓝绿部署）

```bash
# 1. 启动新版本（绿）
docker run -d --name mediask-api-green \
  -p 8081:8080 \
  -e SPRING_PROFILES_ACTIVE=prod \
  mediask-api:v2.0

# 2. 健康检查
curl http://localhost:8081/actuator/health

# 3. 切换 Nginx 流量
# 修改 nginx.conf
upstream mediask {
    server localhost:8081;  # 指向新版本
}

# 4. 重载 Nginx
nginx -s reload

# 5. 停止旧版本（蓝）
docker stop mediask-api-blue
docker rm mediask-api-blue
```

## 8. 备份与恢复

### 8.1 数据库备份

```bash
# 每日自动备份（crontab）
0 3 * * * /usr/bin/docker exec mysql mysqldump -uroot -proot mediask > /backup/mediask_$(date +\%Y\%m\%d).sql
```

### 8.2 Redis 备份

```bash
# RDB 持久化配置
redis-cli CONFIG SET save "900 1 300 10 60 10000"
```

### 8.3 日志归档

```bash
# 压缩 7 天前的日志
find /var/log/mediask -name "*.log" -mtime +7 -exec gzip {} \;
```

## 9. 故障排查

### 9.1 容器无法启动
```bash
# 查看容器日志
docker logs mediask-api

# 进入容器排查
docker exec -it mediask-api sh
```

### 9.2 内存溢出
```bash
# 查看 JVM 堆转储
docker exec mediask-api jmap -dump:format=b,file=/tmp/heap.bin 1
```

### 9.3 数据库连接池耗尽
```bash
# 检查 Actuator 指标
curl http://localhost:8080/actuator/metrics/hikaricp.connections.active
```

## 10. 安全加固

- [ ] 非 root 用户运行容器
- [ ] 镜像扫描（Trivy）
- [ ] 网络隔离（Docker Network）
- [ ] 限制容器资源（CPU/内存）
- [ ] 定期更新基础镜像
- [ ] 敏感配置外部化
