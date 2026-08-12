---
okf_version: "0.1"
type: playbook
id: local-dev-test-build
title: "Playbook: Local Dev, Tests & Builds Across the Workspace"
tags: [playbook, docker-compose, gradle, npm, testing, build]
updated: 2026-07-10
related:
  - ../index.md
  - ../concepts/workspace-structure.md
  - ../concepts/deployment-infrastructure.md
  - ../concepts/frontend-web.md
  - ../concepts/cicd-pipelines.md
---

# Playbook: Local Dev, Tests & Builds

There is **no single "build everything" command** (no nx/turbo). You either bring up
the whole stack with Docker Compose, or work on units individually. See
[Workspace Structure](../concepts/workspace-structure.md).

## Whole stack (recommended for integration)

```bash
# from repo root — ensure JWT_SECRET is exported (compose passes it to gateway + auth)
export JWT_SECRET="local-dev-secret-at-least-32-bytes-long!!"
docker-compose up -d          # postgres, redis, jaeger, prometheus, grafana, 12 services, frontend
./check-health.sh             # probes /actuator/health across services
```
- Frontend → http://localhost:3002 · Gateway → http://localhost:8080
- Jaeger UI 16686 · Prometheus 9090 · Grafana 3003 (admin/admin)
- Postgres auto-initializes from `migrations.sql/V1__complete_schema.sql`.
- Tear down: `docker-compose down` (add `-v` to wipe volumes).

External integrations (Stripe/Mailgun/Twilio/OCR) are **disabled** in dev via
`*_ENABLED=false` — magic-link emails and OCR return stubs/log to console.

## A single backend service

```bash
cd services/<name>-service
./gradlew clean build          # compile + test + jar
./gradlew bootRun              # run locally (needs postgres/redis reachable)
./gradlew compileJava -x test  # fast compile-only check
./gradlew test                 # unit tests (JUnit 5); report in build/reports/tests
./gradlew check                # + Checkstyle (this is what CI lints)
```
Ports: gateway 8080; auth 8081; listing 8082; claim 8083; payment 8084; user 8085;
admin 8086; notification 8087; support 8088; analytics 8089; audit 8090; orchestration 8091.

## Frontend

```bash
cd frontend
npm install
npm run dev                    # http://localhost:3000 (expects gateway on :8080)
npm run build                  # production build — type-check + ESLint ENFORCED (CI gate)
npx tsc --noEmit               # type-check only
npm run lint                   # ESLint only
npm test                       # Jest unit tests
npm run test:e2e               # Playwright e2e   (npm run test:smoke for @smoke only)
```

## Reproducing CI locally

CI (`ci.yml`) = lint → build. Reproduce: backend `./gradlew check` per service;
frontend `npm run lint && npm run build`. Image builds mirror each `Dockerfile`. See
[CI/CD Pipelines](../concepts/cicd-pipelines.md).

## Verifying auth changes

Build passing is necessary but not sufficient for auth — the cookie/gateway flow needs a
running stack. Run the [Verify auth end-to-end](./verify-auth-end-to-end.md) playbook.
