#!/bin/bash

########################
# Secret Management with CSI Driver Demo Module
# Demonstrates why native K8s Secrets are risky and how CSI driver provides better security
########################

shopt -s expand_aliases
alias k='kubecolor'

demo_secretmanagement() {
    local MODULE_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
    local REPO_ROOT="$(dirname "$(dirname "$MODULE_DIR")")"
    local EXAMPLES_DIR="${REPO_ROOT}/secretmanagement/examples"

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

    clear
    section_header "Secret Management: The Mistake 💥" "${RED}"
    echo
    info "Many teams use native Kubernetes Secrets thinking they're secure..."
    info "Even with encryption at rest, secrets still pass through etcd"
    echo

    # Change to examples directory
#    p "cd secretmanagement/examples/vulnerable"
    cd "${EXAMPLES_DIR}/vulnerable"
    echo

    info "Let's create a native Kubernetes Secret with database credentials..."
    pe "cat db-secret.yaml"
    echo
    pe "k apply -f db-secret.yaml"
    echo

    info "Now deploy an app that uses this secret..."
    pe "cat app-with-secret.yaml"
    echo
    pe "k apply -f app-with-secret.yaml"
    echo

    k wait --for=condition=ready pod/app-with-secret --timeout=60s
    echo

    success "App is running with the secret..."
    echo
    danger "But is this really secure? Let's find out..."
    echo
    wait
    sleep 1

    #############################################
    # SCENE 2: The Impact (What This Means)
    #############################################

    clear
    section_header "Secret Management: Understanding the Impact 🔍" "${YELLOW}"
    echo
    info "Even with KMS encryption, secrets are still stored IN etcd..."
    info "Let's see what's stored in etcd..."
    echo

    info "First, let's decode what's in the secret..."
    echo
    pe "k get secret db-secret -o jsonpath='{.data.password}' | base64 -d"
    echo
    echo
    danger "😱 The password is accessible through the API!"
    echo
    wait
    wait

    info "Now let's check etcd..."
    echo
    pe "etcdctl_exec 'etcdctl --endpoints=https://127.0.0.1:2379 --cacert=/etc/kubernetes/pki/etcd/ca.crt --cert=/etc/kubernetes/pki/etcd/server.crt --key=/etc/kubernetes/pki/etcd/server.key get /registry/secrets/default/db-secret' | head -20"
    echo

    danger "Even with encryption, secrets exist in etcd!"
    danger "Anyone with etcd access can decrypt them through the API"
    echo
    wait
    wait

    #############################################
    # SCENE 3: The Attack (Simulated)
    #############################################

    clear
    section_header "Secret Management: The Attack Scenario 🎭" "${RED}"
    echo
    danger "Attack vectors with native Kubernetes Secrets:"
    echo
    wait

    danger "Attack 1: Compromised kubeconfig"
    echo
    info "Attacker steals a service account token with secret read access..."
    echo
    pe "k get secrets --all-namespaces"
    echo
    pe "k get secret db-secret -o yaml"
    echo
    danger "Attacker can read ALL secrets in allowed namespaces!"
    echo
    wait

    danger "Attack 2: etcd backup theft"
    echo
    info "Even encrypted backups can be decrypted if the encryption key is obtained..."
    echo
    danger "Attacker gets backup → Extracts secrets through API replay"
    echo
    wait

    danger "Attack 3: Blast radius"
    echo
    info "ALL secrets in the cluster are in etcd..."
    info "Compromising etcd = compromising EVERY secret"
    echo
    danger "🚨 Database passwords, API keys, certificates - ALL at risk! 🚨"
    echo
    wait

    danger "Attack 4: Environment variable exposure"
    echo
    info "Secrets exposed as env vars can leak through:"
    info "  • Crash dumps"
    info "  • Log files"
    echo
    pe "k exec app-with-secret -- env | grep DB_"
    echo
    danger "Environment variables are easily leaked!"
    echo
    wait
    wait

    #############################################
    # SCENE 4: The Fix (CSI Driver + Vault)
    #############################################

    clear
    section_header "Secret Management: The Fix ✅" "${GREEN}"
    echo
    success "Solution: Use Secrets Store CSI Driver with external provider (Vault)"
    echo
    info "Benefits:"
    echo "  • Secrets NEVER stored in etcd"
    echo "  • Direct retrieval from external provider"
    echo "  • Advanced features: rotation, audit"
    echo "  • Reduced blast radius"
    echo "  • Fine-grained access control"
    echo
    wait

    info "The cluster was pre-configured with:"
    echo "  ✅ Secrets Store CSI Driver installed"
    echo "  ✅ Vault deployed in dev mode"
    echo "  ✅ Secrets and policies configured"
    echo "  ✅ SecretProviderClass deployed"
    echo
    wait

    clear
    info "Let's verify Vault is running with our secrets:"
    echo
    cd "${EXAMPLES_DIR}/vault-setup"
    pe "k exec vault-0 -- env VAULT_TOKEN=root vault kv get secret/db-creds"
    echo
    success "✅ Secret stored in Vault, not etcd!"
    echo
    wait
    wait

    clear
    info "Now let's look at the SecretProviderClass configuration..."
    echo
    info "This tells the CSI driver how to map Vault secrets to filesystem paths"
    echo
    cd "${EXAMPLES_DIR}/csi-driver"
    pe "cat secretproviderclass.yaml"
    echo
    wait
    wait

    clear
    info "Let's look at the app configuration that uses CSI driver to mount secrets from Vault..."
    echo
    pe "cat app-with-csi.yaml"
    echo
    wait
    wait

    clear
    info "The app-with-csi pod was deployed during cluster setup..."
    echo
    info "Let's verify it's running with CSI-mounted secrets..."
    echo
    pe "k get pod app-with-csi"
    echo
    success "✅ App is running with CSI-mounted secrets!"
    echo
    wait
    wait

    #############################################
    # SCENE 5: The Result (Verification)
    #############################################

    clear
    section_header "Secret Management: Verifying the Fix 🔒" "${GREEN}"
    echo
    success "Let's verify secrets are NOT in etcd..."
    echo

    info "Checking etcd for any vault-related secrets..."
    echo
    pe "etcdctl_exec 'etcdctl --endpoints=https://127.0.0.1:2379 --cacert=/etc/kubernetes/pki/etcd/ca.crt --cert=/etc/kubernetes/pki/etcd/server.crt --key=/etc/kubernetes/pki/etcd/server.key get /registry/secrets/default/ --prefix --keys-only' | grep vault || echo \"No vault secrets in etcd!\""
    echo
    success "✅ No secrets stored in etcd!"
    echo
    wait
    wait

    clear
    info "Verify secrets are accessible to the pod from Vault..."
    echo
    pe "k exec app-with-csi -- ls -la /mnt/secrets-store"
    echo
    pe "k exec app-with-csi -- cat /mnt/secrets-store/password"
    echo
    success "✅ App can access secrets from Vault!"
    echo
    wait
    wait

    clear
    info "Check that secrets are NOT in Kubernetes Secrets..."
    echo
    pe "k get secrets | grep -i vault || echo 'No vault secrets in Kubernetes'"
    echo
    success "✅ Secrets managed externally, not in Kubernetes!"
    echo
    wait
    wait

    clear
    section_header "Secret Management: Summary 📋" "${CYAN}"
    echo
    success "✅ Deployed Vault as external secret provider"
    success "✅ Configured Secrets Store CSI Driver"
    success "✅ Secrets stored OUTSIDE of etcd"
    success "✅ Pod retrieves secrets directly from Vault"
    success "✅ No secrets in environment variables"
    success "✅ Reduced blast radius (etcd compromise ≠ secret compromise)"
    echo
    success "🎯 Secrets are now managed externally!"
    success "   Even compromising etcd doesn't expose these secrets"
    echo
    info "Additional benefits:"
    echo "  • Secret rotation via Vault"
    echo "  • Detailed audit logs in Vault"
    echo "  • Multi-cloud secret management"
    echo
    wait

    #############################################
    # Cleanup
    #############################################

    info "Cleaning up Secret Management demo resources..."
    # Only cleanup the vulnerable example resources created during the demo
    k delete pod app-with-secret --force --grace-period=0 --ignore-not-found=true &>/dev/null
    k delete secret db-secret --ignore-not-found=true &>/dev/null

    success "Done"
    echo

    # Return to original directory
    cd - &>/dev/null
}
