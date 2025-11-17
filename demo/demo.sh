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
# Enable kubectl alias for colored output
########################
shopt -s expand_aliases
alias k='kubecolor'

########################
# Configuration
########################
TYPE_SPEED=40
PROMPT_TIMEOUT=1
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

    # Fixed width border (looks good on standard terminal)
    local border_line="═══════════════════════════════════════════════════════════════════"

    echo
    echo -e "${color}${border_line}${NC}"
    echo -e "${color}  ${title}${NC}"
    echo -e "${color}${border_line}${NC}"
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

# Source Image Vulnerability module
source "${SCRIPT_DIR}/modules/imagevulnerability.sh"

# Source Pod Security Standards module
source "${SCRIPT_DIR}/modules/podsecuritystandard.sh"

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

sleep 2

#############################################
# Run Security Demos
#############################################

# Run RBAC demo
demo_rbac

# Run KMS demo
demo_kms

# Run Secret Management demo
demo_secretmanagement

# Run Network Policy demo
demo_networkpolicy

# Run Image Vulnerability demo
demo_imagevulnerability

# Run Pod Security Standards demo
demo_podsecuritystandard

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
