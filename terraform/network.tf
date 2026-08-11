# network.tf
# -----------------------------------------------------------------------------
# Network foundation for the OKE cluster following a standard OKE layout:
#
#   VCN (10.0.0.0/16)
#     |- Internet Gateway   -> public subnet egress/ingress
#     |- NAT Gateway        -> private subnet outbound to internet
#     |- Service Gateway    -> private subnet to OCI services (no internet)
#     |
#     |- Public subnet  (10.0.0.0/24)  : K8s API endpoint + public load balancers
#     |- Private subnet (10.0.10.0/24) : worker nodes
#
# Security lists implement the connectivity OKE requires between worker nodes,
# the control plane, and load balancers.
# -----------------------------------------------------------------------------

# All OCI services reachable through the Service Gateway (index 0 = the
# "All <region> Services" regional CIDR block).
data "oci_core_services" "all_services" {}

# ---------------------------------------------------------------------------
# VCN
# ---------------------------------------------------------------------------
resource "oci_core_vcn" "referral" {
  compartment_id = var.compartment_ocid
  cidr_blocks    = [var.vcn_cidr]
  display_name   = "${var.cluster_name}-vcn"
  dns_label      = "referral"

  freeform_tags = {
    project = "referral"
  }
}

# ---------------------------------------------------------------------------
# Gateways
# ---------------------------------------------------------------------------
resource "oci_core_internet_gateway" "referral" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.referral.id
  display_name   = "${var.cluster_name}-igw"
  enabled        = true
}

resource "oci_core_nat_gateway" "referral" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.referral.id
  display_name   = "${var.cluster_name}-nat"
}

resource "oci_core_service_gateway" "referral" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.referral.id
  display_name   = "${var.cluster_name}-sgw"

  services {
    service_id = data.oci_core_services.all_services.services[0].id
  }
}

# ---------------------------------------------------------------------------
# Route tables
# ---------------------------------------------------------------------------
resource "oci_core_route_table" "referral_public" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.referral.id
  display_name   = "${var.cluster_name}-public-rt"

  route_rules {
    description       = "Default route to the internet."
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
    network_entity_id = oci_core_internet_gateway.referral.id
  }
}

resource "oci_core_route_table" "referral_private" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.referral.id
  display_name   = "${var.cluster_name}-private-rt"

  # NAT-only. A SERVICE_CIDR_BLOCK rule to the service gateway returns
  # 404-NotAuthorizedOrNotFound on this Phoenix tenancy (CLI and Terraform).
  # Nodes still reach OCI services via NAT for bootstrap.
  route_rules {
    description       = "Outbound internet via NAT gateway."
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
    network_entity_id = oci_core_nat_gateway.referral.id
  }
}

# ---------------------------------------------------------------------------
# Security list: public subnet (K8s API endpoint + load balancers)
# ---------------------------------------------------------------------------
resource "oci_core_security_list" "referral_public" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.referral.id
  display_name   = "${var.cluster_name}-public-sl"

  # --- Ingress ---
  ingress_security_rules {
    description = "Public access to the Kubernetes API endpoint."
    protocol    = "6" # TCP
    source      = var.api_endpoint_allowed_cidr
    tcp_options {
      min = 6443
      max = 6443
    }
  }

  ingress_security_rules {
    description = "Worker nodes to Kubernetes API server."
    protocol    = "6"
    source      = var.worker_subnet_cidr
    tcp_options {
      min = 6443
      max = 6443
    }
  }

  ingress_security_rules {
    description = "Worker nodes to control plane (OKE managed control-plane comms)."
    protocol    = "6"
    source      = var.worker_subnet_cidr
    tcp_options {
      min = 12250
      max = 12250
    }
  }

  ingress_security_rules {
    description = "Path MTU discovery from worker nodes."
    protocol    = "1" # ICMP
    source      = var.worker_subnet_cidr
    icmp_options {
      type = 3
      code = 4
    }
  }

  ingress_security_rules {
    description = "Public HTTP to the gateway load balancer."
    protocol    = "6"
    source      = "0.0.0.0/0"
    tcp_options {
      min = 80
      max = 80
    }
  }

  ingress_security_rules {
    description = "Public HTTPS to the gateway load balancer."
    protocol    = "6"
    source      = "0.0.0.0/0"
    tcp_options {
      min = 443
      max = 443
    }
  }

  # --- Egress ---
  egress_security_rules {
    description = "Control plane to worker nodes (kubelet, node ports, etc.)."
    protocol    = "6"
    destination = var.worker_subnet_cidr
  }

  egress_security_rules {
    description = "Path MTU discovery to worker nodes."
    protocol    = "1"
    destination = var.worker_subnet_cidr
    icmp_options {
      type = 3
      code = 4
    }
  }

  egress_security_rules {
    description = "Allow all other egress (OCI services, load balancer backends)."
    protocol    = "all"
    destination = "0.0.0.0/0"
  }
}

# ---------------------------------------------------------------------------
# Security list: private subnet (worker nodes)
# ---------------------------------------------------------------------------
resource "oci_core_security_list" "referral_private" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.referral.id
  display_name   = "${var.cluster_name}-private-sl"

  # --- Ingress ---
  ingress_security_rules {
    description = "Node-to-node: all traffic within the worker subnet."
    protocol    = "all"
    source      = var.worker_subnet_cidr
  }

  ingress_security_rules {
    description = "Control plane / API endpoint subnet to worker nodes (kubelet 10250, etc.)."
    protocol    = "6"
    source      = var.public_subnet_cidr
  }

  ingress_security_rules {
    description = "Load balancer to NodePort range (Service type=LoadBalancer / Ingress)."
    protocol    = "6"
    source      = var.public_subnet_cidr
    tcp_options {
      min = 30000
      max = 32767
    }
  }

  ingress_security_rules {
    description = "Path MTU discovery."
    protocol    = "1"
    source      = "0.0.0.0/0"
    icmp_options {
      type = 3
      code = 4
    }
  }

  # --- Egress ---
  egress_security_rules {
    description = "Allow all egress (control plane, image pull via NAT/SGW, internet)."
    protocol    = "all"
    destination = "0.0.0.0/0"
  }
}

# ---------------------------------------------------------------------------
# Subnets
# ---------------------------------------------------------------------------
resource "oci_core_subnet" "referral_public" {
  compartment_id             = var.compartment_ocid
  vcn_id                     = oci_core_vcn.referral.id
  cidr_block                 = var.public_subnet_cidr
  display_name               = "${var.cluster_name}-public-subnet"
  dns_label                  = "pub"
  route_table_id             = oci_core_route_table.referral_public.id
  security_list_ids          = [oci_core_security_list.referral_public.id]
  prohibit_public_ip_on_vnic = false
}

resource "oci_core_subnet" "referral_private" {
  compartment_id             = var.compartment_ocid
  vcn_id                     = oci_core_vcn.referral.id
  cidr_block                 = var.worker_subnet_cidr
  display_name               = "${var.cluster_name}-private-subnet"
  dns_label                  = "priv"
  route_table_id             = oci_core_route_table.referral_private.id
  security_list_ids          = [oci_core_security_list.referral_private.id]
  prohibit_public_ip_on_vnic = true
}
