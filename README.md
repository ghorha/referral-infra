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

- Reusable workflow: `.github/workflows/service-cd.yml` (Java 21 / Gradle 8.10, matches every service's own toolchain).
- Each Java service repo's `cd.yml` calls it directly on push to `main` via `uses: ghorha/referral-infra/.github/workflows/service-cd.yml@main` + `secrets: inherit` (build Docker image → Helm to Phoenix OKE).
- Fallback / full matrix rollout: `.github/workflows/deploy-service.yml` (single service) and `.github/workflows/deploy-all.yml` (all services), both `workflow_dispatch` — these don't depend on cross-repo secret resolution and still work unchanged if `secrets: inherit` ever fails.
- Details and required org secrets: **`DEPLOYMENT.md`**.

## Fleet status dashboard

Live snapshot of branch drift and undeployed `main` commits:

- **Browse:** [`docs/fleet-status/index.html`](./docs/fleet-status/index.html) (also `fleet-status.md`)
- **Refresh locally:**
  ```bash
  python3 scripts/fleet-status/generate.py \
    --local-root ../ \
    --oci-profile GHORHA \
    --oci-cluster "$OKE_CLUSTER_OCID"
  ```
- **CI:** `.github/workflows/fleet-status.yml` (daily + `workflow_dispatch`) writes the snapshot via GitHub API + OKE.

## Purge test / seed data

Remove all fake/QA/seed data (users on a test email domain + everything they own or
reference) from an environment's shared DB. **Dry run by default** — it prints the row
counts it would delete and changes nothing; pass `--confirm` to apply. Deletes run in a
single transaction in foreign-key-safe order; `flyway_schema_history` is never touched.

```bash
export KUBECONFIG=$HOME/.kube/ghorha-phoenix.config   # connection is read from the referral-db secret

./scripts/purge-test-data.sh                 # dry run: preview what would be deleted
./scripts/purge-test-data.sh --confirm       # actually delete (test data on example.com)

# custom test domains, or a direct connection instead of the k8s secret:
TEST_EMAIL_DOMAINS="example.com,test.local" ./scripts/purge-test-data.sh --confirm
PG_CONNINFO="host=... dbname=... user=... sslmode=require" PGPASSWORD=... ./scripts/purge-test-data.sh
```

"Test data" = any user whose email matches a test domain (default `example.com`, the
reserved QA seed domain) plus their listings, transactions, reviews, ledger rows,
businesses/programs, devices, identity rows, notifications, trust profiles, matching
`email_outbox` rows, and their `audit_logs`.

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
