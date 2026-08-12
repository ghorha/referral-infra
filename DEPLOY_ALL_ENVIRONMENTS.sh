#!/bin/bash

# ============================================================================
# Deploy Referral Marketplace to All Environments
# ============================================================================
# This script helps deploy the platform to dev, staging, and production
# ============================================================================

set -e

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Function to deploy to an environment
deploy_environment() {
  local env=$1
  local values_file=$2
  
  echo ""
  echo "${BLUE}======================================${NC}"
  echo "${BLUE}Deploying to: $env${NC}"
  echo "${BLUE}======================================${NC}"
  echo ""
  
  # Check if kubectl is configured for the cluster
  if ! kubectl get nodes &>/dev/null; then
    echo "${RED}✗ kubectl not configured. Run:${NC}"
    echo "  aws eks update-kubeconfig --name referral-marketplace-$env --region us-east-1"
    return 1
  fi
  
  echo "${YELLOW}1. Checking namespace...${NC}"
  if kubectl get namespace $env &>/dev/null; then
    echo "${GREEN}✓${NC} Namespace '$env' exists"
  else
    echo "${YELLOW}Creating namespace '$env'...${NC}"
    kubectl create namespace $env
    echo "${GREEN}✓${NC} Namespace created"
  fi
  
  echo ""
  echo "${YELLOW}2. Checking secrets...${NC}"
  if kubectl get secret database-secret -n $env &>/dev/null; then
    echo "${GREEN}✓${NC} Secrets exist"
  else
    echo "${RED}✗ Secrets not found${NC}"
    echo "  Please create secrets first:"
    echo "  kubectl apply -f kubernetes/$env/secrets.yaml"
    return 1
  fi
  
  echo ""
  echo "${YELLOW}3. Deploying with Helm...${NC}"
  helm upgrade --install referral-marketplace \
    "$SCRIPT_DIR/helm/referral-marketplace" \
    --namespace $env \
    -f "$SCRIPT_DIR/helm/referral-marketplace/$values_file" \
    --wait \
    --timeout 15m
  
  echo "${GREEN}✓${NC} Deployment complete"
  
  echo ""
  echo "${YELLOW}4. Verifying deployment...${NC}"
  kubectl get pods -n $env
  
  echo ""
  echo "${YELLOW}5. Checking services...${NC}"
  kubectl get svc -n $env
  
  echo ""
  echo "${GREEN}✓ $env environment deployed successfully!${NC}"
  echo ""
}

# Main menu
echo "${BLUE}======================================"
echo "Referral Marketplace Deployment"
echo "======================================${NC}"
echo ""
echo "Select environment to deploy:"
echo "  1) Development"
echo "  2) Staging"
echo "  3) Production"
echo "  4) All environments"
echo "  5) Generate manifests only (no deploy)"
echo "  6) Exit"
echo ""
read -p "Enter choice [1-6]: " choice

case $choice in
  1)
    deploy_environment "dev" "values-dev.yaml"
    ;;
  2)
    deploy_environment "staging" "values-staging.yaml"
    ;;
  3)
    echo "${RED}⚠️  WARNING: Deploying to PRODUCTION${NC}"
    read -p "Are you sure? (yes/no): " confirm
    if [[ "$confirm" == "yes" ]]; then
      deploy_environment "production" "values.yaml"
    else
      echo "Cancelled."
    fi
    ;;
  4)
    echo "${YELLOW}Deploying to all environments...${NC}"
    deploy_environment "dev" "values-dev.yaml"
    deploy_environment "staging" "values-staging.yaml"
    
    echo "${RED}⚠️  Ready to deploy to PRODUCTION${NC}"
    read -p "Deploy to production? (yes/no): " confirm
    if [[ "$confirm" == "yes" ]]; then
      deploy_environment "production" "values.yaml"
    fi
    ;;
  5)
    echo "${YELLOW}Generating manifests...${NC}"
    cd kubernetes
    ./GENERATE_ALL_MANIFESTS.sh
    ;;
  6)
    echo "Exiting."
    exit 0
    ;;
  *)
    echo "${RED}Invalid choice${NC}"
    exit 1
    ;;
esac

echo ""
echo "${GREEN}======================================"
echo "✓ Deployment Script Complete"
echo "======================================${NC}"
echo ""
echo "Access your deployments:"
echo "  Dev:        kubectl get pods -n dev"
echo "  Staging:    kubectl get pods -n staging"
echo "  Production: kubectl get pods -n production"
echo ""

