#!/bin/bash

########################
# KMS (Encryption at Rest) Security Demo Module
# Demonstrates the danger of plain text secret storage in etcd
########################

shopt -s expand_aliases
alias k='kubecolor'

demo_kms() {
    local MODULE_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
    local REPO_ROOT="$(dirname "$(dirname "$MODULE_DIR")")"
    local EXAMPLES_DIR="${REPO_ROOT}/kms/examples"

    # Cluster names
    local CLUSTER_NOENC="kubecon-security-demo-noenc"
    local CLUSTER_ENC="kubecon-security-demo"

    # Helper function to execute etcdctl commands via k exec to the etcd pod
    etcdctl_exec() {
        local etcd_pod=$(k get pods -n kube-system -l component=etcd -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
        if [ -z "$etcd_pod" ]; then
            echo "Error: Could not find etcd pod in kube-system namespace" >&2
            return 1
        fi
        k exec -n kube-system "$etcd_pod" -- sh -c "$1"
    }

    #############################################
    # SCENE 1: The Mistake (Broken)
    #############################################

    # Switch to the no-encryption cluster
    k config use-context "kind-${CLUSTER_NOENC}" &>/dev/null

    clear
    section_header "KMS: The Mistake 💥" "${RED}"
    echo
    info "By default, Kubernetes stores Secrets in PLAIN TEXT in etcd..."
    info "Most teams don't realize this and assume 'Secrets' are encrypted"
    echo
    info "Using cluster: ${CLUSTER_NOENC} (no encryption configured)"
    echo

    # Change to examples directory
#    p "cd kms/examples"
    cd "${EXAMPLES_DIR}"
    echo

    info "Let's create a secret with database credentials..."
    pe "cat demo-secret.yaml"
    echo
    pe "k apply -f demo-secret.yaml"
    echo
    pe "k get secret db-credentials"
    echo
    danger "Secret created, but is it really secure?"
    echo
    wait
    wait

    #############################################
    # SCENE 2: The Impact (What This Means)
    #############################################

    clear
    section_header "KMS: Understanding the Impact 🔍" "${YELLOW}"
    echo
    info "Let's check how secrets are actually stored in etcd..."
    echo

    info "Accessing etcd from the etcd pod in kube-system..."
    echo
    pe "etcdctl_exec 'ETCDCTL_API=3 etcdctl --endpoints=https://127.0.0.1:2379 --cacert=/etc/kubernetes/pki/etcd/ca.crt --cert=/etc/kubernetes/pki/etcd/server.crt --key=/etc/kubernetes/pki/etcd/server.key get /registry/secrets/default/db-credentials'"
    echo
    danger "😱 The password is visible in PLAIN TEXT!"
    danger "Anyone with etcd access can read ALL your secrets!"
    echo
    wait
    wait

    #############################################
    # SCENE 3: The Attack (Simulated)
    #############################################

    clear
    section_header "KMS: The Attack Scenario 🎭" "${RED}"
    echo
    danger "An attacker gains access to the control plane node..."
    danger "They can now extract ALL secrets from the entire cluster!"
    echo
    wait

    danger "Attack 1: Extract all secret names"
    echo
    pe "etcdctl_exec 'ETCDCTL_API=3 etcdctl --endpoints=https://127.0.0.1:2379 --cacert=/etc/kubernetes/pki/etcd/ca.crt --cert=/etc/kubernetes/pki/etcd/server.crt --key=/etc/kubernetes/pki/etcd/server.key get /registry/secrets --prefix --keys-only' | head -10"
    echo
    danger "Attacker knows what secrets exist in the cluster"
    echo
    wait
    wait

    #############################################
    # SCENE 4: The Fix (Implementing Encryption)
    #############################################

    clear
    section_header "KMS: The Fix ✅" "${GREEN}"
    echo
    success "Let's see how encryption at rest protects our secrets!"
    echo

    info "Switching to a cluster with encryption ENABLED..."
    info "This cluster was created with aescbc encryption from the start"
    echo
    k config use-context kind-${CLUSTER_ENC}
    echo
    success "Now using cluster: ${CLUSTER_ENC} (encryption enabled)"
    echo
    wait

    info "Let's review the encryption configuration for this cluster..."
    echo
    pe "cat encryption-config-aescbc.yaml"
    echo
    wait
    wait

    #############################################
    # SCENE 5: The Result (Verification)
    #############################################

    clear
    section_header "KMS: Verifying the Fix 🔒" "${GREEN}"
    echo
    success "Let's verify that secrets are encrypted in this cluster..."
    echo

    info "First, let's create the same secret in the encrypted cluster..."
    echo
    pe "k apply -f demo-secret.yaml"
    echo
    success "Secret created in the encrypted cluster"
    echo
    wait

    info "Now let's check how it's stored in etcd..."
    echo
    pe "etcdctl_exec 'ETCDCTL_API=3 etcdctl --endpoints=https://127.0.0.1:2379 --cacert=/etc/kubernetes/pki/etcd/ca.crt --cert=/etc/kubernetes/pki/etcd/server.crt --key=/etc/kubernetes/pki/etcd/server.key get /registry/secrets/default/db-credentials'"
    echo
    success "✅ Secret is now an encrypted blob!"
    success "✅ Password is NOT readable in etcd!"
    success "✅ Data starts with 'k8s:enc:aescbc:v1:key1:' (encryption marker)"
    echo
    wait
    wait

    clear
    section_header "KMS: Summary 📋" "${CYAN}"
    echo
    success "✅ Demonstrated the problem: Secrets in plain text (no encryption)"
    success "✅ Demonstrated the solution: Secrets encrypted with aescbc"
    success "✅ Verified secrets are encrypted in etcd"
    success "✅ Protected against etcd compromise"
    success "✅ Protected against backup theft"
    echo
    success "🎯 Secrets are now encrypted at rest!"
    success "   Even with etcd access, attacker cannot read credentials"
    echo
#    info "For production, remember to:"
#    echo "  • Use KMS v2 with external key management"
#    echo "  • Rotate keys every 90 days"
#    echo "  • Monitor encryption operations"
#    echo "  • Backup encryption keys separately from etcd"
#    echo
    wait

    #############################################
    # Cleanup
    #############################################

    # Cleanup from both clusters
    k config use-context "kind-${CLUSTER_NOENC}" &>/dev/null
    k delete secret db-credentials --ignore-not-found=true &>/dev/null

    k config use-context "kind-${CLUSTER_ENC}" &>/dev/null
    k delete secret db-credentials --ignore-not-found=true &>/dev/null
    k delete secret test-secret --ignore-not-found=true &>/dev/null

    echo

    # Return to original directory
    cd - &>/dev/null
}
