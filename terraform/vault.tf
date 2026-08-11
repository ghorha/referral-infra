# OCI Vault for Referral application secrets (Twilio SMS, transactional email, and any future
# third-party credentials). Secret *values* are set in the OCI Console (or `oci vault secret`),
# NEVER committed here. External Secrets Operator syncs them into Kubernetes Secrets that the
# services consume via `envFrom` — see deploy/secrets/README.md.
#
# Uses the existing var.compartment_ocid / var.tenancy_ocid / var.region from variables.tf.

resource "oci_kms_vault" "app" {
  compartment_id = var.compartment_ocid
  display_name   = "referral-app-secrets"
  vault_type     = "DEFAULT"
}

resource "oci_kms_key" "app" {
  compartment_id      = var.compartment_ocid
  display_name        = "referral-app-secrets-key"
  management_endpoint = oci_kms_vault.app.management_endpoint
  key_shape {
    algorithm = "AES"
    length    = 32
  }
}

# The secrets External Secrets Operator will read. Each is created with a placeholder so it exists
# immediately; you set the REAL value in the OCI Console afterwards. `ignore_changes` means a later
# `terraform apply` will never clobber a value you set in the console.
locals {
  app_secret_names = [
    "fs-twilio-account-sid",   # ACxxxx…  (your Twilio Account SID)
    "fs-twilio-api-key-sid",   # SKxxxx…  (API Key SID)
    "fs-twilio-api-key-secret",# the API Key secret  — ROTATE the one pasted in chat
    "fs-twilio-from-number",   # +1XXXXXXXXXX  sender number
    "fs-email-provider",       # e.g. "dreamlit" or "smtp"
    "fs-email-api-base",       # provider base URL (if API-based)
    "fs-email-api-key",        # provider API key/token
    "fs-email-from",           # From address, e.g. "no-reply@referral.app"
    "fs-ai-openai-api-key",    # OpenAI API key       (fs-ai gateway)
    "fs-ai-anthropic-api-key", # Anthropic/Claude key (fs-ai gateway)
    "fs-ai-gemini-api-key",    # Google Gemini key    (fs-ai gateway)
    "fs-health-master-key",    # base64(32 random bytes) — PHI envelope-encryption master key (fs-health)
  ]
}

resource "oci_vault_secret" "app" {
  for_each       = toset(local.app_secret_names)
  compartment_id = var.compartment_ocid
  vault_id       = oci_kms_vault.app.id
  key_id         = oci_kms_key.app.id
  secret_name    = each.key

  secret_content {
    content_type = "BASE64"
    content      = base64encode("REPLACE_ME_IN_CONSOLE")
  }

  lifecycle {
    ignore_changes = [secret_content] # value is managed in the OCI Console, not in Terraform
  }
}

# Let the OKE worker nodes — and thus External Secrets Operator, authenticating via instance
# principal — read these secrets and use the wrapping key. Dynamic groups live in the tenancy root.
resource "oci_identity_dynamic_group" "oke_nodes" {
  compartment_id = var.tenancy_ocid
  name           = "referral-oke-nodes"
  description    = "Referral OKE worker node instances (for External Secrets Operator)"
  matching_rule  = "ALL {instance.compartment.id = '${var.compartment_ocid}'}"
}

resource "oci_identity_policy" "eso_read_secrets" {
  compartment_id = var.compartment_ocid
  name           = "referral-eso-read-secrets"
  description    = "Allow OKE nodes to read Referral app secrets from Vault"
  statements = [
    "Allow dynamic-group ${oci_identity_dynamic_group.oke_nodes.name} to read secret-family in compartment id ${var.compartment_ocid}",
    "Allow dynamic-group ${oci_identity_dynamic_group.oke_nodes.name} to use keys in compartment id ${var.compartment_ocid}",
    # ESO's store validation calls GetVault (KMS management) — needs `read vaults`, else the
    # ClusterSecretStore shows ValidationUnknown (secret reads still work via secret-family above).
    "Allow dynamic-group ${oci_identity_dynamic_group.oke_nodes.name} to read vaults in compartment id ${var.compartment_ocid}",
  ]
}

output "app_vault_ocid" {
  description = "OCID of the Referral app-secrets Vault — paste into deploy/secrets/external-secrets.yaml."
  value       = oci_kms_vault.app.id
}
