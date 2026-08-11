# Referral edge: ingress-nginx + cert-manager + Let's Encrypt (OCI OKE)

The public entrypoint for the whole Referral backend is a **single OCI
Always-Free flexible LoadBalancer pinned to 10 Mbps**, owned by the
**ingress-nginx** controller. ingress-nginx terminates TLS (using a free
**Let's Encrypt** certificate obtained by **cert-manager**) and proxies plaintext
HTTP to the Envoy gateway (`referral-api-gateway` ClusterIP Service, port 8080), which does
JWT auth, rate limiting, and fan-out to the `fs-*` services.

```
Internet ──HTTPS──▶ OCI LB (10 Mbps) ──▶ ingress-nginx ──HTTP──▶ referral-api-gateway (Envoy) :8080 ──▶ fs-* services
                    (TLS terminates here, Let's Encrypt cert)
```

Files in this directory:

- `ingress-nginx-values.yaml` — Helm values that make the controller Service an
  OCI Always-Free 10 Mbps flexible LB (1 replica, IngressClass `nginx`).
- `clusterissuer.yaml` — cert-manager `ClusterIssuer`s: `letsencrypt-prod` and
  `letsencrypt-staging` (ACME HTTP-01 via the `nginx` ingress class).
- `ingress.yaml` — the `Ingress` for `api.<domain>` → `referral-api-gateway:8080` with the
  `cert-manager.io/cluster-issuer` annotation and a `tls` block.

## Prerequisites

- An OKE cluster with the OCI cloud-controller-manager (so `type: LoadBalancer`
  Services provision OCI LBs).
- `kubectl` pointed at the cluster and `helm` installed.
- The `referral` namespace and the `referral-api-gateway` Service already deployed.

## Install order

### 1. Install ingress-nginx (provisions the single public OCI LB)

```sh
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update

helm install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx --create-namespace \
  -f ingress-nginx-values.yaml
```

### 2. Install cert-manager (with CRDs)

```sh
helm repo add jetstack https://charts.jetstack.io
helm repo update

helm install cert-manager jetstack/cert-manager \
  --namespace cert-manager --create-namespace \
  --set crds.enabled=true
```

### 3. Create the Let's Encrypt ClusterIssuers

Edit `clusterissuer.yaml` first and replace the `email:` placeholder, then:

```sh
kubectl apply -f clusterissuer.yaml
```

### 4. Get the LoadBalancer external IP

```sh
kubectl get svc ingress-nginx-controller -n ingress-nginx \
  -o jsonpath='{.status.loadBalancer.ingress[0].ip}'; echo
# or simply watch it appear:
kubectl get svc ingress-nginx-controller -n ingress-nginx -w
```

### 5. Point DNS at the LB — REQUIRED BEFORE THE CERT CAN ISSUE

Create an **A record** for `api.<domain>` pointing at the external IP from step 4.
The Let's Encrypt **HTTP-01** challenge validates by hitting
`http://api.<domain>/.well-known/acme-challenge/...` through this LB, so the A
record must resolve to the LB **before** you apply the Ingress. Verify with:

```sh
dig +short api.<domain>       # must return the LB IP
```

### 6. Create the Ingress

Edit `ingress.yaml` and replace `api.example.com` (in **both** the `tls.hosts` and
the `rules.host` fields) with your real hostname, then:

```sh
kubectl apply -f ingress.yaml
```

## Verify the certificate

cert-manager creates a `Certificate` from the Ingress `tls` block and drives it to
`READY=True` once the HTTP-01 challenge succeeds:

```sh
kubectl get certificate -n referral
# NAME                 READY   SECRET                AGE
# api-referral-tls  True    api-referral-tls   2m

# If it is not Ready yet, inspect the ACME order/challenge:
kubectl describe certificate api-referral-tls -n referral
kubectl get certificaterequest,order,challenge -n referral
```

Then confirm TLS end-to-end:

```sh
curl -sSI https://api.<domain>/.well-known/jwks.json | head
# Expect: HTTP/2 200 and a Strict-Transport-Security header from the gateway.
```

## Tips

- **Test with staging first.** While validating DNS and the challenge, set the
  Ingress annotation to `cert-manager.io/cluster-issuer: letsencrypt-staging` to
  avoid Let's Encrypt production rate limits, then switch back to
  `letsencrypt-prod` and re-apply (delete the `api-referral-tls` secret to force
  a fresh prod issuance).
- HSTS (`Strict-Transport-Security`) is emitted by the Envoy gateway
  (`../gateway/configmap.yaml`), so it is present on every API response.
