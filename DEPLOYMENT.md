# Referral deployment (Phoenix OKE + Neon + Vercel)

Continuous delivery for Vouch backends:

```
push to main (service repo)
  → GitHub Actions ci.yml (unit tests, Java 21 / Gradle 8.10)
  → GitHub Actions cd.yml
       → uses: ghorha/referral-infra/.github/workflows/service-cd.yml@main
         with: { service, port }
         secrets: inherit
            → reusable service-cd.yml
                 → ./gradlew bootJar (Java 21 / Gradle 8.10)
                 → docker build/push linux/arm64 → ghcr.io/ghorha/<service>:<sha>
                 → oci ce cluster create-kubeconfig (Phoenix OKE)
                 → helm upgrade --install -n referral (--force-conflicts)
```

Each service repo's `cd.yml` calls this repo's reusable workflow directly with
`secrets: inherit` — viable now that `GH_PAT` and every `OCI_CLI_*`/
`OKE_CLUSTER_OCID` secret are **organization-level secrets with
`visibility: all`** (confirmed via `gh api orgs/ghorha/actions/secrets`), so
they resolve for any repo in the org, including cross-repo `workflow_call`.

**Fallback (manual dispatch):** `deploy-service.yml` / `deploy-all.yml` on
this repo still work unchanged via `workflow_dispatch` and don't depend on
cross-repo secret resolution at all (they run entirely inside this repo, with
GH_PAT only needed by whoever/whatever triggers the dispatch). Use them if
`secrets: inherit` ever fails to resolve secrets across a repo boundary
again:

```bash
gh workflow run deploy-service.yml --repo ghorha/referral-infra \
  -f service=<name> -f port=<port> -f ref=<sha-or-main>
```

Region: **us-phoenix-1**. Frontend deploys separately to **Vercel** (`referral-frontend` `deploy.yml`), not OKE.

## Org secrets (required)

Set on the `ghorha` GitHub org (visibility: all repos):

| Secret                | Purpose                               |
| --------------------- | ------------------------------------- |
| `GH_PAT`              | Checkout private repos + push to GHCR |
| `OCI_CLI_USER`        | OCI API user OCID                     |
| `OCI_CLI_TENANCY`     | Tenancy OCID                          |
| `OCI_CLI_FINGERPRINT` | API key fingerprint                   |
| `OCI_CLI_KEY_CONTENT` | PEM private key body                  |
| `OCI_CLI_REGION`      | `us-phoenix-1`                        |
| `OKE_CLUSTER_OCID`    | Target OKE cluster                    |

Frontend also needs `VERCEL_TOKEN`, `VERCEL_ORG_ID`, `VERCEL_PROJECT_ID`.

## One-time cluster secrets (bootstrap)

Before the first deploy, create the in-cluster Secrets the services read via
`envFrom`. The Phoenix cluster uses **direct `kubectl` Secrets** (not OCI
Vault/ESO). Point kubectl at Phoenix OKE, then run the helpers in
`deploy/scripts/` (full commands + key names in `deploy/README.md` § Secrets):

```bash
oci ce cluster create-kubeconfig --cluster-id "$OKE_CLUSTER_OCID" --region us-phoenix-1 \
  --file $HOME/.kube/config --token-version 2.0.0 --kube-endpoint PUBLIC_ENDPOINT

NEON_PASSWORD=... ./deploy/scripts/create-db-secret.sh            # referral-db, referral-jwt
OPENAI_API_KEY=... ANTHROPIC_API_KEY=... GEMINI_API_KEY=... \
  ./deploy/scripts/create-ai-secret.sh                            # fs-ai-keys (referral-ai-service)
# referral-s3 / referral-smtp: see deploy/README.md § Secrets
```

Each Secret must exist **before** the pods that `envFrom` it start (a missing
Secret → `CreateContainerConfigError`). `referral-ai-service` needs `fs-ai-keys`;
a missing provider key simply falls back to the deterministic `stub` provider.

