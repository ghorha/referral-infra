---
okf_version: "0.1"
type: concept
id: service-claim
title: "Claim Service"
tags: [claims, transactions, escrow, evidence, ocr, reviews, spring-boot, postgres]
port: 8083
updated: 2026-07-10
related:
  - ../index.md
  - ./data-model.md
  - ./service-listing.md
  - ./service-payment.md
  - ./service-notification.md
  - ./service-admin.md
---

# Claim Service

## Purpose
The Claim Service owns the core fulfillment domain of Vouch: it tracks a referral engagement from the moment a Seeker uses a listing through proof submission, review, escrow, payout, and closing. It also manages supporting artifacts — uploaded evidence, in-thread messages, dispute tickets, and post-transaction reviews — and runs OCR over proof images to extract verifiable text. It is the source of truth for transaction state, evidence, and reviews.

## Runtime
- **Port**: 8083
- **Base package**: `com.referralmarketplace.claim`
- **Stack**: Spring Boot 3.2.0 / Java 17 (Spring Web, Data JPA, Validation, Actuator)
- **Directory**: `services/claim-service`
- **Persistence**: PostgreSQL (`referral_marketplace`) via Hibernate; `ddl-auto=validate` locally, `update` in the Compose container.

## API
All routes are exposed under `/api/v1`. Identity arrives as the gateway-injected `X-User-ID` header.

| Method | Path | Purpose |
| --- | --- | --- |
| POST | `/api/v1/claims` | Create a claim for a listing (legacy domain) |
| GET | `/api/v1/claims/{id}` | Get a claim by id |
| POST | `/api/v1/claims/{id}/submit` | Submit a draft claim for review |
| POST | `/api/v1/claims/{id}/dispute` | Dispute a claim |
| GET | `/api/v1/claims/me` | List the caller's claims |
| GET | `/api/v1/claims/{id}/messages` | Page through a claim's message thread |
| POST | `/api/v1/claims/{id}/message` | Add a message to a claim thread |
| DELETE | `/api/v1/claims/{id}` | Delete a claim |
| POST | `/api/v1/files/upload` | Generate a presigned upload URL for evidence |
| POST | `/api/v1/transactions` | Create a transaction (Seeker uses a listing) → STARTED |
| GET | `/api/v1/transactions/{id}` | Get a transaction (caller must be Poster or Seeker) |
| GET | `/api/v1/transactions` | List the caller's transactions, filtered by `role`/`status` |
| POST | `/api/v1/transactions/{id}/submit-proof` | Seeker submits proof → PROOF_SUBMITTED_IN_REVIEW |
| POST | `/api/v1/transactions/{id}/review-proof` | Poster/Admin approves or declines proof |
| POST | `/api/v1/transactions/{id}/poster-received` | Poster marks payment received from business |
| POST | `/api/v1/transactions/{id}/close` | Seeker closes the transaction → TRANSACTION_CLOSED |
| POST | `/api/v1/transactions/{id}/dispute` | Raise a dispute with evidence |
| DELETE | `/api/v1/transactions/{id}` | Cancel/delete a transaction |
| GET | `/api/v1/transactions/stats` | Poster/Seeker dashboard counts |

## Data
Owns these Postgres tables (see [data model](./data-model.md)):
- **transactions** — the real escrow state machine (7 states: STARTED → … → TRANSACTION_CLOSED), money fields in cents (`promisedAmountCents`, `platformFeeCents`, `seekerReceivesCents`), proof URLs, and OCR text/confidence.
- **evidence** — uploaded files linked to a transaction, with `ocrData` (jsonb) and a verification status.
- **messages** — per-transaction message threads.
- **tickets** — disputes/cases (raisedBy SYSTEM/POSTER/SEEKER/ADMIN, priority, status, resolution).
- **reviews** — post-transaction ratings of a person or listing (multi-dimension scores).
- **claims** — the legacy claim table (DRAFT/SUBMITTED/UNDER_REVIEW/APPROVED/REJECTED/PAID/DISPUTED).

It reads `listingId`, `posterId`, and `seekerId` as opaque UUIDs — the listing and user records live in the listing/auth services.

> **Open product decision**: `/claims` (legacy) and `/transactions` (current escrow flow) model overlapping domains. `TransactionController` was split out of `ClaimController`; the two coexist until the claims path is retired.

## Integrations
- **PostgreSQL** — primary datastore (Spring Data JPA, HikariCP).
- **File storage** — local disk vs S3, selected by `STORAGE_TYPE` (`local` in dev; `aws-java-sdk-s3`). Uploads use short-lived presigned URLs.
- **Google Vision OCR** — `google-cloud-vision`; gated by `OCR_ENABLED` (**false** in local dev, so `OcrService` returns mock data).
- **Observability** — Prometheus (`micrometer-registry-prometheus`) and OTLP tracing; SpringDoc/Swagger UI.
- The `spring-boot-starter-websocket` dependency is present but no live WebSocket endpoint is wired yet.

## Inter-service
- **Inbound**: reached only through the API gateway, which validates the JWT and injects the trusted `X-User-ID` / `X-User-Role` / `X-User-Email` headers (stripping any client copies).
- **Outbound**: calls the [listing service](./service-listing.md) over HTTP via `RestTemplate` — `GET /api/v1/listings/{id}/accepts-claims` — to validate a listing before creating a claim (`LISTING_SERVICE_URL`, default `http://listing-service:8082`). Escrow money movement and payout are the province of the [payment service](./service-payment.md); dispute/ticket handling surfaces in the [admin service](./service-admin.md); status changes notify users via the [notification service](./service-notification.md).

## Security
Identity is obtained solely from the gateway-injected `X-User-ID` (UUID) header read on each endpoint; the service does not parse JWTs itself. Ownership checks are enforced in-code (e.g. `getTransaction` returns 403 unless the caller is the Poster or Seeker). There is no local `SecurityConfig`/filter yet — privileged reviewer/admin gating is still marked TODO, so cross-role authorization currently leans on the gateway and callers. See [PRODUCTION_READINESS_AUDIT](../../.claude/context/PRODUCTION_READINESS_AUDIT.md).

## Build & run
```
cd services/claim-service
./gradlew clean build      # compiles + runs unit and integration tests (Testcontainers Postgres)
./gradlew bootRun          # starts on port 8083
```

## Related
- [Service index](../index.md)
- [Shared data model](./data-model.md)
- [Listing service](./service-listing.md)
- [Payment service](./service-payment.md)
- [Notification service](./service-notification.md)
- [Admin service](./service-admin.md)
- [Production readiness audit](../../.claude/context/PRODUCTION_READINESS_AUDIT.md)
