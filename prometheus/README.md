# Prometheus Monitoring Configuration

## Overview

Prometheus configuration for monitoring all 12 microservices, database, cache, and infrastructure components.

---

## 📊 Monitored Services

### Application Services (12)
| Service | Port | Metrics Path | Labels |
|---------|------|--------------|--------|
| API Gateway | 8080 | /actuator/prometheus | gateway |
| Auth Service | 8081 | /actuator/prometheus | core |
| Listing Service | 8082 | /actuator/prometheus | core |
| Claim Service | 8083 | /actuator/prometheus | core |
| Payment Service | 8084 | /actuator/prometheus | core |
| User Service | 8085 | /actuator/prometheus | core |
| Admin Service | 8086 | /actuator/prometheus | admin |
| Notification Service | 8087 | /actuator/prometheus | infrastructure |
| Support Service | 8088 | /actuator/prometheus | admin |
| Analytics Service | 8089 | /actuator/prometheus | infrastructure |
| Audit Service | 8090 | /actuator/prometheus | infrastructure |
| Orchestration Service | 8091 | /actuator/prometheus | gateway |

### Infrastructure Services (3)
| Service | Port | Type |
|---------|------|------|
| PostgreSQL | 5432 | Database |
| Redis | 6379 | Cache |
| Jaeger | 14269 | Tracing |

---

## 🎯 Configuration

### Scrape Interval
- **Global**: 15 seconds
- **All services** scraped every 15s
- **Evaluation interval**: 15s

### Labels
Each service is labeled with:
- `service`: Service name
- `tier`: Service tier (gateway, core, admin, infrastructure)
- `application`: "referral-marketplace"
- `cluster`: Cluster name
- `environment`: Environment (local, dev, staging, production)

---

## 📈 Metrics Collected

### Spring Boot Actuator Metrics

**JVM Metrics:**
- Memory usage (heap, non-heap)
- Garbage collection
- Thread count
- CPU usage

**HTTP Metrics:**
- Request count
- Request duration (percentiles)
- Error rate (4xx, 5xx)
- Active connections

**Database Metrics:**
- Connection pool stats
- Query performance
- Active connections

**Application Metrics:**
- Custom business metrics
- Trace IDs
- User actions
- Service health

### Custom Metrics (Examples)

```
# Claim creation rate
claims_created_total{service="claim-service"}

# Payment success rate
payments_successful_total{service="payment-service"}

# Admin actions
admin_actions_total{service="admin-service",action="approve_claim"}

# API Gateway throughput
http_server_requests_seconds{service="api-gateway",uri="/api/v1/listings"}
```

---

## 🚀 Accessing Prometheus

### Local Development
```bash
# Start with Docker Compose
docker-compose up -d prometheus

# Access UI
http://localhost:9090

# Query examples
http://localhost:9090/graph
```

### Common Queries

```promql
# CPU usage per service
rate(process_cpu_usage{application="referral-marketplace"}[5m])

# Memory usage per service
jvm_memory_used_bytes{application="referral-marketplace"}

# HTTP request rate
rate(http_server_requests_seconds_count{application="referral-marketplace"}[5m])

# HTTP error rate
rate(http_server_requests_seconds_count{status=~"5.."}[5m])

# Database connection pool
hikaricp_connections_active{application="referral-marketplace"}

# Service health status
up{application="referral-marketplace"}
```

---

## 🔍 Service Discovery

### Docker Compose (Local)
Uses `host.docker.internal` to access services from Prometheus container.

### Kubernetes
In Kubernetes, use ServiceMonitor CRDs:

```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: referral-marketplace
  namespace: production
spec:
  selector:
    matchLabels:
      app: referral-marketplace
  endpoints:
  - port: http
    path: /actuator/prometheus
    interval: 15s
```

This automatically discovers all services with the label `app: referral-marketplace`.

---

## 📊 Grafana Dashboards

### Pre-configured Dashboards (Can be imported)

**Spring Boot Dashboard:**
- JVM memory usage
- GC activity
- HTTP request rates
- Database connections
- Thread pools

**Business Metrics Dashboard:**
- Listings created per hour
- Claims submitted per hour
- Payment success rate
- User signups per hour
- Admin actions

**Infrastructure Dashboard:**
- Service health status
- CPU/Memory per service
- Request latency (p50, p95, p99)
- Error rates
- Database performance

**Access Grafana:**
```bash
http://localhost:3001
Username: admin
Password: admin
```

---

## 🚨 Alerting (Ready to Configure)

