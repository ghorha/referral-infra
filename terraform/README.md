# Referral — OCI / OKE Infrastructure (Terraform)

Provisions the Oracle Cloud Infrastructure (OCI) needed to run the Referral
backend: an **OKE** (Oracle Kubernetes Engine) cluster hosting the 9 Spring Boot
microservices plus the Envoy gateway, and the networking required for a public
load balancer in front of the gateway.

## Always-Free ($0) target

This stack is sized to run entirely within the OCI **Always-Free** tier:

- **BASIC OKE cluster** — the Basic control plane is free (Enhanced clusters are
  billed hourly).
- **Arm Ampere A1 worker nodes** (`VM.Standard.A1.Flex`) — the free A1 grant is
  **4 OCPU + 24 GB total across the tenancy**. Defaults: **2 nodes x 2 OCPU /
  12 GB = 4 OCPU + 24 GB** (the whole grant).
- **Free flexible 10 Mbps load balancer** — created by ingress-nginx, not
  Terraform, and pinned to the free shape via annotations (see below).

> **A1 capacity caveat:** Always-Free A1 capacity is frequently exhausted in
> popular regions. `terraform apply` may fail with **"Out of host capacity"** /
> `500-InternalError`. This is an OCI availability issue, not a config bug —
> retry the apply (capacity frees up continuously), try a different availability
> domain, or target a less-contended region.

> **Images:** container images now live in **GitHub Container Registry**
> (`ghcr.io/ghorha/...`), not OCIR. Terraform no longer creates any registry.

## What gets created

| File | Resources |
|------|-----------|
| `versions.tf` | Terraform + `oracle/oci` provider requirements, provider auth, commented remote-state backend |
| `variables.tf` | All input variables (auth, cluster, node pool, networking) + free-LB annotation notes |
| `network.tf` | VCN, Internet/NAT/Service gateways, route tables, security lists, public + private subnets |
| `oke.tf` | BASIC OKE cluster (public API endpoint, flannel CNI) + Arm A1 worker node pool (private subnet, aarch64 image) |
| `outputs.tf` | Cluster OCID, region, kubeconfig command, load balancer note |
| `terraform.tfvars.example` | Example variable values to copy to `terraform.tfvars` |

Everything is prefixed `referral-` and fully parameterized — no real OCIDs or
keys are hardcoded.

## Prerequisites

1. **An OCI account** with a **compartment** to deploy into, and enough
   Always-Free quota for a VCN, a BASIC OKE cluster, and the Arm A1 grant
   (4 OCPU + 24 GB, i.e. the 2 A1 worker nodes).
2. **OCI CLI** installed and configured — needed to fetch the kubeconfig and to
   look up supported values:
   ```bash
   # macOS
   brew install oci-cli
   oci setup config   # or configure ~/.oci/config manually
   ```
3. **An API signing key** uploaded to your IAM user
   (Console -> Profile -> API Keys -> Add API Key). You need:
   - `tenancy_ocid`, `user_ocid`, `compartment_ocid`
   - the key `fingerprint`
   - the local path to the PEM `private_key_path`
4. **Terraform** >= 1.5 and **kubectl** (to talk to the cluster after apply).

## Usage

```bash
cd terraform

# 1. Provide your values
cp terraform.tfvars.example terraform.tfvars
#   ...edit terraform.tfvars: tenancy/compartment/user OCIDs, fingerprint,
#      private_key_path, region, and (importantly) k8s_version.

# 2. Initialise providers
terraform init

# 3. Review the plan
terraform plan

# 4. Create everything
terraform apply
```

State is stored locally by default. For team use, enable the OCI Object Storage
(S3-compatible) backend documented at the bottom of `versions.tf`.

## After apply — get your kubeconfig

`terraform output kubeconfig_command` prints a ready-to-run command. It looks
like:

```bash
oci ce cluster create-kubeconfig \
  --cluster-id <cluster-ocid> \
  --file $HOME/.kube/config \
  --region <region> \
  --token-version 2.0.0 \
  --kube-endpoint PUBLIC_ENDPOINT

kubectl get nodes   # verify
```

## Container images (GitHub Container Registry)

Images are **not** stored in OCIR — Terraform creates no registry. They live in
**GitHub Container Registry** under `ghcr.io/ghorha`:

```
ghcr.io/ghorha/fs-<svc>:<tag>
```

Build/push with the GitHub CLI or Docker (auth uses a GitHub PAT / `GITHUB_TOKEN`
with `write:packages`), typically from CI:

```bash
echo "$GITHUB_TOKEN" | docker login ghcr.io -u <github-user> --password-stdin
docker tag referral-api-gateway:latest ghcr.io/ghorha/referral-api-gateway:latest
docker push ghcr.io/ghorha/referral-api-gateway:latest
```

If the ghcr packages are private, create an `imagePullSecret` (docker-registry
type) in the cluster and reference it from the workload manifests.

## The gateway load balancer (free 10 Mbps)

No standalone load balancer is created by Terraform. Deploy **ingress-nginx** as
a Kubernetes `Service` of type `LoadBalancer`; OKE then provisions a **public
OCI Load Balancer** in the public subnet automatically.

To keep the LB on the **Always-Free** tier, the ingress-nginx Service must
request the free **flexible 10 Mbps** shape (min = max = 10) via OCI
annotations. This goes in the Kubernetes manifests / Helm values, **not** in
Terraform:

```yaml
service.beta.kubernetes.io/oci-load-balancer-shape: "flexible"
service.beta.kubernetes.io/oci-load-balancer-shape-flex-min: "10"
service.beta.kubernetes.io/oci-load-balancer-shape-flex-max: "10"
```

Any other shape, or `min != max`, or a value other than 10, provisions a
**billable** load balancer. Get its address with
`kubectl get svc -n ingress-nginx`.

## Values you MUST review before apply

- **`compartment_ocid`, `tenancy_ocid`, `user_ocid`, `fingerprint`,
  `private_key_path`** — your credentials/tenancy (no defaults).
- **`k8s_version`** — must be a currently supported OKE version. Verify:
  ```bash
  oci ce cluster-options get --cluster-option-id all \
    --query 'data."kubernetes-versions"'
  ```
- **`node_image_ocid`** — auto-discovered by default (the newest Oracle-Linux-8
  **aarch64** image matching `k8s_version`, required by the A1 shape). Set
  explicitly only if discovery finds no image for your chosen
  `k8s_version`/region — make sure you pick an **aarch64** image, not x86:
  ```bash
  oci ce node-pool-options get --node-pool-option-id all \
    --query 'data.sources[?contains("source-name", `aarch64`)].{name:"source-name",id:"image-id"}'
  ```
- **`api_endpoint_allowed_cidr`** — defaults to `0.0.0.0/0`. Restrict it to your
  office/VPN CIDR for production.

## Destroy

```bash
terraform destroy
```
