---
okf_version: "0.1"
type: concept
id: service-user
title: "User Service"
tags: [service, spring-boot, users, businesses, programs, postgres, jpa]
port: 8085
updated: 2026-07-10
related:
  - ../index.md
  - ./data-model.md
  - ./service-auth.md
  - ./service-listing.md
  - ./service-orchestration.md
---

# User Service

## Purpose
The User Service is the system of record for people and organizations on the Vouch marketplace. It manages user profiles (display name, contact info, role, status, bio), the businesses those users own, and the referral **programs** a business runs. It exposes read/search and CRUD operations that other services (via the gateway and the orchestration service) rely on to resolve identities, verify business ownership, and look up program state.

## Runtime
- **Port**: 8085
- **Base package**: `com.referralmarketplace.user`
- **Stack**: Spring Boot 3.2.0 / Java 17
- **Dir**: `services/user-service`
- **Main class**: `UserServiceApplication`

## API
All routes are served under the paths below (the gateway forwards `/api/v1/...` traffic here).

| Method | Path | Purpose |
| --- | --- | --- |
| GET | `/api/v1/users/{id}` | Fetch a user by UUID |
| GET | `/api/v1/users/email/{email}` | Fetch a user by email |
| GET | `/api/v1/users?query=&page=&size=` | Paged user search |
| PATCH | `/api/v1/users/{id}/profile` | Update a user's profile fields |
| POST | `/api/v1/businesses?ownerId=` | Create a business for an owner |
| GET | `/api/v1/businesses/{id}` | Fetch a business by UUID |
| GET | `/api/v1/businesses?ownerId=&query=&page=&size=` | Search businesses (by owner or free text) |
| PUT | `/api/v1/businesses/{id}` | Update a business |
| DELETE | `/api/v1/businesses/{id}` | Delete a business |
| POST | `/api/v1/programs` | Create a referral program |
| GET | `/api/v1/programs/{id}` | Fetch a program by UUID |
| GET | `/api/v1/programs?businessId=&status=&page=&size=` | List programs by business or status |
| PUT | `/api/v1/programs/{id}` | Update a program |
| PATCH | `/api/v1/programs/{id}/status` | Change program status |
| DELETE | `/api/v1/programs/{id}` | Delete a program |

## Data
JPA entities backed by PostgreSQL (`referral_marketplace` DB). This service owns three tables in the [shared data model](./data-model.md):
- **`users`** (`User`) — email (unique), display_name, phone_number, profile_image_url, `role` (POSTER, SEEKER, SUPPORT, ADMIN), `status` (ACTIVE, SUSPENDED, DELETED), bio, audit timestamps.
- **`businesses`** (`Business`) — name, description, `owner_id` (references a user), website (unique), industry, location, logo_url, audit timestamps.
- **`programs`** (`Program`) — name, description, `business_id`, `status` (DRAFT, ACTIVE, PAUSED, INACTIVE), audit timestamps.

Auditing timestamps are populated by Spring Data JPA `AuditingEntityListener`. `ddl-auto` is `validate` (this service does **not** own Flyway migrations — `spring.flyway.enabled=false`).

## Integrations
- **PostgreSQL** via Spring Data JPA + HikariCP (`spring-boot-starter-data-jpa`, `postgresql` driver).
- **Actuator + Micrometer/Prometheus** metrics at `/actuator/health,info,metrics,prometheus`.
- **OpenTelemetry** OTLP distributed tracing (W3C propagation, `traceId` in logs).
- **springdoc-openapi** UI at `/swagger-ui.html`, docs at `/api-docs`.
- **JWT (jjwt)** and `spring-boot-starter-security` are on the classpath. No Redis, WebSocket, or Feign clients — this is a self-contained CRUD service with no outbound service calls.

## Inter-service
- **Reached through the API gateway** (`USER_SERVICE_URL=http://user-service:8085`). Callers such as the [orchestration service](./service-orchestration.md) and the [listing service](./service-listing.md) resolve user/business/program records here.
- **Outbound**: none beyond its own PostgreSQL datastore.

## Security
The API gateway validates the JWT and injects trusted `X-User-ID` (UUID), `X-User-Role`, and `X-User-Email` headers (stripping any client-supplied copies) — see [auth & security architecture](./service-auth.md). Within this service, the acting subject and ownership are currently passed explicitly as path/query parameters (e.g. `ownerId` on business creation, `{id}` on profile update) rather than read from `@RequestHeader("X-User-ID")`; there is no per-endpoint role gating filter in this service (unlike admin/support, which run a `GatewayIdentityFilter`). Requests are expected to arrive only via the authenticated gateway edge.

## Build & run
```bash
cd services/user-service
./gradlew clean build      # compile + tests (JaCoCo report)
./gradlew bootRun          # starts on port 8085
```
Requires a reachable PostgreSQL (`SPRING_DATASOURCE_URL`, `DB_USERNAME`, `DB_PASSWORD`). In Docker Compose it depends on the `postgres` service.

## Related
- [OKF index](../index.md)
- [Shared data model](./data-model.md)
- [Auth & security architecture](./service-auth.md)
- [Listing service](./service-listing.md)
- [Orchestration service](./service-orchestration.md)
