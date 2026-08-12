#!/bin/bash

# ============================================================================
# Generate Kubernetes Manifests for All Services and Environments
# ============================================================================
# This script generates Kubernetes deployment manifests for all 12 services
# across dev, staging, and production environments using Helm
# ============================================================================

set -e

echo "======================================"
echo "Generating Kubernetes Manifests"
echo "======================================"
echo ""

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
HELM_CHART_DIR="$SCRIPT_DIR/helm/referral-marketplace"
OUTPUT_DIR="$SCRIPT_DIR/kubernetes"

# Environments
ENVIRONMENTS=("dev" "staging" "production")

# Services configuration
declare -A SERVICE_PORTS
SERVICE_PORTS=(
  ["api-gateway"]=8080
  ["auth-service"]=8081
  ["listing-service"]=8082
  ["claim-service"]=8083
  ["payment-service"]=8084
  ["user-service"]=8085
  ["admin-service"]=8086
  ["notification-service"]=8087
  ["support-service"]=8088
  ["analytics-service"]=8089
  ["audit-service"]=8090
  ["orchestration-service"]=8091
)

# Function to generate manifest for a service
generate_service_manifest() {
  local environment=$1
  local service=$2
  local port=$3
  local namespace=$environment
  
  # Determine replicas based on environment
  case $environment in
    dev)
      replicas=1
      min_replicas=1
      max_replicas=3
      cpu_request="100m"
      mem_request="256Mi"
      cpu_limit="250m"
      mem_limit="512Mi"
      ;;
    staging)
      replicas=2
      min_replicas=2
      max_replicas=6
      cpu_request="200m"
      mem_request="384Mi"
      cpu_limit="400m"
      mem_limit="768Mi"
      ;;
    production)
      replicas=3
      min_replicas=2
      max_replicas=10
      cpu_request="250m"
      mem_request="512Mi"
      cpu_limit="500m"
      mem_limit="1Gi"
      ;;
  esac
  
  # Special cases for certain services
  if [[ "$service" == "api-gateway" ]] || [[ "$service" == "orchestration-service" ]]; then
    cpu_request="500m"
    mem_request="512Mi"
    cpu_limit="1000m"
    mem_limit="1Gi"
  fi
  
  if [[ "$service" == "claim-service" ]]; then
    cpu_request="500m"
    mem_request="1Gi"
    cpu_limit="1000m"
    mem_limit="2Gi"
  fi
  
  # Output file
  local output_file="$OUTPUT_DIR/$environment/$(printf "%02d" $(echo ${!SERVICE_PORTS[@]} ${service} | tr ' ' '\n' | grep -n "^${service}$" | cut -d: -f1))-${service}.yaml"
  
  cat > "$output_file" <<EOF
---
# ${service^} Deployment
apiVersion: apps/v1
kind: Deployment
metadata:
  name: $service
  namespace: $namespace
  labels:
    app: $service
    version: v1
    environment: $environment
spec:
  replicas: $replicas
  selector:
    matchLabels:
      app: $service
  template:
    metadata:
      labels:
        app: $service
        version: v1
        environment: $environment
      annotations:
        prometheus.io/scrape: "true"
        prometheus.io/port: "$port"
        prometheus.io/path: "/actuator/prometheus"
    spec:
      containers:
      - name: $service
        image: your-ecr-repo/$service:latest
        imagePullPolicy: Always
        ports:
        - containerPort: $port
          name: http
        env:
        - name: SERVER_PORT
          value: "$port"
        - name: SPRING_PROFILES_ACTIVE
          value: "$environment"
EOF

  # Add database config for services that need it
  if [[ "$service" != "analytics-service" ]] && [[ "$service" != "orchestration-service" ]] && [[ "$service" != "api-gateway" ]]; then
    cat >> "$output_file" <<EOF
        - name: DB_USERNAME
          valueFrom:
            secretKeyRef:
              name: database-secret
              key: username
        - name: DB_PASSWORD
          valueFrom:
            secretKeyRef:
              name: database-secret
              key: password
        - name: SPRING_DATASOURCE_URL
          value: "jdbc:postgresql://\$(DB_HOST):\$(DB_PORT)/\$(DB_NAME)"
        - name: DB_HOST
          valueFrom:
            secretKeyRef:
              name: database-secret
              key: host
        - name: DB_PORT
          valueFrom:
            secretKeyRef:
              name: database-secret
              key: port
        - name: DB_NAME
          valueFrom:
            secretKeyRef:
              name: database-secret
              key: database
