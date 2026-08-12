---
okf_version: "0.1"
type: concept
id: service-audit
title: "Audit Service"
tags: [audit, compliance, postgresql, jpa, tracing, async, spring-boot]
port: 8090
updated: 2026-07-10
related:
  - ../index.md
  - ./data-model.md
  - ./service-admin.md
  - ./auth-security-architecture.md
---

# Audit Service

## Purpose

The Audit Service is the platform's append-only **compliance trail**. Other services
POST structured audit events (who did what to which resource, and whether it
succeeded) and the service persists them asynchronously to the shared `audit_logs`
table. Every event is keyed by a distributed-tracing `trace_id`, so an operator can
reconstruct a full cross-service request from a single correlation id. It also exposes
read/query endpoints (filtered and paginated) used by admin/support tooling to answer
"what happened, when, and by whom" questions.

## Runtime

- **Port**: 8090
- **Base package**: `com.referralmarketplace.audit`
- **Stack**: Spring Boot 3.2.0 / Java 17 (Gradle)
- **Dir**: `services/audit-service`
- `@EnableAsync` + `@EnableScheduling`; writes run on `@Async @Transactional` so callers are not blocked.

## API

All routes are under `/api/v1/audit` (reached through the gateway at `/api/v1/audit/**`).

| Method | Path | Purpose |
|--------|------|---------|
| POST | `/logs` | Ingest an audit event (`CreateAuditLogRequest`); returns `202 Accepted`, persisted asynchronously |
| GET | `/logs` | Query logs with optional filters: `actorId`, `targetId`, `eventType`, `action`, `startDate`, `endDate` + `page`/`size` (paginated, newest first) |
| GET | `/logs/actor/{actorId}` | All events performed by an actor (paginated) |
| GET | `/logs/target/{targetId}` | All events affecting a target (paginated) |

Results are sorted by `timestamp` descending. Required ingest fields: `traceId`,
`eventType`, `action`, `result`.

## Data

Single JPA entity `AuditLog` → `audit_logs` table (UUID PK). Columns include
`timestamp`, `trace_id`, `event_type`, `actor_id`/`actor_type`,
`target_id`/`target_type`, `action`, `resource`, `changes` (TEXT), `result`
(success / failure / error), `ip_address`, `user_agent`, and free-form `metadata` (TEXT).
This service **owns** `audit_logs` (admin also reads it). It does **not** run migrations
(`spring.flyway.enabled=false`) and uses `ddl-auto: validate` — the table comes from the
shared schema. See the [Shared Data Model](./data-model.md).

## Integrations

- **PostgreSQL** (`referral_marketplace`, HikariCP) — the only datastore; no Redis, no WebSocket, no Feign clients.
- **Micrometer tracing** (OTel bridge + OTLP exporter, W3C propagation, 100% sampling) — produces/propagates the `traceId` that indexes each log line and audit row.
- **Prometheus** metrics + Actuator (`health,info,metrics,prometheus`) and SpringDoc OpenAPI (`/swagger-ui.html`).
- No external SaaS integrations — nothing to gate behind `*_ENABLED` flags here.

## Inter-service

- **Inbound**: reached only through the **api-gateway** (route `audit-service` → `${AUDIT_SERVICE_URL:http://localhost:8090}`). Producers such as **orchestration-service** and **admin-service** are wired with `AUDIT_SERVICE_URL` to record events.
- **Outbound**: none beyond its own PostgreSQL — it is a leaf/sink service.

## Security

The gateway validates the JWT and injects the trusted `X-User-ID`, `X-User-Role`,
`X-User-Email` headers (stripping any client-supplied copies). Audit is an internal
sink: its `AuditController` does not itself read `X-User-ID` — actor identity travels in
the `CreateAuditLogRequest` body (`actorId`/`actorType`), populated by the calling
service from the gateway-injected identity. The service depends on
`spring-boot-starter-security` and JWT config but defines no custom `SecurityConfig`;
network isolation (gateway-only reachability on the `referral-network`) is the primary
control. See [Auth & Security Architecture](./auth-security-architecture.md).

## Build & run

```bash
cd services/audit-service
./gradlew clean build      # compile + tests (Jacoco, 0.8 target)
./gradlew bootRun          # starts on port 8090
```

## Related

- [OKF index](../index.md)
- [Shared Data Model](./data-model.md) — owns `audit_logs`
- [Admin Service](./service-admin.md) — reads/queries audit logs
- [Auth & Security Architecture](./auth-security-architecture.md) — gateway identity injection & tracing
