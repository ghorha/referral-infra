---
okf_version: "0.1"
type: concept
id: service-auth
title: "Auth Service"
tags: [auth, jwt, magic-link, cookies, redis, postgres, identity, spring-boot]
port: 8081
updated: 2026-07-10
related:
  - ../index.md
  - ./auth-security-architecture.md
  - ./data-model.md
  - ./service-api-gateway.md
  - ./service-user.md
  - ./frontend-web.md
  - ../playbooks/verify-auth-end-to-end.md
---

# Auth Service

## Purpose
The Auth Service is the identity authority for the Vouch marketplace. It authenticates users
via passwordless **magic links** delivered by email, mints signed JWT access/refresh tokens,
and returns them as **httpOnly cookies** so the browser never touches raw tokens. It owns the
canonical `users` and `devices` records, tracks device recognition for each login, exposes the
current-user profile endpoints, and provides phone (OTP) verification. Token lifecycle —
issuance, refresh rotation, and revocation — is backed by Redis.

## Runtime
- **Port**: 8081
- **Base package**: `com.referralmarketplace.auth`
- **Stack**: Spring Boot 3.2.0 / Java 17
- **Directory**: `services/auth-service`
- Postgres (`referral_marketplace`) via Spring Data JPA + Flyway; Redis for magic-link jti,
  token blacklist, and OTP state.

## API
All routes are prefixed with `/api/v1`. `/auth/**` is public (pre-authentication); `/me` requires
an authenticated identity.

| Method | Path                     | Purpose |
|--------|--------------------------|---------|
| POST   | `/api/v1/auth/magic-link`| Issue a single-use magic-link token and email it to the address. |
| POST   | `/api/v1/auth/callback`  | Consume the magic-link token, log in, set httpOnly `access_token`/`refresh_token` cookies. |
| POST   | `/api/v1/auth/refresh`   | Rotate the refresh token (cookie or body) and set a new access-token cookie. |
| POST   | `/api/v1/auth/logout`    | Revoke presented access/refresh tokens in Redis and clear the cookies. |
| GET    | `/api/v1/me`             | Return the current user's profile. |
| PATCH  | `/api/v1/me`             | Update the current user's profile fields. |

## Data
Owns and reads (Flyway `db/migration`, shared `referral_marketplace` Postgres):
- `users` (`User`) — email/phone verification, location, role (`POSTER`/`SEEKER`/`SUPPORT`/`ADMIN`),
  account status, Auth0 linkage. **Canonical user table** for the platform.
- `devices` (`Device`) — per-user device fingerprints for device-recognition on login.
- `auth0_sync_events` (`Auth0SyncEvent`) — audit of Auth0↔platform sync events (JSONB payload).
- `audit_logs` (`AuditLog`), `user_stats` (`UserStats`), `notification_settings` — auxiliary tables.

See [data model](./data-model.md) for the shared schema and which services read these tables.

## Integrations
- **Redis** (`spring-boot-starter-data-redis`) — magic-link jti store (single-use), token blacklist
  (`TokenBlacklistService`), OTP cache, and auth rate limiting.
- **JWT** — `io.jsonwebtoken:jjwt` 0.12.3, HMAC-signed with the shared `JWT_SECRET`.
- **Mailgun** (`mailgun-java`) — magic-link email; DISABLED locally via `MAILGUN_ENABLED=false`
  (magic link is logged instead).
- **Twilio** (`twilio` SDK) — phone-verification SMS; stubbed off via
  `phone.verification.enabled=false` (OTP logged to console in dev).
- Observability: Micrometer/Prometheus + OpenTelemetry OTLP tracing; Unleash feature flags.

## Inter-service
Reached only **through the API gateway**, which validates the JWT and injects trusted
`X-User-ID` / `X-User-Role` / `X-User-Email` headers (stripping any client copies). Auth Service
itself is the token issuer, so downstream services trust tokens it mints. It calls no other
service; it talks only to Postgres and Redis. See [API gateway](./service-api-gateway.md) and
[user service](./service-user.md).

## Security
- Stateless (`SessionCreationPolicy.STATELESS`), CSRF disabled, CORS restricted to known origins.
- `JwtAuthenticationFilter` reads the JWT from the `Authorization: Bearer` header or the httpOnly
  `access_token` cookie, validating signature + revocation before setting the security context;
  `@AuthenticationPrincipal UUID userId` on `/me` is the resolved identity.
- **httpOnly, SameSite=Lax cookies** (Secure toggled on in prod via `app.cookie.secure`); tokens are
  never in the response body.
- **Single-use magic links** — jti persisted in Redis on issue and atomically deleted on callback;
  replays are rejected.
- **Refresh rotation** — refresh token is replaced on every `/refresh`.
- **Revocation** — logout blacklists tokens in Redis (`TokenBlacklistService`).
- **`JwtSecretValidator`** fails startup in prod/staging if `JWT_SECRET` is the built-in default or
  under 32 bytes (loud warning in local dev).

## Build & run
```
cd services/auth-service
./gradlew clean build
./gradlew bootRun        # starts on :8081
```

## Related
- [OKF index](../index.md)
- [Auth security architecture](./auth-security-architecture.md)
- [Shared data model](./data-model.md)
- [API gateway service](./service-api-gateway.md)
- [User service](./service-user.md)
- [Frontend web app](./frontend-web.md)
- [Playbook: verify auth end-to-end](../playbooks/verify-auth-end-to-end.md)
