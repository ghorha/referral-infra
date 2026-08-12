---
okf_version: "0.1"
type: concept
id: workspace-structure
title: "Workspace Structure & Build Model"
tags: [monorepo, polyglot, gradle, npm, docker-compose, workspace]
updated: 2026-07-10
related:
  - ../index.md
  - ./deployment-infrastructure.md
  - ./cicd-pipelines.md
  - ./data-model.md
  - ./frontend-web.md
  - ../playbooks/add-new-service.md
  - ../playbooks/local-dev-test-build.md
---

# Workspace Structure & Build Model

## What kind of monorepo this is

A **polyglot, orchestration‑by‑convention monorepo**. There is **no JavaScript
workspace tooling** and **no unified build graph**:

- ❌ No `pnpm-workspace.yaml`, `turbo.json`, `nx.json`, `lerna.json`.
- ❌ No root `package.json`.
- ❌ No root Gradle `settings.gradle` / `build.gradle` (no Gradle multi‑project).

Instead, each unit builds itself and the repo is composed at the orchestration
layer (Docker Compose locally; Helm/Kubernetes in clusters; GitHub Actions in CI).

## Top-level layout

```
referral/
├── services/                 # 12 independent Spring Boot 3.2 / Java 17 Gradle projects
│   ├── api-gateway/          #   each has its OWN gradlew + settings.gradle + build.gradle
│   ├── auth-service/         #   + Dockerfile + src/{main,test}
│   ├── user-service/  listing-service/  claim-service/  payment-service/
│   ├── admin-service/  notification-service/  support-service/
│   └── analytics-service/  audit-service/  orchestration-service/
├── frontend/                 # Next.js 14 App Router — standalone npm project (own package.json)
├── infrastructure/           # helm/ · kubernetes/{dev,staging,production} · terraform/{aws,azure,gcp} · prometheus/
├── migrations.sql/           # V1__complete_schema.sql — the ONE shared PostgreSQL schema
├── docker-compose.yml        # local orchestration of infra + all services + frontend
├── openapi.yaml              # cross-service API spec
├── error-codes.yaml          # shared error-code catalog (mounted into support-service)
├── DESIGN.md                 # design-system source spec
├── check-health.sh           # probes /actuator/health across services
├── start-all.sh              # convenience local startup
├── .github/workflows/        # CI/CD (see cicd-pipelines)
└── .claude/context/          # engineering context + production-readiness audit
```

## Build model per unit

| Unit | Toolchain | Build | Test | Container |
|------|-----------|-------|------|-----------|
| Each `services/*` | Gradle (wrapper), Java 17, Spring Boot 3.2.0, Spring Cloud 2023.0.0 | `./gradlew clean build` / `bootJar` | `./gradlew test` (JUnit 5, Jacoco 90% rule) | per-service `Dockerfile` |
| `frontend/` | npm, Node 18+, Next 14.0.4, TS 5 | `npm run build` (type-check + ESLint enforced) | `npm test` (Jest), `npm run test:e2e/:smoke` (Playwright) | `frontend/Dockerfile` |

There is **no single command that builds the whole repo**. Build units individually,
or bring the whole system up with `docker-compose up` (each image builds from its
context). See [Run local dev, tests & builds](../playbooks/local-dev-test-build.md).

## Shared surfaces (the real "glue")

Because there is no shared code module, cross-cutting contracts live in specific places:

- **Database** — one shared PostgreSQL database (`referral_marketplace`) defined by
  [`migrations.sql/V1__complete_schema.sql`](../../migrations.sql). Multiple services
  map the same tables with their own JPA entities. See [Shared Data Model](./data-model.md).
- **Identity contract** — downstream services read the gateway‑injected `X-User-ID` /
  `X-User-Role` / `X-User-Email` headers. See [Auth & Security Architecture](./auth-security-architecture.md).
- **API spec** — root `openapi.yaml`; error codes in `error-codes.yaml`.
- **Config** — env vars wired per service in `docker-compose.yml` and
  `infrastructure/kubernetes/*/02-configmap.yaml` + secrets.

## Java package & layer convention

Base package `com.referralmarketplace.<service>` (gateway uses `...gateway`). Layers:
`controller/ · service/ · repository/ · entity/ · dto/ · config/ · security/ · filter/`.

## Conventions when adding units

See the [Add a new service](../playbooks/add-new-service.md) playbook — a new service
must be a self-contained Gradle project, get a gateway route, a docker-compose entry,
a K8s manifest, and CI coverage; it does not "join" a workspace graph.
