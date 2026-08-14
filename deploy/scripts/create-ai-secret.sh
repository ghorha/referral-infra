#!/usr/bin/env bash
set -euo pipefail
# Creates/updates the `fs-ai-keys` Secret consumed by referral-ai-service
# (chart `envFrom: [fs-ai-keys]`) — the AI provider API keys for the identity
# "360 view" embeddings and other AI work.
#
# The Phoenix OKE cluster uses DIRECT kubectl Secrets (like referral-db /
# referral-jwt via create-db-secret.sh), NOT OCI Vault / External Secrets —
# `deploy/secrets/external-secrets.yaml` is a Chicago-era artifact and is not
# applied here. See deploy/README.md § Secrets.
#
# Usage (set the keys you have; any subset is fine):
#   OPENAI_API_KEY=sk-... ANTHROPIC_API_KEY=sk-ant-... GEMINI_API_KEY=AIza... \
#     ./create-ai-secret.sh
#
# With no keys set, referral-ai-service still runs on the deterministic `stub`
# provider — a missing key simply disables that provider in the waterfall.

NS=referral

args=()
keys=()
if [ -n "${OPENAI_API_KEY:-}" ]; then
  args+=(--from-literal=OPENAI_API_KEY="$OPENAI_API_KEY"); keys+=(OPENAI_API_KEY)
fi
if [ -n "${ANTHROPIC_API_KEY:-}" ]; then
  args+=(--from-literal=ANTHROPIC_API_KEY="$ANTHROPIC_API_KEY"); keys+=(ANTHROPIC_API_KEY)
fi
if [ -n "${GEMINI_API_KEY:-}" ]; then
  args+=(--from-literal=GEMINI_API_KEY="$GEMINI_API_KEY"); keys+=(GEMINI_API_KEY)
fi

if [ ${#args[@]} -eq 0 ]; then
  echo "No provider keys set. Set at least one of:" >&2
  echo "  OPENAI_API_KEY / ANTHROPIC_API_KEY / GEMINI_API_KEY" >&2
  echo "(With none, referral-ai-service still answers via the 'stub' provider.)" >&2
  exit 1
fi

# Ensure the namespace exists, then upsert the Secret idempotently.
kubectl create namespace "$NS" --dry-run=client -o yaml | kubectl apply -f -
kubectl -n "$NS" create secret generic fs-ai-keys \
  "${args[@]}" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "Upserted secret fs-ai-keys in ns/$NS with keys: ${keys[*]}"
echo "If referral-ai-service is already running, roll it to pick up the change:"
echo "  kubectl -n $NS rollout restart deployment/referral-ai-service"