EOF
  fi

  # Add JWT secret for most services
  cat >> "$output_file" <<EOF
        - name: JWT_SECRET
          valueFrom:
            secretKeyRef:
              name: jwt-secret
              key: secret
EOF

  # Add Redis config for services that need it
  if [[ "$service" == "api-gateway" ]] || [[ "$service" == "auth-service" ]] || [[ "$service" == "orchestration-service" ]]; then
    cat >> "$output_file" <<EOF
        - name: REDIS_HOST
          valueFrom:
            configMapKeyRef:
              name: referral-marketplace-config
              key: REDIS_HOST
        - name: REDIS_PORT
          valueFrom:
            configMapKeyRef:
              name: referral-marketplace-config
              key: REDIS_PORT
EOF
  fi

  # Service-specific environment variables
  case $service in
    auth-service)
      cat >> "$output_file" <<EOF
        - name: MAILGUN_API_KEY
          valueFrom:
            secretKeyRef:
              name: mailgun-secret
              key: api-key
        - name: MAILGUN_DOMAIN
          valueFrom:
            secretKeyRef:
              name: mailgun-secret
              key: domain
        - name: MAILGUN_ENABLED
          value: "$([[ "$environment" == "dev" ]] && echo "false" || echo "true")"
EOF
      ;;
    payment-service)
      cat >> "$output_file" <<EOF
        - name: STRIPE_API_KEY
          valueFrom:
            secretKeyRef:
              name: stripe-secret
              key: api-key
        - name: STRIPE_WEBHOOK_SECRET
          valueFrom:
            secretKeyRef:
              name: stripe-secret
              key: webhook-secret
        - name: STRIPE_ENABLED
          value: "$([[ "$environment" == "dev" ]] && echo "false" || echo "true")"
EOF
      ;;
    claim-service)
      cat >> "$output_file" <<EOF
        - name: STORAGE_TYPE
          value: "s3"
        - name: S3_BUCKET
          valueFrom:
            secretKeyRef:
              name: aws-s3-secret
              key: bucket
        - name: S3_REGION
          valueFrom:
            secretKeyRef:
              name: aws-s3-secret
              key: region
        - name: OCR_ENABLED
          value: "$([[ "$environment" == "dev" ]] && echo "false" || echo "true")"
EOF
      ;;
  esac

  # Complete the manifest
  cat >> "$output_file" <<EOF
        resources:
          requests:
            cpu: $cpu_request
            memory: $mem_request
          limits:
            cpu: $cpu_limit
            memory: $mem_limit
        livenessProbe:
          httpGet:
            path: /actuator/health/liveness
            port: $port
          initialDelaySeconds: 90
          periodSeconds: 10
          failureThreshold: 3
        readinessProbe:
          httpGet:
            path: /actuator/health/readiness
            port: $port
          initialDelaySeconds: 60
          periodSeconds: 5
          failureThreshold: 3

---
# ${service^} Service
apiVersion: v1
kind: Service
metadata:
  name: $service
  namespace: $namespace
  labels:
    app: $service
    environment: $environment
spec:
  type: ClusterIP
  ports:
  - port: $port
    targetPort: $port
    protocol: TCP
    name: http
  selector:
    app: $service

---
# ${service^} HPA
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: $service-hpa
  namespace: $namespace
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: $service
  minReplicas: $min_replicas
  maxReplicas: $max_replicas
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70
EOF

  echo "${GREEN}✓${NC} Generated $environment/$service"
}

# Create output directories
for env in "${ENVIRONMENTS[@]}"; do
  mkdir -p "$OUTPUT_DIR/$env"
done

# Generate manifests for all services in all environments
echo "${BLUE}Generating manifests for all environments...${NC}"
echo ""

for env in "${ENVIRONMENTS[@]}"; do
  echo "${BLUE}Environment: $env${NC}"
  
  # Generate namespace if not production
  if [[ "$env" != "production" ]]; then
    cat > "$OUTPUT_DIR/$env/00-namespace.yaml" <<EOF
