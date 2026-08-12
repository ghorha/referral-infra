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