## Cross-repo secrets

`service-cd.yml` lives in **referral-infra**. Callers in other repos use
`secrets: inherit`:

```yaml
jobs:
  deploy:
    uses: ghorha/referral-infra/.github/workflows/service-cd.yml@main
    with:
      service: referral-<name>-service
      port: <port>
    secrets: inherit
```

This relies on every secret the reusable workflow needs (`GH_PAT` and each
`OCI_CLI_*`/`OKE_CLUSTER_OCID`) being an **organization-level secret with
`visibility: all`**, not a repo-scoped secret on `referral-infra` alone —
cross-repo `workflow_call` cannot resolve repo-scoped secrets from the
called repo, only org-level ones (or secrets the caller passes explicitly).
If a secret is ever narrowed to `referral-infra` only, `secrets: inherit`
will silently receive empty values for it in the caller. Verify scope with:

```bash
gh api orgs/ghorha/actions/secrets/<NAME> --jq '.visibility'   # expect "all"
```

If that's ever not the case, either widen the secret's visibility, map it
explicitly (`secrets: { NAME: ${{ secrets.NAME }} }` instead of `inherit`),
or fall back to manual dispatch (see "Manual full rollout" below / the
comment header in `service-cd.yml`), which doesn't depend on cross-repo
secret resolution at all.

## Manual full rollout

From `referral-infra`:

```bash
gh workflow run deploy-all.yml --repo ghorha/referral-infra
```

## Fleet status dashboard

`scripts/fleet-status/generate.py` answers:

1. Which non-`main` branches still have commits not merged to `main`
2. Which branches are behind `main` (stale / need rebase)
3. Whether `main` has commits not yet running in production (OKE image tag vs `main` SHA; frontend via last successful `deploy.yml`)

Outputs land in `docs/fleet-status/` (`index.html`, `.md`, `.json`).

```bash
# Local clones + live OKE (OCI profile must reach Phoenix cluster)
python3 scripts/fleet-status/generate.py \
  --local-root /path/to/services \
  --oci-profile GHORHA \
  --oci-cluster "$OKE_CLUSTER_OCID"

# Or fully remote (needs GH_PAT)
GH_PAT=... python3 scripts/fleet-status/generate.py --github --oci-profile GHORHA --oci-cluster "$OKE_CLUSTER_OCID"
```

Scheduled refresh: `gh workflow run fleet-status.yml --repo ghorha/referral-infra`

## Runner

Jobs target `runs-on: [self-hosted, macOS, ARM64]` (ARM images for the OKE node pool). The runner needs Docker, Helm, and OCI CLI. JDK/Gradle are provisioned per-job via `actions/setup-java` + `gradle/actions/setup-gradle` (Java 21 / Gradle 8.10) — never installed globally on the runner.

**This runner is shared with the `piraho` GitHub org's CI/CD.** Never install
tools system-wide, never touch `~/.oci/config` or `~/lib/oracle-cli` directly
(only read an already-preinstalled `oci` CLI), and keep all workflow state
under `${RUNNER_TEMP}`/per-job-scoped paths (see the `DOCKER_CONFIG` and
`oci-ghorha` config-dir handling in `service-cd.yml`) so a `ghorha` job can
never clobber a concurrent `piraho` job's environment, and vice versa.

### Self-hosted Docker note

Parallel `deploy-all` jobs share one Docker daemon. Each job uses an isolated `DOCKER_CONFIG` and does not `docker logout`, avoiding mid-push GHCR 403 races.

## Troubleshooting

- **`Input required and not supplied: token`**: `GH_PAT` must be set as an org secret (and preferably mirrored on `referral-infra`). Service CD maps it into the reusable workflow.
- **Helm SSA conflicts** (`conflicts with kubectl-client-side-apply`): `service-cd` uses `--force-conflicts`.
- **CI using wrong Gradle**: workflows must call `./gradlew` only (never fall back to system `gradle` 9.x).
