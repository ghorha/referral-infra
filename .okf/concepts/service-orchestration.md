---
okf_version: "0.1"
type: concept
id: service-orchestration
title: "Orchestration Service"
tags: [orchestration, bff, feign, aggregation, resilience4j, redis, spring-boot]
port: 8091
updated: 2026-07-10
related:
  - ../index.md
  - ./workspace-structure.md
  - ./service-user.md
  - ./service-listing.md
  - ./service-claim.md
  - ./service-api-gateway.md
---

# Orchestration Service

## Purpose
Backend-for-Frontend (BFF) that composes a single response from several downstream
microservices so a client can render a rich view in one round trip. Today it exposes one
aggregation: given a listing id, it fans out to listing-service, user-service, and
claim-service, then merges the listing, its poster, and a claim count into one payload.
It is the **only** service in the monorepo that uses `@FeignClient` for declarative
inter-service HTTP. Note: the current frontend does **not** consume this service yet —
the home and listing-detail pages call listing-service directly — so it is effectively a
staged/aggregation surface.

## Runtime
- **Port**: 8091 (`SERVER_PORT`).
- **Base package**: `com.referralmarketplace.orchestration`.
- **Stack**: Spring Boot 3.2.0 / Java 17, Spring Cloud 2023.0.0.
- **Dir**: `services/orchestration-service`.
- Runs **without a database** — `DataSourceAutoConfiguration` is excluded in the main app class.

## API
All routes are under `/api/v1/orchestration` (`OrchestrationController`).

| Method | Path | Purpose |
| --- | --- | --- |
| GET | `/listings/{id}/aggregated` | Aggregate a listing with its poster (user) and total claim count into one `AggregatedListingResponse`. |

## Data
Owns **no** entities and **no** tables — it holds no persistence layer at all. It reads data
indirectly by calling the services that own the shared tables: `listings` (listing-service),
`users` (user-service), and `claims` (claim-service). The composed DTO
`AggregatedListingResponse` carries `listing`, `poster`, and `claimCount` as loosely typed maps.
See the shared schema in [data model](./data-model.md).

## Integrations
- **Spring Cloud OpenFeign** — declarative HTTP clients (`ListingServiceClient`,
  `UserServiceClient`, `ClaimServiceClient`); enabled via `@EnableFeignClients`. Feign timeouts
  (connect/read 5000ms) and BASIC logging configured in `FeignConfig` + `application.yml`.
- **Resilience4j** — the aggregation is wrapped with `@CircuitBreaker(name="default")`
  (fallback returns a degraded payload with an error stub) and `@Retry(name="default", maxAttempts=3)`.
- **Redis** — `spring-boot-starter-data-redis` on the classpath for optional caching
  (`REDIS_HOST`/`REDIS_PORT`); no cache logic is wired in the current code.
- **Observability** — Actuator + Micrometer/Prometheus, OpenTelemetry (OTLP) tracing,
  SpringDoc OpenAPI at `/swagger-ui.html`.
- No external third-party integrations (no Stripe/Mailgun/Vision/Twilio) — those live in
  other services and are `*_ENABLED=false` in local dev.

## Inter-service
- **Reached through** the [API gateway](./service-api-gateway.md) at `/api/v1/orchestration/**`.
- **Calls** (Feign, over the docker network):
  - listing-service `GET /api/v1/listings/{id}` → the listing.
  - user-service `GET /api/v1/users/{id}` → the poster (id taken from `listing.posterId`).
  - claim-service `GET /api/v1/claims?listingId=…&page=0&size=1` → `totalElements` used as the count.
- Downstream URLs are injected via env (`LISTING_SERVICE_URL`, `USER_SERVICE_URL`,
  `CLAIM_SERVICE_URL`, plus auth/payment/admin/notification/support/analytics/audit for future clients).

## Security
Sits **behind the gateway**, which validates the JWT and injects trusted `X-User-ID`,
`X-User-Role`, and `X-User-Email` headers (stripping any client-supplied copies). Current
posture: `OrchestrationController` does **not** yet read `X-User-ID`, and the Feign clients do
**not** forward it downstream, so the aggregation performs no per-user gating — it is a
read-only composition endpoint. The service defines no custom `SecurityConfig`; the
`spring-boot-starter-security` starter's defaults apply. `JWT_SECRET` is present in config but
unused by request handling.

## Build & run
```bash
cd services/orchestration-service
./gradlew clean build      # compile + tests (Jacoco)
./gradlew bootRun          # starts on port 8091
```

## Related
- [OKF index](../index.md)
- [Workspace structure](./workspace-structure.md)
- [User Service](./service-user.md)
- [Listing Service](./service-listing.md)
- [Claim Service](./service-claim.md)
- [API Gateway](./service-api-gateway.md)
- [Data model](./data-model.md)
