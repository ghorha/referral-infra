# versions.tf
# -----------------------------------------------------------------------------
# Terraform + provider requirements and the OCI provider configuration for the
# Referral backend infrastructure.
#
# The provider authenticates with an OCI API signing key. All credential values
# are supplied via variables (see variables.tf / terraform.tfvars) so that no
# secrets are ever committed to source control.
# -----------------------------------------------------------------------------

terraform {
  required_version = ">= 1.5"

  required_providers {
    oci = {
      source = "oracle/oci"
      # Pinned to the 6.x line. For a fully reproducible plan, pin an exact
      # patch (e.g. "6.36.0") once you have run `terraform init` and confirmed
      # the version that resolves in your environment.
      version = "~> 7.0"
    }
  }

  # ---------------------------------------------------------------------------
  # Remote state backend (commented out by default -> local state is used).
  #
  # For team use, store state remotely. OCI Object Storage is S3-compatible, so
  # the standard "s3" backend works when pointed at an OCI namespace bucket.
  #
  # Steps:
  #   1. Create a bucket in OCI Object Storage (e.g. "referral-tf-state").
  #   2. Create a Customer Secret Key (Identity -> your user -> Customer Secret
  #      Keys) to get an S3-compatible access key / secret key pair.
  #   3. Fill in <namespace>, <region>, and the key/secret below, then run
  #      `terraform init -migrate-state`.
  #
  # backend "s3" {
  #   bucket                      = "referral-tf-state"
  #   key                         = "oke/terraform.tfstate"
  #   region                      = "us-ashburn-1"
  #   endpoints                   = { s3 = "https://<namespace>.compat.objectstorage.us-ashburn-1.oraclecloud.com" }
  #   skip_region_validation      = true
  #   skip_credentials_validation = true
  #   skip_requesting_account_id  = true
  #   skip_metadata_api_check     = true
  #   skip_s3_checksum            = true
  #   use_path_style              = true
  #   # access_key / secret_key: set via env vars AWS_ACCESS_KEY_ID /
  #   # AWS_SECRET_ACCESS_KEY (the OCI Customer Secret Key pair).
  # }
  # ---------------------------------------------------------------------------
}

# OCI provider — API-key (user principal) authentication.
# Prefer inline private_key (file()) over private_key_path — path-based auth
# was returning 401/404 NotAuthenticated against this Phoenix tenancy even when
# the OCI CLI (same key) succeeded.
provider "oci" {
  tenancy_ocid = var.tenancy_ocid
  user_ocid    = var.user_ocid
  fingerprint  = var.fingerprint
  private_key  = file(var.private_key_path)
  region       = var.region
}