apiVersion: v1
kind: Namespace
metadata:
  name: $env
  labels:
    name: $env
    environment: $env
    project: referral-marketplace
EOF
    echo "${GREEN}✓${NC} Generated $env/00-namespace.yaml"
  fi
  
  # Generate secrets (basic version - update with actual values)
  if [[ ! -f "$OUTPUT_DIR/$env/secrets.yaml" ]] && [[ ! -f "$OUTPUT_DIR/$env/01-secrets.yaml" ]]; then
    cat > "$OUTPUT_DIR/$env/01-secrets.yaml" <<EOF
# NOTE: Update these secrets with actual values from Terraform outputs
# For production, use AWS Secrets Manager or External Secrets Operator

apiVersion: v1
kind: Secret
metadata:
  name: database-secret
  namespace: $env
type: Opaque
stringData:
  username: referral_user
  password: CHANGE_ME
  host: referral-marketplace-$env.xxxxx.rds.amazonaws.com
  port: "5432"
  database: referral_marketplace
---
apiVersion: v1
kind: Secret
metadata:
  name: jwt-secret
  namespace: $env
type: Opaque
stringData:
  secret: $env-jwt-secret-256-bit-key-change-me
---
apiVersion: v1
kind: Secret
metadata:
  name: stripe-secret
  namespace: $env
type: Opaque
stringData:
  api-key: sk_test_${env}_key
  webhook-secret: whsec_${env}_secret
---
apiVersion: v1
kind: Secret
metadata:
  name: mailgun-secret
  namespace: $env
type: Opaque
stringData:
  api-key: ${env}_mailgun_key
  domain: $env.referralmarketplace.com
  from: noreply@$env.referralmarketplace.com
---
apiVersion: v1
kind: Secret
metadata:
  name: aws-s3-secret
  namespace: $env
type: Opaque
stringData:
  bucket: referral-marketplace-files-$env
  region: us-east-1
EOF
    echo "${GREEN}✓${NC} Generated $env/01-secrets.yaml"
  fi
  
  # Generate configmap
  cat > "$OUTPUT_DIR/$env/02-configmap.yaml" <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: referral-marketplace-config
  namespace: $env
data:
  ENVIRONMENT: "$env"
  AUTH_SERVICE_URL: "http://auth-service:8081"
  USER_SERVICE_URL: "http://user-service:8085"
  LISTING_SERVICE_URL: "http://listing-service:8082"
  CLAIM_SERVICE_URL: "http://claim-service:8083"
  PAYMENT_SERVICE_URL: "http://payment-service:8084"
  ADMIN_SERVICE_URL: "http://admin-service:8086"
  NOTIFICATION_SERVICE_URL: "http://notification-service:8087"
  SUPPORT_SERVICE_URL: "http://support-service:8088"
  ANALYTICS_SERVICE_URL: "http://analytics-service:8089"
  AUDIT_SERVICE_URL: "http://audit-service:8090"
  ORCHESTRATION_SERVICE_URL: "http://orchestration-service:8091"
  REDIS_HOST: "referral-marketplace-$env.xxxxx.cache.amazonaws.com"
  REDIS_PORT: "6379"
  MAILGUN_ENABLED: "$([[ "$env" == "dev" ]] && echo "false" || echo "true")"
EOF
  echo "${GREEN}✓${NC} Generated $env/02-configmap.yaml"
  
  # Generate service manifests
  local counter=3
  for service in "${!SERVICE_PORTS[@]}"; do
    generate_service_manifest "$env" "$service" "${SERVICE_PORTS[$service]}"
    ((counter++))
  done
  
  echo ""
done

echo ""
echo "${GREEN}======================================"
echo "✓ Manifest Generation Complete"
echo "======================================${NC}"
echo ""
echo "Generated manifests for:"
for env in "${ENVIRONMENTS[@]}"; do
  count=$(ls -1 "$OUTPUT_DIR/$env"/*.yaml 2>/dev/null | wc -l)
  echo "  $env: $count files"
done
echo ""
echo "To deploy:"
echo "  kubectl apply -f infrastructure/kubernetes/dev/"
echo "  kubectl apply -f infrastructure/kubernetes/staging/"
echo "  kubectl apply -f infrastructure/kubernetes/production/"
echo ""

