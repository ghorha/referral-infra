# outputs.tf
# -----------------------------------------------------------------------------
# Useful values surfaced after `terraform apply`: the cluster OCID, the region,
# a ready-to-run kubeconfig command, and a note on how the public load balancer
# for ingress-nginx is created (and how to keep it on the free tier).
#
# Container images now live in GitHub Container Registry (ghcr.io/ghorha), not
# OCIR, so there are no registry namespace/repository/image-path outputs here.
# -----------------------------------------------------------------------------

output "cluster_id" {
  description = "OCID of the OKE cluster."
  value       = oci_containerengine_cluster.referral.id
}

output "cluster_kubernetes_version" {
  description = "Kubernetes version the cluster was created with."
  value       = oci_containerengine_cluster.referral.kubernetes_version
}

output "region" {
  description = "OCI region the cluster runs in."
  value       = var.region
}

output "kubeconfig_command" {
  description = "Run this after apply to write a kubeconfig for kubectl/helm."
  value = join(" ", [
    "oci ce cluster create-kubeconfig",
    "--cluster-id ${oci_containerengine_cluster.referral.id}",
    "--file $HOME/.kube/config",
    "--region ${var.region}",
    "--token-version 2.0.0",
    "--kube-endpoint PUBLIC_ENDPOINT",
  ])
}

output "load_balancer_note" {
  description = "How the public load balancer for ingress-nginx is provisioned (and kept free)."
  value       = <<-EOT
    No standalone OCI Load Balancer is created by Terraform. When you deploy
    ingress-nginx, its Service of type LoadBalancer makes OKE provision a public
    OCI Load Balancer in the public subnet (see options.service_lb_subnet_ids in
    oke.tf).

    To keep it on the Always-Free tier ($0), the ingress-nginx Service MUST
    request the free FLEXIBLE 10 Mbps shape (min = max = 10) via OCI
    annotations. This lives in the Kubernetes manifests / Helm values, NOT in
    Terraform:

      service.beta.kubernetes.io/oci-load-balancer-shape: "flexible"
      service.beta.kubernetes.io/oci-load-balancer-shape-flex-min: "10"
      service.beta.kubernetes.io/oci-load-balancer-shape-flex-max: "10"

    Omitting these (or setting min != max, or a value other than 10) provisions
    a billable load balancer.

    Get the LB public IP after deploying ingress-nginx:
      kubectl get svc -n ingress-nginx
    (look at the EXTERNAL-IP column)
  EOT
}
