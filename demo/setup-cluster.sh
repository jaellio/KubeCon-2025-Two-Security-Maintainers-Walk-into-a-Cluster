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
    echo -e " ${GREEN}✅ $1${NC}"
}

error() {
    echo -e " ${RED}❌ $1${NC}"
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
    kind delete cluster --name "${CLUSTER_NAME}"
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

# Create encryption configuration with aescbc (for encrypted cluster)
info "Creating encryption configuration (aescbc)..."
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

success "Encryption configuration created (aescbc enabled)"

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
    readOnly: false
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
        readOnly: false
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

REPO_ROOT="$(dirname "$SCRIPT_DIR")"

###########################
#### Setup Network Policy Demo Resources
###########################

section "Setting up Network Policy Demo Resources"

info "Deploying demo pods for network policy demo..."
kubectl apply -f "${REPO_ROOT}/networkpolicy/examples/demo-pods.yaml"
echo

info "Waiting for demo pods to be ready..."
kubectl wait --for=condition=ready pod/client-pod -n demo-app --timeout=60s
kubectl wait --for=condition=ready pod/server-pod -n demo-app --timeout=60s
kubectl wait --for=condition=ready pod/sensitive-pod -n demo-sensitive --timeout=60s
echo

success "Network policy demo pods ready"
echo

##########################
### Setup Pod Security Standards Demo
##########################

section "Setting up Pod Security Standards Demo Resources"

info "Creating production namespace (without PSS enforcement)..."
kubectl apply -f "${REPO_ROOT}/podsecuritystandard/examples/setup/prod-namespace.yaml"
echo

info "Deploying privileged-app pod in production..."
kubectl apply -f "${REPO_ROOT}/podsecuritystandard/examples/setup/privileged-app.yaml"
echo

info "Waiting for privileged-app to be ready..."
kubectl wait --for=condition=ready pod/privileged-app -n prod --timeout=60s
echo

success "Pod Security Standards demo resources ready"
echo

##########################
### Setup Image Vulnerability Demo
##########################

section "Setting up Image Vulnerability Demo Resources"

info "Deploying pod with vulnerable image (node:10)..."
kubectl apply -f "${REPO_ROOT}/imagevulnerability/examples/vulnerableimagepod.yaml"
echo

info "Waiting for vulnerable-node-demo to be ready..."
kubectl wait --for=condition=ready pod/vulnerable-node-demo --timeout=60s
echo

success "Image Vulnerability demo resources ready"
echo

##########################
### Install Secrets Store CSI Driver
##########################

section "Installing Secrets Store CSI Driver"

info "Adding Secrets Store CSI Driver Helm repository..."
helm repo add secrets-store-csi-driver https://kubernetes-sigs.github.io/secrets-store-csi-driver/charts &> /dev/null || true
helm repo update &> /dev/null

info "Installing Secrets Store CSI Driver..."
helm install csi-secrets-store secrets-store-csi-driver/secrets-store-csi-driver \
    --namespace kube-system \
    --set syncSecret.enabled=false \
    --set enableSecretRotation=true \
    --wait &> /dev/null

success "Secrets Store CSI Driver installed"

info "Installing Vault CSI Provider..."
kubectl apply -f https://raw.githubusercontent.com/hashicorp/vault-csi-provider/v1.4.3/deployment/vault-csi-provider.yaml

success "Vault CSI Provider installed"

info "Verifying CSI driver installation..."
kubectl get pods -n kube-system -l app.kubernetes.io/name=secrets-store-csi-driver
kubectl get pods -n csi -l app.kubernetes.io/name=vault-csi-provider

success "CSI Driver components are running"

#########################
## Deploy and Configure Vault
#########################

section "Deploying and Configuring Vault"

REPO_ROOT="$(dirname "$SCRIPT_DIR")"

info "Deploying Vault in dev mode..."
kubectl apply -f "${REPO_ROOT}/secretmanagement/examples/vault-setup/vault-dev.yaml"
echo

info "Waiting for Vault to be ready..."
kubectl wait --for=condition=ready pod -l app=vault --timeout=90s
echo

success "Vault is running!"
echo

info "Configuring Vault with secrets and policies..."
cd "${REPO_ROOT}/secretmanagement/examples/vault-setup"
bash vault-config.sh &> /dev/null
cd - &> /dev/null

success "Vault configured with database credentials and policies"
echo

info "Deploying SecretProviderClass..."
kubectl apply -f "${REPO_ROOT}/secretmanagement/examples/csi-driver/secretproviderclass.yaml"
echo

success "SecretProviderClass deployed"
echo

info "Creating ServiceAccount and RBAC for CSI app..."
kubectl apply -f "${REPO_ROOT}/secretmanagement/examples/vault-setup/rbac.yaml"
echo

success "ServiceAccount and RBAC created"
echo

info "Deploying app-with-csi pod..."
kubectl apply -f "${REPO_ROOT}/secretmanagement/examples/csi-driver/app-with-csi.yaml"
echo

info "Waiting for app-with-csi to be ready..."
kubectl wait --for=condition=ready pod/app-with-csi --timeout=90s
echo

success "app-with-csi pod deployed and running"
echo

success "✅ Vault and CSI driver are fully configured and ready for demo!"



#########################
## Create Second Cluster (No Encryption)
#########################

section "Creating Second Cluster (No Encryption)"

info "Creating a simple cluster WITHOUT encryption for comparison..."
info "Cluster name: ${CLUSTER_NAME}-noenc"
echo

kind delete cluster --name "${CLUSTER_NAME}-noenc"
kind create cluster --name "${CLUSTER_NAME}-noenc"

echo
success "Second cluster created (no encryption)!"

info "Waiting for cluster to be ready..."
kubectl wait --for=condition=Ready nodes --all --timeout=60s --context "kind-${CLUSTER_NAME}-noenc"

echo
success "Both clusters are ready!"

########################
# Summary
########################

section "Setup Complete!"

echo
success "Kind cluster is ready for the demo!"
echo
info "Configuration summary:"
echo
echo "Cluster: ${CLUSTER_NAME}"
echo "  • Encryption: aescbc enabled"
echo "  • Context: kind-${CLUSTER_NAME}"
echo "  • Demo Resources:"
echo "    - Pod Security Standards: prod namespace with privileged-app"
echo "    - Image Vulnerability: vulnerable-node-demo pod with node:10"
echo
info "Next steps:"
echo "  1. Run the demo: ./demo.sh"
echo "  2. When done, cleanup: ./cleanup-cluster.sh"
echo
info "Note: First demo run may take slightly longer as images are pulled"
echo
success "You're all set! 🚀"
echo
