# KubeCon 2025 Security Demo

This directory contains an interactive demo script for the KubeCon 2025 talk: **"No Joke: Two Security Maintainers Walk into a Cluster"**.

## Overview

The demo uses [demo-magic](https://github.com/paxtonhare/demo-magic) to create a scripted, repeatable demonstration of common Kubernetes security pitfalls and their fixes. The demo follows a **"broken → fix"** narrative pattern to clearly illustrate the impact of misconfigurations and how to properly secure your cluster.

## Prerequisites

Before running the demo, ensure you have the following installed:

- **kind** (Kubernetes in Docker) - For creating local clusters
- **kubectl** - For interacting with Kubernetes
- **docker** - Required for kind and for accessing etcd in demos
- **bash** - For running the demo scripts

### Verify Prerequisites

```bash
# Check kind installation
kind version

# Check kubectl installation
kubectl version --client

# Check docker installation
docker --version

# Check docker is running
docker info

# Check bash version (3.2+ required)
bash --version
```

## Quick Start

The demo uses a **3-step workflow**:

```bash
# Step 1: Setup (one-time, before demo)
cd demo
./setup-cluster.sh      # Creates pre-configured cluster (~2-3 minutes)

# Step 2: Run Demo (repeatable)
./demo.sh              # Runs all security demonstrations

# Step 3: Cleanup (after demo)
./cleanup-cluster.sh   # Removes cluster and temporary files
```

## Directory Structure

```
demo/
├── README.md              # This file
├── setup-cluster.sh      # Pre-demo cluster setup script
├── cleanup-cluster.sh    # Post-demo cleanup script
├── demo-magic.sh          # Demo-magic script (simulates typing)
├── demo.sh               # Main demo orchestrator script
└── modules/
    ├── rbac.sh           # RBAC security demo module
    ├── networkpolicy.sh  # Network Policy security demo module
    ├── kms.sh            # KMS (Encryption at Rest) demo module
    └── secretmanagement.sh # Secret Management (CSI Driver) demo module
```

## Setup Instructions

### Before the Demo

**Run the setup script to create a pre-configured cluster:**

```bash
cd demo
./setup-cluster.sh
```

**What this does:**
- Checks prerequisites (kind, kubectl, docker, helm)
- Generates encryption key for KMS demo
- Creates kind cluster with encryption pre-configured
- Pre-loads container images (nginx, netshoot, kubectl, vault)
- Installs Secrets Store CSI Driver and Vault provider
- Verifies cluster health
- Shows ready confirmation

**Time:** 3-5 minutes (do this before your presentation!)

### Running the Demo

**After setup is complete, run the demo:**

```bash
cd demo
./demo.sh
```

**What this does:**
- Verifies cluster is running
- Runs RBAC demo (cluster-admin misconfiguration)
- Runs Network Policy demo (missing segmentation)
- Runs KMS demo (plain text secrets in etcd)
- Runs Secret Management demo (CSI driver with Vault)
- Shows completion summary

**Time:** 20-25 minutes total (5-7 minutes per topic)

### After the Demo

**Clean up resources:**

```bash
cd demo
./cleanup-cluster.sh
```

**What this does:**
- Deletes the kind cluster
- Removes temporary configuration files
- Confirms cleanup

### Demo Modes

### Interactive Mode (Default)

By default, the demo runs in **interactive mode**:
- Press **ENTER** to advance to the next command
- The script simulates typing each command
- Commands execute after you press ENTER again

This is ideal for live presentations where you want to control the pace.

### Auto-Advance Mode (For Recording)

Run the demo with automatic progression (5-second delays):

```bash
./demo.sh -w5
```

Options:
- `-w<seconds>` - Auto-advance after specified seconds (e.g., `-w3`, `-w5`, `-w10`)

This is ideal for:
- Recording backup footage
- Creating tutorial videos
- Practice runs

### Debug Mode (No Typing Simulation)

Run without the typing simulation:

```bash
./demo.sh -d
```

This immediately executes commands without the simulated typing effect, useful for:
- Debugging script issues
- Quickly testing changes
- Validating command syntax

## Demo Topics

### 1. RBAC (Role-Based Access Control)

**The Mistake**: A developer binds a service account to `cluster-admin` for testing convenience and forgets to remove it.

**The Impact**:
- Complete cluster compromise if the pod is breached
- Attacker can read all secrets, delete resources, create admin accounts
- No namespace isolation

**The Fix**:
- Remove `cluster-admin` ClusterRoleBinding
- Apply namespace-scoped Role with minimal permissions
- Grant only necessary access (pods, services, configmaps)
- Block secret access and cluster-wide operations

**Demo Flow**:
1. **Scene 1**: Show the vulnerable cluster-admin binding
2. **Scene 2**: Demonstrate the impact with `kubectl auth can-i` tests
3. **Scene 3**: Simulate an attack from inside a compromised pod
4. **Scene 4**: Apply the fix with scoped RBAC
5. **Scene 5**: Verify the fix blocks dangerous operations

### 2. Network Policy

**The Mistake**: Teams deploy applications without any NetworkPolicy, leaving all pod-to-pod communication wide open.

**The Impact**:
- No network segmentation between namespaces
- Compromised pods can perform lateral movement
- Data exfiltration to external servers unrestricted
- DNS tunneling attacks possible

**The Fix**:
- Apply default deny-all NetworkPolicy
- Selectively allow necessary internal traffic
- Restrict egress to internal network only
- Lock down DNS to CoreDNS in kube-system

**Demo Flow**:
1. **Scene 1**: Deploy pods without NetworkPolicy
2. **Scene 2**: Show unrestricted access (cross-namespace, internet, arbitrary DNS)
3. **Scene 3**: Simulate attacks (lateral movement, data exfiltration, DNS tunneling)
4. **Scene 4**: Apply progressive NetworkPolicy fixes
5. **Scene 5**: Verify all attacks are now blocked

### 3. KMS (Encryption at Rest)

**The Mistake**: Kubernetes stores Secrets in plain text in etcd by default. Most teams don't realize this.

**The Impact**:
- Anyone with etcd access can read ALL credentials
- Backup files contain plain-text secrets
- No protection against insider threats or backup theft
- Compliance violations (PCI-DSS, HIPAA, SOC 2)

**The Fix**:
- Enable encryption at rest with EncryptionConfiguration
- Use aescbc for demo (KMS v2 with external key management for production)
- Re-encrypt existing secrets
- Verify secrets are encrypted in etcd

**Demo Flow**:
1. **Scene 1**: Create secret, explain default plain text storage
2. **Scene 2**: Access etcd and read password in plain text
3. **Scene 3**: Simulate attacker extracting all credentials
4. **Scene 4**: Show pre-configured encryption, re-encrypt secrets
5. **Scene 5**: Verify secrets are now encrypted blobs

### 4. Secret Management with CSI Driver

**The Mistake**: Teams use native Kubernetes Secrets thinking they're secure, but even with encryption, secrets still exist in etcd.

**The Impact**:
- Secrets are vulnerable to etcd compromise
- Anyone with API access can read secrets
- Backup theft exposes all credentials
- No advanced lifecycle management (rotation, versioning)
- Large blast radius if etcd is compromised
- Environment variable exposure through logs/dumps

**The Fix**:
- Deploy Secrets Store CSI Driver
- Use external secret provider (HashiCorp Vault)
- Secrets stored OUTSIDE of etcd
- Direct retrieval from Vault
- Advanced features: rotation, audit logs, TTL
- Reduced blast radius

**Demo Flow**:
1. **Scene 1**: Create native K8s Secret, deploy app using it
2. **Scene 2**: Show secret exists in etcd (even with encryption)
3. **Scene 3**: Demonstrate multiple attack vectors (API access, backups, env vars)
4. **Scene 4**: Deploy Vault + CSI driver, configure external secrets
5. **Scene 5**: Verify secrets NOT in etcd, app accesses from Vault

### (More Topics Coming Soon)

The modular structure allows easy addition of new security topics:
- Pod Security Standards violations
- Image vulnerability scanning gaps
- Supply chain security

## Troubleshooting

### Cluster Setup Issues

**Problem**: `setup-cluster.sh` fails with "cluster already exists"
```bash
# Solution: Delete existing cluster
kind delete cluster --name kubecon-security-demo
./setup-cluster.sh
```

**Problem**: Docker daemon not running
```bash
# Solution: Start Docker Desktop or docker service
# macOS: Start Docker Desktop app
# Linux: sudo systemctl start docker
```

**Problem**: Images fail to pre-load
```bash
# Solution: Pull images manually
docker pull nginx:alpine
docker pull bitnami/kubectl:latest
docker pull nicolaka/netshoot:latest
docker pull hashicorp/vault:1.15
kind load docker-image nginx:alpine --name kubecon-security-demo
kind load docker-image hashicorp/vault:1.15 --name kubecon-security-demo
```

**Problem**: CSI driver installation fails
```bash
# Check helm installation
helm version

# Add helm repos manually
helm repo add secrets-store-csi-driver https://kubernetes-sigs.github.io/secrets-store-csi-driver/charts
helm repo add hashicorp https://helm.releases.hashicorp.com
helm repo update

# Verify CSI pods are running
kubectl get pods -n kube-system -l app.kubernetes.io/name=secrets-store-csi-driver
kubectl get pods -n kube-system -l app.kubernetes.io/name=vault-csi-provider
```

### Demo Execution Issues

**Problem**: `demo.sh` says "Cluster not found"
```bash
# Solution: Run setup first
./setup-cluster.sh
```

**Problem**: Pods not starting in Network Policy demo
```bash
# Check pod status
kubectl get pods -A

# Check events
kubectl get events --sort-by='.lastTimestamp'

# Restart if needed
kubectl delete pod --all -n demo-app
kubectl delete pod --all -n demo-sensitive
```

**Problem**: etcdctl commands fail in KMS demo
```bash
# Verify control plane container exists
docker ps | grep control-plane

# Verify etcd certificates exist
docker exec kubecon-security-demo-control-plane ls /etc/kubernetes/pki/etcd/
```

**Problem**: Vault pods not starting in Secret Management demo
```bash
# Check Vault pod status
kubectl get pods -l app=vault

# Check events
kubectl describe pod vault-0

# Check CSI driver is running
kubectl get pods -n kube-system -l app.kubernetes.io/name=secrets-store-csi-driver

# Restart vault if needed
kubectl delete pod vault-0
kubectl wait --for=condition=ready pod/vault-0 --timeout=90s
```

**Problem**: Demo script hangs or freezes
```bash
# Run in debug mode (no typing simulation)
./demo.sh -d

# Or skip to next section by pressing ENTER multiple times
```

### General Tips

- **Re-run setup if needed**: Setup script is idempotent
- **Check cluster health**: `kubectl get nodes` should show "Ready"
- **View logs**: Check demo script output for error messages
- **Clean slate**: Run `./cleanup-cluster.sh` then `./setup-cluster.sh` to start fresh

## Recording Tips
