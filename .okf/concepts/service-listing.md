---
okf_version: "0.1"
type: concept
id: service-listing
title: "Listing Service"
tags: [listing, programs, catalog, postgresql, jpa, spring-boot]
port: 8082
updated: 2026-07-10
related:
  - ../index.md
  - ./data-model.md
  - ./service-claim.md
  - ./service-orchestration.md
  - ./service-api-gateway.md
---

# Listing Service

## Purpose
The Listing Service is the catalog of the Vouch marketplace. It owns referral **listings** (a poster's offer: title, description, reward amount, max claims, time window, lifecycle status) and the reference **programs**/**businesses** they belong to. It exposes public read access to the active listing catalog and authenticated write access for posters to create and activate their own listings. A scheduled job expires listings whose time window has lapsed.

## Runtime
- **Port**: 8082
- **Base package**: `com.referralmarketplace.listing`
- **Stack**: Spring Boot 3.2.0 / Java 17
- **Directory**: `services/listing-service`

## API
All paths are prefixed with `/api/v1`. `X-User-ID` is the gateway-injected caller UUID.

| Method | Path | Purpose |
| --- | --- | --- |
| GET | `/listings` | List active listings, paginated (`page`, `size`, optional `search`). **Public** (gateway allowlist). |
| GET | `/listings/{id}` | Get a single listing by ID with its claim count. |
| POST | `/listings` | Create a listing (starts `active`). Requires `X-User-ID`. |
| POST | `/listings/{id}/activate` | Activate a listing; poster-only (ownership enforced). Requires `X-User-ID`. |
| GET | `/listings/me/listings` | List the caller's own listings, paginated. Requires `X-User-ID`. |
| GET | `/listings/{id}/accepts-claims` | Boolean check — whether the listing is active, unexpired, and under `maxClaims`. |
| GET | `/programs` | List programs, paginated (optional `search` or `category`). |
| GET | `/programs/{id}` | Get a single program by ID. |

## Data
Backed by the shared PostgreSQL database `referral_marketplace` (see [shared data model](./data-model.md)). Hibernate runs with `ddl-auto: validate` and Flyway disabled — the schema is owned/migrated by the auth-service.

- **Owns/writes**: `listings` (reward stored as `numeric(10,2)` dollars, surfaced as `amountCents` in the DTO), `programs`, `businesses`.
- **Reads**: `claims` — via `ListingRepository.countClaimsByListingId(...)` to compute per-listing claim counts and the `acceptsNewClaims` flag; the authoritative claim lifecycle lives in the [Claim Service](./service-claim.md).

**Known quirk**: `ListingDto.fromEntity` sets `businessName = listing.getTitle()` and `programName = ""` — listings are not yet linked to a `program`/`business` row, so those DTO fields are placeholders.

## Integrations
No external SaaS integrations (no Stripe/Mailgun/Google Vision/Twilio), no Feign clients, no Redis, no WebSocket. Dependencies (from `build.gradle`) are PostgreSQL + Flyway (disabled), Spring cache, Actuator, Micrometer Prometheus metrics, OpenTelemetry OTLP tracing, and SpringDoc OpenAPI (`/swagger-ui.html`, `/api-docs`).

## Inter-service
- **Reached through** the [API Gateway](./service-api-gateway.md); the [Orchestration Service](./service-orchestration.md) also calls it as part of cross-service flows. `GET /listings` and `GET /listings/{id}` are on the gateway public allowlist; writes carry the gateway-injected identity headers.
- **Calls out to**: nothing but its own PostgreSQL database — it makes no outbound service calls.

## Security
Identity comes entirely from the trusted gateway-injected `X-User-ID` (UUID) header, read via `@RequestHeader("X-User-ID")` on the create/activate/me endpoints; the gateway validates the JWT and strips any client-supplied copies. This service has no Spring Security config or role gating of its own — read endpoints are intentionally public via the gateway allowlist. Ownership is enforced in `activateListing`, which throws if `posterId != X-User-ID`.

## Build & run
```bash
cd services/listing-service
./gradlew clean build      # compile + tests
./gradlew bootRun          # starts on port 8082
```

## Related
- [Vouch concept index](../index.md)
- [Shared data model (PostgreSQL)](./data-model.md)
- [Claim Service](./service-claim.md) — consumes listings, owns the `claims` table
- [Orchestration Service](./service-orchestration.md) — cross-service caller
- [API Gateway](./service-api-gateway.md) — identity injection and public allowlist
