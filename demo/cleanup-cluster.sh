#!/bin/bash

########################
# KubeCon 2025 Security Demo
# Cluster Cleanup Script
#
# This script removes the kind cluster and temporary files
# created during setup.
########################

set -e

# Configuration
CLUSTER_NAME="kubecon-security-demo"
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
TEMP_DIR="${SCRIPT_DIR}/.cluster-config"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Helper functions
info() {
    echo -e "${CYAN}ℹ️  $1${NC}"
}

success() {
    echo -e " ${GREEN}✅ $1${NC}"
}

warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

section() {
    echo
    echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
    echo
}

########################
# Main Cleanup
########################

section "Cleanup Demo Cluster"

# Check if cluster exists
if kind get clusters 2>/dev/null | grep -q "^${CLUSTER_NAME}$"; then
    info "Deleting kind cluster '${CLUSTER_NAME}'..."
    kind delete cluster --name "${CLUSTER_NAME}"
    success "Cluster deleted"
else
    warning "Cluster '${CLUSTER_NAME}' not found (already deleted?)"
fi

# Check if second cluster exists
if kind get clusters 2>/dev/null | grep -q "^${CLUSTER_NAME}-noenc$"; then
    info "Deleting kind cluster '${CLUSTER_NAME}-noenc'..."
    kind delete cluster --name "${CLUSTER_NAME}-noenc"
    success "Second cluster deleted"
else
    warning "Cluster '${CLUSTER_NAME}-noenc' not found (already deleted?)"
fi

# Clean up temporary files
if [ -d "${TEMP_DIR}" ]; then
    info "Removing temporary configuration files..."
    rm -rf "${TEMP_DIR}"
    success "Temporary files removed"
fi

section "Cleanup Complete!"

echo
success "All demo resources have been removed"
echo
info "To run the demo again:"
echo "  1. Run ./setup-cluster.sh to create a new cluster"
echo "  2. Run ./demo.sh to start the demo"
echo
