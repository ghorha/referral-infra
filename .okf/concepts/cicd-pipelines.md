---
okf_version: "0.1"
type: concept
id: cicd-pipelines
title: "CI/CD Pipelines (GitHub Actions → GHCR → OCI OKE)"
tags: [ci, cd, github-actions, oci, oke, ghcr, helm]
updated: 2026-08-12
related:
  - ../index.md
  - ./deployment-infrastructure.md
  - ../../DEPLOYMENT.md
---

# CI/CD Pipelines

Each `ghorha/referral-*-service` is its own git repo. Continuous delivery is **per service**, not monorepo.

## Backend path (Java services)

1. **CI** — `ci.yml` in the service repo: Gradle `test` on self-hosted `macOS`/`ARM64`.
2. **CD** — `cd.yml` on push to `main` / `workflow_dispatch`:
   - Calls reusable `ghorha/referral-infra/.github/workflows/service-cd.yml@main`
   - Builds `bootJar`, Docker `linux/arm64`, pushes `ghcr.io/ghorha/<service>:<sha>`
   - Configures kubeconfig via OCI CLI → Phoenix OKE
   - `helm upgrade --install` into namespace `referral`

## Frontend

`referral-frontend` → Vercel (`deploy.yml`), not OKE.

## Manual matrix

`referral-infra` `deploy-all.yml` rolls all Java services (workflow_dispatch).

## Secrets rule

Cross-repo reusable workflows **cannot** use `secrets: inherit`. Callers must map org secrets (`GH_PAT`, `OCI_CLI_*`, `OKE_CLUSTER_OCID`) explicitly. See root `DEPLOYMENT.md`.

## Self-hosted runner caveats
- Isolate `DOCKER_CONFIG` per deploy job; never logout on shared Docker daemon (parallel GHCR 403).
- Persist `KUBECONFIG`, `OCI_CLI_CONFIG_FILE`, and Homebrew PATH for OKE exec auth in Helm.
