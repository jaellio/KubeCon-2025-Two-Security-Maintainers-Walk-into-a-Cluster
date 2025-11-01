#!/bin/bash

########################
# KubeCon 2025 Security Demo
# Cluster Setup Script
#
# This script creates a pre-configured kind cluster
# with all necessary settings for the security demos.
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
    echo -e "${GREEN}✅ $1${NC}"
}

error() {
    echo -e "${RED}❌ $1${NC}"
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
# Prerequisites Check
########################

section "Checking Prerequisites"

# Check for kind
if ! command -v kind &> /dev/null; then
    error "kind is not installed. Please install kind first."
    echo "  Visit: https://kind.sigs.k8s.io/docs/user/quick-start/#installation"
    exit 1
fi
success "kind installed: $(kind version)"

# Check for kubectl
if ! command -v kubectl &> /dev/null; then
    error "kubectl is not installed. Please install kubectl first."
    echo "  Visit: https://kubernetes.io/docs/tasks/tools/"
    exit 1
fi
success "kubectl installed: $(kubectl version --client --short 2>/dev/null || kubectl version --client)"

# Check for docker
if ! command -v docker &> /dev/null; then
    error "docker is not installed. Please install docker first."
    exit 1
fi
if ! docker info &> /dev/null; then
    error "docker daemon is not running. Please start docker first."
    exit 1
fi
success "docker is running"

# Check for helm
if ! command -v helm &> /dev/null; then
    error "helm is not installed. Please install helm first."
    echo "  Visit: https://helm.sh/docs/intro/install/"
    exit 1
fi
success "helm installed: $(helm version --short)"

########################
# Cleanup Old Cluster
########################

section "Checking for Existing Cluster"

if kind get clusters 2>/dev/null | grep -q "^${CLUSTER_NAME}$"; then
    warning "Cluster '${CLUSTER_NAME}' already exists"
    read -p "Delete and recreate? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        info "Deleting existing cluster..."
        kind delete cluster --name "${CLUSTER_NAME}"
        success "Old cluster deleted"
    else
        info "Using existing cluster"
        kubectl cluster-info --context "kind-${CLUSTER_NAME}"
        echo
        success "Cluster is ready! You can run ./demo.sh now"
        exit 0
    fi
else
    info "No existing cluster found"
fi

########################
# Prepare Configuration
########################

section "Preparing Cluster Configuration"

# Create temp directory
mkdir -p "${TEMP_DIR}"

# Generate encryption key for KMS demo (aescbc)
info "Generating encryption key for KMS demo..."
ENCRYPTION_KEY=$(head -c 32 /dev/urandom | base64)

# Create encryption configuration
cat > "${TEMP_DIR}/encryption-config.yaml" << EOF
apiVersion: apiserver.config.k8s.io/v1
kind: EncryptionConfiguration
resources:
  - resources:
      - secrets
    providers:
      - aescbc:
          keys:
            - name: key1
              secret: ${ENCRYPTION_KEY}
      - identity: {}
EOF

success "Encryption configuration created"

# Create kind cluster configuration
cat > "${TEMP_DIR}/kind-config.yaml" << EOF
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
name: ${CLUSTER_NAME}
nodes:
- role: control-plane
  extraMounts:
  - hostPath: ${TEMP_DIR}/encryption-config.yaml
    containerPath: /etc/kubernetes/enc/encryption-config.yaml
    readOnly: true
  kubeadmConfigPatches:
  - |
    kind: ClusterConfiguration
    apiServer:
      extraArgs:
        encryption-provider-config: /etc/kubernetes/enc/encryption-config.yaml
      extraVolumes:
      - name: encryption-config
        hostPath: /etc/kubernetes/enc
        mountPath: /etc/kubernetes/enc
        readOnly: true
EOF

success "Kind cluster configuration created"

########################
# Create Cluster
########################

section "Creating Kind Cluster"

info "Creating cluster '${CLUSTER_NAME}'..."
info "This may take 2-3 minutes..."
echo

kind create cluster --config "${TEMP_DIR}/kind-config.yaml"

echo
success "Cluster created successfully!"

########################
# Verify Cluster
########################

section "Verifying Cluster"

info "Waiting for cluster to be ready..."
kubectl wait --for=condition=Ready nodes --all --timeout=60s

info "Checking cluster info..."
kubectl cluster-info --context "kind-${CLUSTER_NAME}"

echo
success "Cluster is healthy!"

########################
# Pre-pull Images
########################

section "Pre-pulling Demo Images"

info "Pre-pulling container images for faster demo..."

# Images used in demos
IMAGES=(
    "nginx:alpine"
    "bitnami/kubectl:latest"
    "nicolaka/netshoot:latest"
    "hashicorp/vault:1.15"
)

for image in "${IMAGES[@]}"; do
    info "Pulling ${image}..."
    docker pull "${image}" &> /dev/null || warning "Failed to pull ${image}"
    # Load into kind cluster
    kind load docker-image "${image}" --name "${CLUSTER_NAME}" &> /dev/null || warning "Failed to load ${image} into cluster"
done

success "Images pre-loaded into cluster"

########################
# Install Secrets Store CSI Driver
########################

section "Installing Secrets Store CSI Driver"

info "Adding Secrets Store CSI Driver Helm repository..."
helm repo add secrets-store-csi-driver https://kubernetes-sigs.github.io/secrets-store-csi-driver/charts &> /dev/null || true
helm repo update &> /dev/null

info "Installing Secrets Store CSI Driver..."
helm install csi-secrets-store secrets-store-csi-driver/secrets-store-csi-driver \
    --namespace kube-system \
    --set syncSecret.enabled=true \
    --set enableSecretRotation=true \
    --wait &> /dev/null

success "Secrets Store CSI Driver installed"

info "Installing Vault CSI Provider..."
helm install vault-csi-provider hashicorp/vault-csi-provider \
    --namespace kube-system \
    --set "image.repository=hashicorp/vault-csi-provider" \
    --set "image.tag=1.4.2" \
    --wait &> /dev/null || {
    # If hashicorp helm repo not added yet, add it
    info "Adding HashiCorp Helm repository..."
    helm repo add hashicorp https://helm.releases.hashicorp.com &> /dev/null
    helm repo update &> /dev/null
    helm install vault-csi-provider hashicorp/vault-csi-provider \
        --namespace kube-system \
        --wait &> /dev/null
}

success "Vault CSI Provider installed"

info "Verifying CSI driver installation..."
kubectl get pods -n kube-system -l app.kubernetes.io/name=secrets-store-csi-driver
kubectl get pods -n kube-system -l app.kubernetes.io/name=vault-csi-provider

success "CSI Driver components are running"

########################
# Summary
########################

section "Setup Complete!"

echo
success "Kind cluster '${CLUSTER_NAME}' is ready for the demo!"
echo
info "Configuration summary:"
echo "  • Cluster name: ${CLUSTER_NAME}"
echo "  • Encryption: aescbc (pre-configured for KMS demo)"
echo "  • Images: Pre-loaded (nginx, kubectl, netshoot, vault)"
echo "  • CSI Driver: Secrets Store CSI Driver + Vault Provider"
echo "  • Context: kind-${CLUSTER_NAME}"
echo
info "Next steps:"
echo "  1. Run the demo: ./demo.sh"
echo "  2. When done, cleanup: ./cleanup-cluster.sh"
echo
success "You're all set! 🚀"
echo