### Sample Alert Rules

Create `alerts/service-alerts.yml`:

```yaml
groups:
  - name: service_alerts
    interval: 30s
    rules:
      # Service Down
      - alert: ServiceDown
        expr: up{application="referral-marketplace"} == 0
        for: 2m
        labels:
          severity: critical
        annotations:
          summary: "Service {{ $labels.service }} is down"
          description: "{{ $labels.service }} has been down for 2 minutes"

      # High Error Rate
      - alert: HighErrorRate
        expr: rate(http_server_requests_seconds_count{status=~"5.."}[5m]) > 0.05
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High error rate on {{ $labels.service }}"
          description: "Error rate is {{ $value }} per second"

      # High Memory Usage
      - alert: HighMemoryUsage
        expr: jvm_memory_used_bytes / jvm_memory_max_bytes > 0.9
        for: 10m
        labels:
          severity: warning
        annotations:
          summary: "High memory usage on {{ $labels.service }}"
          description: "Memory usage is {{ $value | humanizePercentage }}"

      # Database Connection Pool Exhaustion
      - alert: DatabaseConnectionPoolExhausted
        expr: hikaricp_connections_active / hikaricp_connections_max > 0.9
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "Database connection pool nearly exhausted"
          description: "{{ $labels.service }} using {{ $value | humanizePercentage }} of connections"
```

---

## 🔧 Configuration Updates

### What Was Updated ✅

**Added:**
- ✅ All 12 microservices (8080-8091)
- ✅ Service-specific labels (gateway, core, admin, infrastructure)
- ✅ Jaeger monitoring
- ✅ Better organization with comments
- ✅ External labels (cluster, environment)
- ✅ Alerting configuration (ready)

**Labels Added:**
- `service` - Service name
- `tier` - Service tier
- `application` - "referral-marketplace"
- `cluster` - Cluster identifier
- `environment` - Environment name

---

## 📈 Monitoring Stack

### Components

**Prometheus** (Port 9090)
- Metrics collection
- Time-series database
- Query engine
- Alerting engine

**Grafana** (Port 3001)
- Metrics visualization
- Dashboards
- Alerting UI
- User management

**Jaeger** (Port 16686)
- Distributed tracing
- Request flow visualization
- Performance analysis
- Dependency mapping

---

## ✅ Prometheus Configuration Complete

```
╔════════════════════════════════════════════════════╗
║   PROMETHEUS MONITORING UPDATED ✅                 ║
╠════════════════════════════════════════════════════╣
║                                                    ║
║  ✅ All 12 Services Configured                     ║
║     - API Gateway (8080)                           ║
║     - Auth Service (8081)                          ║
║     - Listing Service (8082)                       ║
║     - Claim Service (8083)                         ║
║     - Payment Service (8084)                       ║
║     - User Service (8085)                          ║
║     - Admin Service (8086)                         ║
║     - Notification Service (8087)                  ║
║     - Support Service (8088)                       ║
║     - Analytics Service (8089)                     ║
║     - Audit Service (8090)                         ║
║     - Orchestration Service (8091)                 ║
║                                                    ║
║  ✅ Infrastructure Monitoring                      ║
║     - PostgreSQL                                   ║
║     - Redis                                        ║
║     - Jaeger                                       ║
║                                                    ║
║  ✅ Labels & Organization                          ║
║     - Service tiers                                ║
║     - Environment labels                           ║
║     - Custom labels                                ║
║                                                    ║
║  ✅ Alerting Ready                                 ║
║     - Alert rules template                         ║
║     - Notification channels ready                  ║
║                                                    ║
║  STATUS: COMPLETE MONITORING 🚀                    ║
║                                                    ║
╚════════════════════════════════════════════════════╝
```

---

## 🚀 Usage

### View Metrics
```bash
# Start monitoring stack
docker-compose up -d prometheus grafana

# Access Prometheus
http://localhost:9090

# Access Grafana
http://localhost:3001 (admin/admin)
```

### Query Service Metrics
```promql
# All services up status
up{application="referral-marketplace"}

# Request rate by service
rate(http_server_requests_seconds_count{application="referral-marketplace"}[5m])

# Error rate by service
rate(http_server_requests_seconds_count{status=~"5..",application="referral-marketplace"}[5m])

# CPU usage by tier
avg by (tier) (process_cpu_usage{application="referral-marketplace"})

# Memory usage by service
jvm_memory_used_bytes{application="referral-marketplace"}
```

---

**Prometheus now monitors all 12 services with proper labels and organization!** ✅

