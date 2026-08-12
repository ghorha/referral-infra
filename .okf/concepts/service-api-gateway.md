---
okf_version: "0.1"
type: concept
id: service-api-gateway
title: "API Gateway Service"
tags: [gateway, spring-cloud-gateway, webflux, jwt, trust-boundary, rate-limiting, routing, cors]
port: 8080
updated: 2026-07-10
related:
  - ../index.md
  - ./workspace-structure.md
  - ./auth-security-architecture.md
  - ./cicd-pipelines.md
  - ./deployment-infrastructure.md
  - ./service-auth.md
  - ./service-orchestration.md
  - ../playbooks/verify-auth-end-to-end.md
---

# API Gateway Service

## Purpose
The API Gateway is the single public ingress for the entire Vouch platform and the
security trust boundary in front of every microservice. Built on reactive Spring
Cloud Gateway (WebFlux), it terminates client traffic, validates JWTs, strips any
client-supplied identity headers and re-injects trusted `X-User-ID` / `X-User-Role` /
`X-User-Email` headers derived from the token's claims, enforces roles for privileged
areas, applies Redis-backed rate limiting and CORS, and routes each request to the
owning downstream service. It has no database and no `/api/v1` business endpoints of
its own.

## Runtime
- **Port**: 8080 (`SERVER_PORT`)
- **Base package**: `com.referralmarketplace.gateway`
- **Stack**: Spring Boot 3.2.0 / Spring Cloud 2023.0.0 / Java 17 (reactive WebFlux)
- **Directory**: `services/api-gateway`
- **Entry point**: `GatewayApplication`

## API
The gateway exposes no `/api/v1/**` controllers. Its "API" is the set of routes it
proxies (defined in `application.yml`) plus operational actuator endpoints.

| Method | Path | Purpose |
| --- | --- | --- |
| ALL | `/actuator/health`, `/actuator/info`, `/actuator/metrics`, `/actuator/prometheus`, `/actuator/gateway` | Health, metrics, Prometheus scrape, gateway route introspection (public passthrough) |

### Routes (proxy targets)
| Path predicate | Route id → upstream |
| --- | --- |
| `/api/v1/auth/**` | auth-service (8081) — rate limited 5/10 per IP |
| `/api/v1/me/**` | auth-service (8081) — current-user profile |
| `/api/v1/users/**`, `/api/v1/businesses/**`, `/api/v1/programs/**` | user-service (8085) |
| `/api/v1/listings/**` | listing-service (8082) |
| `/api/v1/claims/**`, `/api/v1/files/**` | claim-service (8083) — rate limited 3/5 per user |
| `/api/v1/payments/**`, `/api/v1/webhooks/**` | payment-service (8084) |
| `/api/v1/admin/**` | admin-service (8086) — ADMIN role gated |
| `/api/v1/notifications/**`, `/ws/**` | notification-service (8087) — includes WebSocket |
| `/api/v1/support/**` | support-service (8088) — ADMIN/SUPPORT role gated |
| `/api/v1/analytics/**` | analytics-service (8089) |
| `/api/v1/audit/**` | audit-service (8090) |
| `/api/v1/orchestration/**` | orchestration-service (8091) |

## Data
None. The gateway owns no tables and holds no persistent domain state. Its only
stateful dependency is Redis, used for rate-limiter buckets and the shared JWT
revocation blacklist (see the [shared data model](./data-model.md) for what the
downstream services persist).

## Integrations
- **Redis** (`spring-boot-starter-data-redis-reactive`, `REDIS_HOST`/`REDIS_PORT`) —
  `RequestRateLimiter` token buckets and the `token:blacklist:*` revocation keys that
  mirror auth-service's `TokenBlacklistService`.
- **jjwt 0.12.3** — HMAC-SHA JWT validation at the trust boundary using the shared
  `JWT_SECRET` (must equal auth-service's signing key).
- **Resilience4j** — circuit breaker / time limiter config for upstream calls; routes
  carry a default `Retry` filter (BAD_GATEWAY, SERVICE_UNAVAILABLE) with backoff.
- **Micrometer + OpenTelemetry (OTLP)** — Prometheus metrics and W3C trace propagation.
- No Feign clients; routing is declarative via Spring Cloud Gateway route predicates.

## Inter-service
Every external request enters here; the gateway is the only component exposed to the
public internet. It forwards to the twelve downstream services listed above over the
internal `referral-network` using the `*_SERVICE_URL` environment variables. It never
calls a service on the client's behalf beyond proxying, and downstream services trust
the injected identity headers instead of re-validating the JWT.

## Security
The `JwtAuthGlobalFilter` (order `HIGHEST_PRECEDENCE + 100`, just after `TraceIdFilter`)
is the platform's real authentication layer. On every non-public request it:
1. strips any client-supplied `X-User-ID` / `X-User-Role` / `X-User-Email` headers so
   they can never be spoofed;
2. extracts the token from the `access_token` httpOnly cookie or `Authorization: Bearer`
   header and validates signature + expiry, rejecting non-access tokens (any `type`
   claim);
3. checks the Redis revocation blacklist (per-token suffix key + per-user issued-at
   cutoff), failing open on Redis errors so an outage degrades revocation rather than
   blocking all traffic;
4. enforces roles at the boundary — `/api/v1/admin/**` requires `ADMIN`,
   `/api/v1/support/**` requires `ADMIN` or `SUPPORT`;
5. re-injects the verified `X-User-ID` / `X-User-Role` / `X-User-Email` headers from the
   token claims before routing.

Public allowlist (no auth, identity still stripped): `/api/v1/auth/**`, `/actuator/**`,
`/api/v1/webhooks/**` (external provider callbacks), CORS `OPTIONS` preflight, and
`GET /api/v1/listings**` except `/api/v1/listings/me*` (public marketplace browse).

Supporting global filters: `TraceIdFilter` (mints/propagates `X-Trace-ID`),
`SecurityHeadersFilter` (OWASP headers — CSP, X-Frame-Options DENY, HSTS in prod,
no-store on auth/payments), and `LoggingFilter` (request/response timing). CORS is
configured globally for `http://localhost:3000` and `https://referralmarketplace.com`
with credentials allowed; the identity headers are deliberately excluded from
`allowedHeaders`. See [auth & security architecture](./auth-security-architecture.md).

## Build & run
```bash
cd services/api-gateway
./gradlew clean build      # build + tests (Jacoco, 90% target)
./gradlew bootRun          # runs on port 8080
```
Requires Redis reachable and `JWT_SECRET` matching auth-service. In Docker Compose the
service is `api-gateway` with the `*_SERVICE_URL` env vars pointing at each upstream.

## Related
- [OKF index](../index.md)
- [Workspace structure](./workspace-structure.md)
- [Auth & security architecture](./auth-security-architecture.md)
- [CI/CD pipelines](./cicd-pipelines.md)
- [Deployment & infrastructure](./deployment-infrastructure.md)
- [Auth service](./service-auth.md)
- [Orchestration service](./service-orchestration.md)
- [Playbook: verify auth end-to-end](../playbooks/verify-auth-end-to-end.md)
- [Shared data model](./data-model.md)
