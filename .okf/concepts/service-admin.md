---
okf_version: "0.1"
type: concept
id: service-admin
title: "Admin Service"
tags: [admin, backoffice, claims-review, moderation, dashboard, audit-logs, spring-boot, rbac]
port: 8086
updated: 2026-07-10
related:
  - ../index.md
  - ./auth-security-architecture.md
  - ./service-claim.md
  - ./service-payment.md
  - ./service-audit.md
  - ./data-model.md
---

# Admin Service

## Purpose
The Admin Service is the back-office control plane for the Vouch marketplace. It gives platform administrators a single API for operational oversight: a dashboard of system stats, aggregate analytics metrics, browsing the platform audit trail, claim adjudication (review, approve, reject, trigger payout), listing takedowns, and user management (create support users, list/filter users, update role/status). It reads directly from the shared PostgreSQL schema rather than proxying every other service.

## Runtime
- **Port**: 8086
- **Base package**: `com.referralmarketplace.admin`
- **Stack**: Spring Boot 3.2.0 / Java 17 (Gradle)
- **Directory**: `services/admin-service`
- **Entry point**: `AdminServiceApplication`

## API
All routes are under `/api/v1/admin` (`AdminController`).

| Method | Path | Purpose |
| --- | --- | --- |
| POST | `/api/v1/admin/users` | Create a SUPPORT user (email + display name) |
| GET | `/api/v1/admin/users` | List/paginate users; filter by `role`, `status`, `search` |
| GET | `/api/v1/admin/users/{id}` | Fetch a single user by UUID |
| PATCH | `/api/v1/admin/users/{id}` | Update a user's display name, role, or status |
| GET | `/api/v1/admin/claims` | List claims for review; filter by comma-separated `status` (defaults to UNDER_REVIEW) |
| PATCH | `/api/v1/admin/claims/{id}/approve` | Approve a claim (optional review notes) |
| PATCH | `/api/v1/admin/claims/{id}/reject` | Reject a claim with a required reason |
| POST | `/api/v1/admin/claims/{id}/payout` | Flip an APPROVED claim to PAID |
| POST | `/api/v1/admin/listings/{id}/takedown` | Force a listing to TAKEN_DOWN |
| GET | `/api/v1/admin/dashboard` | Aggregate system stats + pending-claim counts |
| GET | `/api/v1/admin/audit-logs` | Paginate audit logs; filter by actor/target/eventType/action/date range |
| GET | `/api/v1/admin/analytics/metrics` | Aggregate user/listing/claim/revenue metrics |

## Data
The service maps four JPA entities onto the shared PostgreSQL database (`referral_marketplace`) with `ddl-auto: validate` and Flyway disabled (`flyway.enabled: false` — admin-service does not own migrations, it is a read-mostly consumer of tables owned elsewhere):

- **`users`** (`User`: email, displayName, role POSTER/SEEKER/SUPPORT/ADMIN, status ACTIVE/SUSPENDED/DELETED) — owned by the user/auth domain; admin reads and mutates role/status here.
- **`claims`** (`Claim`: listingId, seekerId, status INITIATED/UNDER_REVIEW/APPROVED/REJECTED/PAID, rewardAmount, reviewedAt, paidAt, notes) — owned by the claim domain; admin mutates status during adjudication.
- **`listings`** (`Listing`: title, posterId, rewardAmount, status DRAFT/ACTIVE/EXPIRED/TAKEN_DOWN) — owned by the listing domain; admin flips status on takedown.
- **`audit_logs`** (`AuditLog`: timestamp, traceId, eventType, actor/target, action, result, metadata) — read-only from the admin side.

See [data-model.md](./data-model.md) for the canonical shared schema.

## Integrations
- **PostgreSQL** via Spring Data JPA (HikariCP), the only backing store it touches directly.
- **OpenFeign** (`spring-cloud-starter-openfeign`) and **Resilience4j** circuit breaker are on the classpath and service URLs (auth, user, listing, claim, payment, analytics, audit) are configured under `services:` for future service-to-service calls; no Feign clients are wired into the current controller paths.
- **Actuator + Micrometer/Prometheus + OpenTelemetry (OTLP)** for health, metrics, and tracing.
- **SpringDoc OpenAPI / Swagger UI** at `/swagger-ui.html`.
- No external SaaS integrations (Stripe/Mailgun/Vision/Twilio) are called from this service.
- **Known gaps**: dashboard `totalRevenue`/`escrowBalance` and the 24h recent-activity counts are hardcoded to `0` (revenue/escrow are TODOs pending the payment service); `POST /claims/{id}/payout` only flips claim status to PAID and does NOT call Stripe or the payment service.

## Inter-service
Reached only **through the API gateway** at `http://admin-service:8086` (compose `ADMIN_SERVICE_URL`). It does not currently originate outbound service calls in request handling — all reads/writes go straight to the shared PostgreSQL tables. Claim payout and revenue figures that would depend on [service-payment](./service-payment.md) are stubbed today. Related domains it acts upon live in [service-claim](./service-claim.md) and [service-audit](./service-audit.md).

## Security
Identity is **gateway-injected**: the API gateway validates the JWT (httpOnly cookie/Bearer), strips any client-supplied copies, and forwards `X-User-ID` (UUID), `X-User-Role`, and `X-User-Email`. `GatewayIdentityFilter` (a `OncePerRequestFilter`) reads `X-User-ID` + `X-User-Role`, builds a `ROLE_<role>` authority, and populates the `SecurityContext`; malformed headers leave the request unauthenticated. `SecurityConfig` is **stateless** (`SessionCreationPolicy.STATELESS`), disables HTTP Basic / form login / CSRF (no more default `admin/admin`), permits `/actuator/**`, and gates every `/api/v1/admin/**` route with `hasRole("ADMIN")`. The header trust is only sound behind the gateway; blocking direct in-cluster access via a Kubernetes NetworkPolicy is deferred to Phase 4. See [auth-security-architecture.md](./auth-security-architecture.md).

## Build & run
```bash
cd services/admin-service
./gradlew clean build      # compile + test (Jacoco, 80% target)
./gradlew bootRun          # starts on port 8086
```

## Related
- [Concept index](../index.md)
- [Auth & security architecture](./auth-security-architecture.md)
- [Claim service](./service-claim.md)
- [Payment service](./service-payment.md)
- [Audit service](./service-audit.md)
- [Shared data model](./data-model.md)
- [Production readiness audit](../../.claude/context/PRODUCTION_READINESS_AUDIT.md)
