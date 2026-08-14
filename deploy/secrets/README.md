# Secret storage for the OKE cluster — OCI Vault + External Secrets Operator

> **⚠️ Not the mechanism used on the current (Phoenix / `us-phoenix-1`) cluster.**
> The live cluster provisions Secrets **directly with `kubectl`** — see
> `../README.md` § Secrets and `../scripts/create-db-secret.sh` /
> `../scripts/create-ai-secret.sh`. The OCI-Vault + ESO flow described below
> (and `external-secrets.yaml`) targets a **`us-chicago-1`** vault and is kept
> for reference only; update its region + vault OCID before ever applying it.

Plaintext credentials never live in git or in raw manifests. They live in **OCI Vault** (encrypted
at rest by a KMS key), and **External Secrets Operator (ESO)** syncs them into Kubernetes Secrets
that the services already read via `envFrom`.

```
  You (OCI Console)  ──save value──▶  OCI Vault secret  ──ESO sync──▶  K8s Secret  ──envFrom──▶  pod
     the "link" ↑                     (encrypted, KMS)                 (referral ns)
```

## One-time setup

### 1. Create the Vault + secret placeholders (Terraform)

`terraform/vault.tf` adds the Vault, a KMS key, the secret placeholders, and an IAM policy that lets
the OKE nodes read them. From `terraform/`:

```bash
terraform plan -out tfplan       # review — it ADDS a vault, key, 8 secrets, 1 dynamic group, 1 policy
terraform apply tfplan
terraform output app_vault_ocid  # -> ocid1.vault.oc1...  (used in step 3)
```

### 2. Install External Secrets Operator

```bash
helm repo add external-secrets https://charts.external-secrets.io && helm repo update
helm install external-secrets external-secrets/external-secrets \
  -n external-secrets --create-namespace --set installCRDs=true
```

### 3. Point ESO at the Vault and sync

Edit `deploy/secrets/external-secrets.yaml` — set `region` (your `var.region`, e.g. `us-ashburn-1`)
and `vault` (the `app_vault_ocid` from step 1) — then:

```bash
kubectl apply -f deploy/secrets/external-secrets.yaml
kubectl -n referral get externalsecret     # STATUS should become SecretSynced
kubectl -n referral get secret fs-twilio fs-email   # created by ESO
```

## Saving a credential — the link

**Open the OCI Console → Vault:** https://cloud.oracle.com/security/kms/vaults
(top-right region selector must match `var.region`.) Then:

1. Open the **`referral-app-secrets`** vault → **Secrets**.
2. Click a secret (e.g. `fs-twilio-api-key-secret`) → **Create Secret Version** → paste the value → save.
3. Do the same for each credential below. ESO picks up changes within `refreshInterval` (1h) — force
   an immediate resync with `kubectl -n referral annotate externalsecret fs-twilio force-sync=$(date +%s) --overwrite`.

Prefer the CLI? `oci vault secret update-base64 --secret-id <ocid> --secret-content-content "$(printf %s 'VALUE' | base64)"`.

### What goes where

| OCI Vault secret           | Becomes (K8s `fs-twilio`) | Value                                                    |
| -------------------------- | ------------------------- | -------------------------------------------------------- |
| `fs-twilio-account-sid`    | `TWILIO_ACCOUNT_SID`      | `AC…` Account SID                                        |
| `fs-twilio-api-key-sid`    | `TWILIO_API_KEY_SID`      | `SK…` API Key SID                                        |
| `fs-twilio-api-key-secret` | `TWILIO_API_KEY_SECRET`   | API Key secret **(rotate the one pasted in chat first)** |
| `fs-twilio-from-number`    | `TWILIO_FROM_NUMBER`      | `+1…` sender number                                      |

| OCI Vault secret    | Becomes (K8s `fs-email`) | Value                            |
| ------------------- | ------------------------ | -------------------------------- |
| `fs-email-provider` | `EMAIL_PROVIDER`         | `dreamlit` or `smtp`             |
| `fs-email-api-base` | `EMAIL_API_BASE`         | provider base URL (if API-based) |
| `fs-email-api-key`  | `EMAIL_API_KEY`          | provider API key/token           |
| `fs-email-from`     | `EMAIL_FROM`             | e.g. `no-reply@referral.app`     |

## Consuming a secret from a service

Add the synced secret to the service's Helm values `envFrom` (like `referral-db` today), e.g. in
`deploy/values/fs-notification.yaml`:

```yaml
envFrom:
  - referral-db
  - fs-email # email creds
  - fs-twilio # sms creds
```

## Notes

- **Rotate the Twilio API-key secret** you pasted into chat — it's in the conversation log. Create a
  new API key in the Twilio Console, store _that_ one in the vault.
- **Applied & verified** on `us-chicago-1` — ESO syncs `fs-twilio` + `fs-email`. The manifests use
  API `external-secrets.io/v1` (ESO v2.x no longer serves `v1beta1`). A `read vaults` grant was added
  to the policy to clear ESO's store-validation warning — `terraform apply` again to pick it up
  (secret _reads_ already work without it, via `secret-family`).
- Rollback: `kubectl delete -f deploy/secrets/external-secrets.yaml` removes the sync (and the K8s
  Secrets it owns); the Vault values stay put.
