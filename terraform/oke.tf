# oke.tf
# -----------------------------------------------------------------------------
# The OKE cluster and its worker node pool.
#
#   - VCN-native networking with the flannel (overlay) CNI.
#   - Public Kubernetes API endpoint in the public subnet.
#   - Public load balancers created (by Kubernetes at deploy time) in the
#     public subnet via service_lb_subnet_ids.
#   - Worker nodes run in the private subnet, spread across all availability
#     domains, on a Flex compute shape sized from variables.
# -----------------------------------------------------------------------------

# Availability domains in the region — used to spread worker nodes.
data "oci_identity_availability_domains" "ads" {
  compartment_id = var.tenancy_ocid
}

# Node image: pin via var.node_image_ocid (required for Phoenix bootstrap).
# Auto-discovery via oci_containerengine_node_pool_option was flaky on this
# tenancy (401/RelatedResourceNotAuthorized from Terraform provider even when
# the OCI CLI succeeds), so we require an explicit aarch64 OKE image OCID.
locals {
  node_image_id = var.node_image_ocid
}

# ---------------------------------------------------------------------------
# OKE cluster (control plane)
# ---------------------------------------------------------------------------
resource "oci_containerengine_cluster" "referral" {
  compartment_id     = var.compartment_ocid
  kubernetes_version = var.k8s_version
  name               = var.cluster_name
  vcn_id             = oci_core_vcn.referral.id

  # BASIC_CLUSTER keeps the OKE control plane on the free tier ($0). Enhanced
  # clusters incur an hourly control-plane charge, so do NOT switch this back to
  # ENHANCED_CLUSTER if the goal is to stay Always-Free.
  type = "BASIC_CLUSTER"

  endpoint_config {
    is_public_ip_enabled = true
    subnet_id            = oci_core_subnet.referral_public.id
  }

  cluster_pod_network_options {
    cni_type = "FLANNEL_OVERLAY"
  }

  options {
    # Public load balancers (Envoy gateway Service type=LoadBalancer) land here.
    service_lb_subnet_ids = [oci_core_subnet.referral_public.id]

    add_ons {
      is_kubernetes_dashboard_enabled = false
      is_tiller_enabled               = false
    }

    kubernetes_network_config {
      pods_cidr     = var.pods_cidr
      services_cidr = var.services_cidr
    }
  }

  freeform_tags = {
    project = "referral"
  }
}

# ---------------------------------------------------------------------------
# Worker node pool (private subnet) — Arm Ampere A1 (Always-Free)
# ---------------------------------------------------------------------------
# Uses the VM.Standard.A1.Flex (Arm/aarch64) shape. The Always-Free A1 grant is
# 4 OCPU + 24 GB total across the WHOLE tenancy; the defaults here (2 nodes x
# 2 OCPU / 12 GB = 4 OCPU + 24 GB) consume exactly that budget, so there is no
# room for additional A1 instances elsewhere in the tenancy.
#
# CAPACITY CAVEAT: A1 capacity is frequently exhausted in popular regions and
# apply can fail with "Out of host capacity" / "500-InternalError". This is an
# OCI availability issue, not a config bug. Workarounds: retry the apply
# (capacity is released continuously), try a different availability domain, or
# create the tenancy in / target a less-contended region.
resource "oci_containerengine_node_pool" "referral" {
  cluster_id         = oci_containerengine_cluster.referral.id
  compartment_id     = var.compartment_ocid
  kubernetes_version = var.k8s_version
  name               = "${var.cluster_name}-np-1"
  node_shape         = var.node_shape

  node_config_details {
    size = var.node_pool_size

    # Spread nodes across every availability domain in the region.
    dynamic "placement_configs" {
      for_each = data.oci_identity_availability_domains.ads.availability_domains
      content {
        availability_domain = placement_configs.value.name
        subnet_id           = oci_core_subnet.referral_private.id
      }
    }
  }

  # A1.Flex sizing. Keep node_pool_size * node_ocpus <= 4 and
  # node_pool_size * node_memory_gb <= 24 to stay within the Always-Free grant.
  node_shape_config {
    ocpus         = var.node_ocpus
    memory_in_gbs = var.node_memory_gb
  }

  node_source_details {
    source_type             = "IMAGE"
    image_id                = local.node_image_id
    boot_volume_size_in_gbs = var.node_boot_volume_gb
  }

  # Optional SSH access to nodes for debugging.
  ssh_public_key = var.ssh_public_key != "" ? var.ssh_public_key : null

  initial_node_labels {
    key   = "project"
    value = "referral"
  }

  freeform_tags = {
    project = "referral"
  }
}
