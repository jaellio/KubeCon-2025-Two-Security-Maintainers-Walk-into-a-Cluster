#!/bin/bash

########################
# KubeCon 2025 Security Demo
# "No Joke: Two Security Maintainers Walk into a Cluster"
#
# This demo showcases common Kubernetes security pitfalls
# and their fixes using a "broken → fix" narrative.
########################

# Get the directory where this script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

########################
# Source demo-magic
########################
. "${SCRIPT_DIR}/demo-magic.sh"

########################
# Configuration
########################
TYPE_SPEED=30
DEMO_PROMPT="${GREEN}➜ ${CYAN}\W ${COLOR_RESET}"

# Cluster name
CLUSTER_NAME="kubecon-security-demo"

########################
# Color Definitions
########################
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m' # No Color

########################
# Helper Functions
########################

section_header() {
    local title="$1"
    local color="${2:-$CYAN}"

    # Calculate string length (not perfect with emojis, but simple and reliable)
    local title_len=${#title}

    # Border width = text length + 4 (for "  " on each side)
    local border_width=$((title_len + 4))

    # Generate the top/bottom border line
    local border_line=$(printf '═%.0s' $(seq 1 $border_width))

    # Generate the empty line with spaces
    local empty_line=$(printf ' %.0s' $(seq 1 $border_width))

    echo
    echo -e "${color}╔${border_line}╗${NC}"
    echo -e "${color}║${empty_line}║${NC}"
    echo -e "${color}║${NC}  ${title}  ${color}║${NC}"
    echo -e "${color}║${empty_line}║${NC}"
    echo -e "${color}╚${border_line}╝${NC}"
    echo
}

danger() {
    echo -e "${RED}🚨 $1${NC}"
}

success() {
    echo -e "${GREEN}✅ $1${NC}"
}

info() {
    echo -e "${CYAN}ℹ️  $1${NC}"
}

warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

########################
# Source Module Scripts
########################

# Source RBAC module
source "${SCRIPT_DIR}/modules/rbac.sh"

# Source Network Policy module
source "${SCRIPT_DIR}/modules/networkpolicy.sh"

# Source KMS module
source "${SCRIPT_DIR}/modules/kms.sh"

# Source Secret Management module
source "${SCRIPT_DIR}/modules/secretmanagement.sh"

# Add more modules here as you expand
# source "${SCRIPT_DIR}/modules/podsecurity.sh"

########################
# Main Demo Flow
########################

clear

section_header "KubeCon 2025 - No Joke: Two Security Maintainers Walk into a Cluster" "${MAGENTA}"
echo
info "This demo showcases common security misconfigurations"
info "and demonstrates how to fix them properly."
echo
info "Topics covered:"
echo "  • RBAC: Overly permissive service account bindings"
echo "  • Network Policy: Missing network segmentation"
echo "  • KMS: Secrets stored in plain text"
echo "  • Secret Management: Secure external secret storage"
echo
wait

#############################################
# Verify Cluster Exists
#############################################

clear
section_header "Verifying Cluster Setup ✓" "${BLUE}"
echo
info "Checking if cluster is ready..."
echo

# Check if cluster exists
if ! kubectl cluster-info &>/dev/null; then
    error "Cluster not found!"
    echo
    error "Please run ./setup-cluster.sh first to create the cluster"
    echo
    exit 1
fi

success "Cluster is ready!"
pe "kubectl cluster-info"
echo
wait

#############################################
# Run Security Demos
#############################################

# Run RBAC demo
demo_rbac

# Run Network Policy demo
demo_networkpolicy

# Run KMS demo
demo_kms

# Run Secret Management demo
demo_secretmanagement

# Add more demos here as you expand
# demo_podsecurity

#############################################
# Demo Complete
#############################################

clear
section_header "Demo Complete! 🎉" "${GREEN}"
echo
success "Thank you for watching!"
echo
info "Key Takeaways:"
echo "  • Always follow the principle of least privilege"
echo "  • Never use cluster-admin for application workloads"
echo "  • Implement default-deny network policies"
echo "  • Enable encryption at rest for Secrets (use KMS v2 in production)"
echo "  • Use external secret management (CSI driver + Vault/KMS)"
echo "  • Secrets should NEVER be stored in etcd if possible"
echo "  • Audit your RBAC and network policies regularly"
echo "  • Test your security configurations"
echo
info "To cleanup:"
echo "  Run ./cleanup-cluster.sh to delete the kind cluster"
echo
info "Questions? Feedback? Let's chat!"
echo
