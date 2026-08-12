---
okf_version: "0.1"
type: playbook
id: add-new-service
title: "Playbook: Add a New Service/Package to the Monorepo"
tags: [playbook, scaffolding, gradle, gateway, docker-compose, kubernetes, ci]
updated: 2026-07-10
related:
  - ../index.md
  - ../concepts/workspace-structure.md
  - ../concepts/service-api-gateway.md
  - ../concepts/auth-security-architecture.md
  - ../concepts/deployment-infrastructure.md
  - ../concepts/cicd-pipelines.md
---

# Playbook: Add a New Service/Package

There is **no workspace generator** (no nx/turbo). A new backend service is a
self-contained Gradle project that you wire into the orchestration layers by hand.
See [Workspace Structure](../concepts/workspace-structure.md) for why.

## 1. Scaffold the Gradle project

Create `services/<name>-service/` with its own:
- `build.gradle` (copy an existing service, e.g. `user-service`; keep Spring Boot `3.2.0`,
  Java 17, Spring Cloud `2023.0.0` BOM; add only the starters you need),
- `settings.gradle` (`rootProject.name = '<name>-service'`), `gradlew`/`gradlew.bat`, `gradle/`,
- `Dockerfile` (copy an existing one; expose the chosen port),
- `src/main/java/com/referralmarketplace/<name>/<Name>ServiceApplication.java` + layered packages
  (`controller/ service/ repository/ entity/ dto/ config/`),
- `src/main/resources/application.yml` (+ `application-prod.yml`), `SERVER_PORT` env, actuator
  `health,info,metrics,prometheus`.

Pick the **next free port** (current map ends at 8091 — see
[Deployment & Infrastructure](../concepts/deployment-infrastructure.md)); expose endpoints under
`/api/v1/<name>/**`.

## 2. Wire identity & security (REQUIRED)

Downstream services never trust the client. Read the caller as
`@RequestHeader("X-User-ID") UUID userId` (injected by the gateway). If the service is
privileged, add a `SecurityConfig` + `GatewayIdentityFilter` that enforces `X-User-Role`
(copy [admin-service](../concepts/service-admin.md) / [support-service](../concepts/service-support.md)).
See [Auth & Security Architecture](../concepts/auth-security-architecture.md). **Never** re-accept
client-supplied `X-User-ID`.

## 3. Add a gateway route

In `services/api-gateway/src/main/resources/application.yml`, add a route:
```yaml
- id: <name>-service
  uri: ${<NAME>_SERVICE_URL:http://localhost:<port>}
  predicates:
    - Path=/api/v1/<name>/**
```
Decide public vs protected: the gateway auth-filter's allowlist
(`JwtAuthGlobalFilter.isPublic`) defaults everything to protected. Only add to the
allowlist if the route must be anonymous. See [API Gateway](../concepts/service-api-gateway.md).

## 4. Data (if it needs persistence)

Add tables to `migrations.sql/V1__complete_schema.sql` (the single shared schema — see
[Shared Data Model](../concepts/data-model.md)) and remember other services may map the
same tables. Use `ddl-auto: validate` in prod.

## 5. docker-compose

Add a service block to `docker-compose.yml` mirroring an existing one: build context,
`SERVER_PORT`, `SPRING_DATASOURCE_URL`, `DB_USERNAME/PASSWORD`, `JWT_SECRET` (if it validates
tokens), `REDIS_HOST/PORT`, `depends_on` postgres/redis, healthcheck on `/actuator/health`,
and the `referral-network`. Add its URL env var to the `api-gateway` and `orchestration-service` blocks.

## 6. Kubernetes / Helm

Add a manifest under `infrastructure/kubernetes/{dev,staging,production}/` using the
`app: <name>-service` label convention, and **add the service to the
`allow-backends-from-gateway-only` NetworkPolicy** list in
`production/06-network-policies.yaml`. Add values to the Helm chart.

## 7. CI/CD

`build-and-push-images.yml` uses change detection — extend its matrix/paths for the new
service so its image builds and its tests run. See [CI/CD Pipelines](../concepts/cicd-pipelines.md).

## 8. Document it

Add an OKF concept file `.okf/concepts/service-<name>.md` (`type: concept`), link it from
[index.md](../index.md), and note the addition in [log.md](../log.md).
