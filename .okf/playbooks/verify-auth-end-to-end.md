---
okf_version: "0.1"
type: playbook
id: verify-auth-end-to-end
title: "Playbook: Verify Auth End-to-End (Live Smoke Test)"
tags: [playbook, security, smoke-test, jwt, cookies, verification]
updated: 2026-07-10
related:
  - ../index.md
  - ../concepts/auth-security-architecture.md
  - ../concepts/service-api-gateway.md
  - ../concepts/service-auth.md
  - ../playbooks/local-dev-test-build.md
---

# Playbook: Verify Auth End-to-End (Live Smoke Test)

The Phase 2 auth rework compiles/builds green, but the **runtime flow** (cookie
round-trips, gateway→downstream identity, single-use links, revocation) can only be
confirmed against the full running stack. Run this before trusting auth in any
environment. Concepts: [Auth & Security Architecture](../concepts/auth-security-architecture.md).

## Setup

```bash
export JWT_SECRET="local-dev-secret-at-least-32-bytes-long!!"   # gateway + auth MUST share it
docker-compose up -d && ./check-health.sh
```

## Checklist

1. **Magic-link login.** Request a link (`POST /api/v1/auth/magic-link`), open the callback
   (`/auth/callback?token=…`). In dev, Mailgun is off — grab the link from the auth-service logs.
   ✅ Expect: `access_token` + `refresh_token` **httpOnly** cookies set; you land authenticated.
2. **Single-use link.** Re-open the same magic link.
   ✅ Expect: **rejected** ("already used / expired") — the `jti` was consumed in Redis.
3. **Cookie-authenticated call.** Load `/dashboard` (calls `/api/v1/listings/me/listings`, `/claims/me`).
   ✅ Expect: works via cookie. Now delete the cookie / call with none → **401**.
4. **Identity cannot be spoofed.** Send `X-User-ID: <another-user-uuid>` from the browser/curl.
   ✅ Expect: gateway **strips** it; you still act as yourself (not the victim).
5. **Role gate.** As a non-admin, hit `GET /api/v1/admin/dashboard`.
   ✅ Expect: **403** at the gateway. Repeat for `/api/v1/support/**` as a non-support/non-admin.
6. **Logout revocation.** Logout, then reuse the pre-logout access token directly against the gateway.
   ✅ Expect: **401** (token blacklisted in Redis).
7. **Refresh rotation.** Call `POST /api/v1/auth/refresh`; capture the new refresh cookie; then try
   the OLD refresh token again.
   ✅ Expect: new access+refresh issued; the old refresh token is **rejected** (revoked).
8. **Silent refresh.** Let the access token expire mid-session (or delete just the `access_token`
   cookie) and make a protected request from the app.
   ✅ Expect: the client's 401 interceptor silently refreshes and replays once; no bounce to login
   for the public `/api/v1/me` probe.

## If a step fails

- Steps 1/3 failing with 401 everywhere → check `JWT_SECRET` is identical for gateway + auth
  (compose env), and that the gateway can reach Redis.
- Step 4 not stripping → confirm `JwtAuthGlobalFilter` is active (it's a `GlobalFilter`, ordered
  after `TraceIdFilter`) and CORS no longer allow-lists `X-User-ID`.
- Steps 2/6/7 failing → verify Redis connectivity from both gateway and auth-service.

See [API Gateway](../concepts/service-api-gateway.md) and [Auth Service](../concepts/service-auth.md).
