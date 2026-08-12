#!/bin/bash

# ============================================================================
# Generate All Kubernetes Manifests Using Helm
# ============================================================================
# This script uses Helm to generate Kubernetes manifests for all environments
# ============================================================================

set -e

echo "======================================"
echo "Generating K8s Manifests with Helm"
echo "======================================"
echo ""

GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
HELM_CHART="$SCRIPT_DIR/../helm/referral-marketplace"
OUTPUT_BASE="$SCRIPT_DIR"

# Function to generate manifests for an environment
generate_manifests() {
  local env=$1
  local values_file=$2
  local output_dir="$OUTPUT_BASE/$env"
  
  echo "${BLUE}Generating manifests for: $env${NC}"
  
  # Create output directory
  mkdir -p "$output_dir"
  
  # Generate manifests using Helm template
  helm template referral-marketplace "$HELM_CHART" \
    --namespace "$env" \
    -f "$HELM_CHART/$values_file" \
    --output-dir "$output_dir"
  
  echo "${GREEN}✓${NC} Generated manifests in $output_dir"
  echo ""
}

# Generate for each environment
generate_manifests "dev" "values-dev.yaml"
generate_manifests "staging" "values-staging.yaml"
generate_manifests "production" "values.yaml"

echo "${GREEN}======================================"
echo "✓ All Manifests Generated"
echo "======================================${NC}"
echo ""
echo "Manifests generated in:"
echo "  - infrastructure/kubernetes/dev/"
echo "  - infrastructure/kubernetes/staging/"
echo "  - infrastructure/kubernetes/production/"
echo ""
echo "To deploy:"
echo "  kubectl apply -f infrastructure/kubernetes/dev/ --recursive"
echo "  kubectl apply -f infrastructure/kubernetes/staging/ --recursive"
echo "  kubectl apply -f infrastructure/kubernetes/production/ --recursive"
echo ""

