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
