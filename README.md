# referral-infra

**Infrastructure** for the Vouch referral-code marketplace.

Deploy assets: Terraform, Helm/Kubernetes manifests, Prometheus config, and cluster migrations.

## Stack
Terraform, Helm/Kubernetes, Prometheus, SQL migrations

## Quick start
```bash
# from this repo
See DEPLOYMENT.md and deploy/
```

## CI/CD (GitHub → GHCR → OCI OKE)

- Reusable workflow: `.github/workflows/service-cd.yml`
- Each Java service repo has `cd.yml` that calls it on push to `main` (build Docker image → Helm to Phoenix OKE).
- Full matrix rollout: `.github/workflows/deploy-all.yml` (workflow_dispatch).
- Details and required org secrets: **`DEPLOYMENT.md`**.

## Test
```bash
terraform validate (where applicable)
```

## Project layout
```
deploy/         # Helm chart + values + ingress/secrets helpers
terraform/      # OCI/AWS modules & environments
kubernetes/     # Reference manifests
migrations.sql/ # Cluster-oriented schema reference
prometheus/
```

## GitHub
`https://github.com/ghorha/referral-infra`

## Related
- Product contracts: `ghorha/referral-product`
- Deploy: `ghorha/referral-infra`
- Cross-service tests: `ghorha/referral-tests`
- AI skills/context: `ghorha/referral-agents`

## For AI agents
Repo-local guidance lives in **`.okf/`** (`index.md` + `concepts/`). Read that before making structural changes.

## Keeping docs current

Any change in this repo must update **README.md** (for humans) and **`.okf/`** (for AI agents) in the same change set.

## Security notes

Secrets manifests renamed to *.example.yaml; staging NetworkPolicy; API CIDR default not 0.0.0.0/0.
