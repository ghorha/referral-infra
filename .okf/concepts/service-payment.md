---
okf_version: "0.1"
type: concept
id: service-payment
title: "Payment Service"
tags: [payment, escrow, ledger, stripe, webhooks, postgresql, spring-boot]
port: 8084
updated: 2026-07-10
related:
  - ../index.md
  - ./data-model.md
  - ./service-claim.md
  - ./service-admin.md
  - ./auth-security-architecture.md
---

# Payment Service

**Purpose** — Owns the money side of the marketplace: it holds a poster's reward
funds in escrow when a listing is funded, pays out to a seeker when a claim is
approved, and refunds unspent escrow back to the poster. Every movement is
recorded as an immutable double-entry-style row in a single `ledger` table, and
the current escrow balance for a listing is *derived* (holds minus payouts,
refunds and fees) rather than stored. Stripe is the intended payment rail, but it
is disabled in local dev, so the service records ledger entries against mock
Stripe objects.

**Runtime** — Port **8084**, base package `com.referralmarketplace.payment`,
Spring Boot 3.2.0 / Java 17, dir `services/payment-service`. PostgreSQL via
Spring Data JPA; Hibernate `ddl-auto` is `validate` locally and `update` in
docker-compose. Actuator health/metrics/prometheus exposed.

## API

All routes are served under the gateway. `/api/v1/payments/**` requires a valid
access token; `/api/v1/webhooks/**` is a **public** gateway route (external
provider callbacks) — see Security.

| Method | Path | Purpose |
|--------|------|---------|
| POST | `/api/v1/payments/listings/{listingId}/fund` | Create Stripe PaymentIntent + `ESCROW_HOLD` ledger entry (body: `posterId`, `amountCents`, `count`) |
| GET  | `/api/v1/payments/listings/{listingId}/escrow-balance` | Return derived escrow balance (cents + formatted `$`) |
| POST | `/api/v1/payments/listings/{listingId}/payout` | Pay an approved claim (body: `claimId`, `amountCents`, `stripeAccountId`); guards against insufficient balance |
| POST | `/api/v1/payments/listings/{listingId}/refund` | Refund escrow to poster (`amountCents` query param) |
| POST | `/api/v1/webhooks/stripe` | Stripe event callback; verifies `Stripe-Signature` in prod, mock-parses in dev |

## Data

Owns the **`ledger`** table exclusively via the `Ledger` entity — the only table
this service maps. Columns of note: `listingId`, nullable `claimId`,
`transactionType` (`ESCROW_HOLD`, `ESCROW_RELEASE`, `PAYOUT`, `REFUND`, `FEE`),
`amountCents` (money is stored in **cents**), `status` (`PENDING`, `COMPLETED`,
`FAILED`, `CANCELLED`), a **unique** `webhookEventId` for idempotency, Stripe
correlation ids (`stripePaymentIntentId`, `stripePayoutId`), and a `jsonb`
`metadata` map. It references `listing`/`claim` rows only by id (no JPA join). See
the [shared data model](./data-model.md).

## Integrations

- **Stripe** (`com.stripe:stripe-java`) — PaymentIntents and Payouts. Gated by
  `stripe.enabled` (`STRIPE_ENABLED=false` in compose). When disabled the
  `StripeService` returns mock objects and webhooks skip signature verification.
- **Gson** — parses raw webhook JSON in dev mock mode.
- **PostgreSQL** — the only persistent dependency; no Redis, WebSocket or Feign
  clients are wired in this service.

## Inter-service

Reached **only through the api-gateway**; there is no service-to-service inbound
path. It is a leaf/terminal service — it makes **no** outbound calls to other
microservices (no Feign/WebClient/RestTemplate). Its only external egress is to
Stripe (when enabled). Callers such as [claim-service](./service-claim.md) and
[admin-service](./service-admin.md) drive funding/payout/refund flows through the
gateway rather than calling this service directly.

## Security

Identity is established at the **api-gateway**: it validates the JWT and injects
trusted `X-User-ID` / `X-User-Role` / `X-User-Email` headers (stripping any
client-supplied copies). The `/api/v1/payments/**` routes are authenticated at
the gateway on that basis. Note the current posture: the controllers do **not**
yet read `X-User-ID` — they trust the `listingId`/`claimId` in the path and the
`posterId` in the request body, so there is no in-service ownership check tying a
payment action to the caller (a hardening gap). The `/api/v1/webhooks/stripe`
route is intentionally **public** at the gateway (external Stripe callbacks);
authenticity is meant to come from `Stripe-Signature` verification, which is
bypassed while `STRIPE_ENABLED=false`. See
[auth & security architecture](./auth-security-architecture.md).

> **Known gap:** these payment endpoints are currently **not wired into the
> frontend UI** — funding/payout/refund are reachable via the API but have no
> user-facing flow yet.

## Build & run

```
cd services/payment-service
./gradlew clean build      # compile + tests (Testcontainers Postgres)
./gradlew bootRun          # starts on port 8084
```

## Related

- [OKF index](../index.md)
- [Shared data model](./data-model.md) — the `ledger` table
- [Claim service](./service-claim.md) — approvals that trigger payouts
- [Admin service](./service-admin.md) — operational oversight of transactions
- [Auth & security architecture](./auth-security-architecture.md) — gateway identity injection
