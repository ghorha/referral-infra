# Referral deployment (Phoenix OKE + Neon + Vercel)

Continuous delivery for Vouch backends:

```
push to main (service repo)
  → GitHub Actions ci.yml (unit tests)
  → GitHub Actions cd.yml
       → reusable workflow ghorha/referral-infra/.github/workflows/service-cd.yml
            → ./gradlew bootJar
            → docker build/push linux/arm64 → ghcr.io/ghorha/<service>:<sha>
            → oci ce cluster create-kubeconfig (Phoenix OKE)
            → helm upgrade --install -n referral
```

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

## Runner

Jobs target `runs-on: [self-hosted, macOS, ARM64]` (ARM images for the OKE node pool). The runner needs Docker, JDK 17, Helm, and OCI CLI.
