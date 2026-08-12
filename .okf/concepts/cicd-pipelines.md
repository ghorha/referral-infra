---
okf_version: "0.1"
type: concept
id: cicd-pipelines
title: "CI/CD Pipelines (GitHub Actions)"
tags: [ci, cd, github-actions, blue-green, gradle, eslint, deployment]
updated: 2026-07-10
related:
  - ../index.md
  - ./workspace-structure.md
  - ./deployment-infrastructure.md
  - ../playbooks/local-dev-test-build.md
---

# CI/CD Pipelines (GitHub Actions)

Nine workflows under `.github/workflows/`. Because there is no unified build graph
(see [Workspace Structure](./workspace-structure.md)), pipelines operate per-unit /
via change detection rather than a single monorepo task runner.

| Workflow | Trigger | Purpose |
|----------|---------|---------|
| `ci.yml` | push (all branches) + PR → main/staging | **Lint → build → merge-gate.** Checkstyle (backend) + ESLint (frontend) must pass, then Gradle + `next build`. `merge-gate-check` job gates merges. |
| `ci-test-all-services.yml` | PR + push | Test matrix across services + a `test-summary` job. |
| `build-and-push-images.yml` | push + PR + manual | **Change detection → build/push Docker images → update manifests.** Only rebuilds changed units. |
| `deploy-to-dev.yml` | push + manual | Deploy to the dev environment. |
| `deploy-to-staging.yml` | push + manual | Deploy to staging. |
| `deploy-to-production.yml` | push + manual | Deploy to production (with pre-deploy checks). |
| `staging.yml` | push | Regression → build/deploy → smoke → rollback-on-failure. |
| `production.yml` | push | Full **blue-green** release: manual approval → regression → build/backup → deploy-green → pre-switch smoke → traffic-switch → post-deploy verify → cleanup-blue. |
| `smoke-tests-daily.yml` | schedule (cron) + manual | Daily smoke tests. |

## Pipeline notes

- **Lint is enforced.** The frontend `next.config.js` sets `eslint.ignoreDuringBuilds:false`,
  so `next build` fails on ESLint errors (currently zero). Backend runs Checkstyle via
  `./gradlew check`.
- **Change detection** in `build-and-push-images.yml` is how a multi-unit repo avoids
  rebuilding everything on every change.
- **Environments:** dev → staging → production, promoted through the deploy workflows;
  production uses blue-green with a manual approval gate.

## Gaps to address (from the audit)

- Add **gitleaks** (secret scanning) to CI.
- Keep the frontend `tsc`/lint/build gates green (they are, as of 2026-07-10).
- Wire Jacoco's 90% coverage rule into `check` if coverage enforcement is desired
  (currently defined but not gating).

See [Deployment & Infrastructure](./deployment-infrastructure.md) for what these
pipelines deploy onto, and [local dev/test/build](../playbooks/local-dev-test-build.md)
to reproduce CI steps locally.
