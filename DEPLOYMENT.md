# Referral deployment (Phoenix OKE + Neon + Vercel)

Continuous delivery for Vouch backends:

```
push to main (service repo)
  → GitHub Actions ci.yml (unit tests)
  → GitHub Actions cd.yml
       → gh workflow run deploy-service.yml on ghorha/referral-infra
            → reusable service-cd.yml (secrets from referral-infra)
                 → ./gradlew bootJar
                 → docker build/push linux/arm64 → ghcr.io/ghorha/<service>:<sha>
                 → oci ce cluster create-kubeconfig (Phoenix OKE)
                 → helm upgrade --install -n referral (--force-conflicts)
```

Service repos only need `GH_PAT`. OCI secrets stay on `referral-infra`.

Region: **us-phoenix-1**. Frontend deploys separately to **Vercel** (`referral-frontend` `deploy.yml`), not OKE.

## Org secrets (required)

Set on the `ghorha` GitHub org (visibility: all repos):

| Secret | Purpose |
|--------|---------|
| `GH_PAT` | Checkout private repos + push to GHCR |
| `OCI_CLI_USER` | OCI API user OCID |
| `OCI_CLI_TENANCY` | Tenancy OCID |
| `OCI_CLI_FINGERPRINT` | API key fingerprint |
| `OCI_CLI_KEY_CONTENT` | PEM private key body |
| `OCI_CLI_REGION` | `us-phoenix-1` |
| `OKE_CLUSTER_OCID` | Target OKE cluster |

Frontend also needs `VERCEL_TOKEN`, `VERCEL_ORG_ID`, `VERCEL_PROJECT_ID`.

## Important: cross-repo secrets

`service-cd.yml` lives in **referral-infra**. Callers in other repos **cannot** use `secrets: inherit` (GitHub limitation for cross-repo reusable workflows). Each service `cd.yml` must map secrets explicitly:

```yaml
secrets:
  GH_PAT: ${{ secrets.GH_PAT }}
  OCI_CLI_USER: ${{ secrets.OCI_CLI_USER }}
  # ... same for remaining OCI_* and OKE_CLUSTER_OCID
```

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

Jobs target `runs-on: [self-hosted, macOS, ARM64]` (ARM images for the OKE node pool). The runner needs Docker, JDK 17, Helm, and OCI CLI.



### Self-hosted Docker note
Parallel `deploy-all` jobs share one Docker daemon. Each job uses an isolated `DOCKER_CONFIG` and does not `docker logout`, avoiding mid-push GHCR 403 races.

## Troubleshooting

- **`Input required and not supplied: token`**: `GH_PAT` must be set as an org secret (and preferably mirrored on `referral-infra`). Service CD maps it into the reusable workflow.
- **Helm SSA conflicts** (`conflicts with kubectl-client-side-apply`): `service-cd` uses `--force-conflicts`.
- **CI using wrong Gradle**: workflows must call `./gradlew` only (never fall back to system `gradle` 9.x).
