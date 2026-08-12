---
okf_version: "0.1"
type: index
id: root-index
title: "Vouch — Referral Exchange Hub · OKF Bundle"
tags: [monorepo, polyglot, spring-boot, nextjs, microservices, referral-marketplace]
updated: 2026-07-10
related:
  - ./log.md
  - ./concepts/workspace-structure.md
  - ./concepts/deployment-infrastructure.md
  - ./concepts/cicd-pipelines.md
  - ./concepts/auth-security-architecture.md
  - ./concepts/data-model.md
---

# Vouch — Referral Exchange Hub

Open Knowledge Format (v0.1) bundle for the **Vouch** monorepo: a peer-to-peer
referral‑code marketplace. Code owners ("posters") monetize referral codes;
"seekers" find and use them; trust is backed by escrow, OCR proof verification,
reviews, and a support/dispute workflow.

> ⚠️ **Reality check.** The repo's `README.md`, `docs/`, and `.cursor/*.md` claim
> "100% complete / production ready". That is aspirational. See
> [Production Readiness Audit](../.claude/context/PRODUCTION_READINESS_AUDIT.md)
> and [log.md](./log.md) for the true state and the work completed in Phase 1
> (design + integration) and Phase 2 (auth/security).

## Monorepo shape (important)

This is a **polyglot, orchestration‑by‑convention monorepo**, NOT a JS‑workspace
monorepo. There is **no pnpm / turborepo / nx / lerna**, no root `package.json`,
and **no root Gradle multi‑project** (`settings.gradle`). Each backend service is
a fully independent Gradle project; the frontend is a standalone npm project.
The "workspace" is glued together by convention. See
[Workspace Structure](./concepts/workspace-structure.md).

```
referral/
├── services/            # 12 independent Spring Boot 3.2 / Java 17 Gradle services
├── frontend/            # Next.js 14 App Router app (standalone npm project)
├── infrastructure/      # helm/ · kubernetes/ · terraform/ · prometheus/
├── migrations.sql/      # the single shared PostgreSQL schema (V1__complete_schema.sql)
├── docker-compose.yml   # local orchestration of the whole stack
├── openapi.yaml         # API spec · error-codes.yaml · check-health.sh · start-all.sh
└── .github/workflows/   # 9 GitHub Actions pipelines (CI + deploy)
```

## High-level architecture

```
Browser (Next.js :3000)
   │  same-origin /api/v1/*  (Next rewrite → gateway); httpOnly cookie auth
   ▼
API Gateway (:8080)  — Spring Cloud Gateway (reactive)
   │  JwtAuthGlobalFilter: validate JWT · strip+inject X-User-ID/Role/Email · role-gate · rate-limit
   ├── auth (8081) ── PostgreSQL + Redis   (magic-link, JWT, devices, cookies)
   ├── orchestration (8091) ─ Feign ─► user / listing / claim   (BFF)
   └── user 8085 · listing 8082 · claim 8083 · payment 8084 · admin 8086 ·
       notification 8087 · support 8088 · analytics 8089 · audit 8090
                    │
       Shared PostgreSQL (:5432)  +  Redis (:6379)
       External (disabled in dev): Stripe · Mailgun · Google Vision · Twilio
       Observability: Prometheus 9090 · Grafana 3003 · Jaeger 16686
```

## Knowledge graph

### Workspace, infrastructure & delivery
- [Workspace Structure](./concepts/workspace-structure.md) — polyglot layout, build model, shared surfaces
- [Deployment & Infrastructure](./concepts/deployment-infrastructure.md) — docker-compose, Helm, K8s, Terraform, observability
- [CI/CD Pipelines](./concepts/cicd-pipelines.md) — the 9 GitHub Actions workflows

### Cross-cutting architecture
- [Auth & Security Architecture](./concepts/auth-security-architecture.md) — the gateway trust boundary, JWT, httpOnly cookies, roles
- [Shared Data Model](./concepts/data-model.md) — the single PostgreSQL schema shared by all services

### Frontend
- [Frontend Web App](./concepts/frontend-web.md) — Next.js 14 app, routes, cookie auth, API client
- [Design System (Vouch 2.0)](./concepts/design-system.md) — Material‑3 tokens, `components/ui`, type/motion

### Backend services (each an independent Gradle project)
- [API Gateway](./concepts/service-api-gateway.md) — :8080, the only public ingress
- [Auth Service](./concepts/service-auth.md) — :8081
- [User Service](./concepts/service-user.md) — :8085
- [Listing Service](./concepts/service-listing.md) — :8082
- [Claim Service](./concepts/service-claim.md) — :8083
- [Payment Service](./concepts/service-payment.md) — :8084
- [Admin Service](./concepts/service-admin.md) — :8086
- [Notification Service](./concepts/service-notification.md) — :8087
- [Support Service](./concepts/service-support.md) — :8088
- [Analytics Service](./concepts/service-analytics.md) — :8089
- [Audit Service](./concepts/service-audit.md) — :8090
- [Orchestration Service (BFF)](./concepts/service-orchestration.md) — :8091

### Playbooks
- [Add a new service to the monorepo](./playbooks/add-new-service.md)
- [Run local dev, tests & builds](./playbooks/local-dev-test-build.md)
- [Verify auth end-to-end (smoke test)](./playbooks/verify-auth-end-to-end.md)

## Doc sync rule (mandatory)

When code, APIs, config, ports, layout, or behavior in this repo change, update:

1. Root `README.md` — human run/test/usage guidance
2. This `.okf/` tree — agent concepts/index, plus a dated note in `log.md`

Do not ship code-only changes when those surfaces moved.

