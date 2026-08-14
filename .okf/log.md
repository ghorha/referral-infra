---
okf_version: "0.1"
type: log
id: okf-log
title: "OKF Change Ledger"
tags: [ledger, changelog]
updated: 2026-07-10
related:
  - ./index.md
---

# OKF Change Ledger

Chronological record of changes to this knowledge bundle and material changes to
the codebase it describes. Newest first.

- 2026-08-13: Wired the new `referral-ai-service` (AI orchestrator, port 8092)
  into deploy. Added it to `deploy-all.yml`'s rollout matrix and created
  `deploy/values/referral-ai-service.yaml` (stateless — no `referral-db`/
  `referral-jwt`; `envFrom: [fs-ai-keys]` for the provider API keys, which ESO
  already syncs from OCI Vault per `deploy/secrets/external-secrets.yaml`:
  `OPENAI_API_KEY` / `ANTHROPIC_API_KEY` / `GEMINI_API_KEY`). Added a row to the
  service/port/secrets table in `deploy/README.md`. No new secret plumbing was
  needed — the `fs-ai-keys` ExternalSecret already existed for this purpose.

## 2026-07-10 — OKF bundle initialized

- Initialized the `.okf/` Open Knowledge Format bundle (v0.1) at the workspace root.
- Created the entry point [index.md](./index.md) and this ledger.
- Authored cross-cutting concepts: [Workspace Structure](./concepts/workspace-structure.md),
  [Deployment & Infrastructure](./concepts/deployment-infrastructure.md),
  [CI/CD Pipelines](./concepts/cicd-pipelines.md),
  [Auth & Security Architecture](./concepts/auth-security-architecture.md),
  [Shared Data Model](./concepts/data-model.md),
  [Frontend Web App](./concepts/frontend-web.md),
  [Design System](./concepts/design-system.md).
- Authored one `type: concept` file per backend service (12) under `concepts/`.
- Authored playbooks: [add a new service](./playbooks/add-new-service.md),
  [local dev/test/build](./playbooks/local-dev-test-build.md),
  [verify auth end-to-end](./playbooks/verify-auth-end-to-end.md).
- Recorded the true project state: the "100% complete" marketing docs are aspirational;
  ground truth is captured in the [Production Readiness Audit](../.claude/context/PRODUCTION_READINESS_AUDIT.md).

### Codebase context captured at initialization

The bundle reflects work already completed on branch `feat/vouch-redesign-auth-hardening`
(9 commits, uncommitted only: `.claude/settings.json`):

- **Phase 1 — frontend design + integration.** New "Vouch 2.0" Material‑3 design system
  and shared `components/ui` library; all 26 pages migrated and wired to real endpoints;
  fabricated data removed; 11 adversarially‑confirmed bugs fixed.
- **Phase 2 — auth/security.** Gateway `JwtAuthGlobalFilter` (validate JWT, strip+inject
  `X-User-ID/Role/Email`, role‑gate `/admin` & `/support`, revocation check); httpOnly cookie
  tokens; single‑use magic links; logout revocation; refresh‑token rotation; admin/support
  gateway‑identity `SecurityFilterChain`; CSP/HSTS; K8s NetworkPolicies.

### Verification status

All touched services compile (`./gradlew compileJava`); the frontend builds green
(`npm run build`, type‑check + ESLint enforced, 26/26 pages). The **runtime auth flow
still requires a live smoke test** on the full stack — see
[Verify auth end-to-end](./playbooks/verify-auth-end-to-end.md).

### Still open (deferred / external)

External‑credential blockers (Stripe, Mailgun, Google OAuth, Google Vision OCR), the
`/claims` vs `/transactions` domain product decision, and the live auth smoke test.

- 2026-08-12: Added mandatory README + .okf doc-sync rule.

- 2026-08-12: SECURITY — Secrets manifests renamed to *.example.yaml; staging NetworkPolicy; API CIDR default not 0.0.0.0/0.

- 2026-08-12: CI/CD — Document GitHub → GHCR → OCI OKE path; note that cross-repo `service-cd` callers must map secrets explicitly (not `secrets: inherit`).
- 2026-08-12: CI/CD harden — default checkout for caller, GHCR via PAT, helm --force-conflicts, per-job kubeconfig, deploy-service.yml.

- 2026-08-12: CD — ensure Homebrew `/opt/homebrew/bin` is on PATH so `oci` is found on self-hosted macOS runners.
- 2026-08-12b: CI/CD — green unit tests / workflows; CD secrets + helm conflict handling.
- 2026-08-12: CD — services dispatch deploy-service.yml on infra so OCI secrets resolve from referral-infra.
- 2026-08-12: CD — validate service ref is main or sha before checkout.
- 2026-08-12: CD — pass KUBECONFIG/OCI_CLI_CONFIG_FILE/PATH to helm step for OKE exec auth.
- 2026-08-12: CD — isolate DOCKER_CONFIG per job; no docker logout (fixes parallel GHCR 403).
- 2026-08-12: CD — DOCKER_CONFIG keyed by service+run_id+attempt for matrix safety.
- 2026-08-12: Add fleet-status dashboard (branch drift + undeployed main vs OKE).

- 2026-08-13: CI/CD — bumped `service-cd.yml` from JDK 17/no-pinned-Gradle to
  Java 21 / Gradle 8.10 (matching every service repo's own migration), and
  removed the risky "fall back to system `gradle`" branch in the bootJar
  step (now hard-fails with `::error::` if a service's `./gradlew` is
  missing, per this file's own "CI using wrong Gradle" troubleshooting
  note). Updated the header comment, `README.md`, and `DEPLOYMENT.md` to
  reflect that service repos now call this workflow directly with
  `secrets: inherit` instead of dispatching `deploy-service.yml` — verified
  via `gh api orgs/ghorha/actions/secrets/<NAME>` that `GH_PAT` and every
  `OCI_CLI_*`/`OKE_CLUSTER_OCID` secret are org-level with `visibility: all`,
  which is what makes cross-repo `secrets: inherit` resolve correctly (the
  two prior attempts at this exact pattern, `732d23c` and `d87e0b1`, predated
  that and failed with empty secrets). `deploy-service.yml`/`deploy-all.yml`
  are unchanged and remain the fallback path. No changes to the OCI/Docker/
  Helm steps themselves, and nothing touching the runner outside each job's
  own scoped temp paths — this runner is shared with the `piraho` org.

- 2026-08-13c: CI/CD HARDENING — `service-cd.yml`'s `Build and push image
(linux/arm64)` step (`docker/build-push-action@v6`) hung indefinitely on
  the shared self-hosted runner after the Java 21/Gradle 8.10 migration was
  pushed across all 12 service repos at once — the same failure mode
  observed independently in each service's own `ci.yml` `docker build`
  step, confirming a wedged Docker daemon on the runner host rather than
  anything specific to this workflow. With only 2 self-hosted runners for
  the whole org, one stuck job starves every other queued CI/CD run for
  hours. Added `timeout-minutes: 30` to the `build-and-deploy` job and
  `timeout-minutes: 15` to the image build/push step specifically. Also
  gave the job an explicit `name:` including `${{ inputs.service }}` so the
  runner's terminal log and the Actions UI clearly show which service is
  deploying (previously just "deploy / build-and-deploy" with no service
  identity visible without opening the run).
