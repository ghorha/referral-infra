---
okf_version: "0.1"
type: concept
id: service-analytics
title: "Analytics Service"
tags: [analytics, event-tracking, spring-boot, stateless, jsonl, queue-optional]
port: 8089
updated: 2026-07-10
related:
  - ../index.md
  - ./deployment-infrastructure.md
  - ./service-api-gateway.md
---

# Analytics Service

## Purpose
The Analytics Service is a lightweight, fire-and-forget event sink for the Vouch platform. It accepts arbitrary product/behavioral events (event type, user, trace id, free-form properties) over a single HTTP endpoint and records them asynchronously. It exists so other services can emit telemetry without owning storage or a queue; in local/MVP mode it persists to partitioned JSONL files on disk, and it can optionally forward to a message queue when enabled. It holds no relational state and is intentionally minimal.

## Runtime
- **Port**: 8089 (`SERVER_PORT`)
- **Base package**: `com.referralmarketplace.analytics`
- **Stack**: Spring Boot 3.2.0 / Java 17
- **Dir**: `services/analytics-service`
- **Notable**: `@SpringBootApplication(exclude = DataSourceAutoConfiguration.class)` — no datasource is wired. `@EnableAsync` + `@EnableScheduling` are on the application class; event handling runs on an async thread.

## API
Base path: `/api/v1/analytics`

| Method | Path | Purpose |
| ------ | ---- | ------- |
| POST | `/api/v1/analytics/events` | Accept an analytics event; validates the body, hands it to the async tracker, and returns `202 Accepted` with `{status: accepted, message: ...}`. Processing is asynchronous. |

Request body (`AnalyticsEventRequest`): `eventType` (required, not blank), `userId` (required UUID), `traceId` (optional), `properties` (optional `Map<String,Object>`). Actuator (`/actuator/health`, `/info`, `/metrics`, `/prometheus`) and SpringDoc (`/api-docs`, `/swagger-ui.html`) are also exposed.

## Data
- **No database.** `DataSourceAutoConfiguration` is excluded and there is no JPA/Mongo dependency, so this service owns and reads **no shared tables** — it does not participate in the shared data model (see [data model](./data-model.md)).
- `AnalyticsEvent` is a plain Lombok model (`eventId`, `eventType`, `userId`, `traceId`, `timestamp`, `properties`), not an entity.
- **Persistence** (default MVP): events are serialized to newline-delimited JSON at `ANALYTICS_STORAGE_PATH` (default `./analytics-events`), partitioned as `date=<yyyy-MM-dd>/hour=<HH>/events.jsonl`.

## Integrations
- **Optional message queue** — gated by `ANALYTICS_QUEUE_ENABLED` (default `false`). When enabled, `sendToQueue(...)` is invoked (placeholder/TODO for SQS/Service Bus/Pub-Sub); when disabled, events are written to local JSONL. `ANALYTICS_QUEUE_NAME` (default `analytics-events`) names the target queue.
- **No external integrations** — no Stripe/Mailgun/Google Vision/Twilio, no Redis, no WebSocket, no Feign clients. `build.gradle` pulls only Spring web/security/validation/actuator/AOP, JWT (jjwt), SpringDoc, Micrometer/Prometheus, and OpenTelemetry OTLP tracing.
- **Observability**: Micrometer + Prometheus registry and W3C OpenTelemetry trace propagation (`traceId` is carried on each event).

## Inter-service
- **Inbound**: reached through the [API gateway](./service-api-gateway.md); any service or client posts events to `/api/v1/analytics/events`. In `docker-compose.yml` it is addressed as `http://analytics-service:8089` (`ANALYTICS_SERVICE_URL`).
- **Outbound**: none. It calls no other services and no database — it only writes to the local filesystem (or the optional queue).

## Security
- Identity comes from the gateway, which validates the JWT and injects trusted `X-User-ID` / `X-User-Role` / `X-User-Email` headers (stripping client copies). This service, however, does **not** read `X-User-ID`; the actor is taken from the `userId` field in the request body.
- There is **no `SecurityConfig` and no role gating** in this service. `spring-boot-starter-security` is on the classpath but unconfigured, so Spring Boot's default filter chain applies. It is not a role-enforcing service like admin/support; it is expected to sit behind the gateway and treat all callers as trusted internal emitters.
- **Not wired to the UI** — the web app's analytics surfaces are honestly empty; nothing in the frontend currently posts to this endpoint.

## Build & run
```bash
cd services/analytics-service
./gradlew clean build      # compile + test (JaCoCo report)
./gradlew bootRun          # starts on port 8089
```
Docker: built from `services/analytics-service/Dockerfile`, published on `8089`, healthchecked at `/actuator/health`.

## Related
- [OKF index](../index.md)
- [Deployment & infrastructure](./deployment-infrastructure.md)
- [API Gateway service](./service-api-gateway.md)
- [Shared data model](./data-model.md) — this service owns no tables in it
