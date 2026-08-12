# variables.tf
# -----------------------------------------------------------------------------
# Input variables for the Referral OKE stack.
#
# Authentication values (tenancy/user/fingerprint/key) and tenancy-specific
# values (compartment, region) have NO safe defaults and must be supplied via
# terraform.tfvars or environment variables (TF_VAR_*). Everything else has a
# sensible default that can be overridden.
# -----------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# Authentication / tenancy (no defaults — you must supply these)
# ---------------------------------------------------------------------------

variable "tenancy_ocid" {
  description = "OCID of your OCI tenancy (root). Find it under Profile -> Tenancy."
  type        = string
}

variable "compartment_ocid" {
  description = "OCID of the compartment where all Referral resources are created."
  type        = string
}

variable "region" {
  description = "OCI region identifier, e.g. us-phoenix-1, us-phoenix-1, eu-frankfurt-1."
  type        = string
  default     = "us-phoenix-1"
}

variable "user_ocid" {
  description = "OCID of the IAM user whose API signing key is used for auth."
  type        = string
}

variable "fingerprint" {
  description = "Fingerprint of the API signing key uploaded to the IAM user."
  type        = string
  sensitive   = true
}

variable "private_key_path" {
  description = "Local filesystem path to the PEM API signing private key (e.g. ~/.oci/oci_api_key.pem)."
  type        = string
  sensitive   = true
}

# ---------------------------------------------------------------------------
# Cluster configuration
# ---------------------------------------------------------------------------

variable "cluster_name" {
  description = "Name/prefix for the OKE cluster and related resources."
  type        = string
  default     = "referral"
}

variable "k8s_version" {
  description = <<-EOT
    Kubernetes version for the OKE control plane and node pool, e.g. "v1.34.2".
    OKE only accepts specific supported versions and this list changes over
    time. VERIFY before apply with:
      oci ce cluster-options get --cluster-option-id all \
        --query 'data."kubernetes-versions"'
    Adjust this value to a currently supported version if the plan/apply fails.
  EOT
  type        = string
  default     = "v1.34.2"
}

variable "node_pool_size" {
  description = <<-EOT
    Number of worker nodes in the node pool (spread across ADs). Kept within the
    Always-Free Arm A1 grant: node_pool_size * node_ocpus must be <= 4 OCPU and
    node_pool_size * node_memory_gb must be <= 24 GB across the whole tenancy.
    Default 2 nodes x 2 OCPU / 12 GB = 4 OCPU + 24 GB (the full free grant).
  EOT
  type        = number
  default     = 2
}

variable "node_shape" {
  description = <<-EOT
    Compute shape for worker nodes. Defaults to the Always-Free Arm Ampere A1
    flex shape (VM.Standard.A1.Flex, aarch64). Flex shapes allow custom
    OCPU/memory. If you change this to an x86 shape you MUST also change the
    node image to an x86 image (see node_image_ocid / oke.tf image discovery).
  EOT
  type        = string
  default     = "VM.Standard.A1.Flex"
}

variable "node_ocpus" {
  description = "OCPUs per worker node (only used for Flex shapes). Free A1 grant is 4 OCPU total across the tenancy."
  type        = number
  default     = 2
}

variable "node_memory_gb" {
  description = "Memory in GB per worker node (only used for Flex shapes). Free A1 grant is 24 GB total across the tenancy."
  type        = number
  default     = 12
}

variable "node_boot_volume_gb" {
  description = "Boot volume size (GB) for each worker node. Minimum 50."
  type        = number
  default     = 50
}

variable "node_image_ocid" {
  description = <<-EOT
    Optional explicit OCID of the worker node OS image. Leave null to let
    Terraform auto-discover the newest Oracle-Linux-8 OKE image that matches
    k8s_version AND the Arm/aarch64 architecture required by the A1 shape.
    Image OCIDs differ by architecture (an x86 image will not boot on A1), so
    discovery filters for the "aarch64" image. Image OCIDs are also region- and
    version-specific, so if auto-discovery finds nothing (e.g. for a brand-new
    k8s version) set this explicitly to an aarch64 image. List candidates with:
      oci ce node-pool-options get --node-pool-option-id all \
        --query 'data.sources[?contains("source-name", `aarch64`)].{name:"source-name",id:"image-id"}'
  EOT
  type        = string
  default     = null
}

variable "ssh_public_key" {
  description = "Optional SSH public key to install on worker nodes for debugging. Empty = no key."
  type        = string
  default     = ""
}

# ---------------------------------------------------------------------------
# Networking (defaults follow a standard OKE layout)
# ---------------------------------------------------------------------------

variable "vcn_cidr" {
  description = "CIDR block for the VCN."
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidr" {
  description = "CIDR for the public subnet (K8s API endpoint + public load balancers)."
  type        = string
  default     = "10.0.0.0/24"
}

variable "worker_subnet_cidr" {
  description = "CIDR for the private subnet that hosts the worker nodes."
  type        = string
  default     = "10.0.10.0/24"
}

variable "pods_cidr" {
  description = "CIDR for Kubernetes pods (flannel overlay)."
  type        = string
  default     = "10.244.0.0/16"
}

variable "services_cidr" {
  description = "CIDR for Kubernetes ClusterIP services."
  type        = string
  default     = "10.96.0.0/16"
}

variable "api_endpoint_allowed_cidr" {
  description = "CIDR allowed to reach the public Kubernetes API endpoint (6443). Restrict to your office/VPN for production."
  type        = string
  default = "10.0.0.0/8"
}

# ---------------------------------------------------------------------------
# Load balancer (NOT provisioned by Terraform — documented here for reference)
# ---------------------------------------------------------------------------
# There is deliberately no OCI Load Balancer resource in this stack. The public
# LB is created by OKE when ingress-nginx is deployed as a Service of type
# LoadBalancer (its backends land in the public subnet via
# options.service_lb_subnet_ids in oke.tf).
#
# To stay Always-Free ($0), the ingress-nginx Service MUST request the free
# FLEXIBLE 10 Mbps LB shape (min = max = 10 Mbps) via OCI annotations. This is
# configured in the Kubernetes manifests / Helm values, NOT in Terraform:
#
#   service.beta.kubernetes.io/oci-load-balancer-shape:          "flexible"
#   service.beta.kubernetes.io/oci-load-balancer-shape-flex-min: "10"
#   service.beta.kubernetes.io/oci-load-balancer-shape-flex-max: "10"
#
# Any other shape, or min != max, or a bandwidth other than 10, provisions a
# billable load balancer.
