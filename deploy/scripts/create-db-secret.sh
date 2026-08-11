#!/usr/bin/env bash
set -euo pipefail
# Usage: NEON_PASSWORD=... ./create-db-secret.sh
NS=referral
POOLER_HOST=${POOLER_HOST:-ep-royal-rain-ax9qaocc-pooler.c-4.us-east-2.aws.neon.tech}
USER=${NEON_USER:-neondb_owner}
PASS=${NEON_PASSWORD:?set NEON_PASSWORD}
JDBC="jdbc:postgresql://${POOLER_HOST}/neondb?sslmode=require"
kubectl create namespace "$NS" --dry-run=client -o yaml | kubectl apply -f -
kubectl -n "$NS" create secret generic referral-db \
  --from-literal=SPRING_DATASOURCE_URL="$JDBC" \
  --from-literal=SPRING_DATASOURCE_USERNAME="$USER" \
  --from-literal=SPRING_DATASOURCE_PASSWORD="$PASS" \
  --from-literal=DATABASE_URL="$JDBC" \
  --from-literal=DATABASE_USER="$USER" \
  --from-literal=DATABASE_PASSWORD="$PASS" \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl -n "$NS" create secret generic referral-jwt \
  --from-literal=JWT_SECRET="$(openssl rand -base64 48)" \
  --dry-run=client -o yaml | kubectl apply -f -
echo "Created referral-db and referral-jwt in ns/$NS"
echo "TODO: create referral-redis (Upstash free or in-cluster Redis)"
