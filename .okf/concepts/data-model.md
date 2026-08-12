---
okf_version: "0.1"
type: concept
id: data-model
title: "Shared Data Model (PostgreSQL)"
tags: [postgresql, schema, jpa, shared-database, redis]
updated: 2026-07-10
related:
  - ../index.md
  - ./workspace-structure.md
  - ./service-auth.md
  - ./service-listing.md
  - ./service-claim.md
  - ./service-payment.md
---

# Shared Data Model (PostgreSQL)

## One database, many services

All data services share **one** PostgreSQL 15 database, `referral_marketplace`
(user `referral_user`, port 5432). This is a shared‑database design, **not**
database‑per‑service: several services map the **same tables** with their own JPA
entity classes (e.g. `admin`, `support`, `listing`, `claim` each define their own
`User`/`Claim`/`Listing` views). **A schema change can ripple across multiple
services — check every service that maps a changed table.**

- Canonical schema: [`migrations.sql/V1__complete_schema.sql`](../../migrations.sql)
  (mounted into the postgres container at first boot).
- `auth-service` additionally runs **Flyway** (`db/migration/V1–V3`); other services use
  Hibernate `ddl-auto` (`update` in docker, `validate` in auth).
- UUID primary keys everywhere; timestamps `TIMESTAMPTZ` (UTC); money stored in **cents**
  (ledger) — `listings.reward_amount` is `DECIMAL(10,2)`. Extensions: `uuid-ossp`, `pg_trgm`.

## Tables (12) and owning service(s)

| Table | Owner(s) | Notes |
|-------|----------|-------|
| `users` | [auth](./service-auth.md), [user](./service-user.md) (+admin/support read) | `role` poster/seeker/support/admin; `status` active/inactive/suspended/deleted |
| `devices` | [auth](./service-auth.md) | fingerprinting; unique `(user_id, device_id)` |
| `businesses` | [user](./service-user.md) | unique `website` |
| `programs` | [user](./service-user.md) | referral programs under a business |
| `listings` | [listing](./service-listing.md) (+admin) | `status` draft/active/expired/taken_down |
| `claims` | [claim](./service-claim.md) (+admin/support) | unique `(listing_id, seeker_id)`; `status` draft/submitted/under_review/approved/rejected/paid/disputed; `submission_data` JSONB |
| `evidence` | [claim](./service-claim.md) | proof files; `ocr_data` JSONB |
| `messages` | [claim](./service-claim.md) (+support) | per-claim chat |
| `ledger` | [payment](./service-payment.md) | `amount_cents`; type escrow_hold/escrow_release/payout/refund/fee; Stripe ids |
| `notifications` | [notification](./service-notification.md) | partial index on unread |
| `audit_logs` | [audit](./service-audit.md) (+admin) | keyed by `trace_id`; result success/failure/error |
| `reviews` | (future) | rating 1–5; unique `claim_id` |

Views: `listings_with_stats`, `user_claim_stats`, `poster_listing_stats`.

## Redis

Used for: gateway rate limiting; the **JWT revocation blacklist** (`token:blacklist:*`)
shared between the gateway and auth-service; single-use **magic-link jti** markers
(`magiclink:{jti}`); phone-verification codes. See
[Auth & Security Architecture](./auth-security-architecture.md).

## Notable data-integrity caveats (from the audit)

- The real **escrow/transaction** domain (`transactions` table via claim-service) is a
  separate lifecycle from the legacy `claims` table — reconciling them is an open
  product decision.
- Admin dashboard revenue/escrow figures are currently hardcoded `0` on the backend.
