---
okf_version: "0.1"
type: concept
id: auth-security-architecture
title: "Auth & Security Architecture"
tags: [security, jwt, gateway, httponly-cookies, rbac, magic-link, trust-boundary]
updated: 2026-07-10
related:
  - ../index.md
  - ./service-api-gateway.md
  - ./service-auth.md
  - ./service-admin.md
  - ./service-support.md
  - ./frontend-web.md
  - ../playbooks/verify-auth-end-to-end.md
---

# Auth & Security Architecture

Cross-cutting authentication/authorization model. This is the **trust boundary** of
the platform and was rebuilt in Phase 2 (see [log](../log.md)); the original state had
a complete auth bypass.

## The trust boundary: the API gateway

The [API Gateway](./service-api-gateway.md) is the **only public ingress** and the sole
place identity is established. `JwtAuthGlobalFilter` (a reactive `GlobalFilter`, ordered
right after `TraceIdFilter`) does, on every non-public request:

1. **Validate** the JWT (HMAC‑SHA signature + expiry) with the shared `JWT_SECRET`.
2. **Revocation check** against the Redis blacklist (`token:blacklist:*`, shared with auth-service).
3. **Strip** any client‑supplied `X-User-ID` / `X-User-Role` / `X-User-Email` headers.
4. **Inject** those headers from the *verified* token claims (`sub`, `role`, `email`).
5. **Role‑gate**: `/api/v1/admin/**` → `ADMIN`; `/api/v1/support/**` → `ADMIN|SUPPORT`.

Token is read from the `access_token` **httpOnly cookie** (preferred) or an
`Authorization: Bearer` header. Public allowlist: `/api/v1/auth/**`, `/actuator/**`,
`/api/v1/webhooks/**`, and `GET /api/v1/listings*` (except `/listings/me*`).

## Downstream identity contract

Backend services obtain the caller via the **gateway‑injected header
`X-User-ID`** (`@RequestHeader("X-User-ID") UUID userId`). listing/claim have no auth of
their own and trust the header (safe *only* because the gateway strips client copies).
[admin-service](./service-admin.md) and [support-service](./service-support.md) add a
stateless `SecurityFilterChain` + `GatewayIdentityFilter` that turns `X-User-Role` into a
Spring authority and enforces the role again (defense in depth). This header‑trust model
requires the **K8s NetworkPolicy** (default-deny + gateway-only ingress) to block direct
in-cluster access — see [Deployment & Infrastructure](./deployment-infrastructure.md).

## Tokens & sessions (auth-service)

- **Magic link** (passwordless): a short‑lived (15 min) JWT with a `jti` stored in Redis,
  **consumed once** at `/callback` (replay rejected).
- **Access token** (24h) + **refresh token** (7d), both HMAC‑signed; `sub`=userId, claims
  `email`, `role`. Delivered as **httpOnly, SameSite=Lax cookies** (not in the JSON body).
- **Refresh** (`/api/v1/auth/refresh`) **rotates**: issues a new refresh token and revokes
  the presented one.
- **Logout** revokes access + refresh (Redis blacklist) and clears cookies.
- **Fail-fast**: startup aborts in prod/staging if `JWT_SECRET` is the default or < 32 bytes.

## Frontend (browser)

No tokens in `localStorage`. The axios client is same-origin (`/api/*` proxied to the
gateway by the Next rewrite → first-party cookies) with `withCredentials`, plus a guarded
401→refresh→replay interceptor. Security headers (CSP, HSTS, X-Frame-Options, etc.) are set
in `next.config.js`. See [Frontend Web App](./frontend-web.md).

## Still open

- Per-service JWT validation as full defense-in-depth (currently header-trust + NetworkPolicy).
- CSP still uses `script-src 'unsafe-inline'` (Next hydration) — tighten with nonces.
- Google OAuth (`POST /api/v1/auth/google`) is not implemented; the button is feature-gated off.
- The end-to-end flow must be **smoke-tested live** — see
  [Verify auth end-to-end](../playbooks/verify-auth-end-to-end.md).
