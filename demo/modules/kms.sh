#!/bin/bash

########################
# KMS (Encryption at Rest) Security Demo Module
# Demonstrates the danger of plain text secret storage in etcd
########################

demo_kms() {
    local MODULE_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
    local REPO_ROOT="$(dirname "$(dirname "$MODULE_DIR")")"
    local EXAMPLES_DIR="${REPO_ROOT}/kms/examples"

    #############################################
    # SCENE 1: The Mistake (Broken)
    #############################################

    clear
    section_header "KMS: The Mistake 💥" "${RED}"
    echo
    info "By default, Kubernetes stores Secrets in PLAIN TEXT in etcd..."
    info "Most teams don't realize this and assume 'Secrets' are encrypted"
    echo

    # Change to examples directory
    p "cd kms/examples"
    cd "${EXAMPLES_DIR}"
    echo

    info "Let's create a secret with database credentials..."
    pe "cat demo-secret.yaml"
    echo
    pe "kubectl apply -f demo-secret.yaml"
    echo
    pe "kubectl get secret db-credentials"
    echo
    danger "Secret created, but is it really secure?"
    echo
    wait

    #############################################
    # SCENE 2: The Impact (What This Means)
    #############################################

    clear
    section_header "KMS: Understanding the Impact 🔍" "${YELLOW}"
    echo
    info "Let's check how secrets are actually stored in etcd..."
    echo

    info "Accessing etcd from the control plane container..."
    echo
    pe "docker exec kubecon-security-demo-control-plane bash -c 'ETCDCTL_API=3 etcdctl --endpoints=https://127.0.0.1:2379 --cacert=/etc/kubernetes/pki/etcd/ca.crt --cert=/etc/kubernetes/pki/etcd/server.crt --key=/etc/kubernetes/pki/etcd/server.key get /registry/secrets/default/db-credentials'"
    echo
    danger "😱 The password is visible in PLAIN TEXT!"
    danger "Anyone with etcd access can read ALL your secrets!"
    echo
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
    pe "docker exec kubecon-security-demo-control-plane bash -c 'ETCDCTL_API=3 etcdctl --endpoints=https://127.0.0.1:2379 --cacert=/etc/kubernetes/pki/etcd/ca.crt --cert=/etc/kubernetes/pki/etcd/server.crt --key=/etc/kubernetes/pki/etcd/server.key get /registry/secrets --prefix --keys-only | head -10'"
    echo
    danger "Attacker knows what secrets exist in the cluster"
    echo
    wait

    danger "Attack 2: Read secrets from all namespaces"
    echo
    info "The attacker can read database passwords, API keys, certificates..."
    pe "kubectl get secrets --all-namespaces"
    echo
    danger "With etcd access, ALL of these are readable in plain text!"
    echo
    wait

    danger "Attack 3: Backup file theft"
    echo
    info "Even etcd backups contain plain-text secrets..."
    echo
    danger "Attacker steals backup → Gets ALL credentials offline"
    danger "No API server access needed, no detection possible"
    echo
    danger "🚨 COMPLETE CREDENTIAL THEFT - NO ENCRYPTION! 🚨"
    echo
    wait

    #############################################
    # SCENE 4: The Fix (Implementing Encryption)
    #############################################

    clear
    section_header "KMS: The Fix ✅" "${GREEN}"
    echo
    success "Good news: Encryption was pre-configured during cluster setup!"
    echo

    info "The cluster was created with this EncryptionConfiguration:"
    echo
    info "Location: /etc/kubernetes/enc/encryption-config.yaml (inside control plane)"
    echo
    pe "cat encryption-config-aescbc.yaml"
    echo
    wait

    success "This config uses aescbc (AES-CBC encryption)"
    info "In production, you should use KMS v2 instead:"
    echo
    pe "cat encryption-config-kms-v2.yaml | head -20"
    echo
    info "KMS v2 provides:"
    echo "  • External key management (AWS KMS, Azure Key Vault, etc.)"
    echo "  • Automatic key rotation"
    echo "  • Audit trail of all key access"
    echo "  • Compliance-friendly"
    echo
    wait

    info "Now let's activate the encryption by re-encrypting existing secrets..."
    echo
    pe "kubectl get secrets --all-namespaces -o json | kubectl replace -f -"
    echo
    success "All secrets have been re-encrypted!"
    echo
    wait

    #############################################
    # SCENE 5: The Result (Verification)
    #############################################

    clear
    section_header "KMS: Verifying the Fix 🔒" "${GREEN}"
    echo
    success "Let's verify that secrets are now encrypted in etcd..."
    echo

    info "Reading the same secret from etcd again..."
    echo
    pe "docker exec kubecon-security-demo-control-plane bash -c 'ETCDCTL_API=3 etcdctl --endpoints=https://127.0.0.1:2379 --cacert=/etc/kubernetes/pki/etcd/ca.crt --cert=/etc/kubernetes/pki/etcd/server.crt --key=/etc/kubernetes/pki/etcd/server.key get /registry/secrets/default/db-credentials'"
    echo
    success "✅ Secret is now an encrypted blob!"
    success "✅ Password is NOT readable in etcd!"
    success "✅ Data starts with 'k8s:enc:aescbc:v1:key1:' (encryption marker)"
    echo
    wait

    info "Let's create a NEW secret to confirm encryption is active..."
    echo
    pe "kubectl create secret generic test-secret --from-literal=data=sensitive"
    echo
    pe "docker exec kubecon-security-demo-control-plane bash -c 'ETCDCTL_API=3 etcdctl --endpoints=https://127.0.0.1:2379 --cacert=/etc/kubernetes/pki/etcd/ca.crt --cert=/etc/kubernetes/pki/etcd/server.crt --key=/etc/kubernetes/pki/etcd/server.key get /registry/secrets/default/test-secret' | head -5"
    echo
    success "✅ New secrets are automatically encrypted!"
    echo
    wait

    clear
    section_header "KMS: Summary 📋" "${CYAN}"
    echo
    success "✅ Enabled encryption at rest for Secrets"
    success "✅ Re-encrypted all existing secrets"
    success "✅ Verified secrets are encrypted in etcd"
    success "✅ Protected against etcd compromise"
    success "✅ Protected against backup theft"
    success "✅ Protected against insider threats"
    echo
    success "🎯 Secrets are now encrypted at rest!"
    success "   Even with etcd access, attacker cannot read credentials"
    echo
    info "For production, remember to:"
    echo "  • Use KMS v2 with external key management"
    echo "  • Rotate keys every 90 days"
    echo "  • Monitor encryption operations"
    echo "  • Backup encryption keys separately from etcd"
    echo
    wait

    #############################################
    # Cleanup
    #############################################

    info "Cleaning up KMS demo resources..."
    kubectl delete secret db-credentials --ignore-not-found=true &>/dev/null
    kubectl delete secret test-secret --ignore-not-found=true &>/dev/null
    success "Done"
    echo

    # Return to original directory
    cd - &>/dev/null
}
