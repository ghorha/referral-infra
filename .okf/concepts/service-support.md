---
okf_version: "0.1"
type: concept
id: service-support
title: "Support Service"
tags: [service, support, spring-boot, admin, claims, error-codes, security]
port: 8088
updated: 2026-07-10
related:
  - ../index.md
  - ./auth-security-architecture.md
  - ./service-claim.md
  - ./service-user.md
  - ./data-model.md
---

# Support Service

## Purpose
The Support Service is the read-mostly back office for the customer-support and admin teams. It surfaces an operational dashboard, lets agents look up customers and their claims, add internal notes/messages to a claim, escalate a claim to admin, and resolve human-readable meaning for platform error codes. It does not own its data — it reads the shared `users`, `claims`, and `messages` tables via JPA and treats error-code metadata as a static, file-backed catalog.

## Runtime
- **Port**: 8088
- **Base package**: `com.referralmarketplace.support`
- **Stack**: Spring Boot 3.2.0 / Java 17 (Gradle)
- **Dir**: `services/support-service`
- **DB**: PostgreSQL `referral_marketplace` (Hibernate `ddl-auto=validate`; Flyway disabled — this service does not own migrations)

## API
All routes are under `/api/v1/support` and require role `ADMIN` or `SUPPORT`.

| Method | Path | Purpose |
| --- | --- | --- |
| GET | `/dashboard` | Aggregate support metrics (total customers, pending/under-review claims; active/resolved counts are stubbed) |
| GET | `/search?query=&page=&size=` | Paged customer search by email/name |
| GET | `/users/{id}` | Fetch a single customer profile |
| GET | `/users/{id}/claims?page=&size=` | Paged claims for a customer (by `seekerId`, newest first) |
| POST | `/claims/{id}/messages` | Add an internal message/note to a claim |
| POST | `/claims/{id}/escalate` | Escalate a claim (prefixes an `ESCALATED TO ADMIN` note) |
| GET | `/errors?query=` | Search the error-code catalog |
| GET | `/errors/{code}` | Look up a single error code's meaning/remediation |

> There is **no backend ticket API**. The support-ticket UI is an honest "coming soon" placeholder; no endpoints back it yet.

## Data
JPA entities map to shared tables that are **owned by other services** — support-service is effectively a reader/annotator, not the owner:
- `User` → `users` table (owned by [user-service](./service-user.md))
- `Claim` → `claims` table (owned by [claim-service](./service-claim.md))
- `Message` → `messages` table (claim conversation; support appends notes here)

See the [shared data model](./data-model.md) for the canonical schema. Error codes are **not** in the DB: they come from an `error-codes.yaml` catalog parsed at runtime (SnakeYAML) into `ErrorCodeDto`.

## Integrations
- **PostgreSQL** via Spring Data JPA (Hikari pool) — the only backing store.
- **error-codes.yaml** — mounted read-only into the container (`ERROR_CODES_FILE=/app/error-codes.yaml`, bind-mounted from the repo root in `docker-compose.yml`) and read by `ErrorCodeService`.
- **Resilience4j** circuit breaker + **Actuator/Micrometer/Prometheus** + **OpenTelemetry (OTLP)** tracing + **SpringDoc/Swagger** (`/swagger-ui.html`).
- No Redis, no WebSocket, no Feign clients. External integrations (Stripe/Mailgun/Google Vision/Twilio) are **not used** by this service.

## Inter-service
Reached **only through the API gateway** (compose exposes it as `SUPPORT_SERVICE_URL=http://support-service:8088`). It makes no outbound service calls — it reads/writes the shared Postgres tables directly and reads the mounted error-code file. There are no Feign/HTTP dependencies on other services.

## Security
Post Phase 1 + Phase 2, this service is stateless and gateway-trusting (no more default HTTP Basic / admin-admin):
- The **API gateway** validates the JWT/cookie and injects trusted `X-User-ID`, `X-User-Role`, `X-User-Email` headers, stripping any client-supplied copies.
- `GatewayIdentityFilter` reads `X-User-ID` (UUID principal) and `X-User-Role`, building a `ROLE_<role>` authority.
- `SecurityConfig` is stateless (`SessionCreationPolicy.STATELESS`), disables HTTP Basic/form login/CSRF, permits `/actuator/**`, and gates `/api/v1/support/**` to `hasAnyRole("ADMIN","SUPPORT")`.
- **Caveat**: header trust is unconditional, so a Kubernetes NetworkPolicy restricting ingress to the gateway is required to prevent header forgery on direct in-cluster access (deferred to Phase 4). See [auth & security architecture](./auth-security-architecture.md) and the [production readiness audit](../../.claude/context/PRODUCTION_READINESS_AUDIT.md).

## Build & run
```bash
cd services/support-service
./gradlew clean build      # compile + tests
./gradlew bootRun          # starts on port 8088
```

## Related
- [OKF index](../index.md)
- [Auth & security architecture](./auth-security-architecture.md)
- [Claim service](./service-claim.md)
- [User service](./service-user.md)
- [Shared data model](./data-model.md)
- [Production readiness audit](../../.claude/context/PRODUCTION_READINESS_AUDIT.md)
