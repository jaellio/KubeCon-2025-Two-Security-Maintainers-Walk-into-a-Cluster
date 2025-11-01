#!/bin/bash

########################
# Secret Management with CSI Driver Demo Module
# Demonstrates why native K8s Secrets are risky and how CSI driver provides better security
########################

demo_secretmanagement() {
    local MODULE_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
    local REPO_ROOT="$(dirname "$(dirname "$MODULE_DIR")")"
    local EXAMPLES_DIR="${REPO_ROOT}/secretmanagement/examples"

    #############################################
    # SCENE 1: The Mistake (Broken)
    #############################################

    clear
    section_header "Secret Management: The Mistake 💥" "${RED}"
    echo
    info "Many teams use native Kubernetes Secrets thinking they're secure..."
    info "Even with encryption at rest (KMS), secrets still pass through etcd"
    echo

    # Change to examples directory
    p "cd secretmanagement/examples/vulnerable"
    cd "${EXAMPLES_DIR}/vulnerable"
    echo

    info "Let's create a native Kubernetes Secret with database credentials..."
    pe "cat db-secret.yaml"
    echo
    pe "kubectl apply -f db-secret.yaml"
    echo

    info "Now deploy an app that uses this secret..."
    pe "cat app-with-secret.yaml"
    echo
    pe "kubectl apply -f app-with-secret.yaml"
    echo

    pe "kubectl wait --for=condition=ready pod/app-with-secret --timeout=60s"
    echo

    success "App is running with the secret..."
    echo
    danger "But is this really secure? Let's find out..."
    echo
    wait

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
    pe "kubectl get secret db-secret -o jsonpath='{.data.password}'"
    echo
    echo
    info "That's base64 encoded. Let's decode it:"
    echo
    pe "kubectl get secret db-secret -o jsonpath='{.data.password}' | base64 -d"
    echo
    echo
    danger "😱 The password is accessible through the API!"
    echo
    wait

    info "Now let's check etcd..."
    echo
    pe "docker exec kubecon-security-demo-control-plane bash -c 'ETCDCTL_API=3 etcdctl --endpoints=https://127.0.0.1:2379 --cacert=/etc/kubernetes/pki/etcd/ca.crt --cert=/etc/kubernetes/pki/etcd/server.crt --key=/etc/kubernetes/pki/etcd/server.key get /registry/secrets/default/db-secret' | head -20"
    echo

    danger "Even with encryption, secrets exist in etcd!"
    danger "Anyone with etcd access can decrypt them through the API"
    echo
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
    pe "kubectl get secrets --all-namespaces"
    echo
    pe "kubectl get secret db-secret -o yaml"
    echo
    danger "Attacker can read ALL secrets in allowed namespaces!"
    echo
    wait

    danger "Attack 2: etcd backup theft"
    echo
    info "Even encrypted backups can be decrypted if the encryption key is obtained..."
    info "Backups often stored in less secure locations (S3 buckets, shared storage)"
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
    info "  • /proc filesystem"
    echo
    pe "kubectl exec app-with-secret -- env | grep DB_"
    echo
    danger "Environment variables are easily leaked!"
    echo
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
    echo "  • Advanced features: rotation, versioning, audit logs"
    echo "  • Reduced blast radius"
    echo "  • Fine-grained access control"
    echo
    wait

    info "Step 1: Deploy HashiCorp Vault in dev mode"
    echo
    p "cd ../vault-setup"
    cd "${EXAMPLES_DIR}/vault-setup"
    echo
    pe "cat vault-dev.yaml | head -30"
    echo
    pe "kubectl apply -f vault-dev.yaml"
    echo
    pe "kubectl wait --for=condition=ready pod/vault-0 --timeout=90s"
    echo
    success "Vault is running!"
    echo
    wait

    info "Step 2: Configure Vault with our secrets and policies"
    echo
    pe "cat vault-config.sh | head -40"
    echo
    pe "bash vault-config.sh"
    echo
    success "Vault configured with database credentials and policies!"
    echo
    wait

    info "Let's verify the secret is in Vault, NOT in Kubernetes:"
    echo
    pe "kubectl exec vault-0 -- vault kv get secret/db-creds"
    echo
    success "✅ Secret stored in Vault, not etcd!"
    echo
    wait

    info "Step 3: Create ServiceAccount for our app"
    echo
    pe "cat rbac.yaml"
    echo
    pe "kubectl apply -f rbac.yaml"
    echo
    wait

    info "Step 4: Configure SecretProviderClass (CSI driver config)"
    echo
    p "cd ../csi-driver"
    cd "${EXAMPLES_DIR}/csi-driver"
    echo
    pe "cat secretproviderclass.yaml"
    echo
    info "This maps Vault secrets to filesystem paths in the pod"
    echo
    pe "kubectl apply -f secretproviderclass.yaml"
    echo
    wait

    info "Step 5: Deploy app using CSI driver"
    echo
    pe "cat app-with-csi.yaml"
    echo
    pe "kubectl apply -f app-with-csi.yaml"
    echo
    pe "kubectl wait --for=condition=ready pod/app-with-csi --timeout=60s"
    echo
    success "App is running with CSI-mounted secrets!"
    echo
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
    pe "docker exec kubecon-security-demo-control-plane bash -c 'ETCDCTL_API=3 etcdctl --endpoints=https://127.0.0.1:2379 --cacert=/etc/kubernetes/pki/etcd/ca.crt --cert=/etc/kubernetes/pki/etcd/server.crt --key=/etc/kubernetes/pki/etcd/server.key get /registry/secrets/default/ --prefix --keys-only | grep vault || echo \"No vault secrets in etcd!\"'"
    echo
    success "✅ No secrets stored in etcd!"
    echo
    wait

    info "Verify secrets are accessible to the pod from Vault..."
    echo
    pe "kubectl exec app-with-csi -- ls -la /mnt/secrets-store"
    echo
    pe "kubectl exec app-with-csi -- cat /mnt/secrets-store/username"
    echo
    pe "kubectl exec app-with-csi -- cat /mnt/secrets-store/password"
    echo
    pe "kubectl exec app-with-csi -- cat /mnt/secrets-store/host"
    echo
    success "✅ App can access secrets from Vault!"
    echo
    wait

    info "Check that secrets are NOT in Kubernetes Secrets..."
    echo
    pe "kubectl get secrets | grep -i vault || echo 'No vault secrets in Kubernetes'"
    echo
    success "✅ Secrets managed externally, not in Kubernetes!"
    echo
    wait

    info "Compare the two approaches:"
    echo
    echo "Native K8s Secret (app-with-secret):"
    pe "kubectl exec app-with-secret -- env | grep DB_PASSWORD"
    echo
    echo "CSI Driver with Vault (app-with-csi):"
    pe "kubectl exec app-with-csi -- sh -c 'cat /mnt/secrets-store/password'"
    echo
    info "CSI approach: Secrets mounted as files, not env vars!"
    success "Less risk of leaking through logs or crash dumps"
    echo
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
    echo "  • Dynamic secrets (database credentials with TTL)"
    echo "  • Multi-cloud secret management"
    echo "  • Compliance-friendly (FIPS, PCI-DSS)"
    echo
    info "For production, remember to:"
    echo "  • Deploy Vault in HA mode (not dev mode!)"
    echo "  • Enable TLS for all Vault communication"
    echo "  • Use Vault namespaces for multi-tenancy"
    echo "  • Configure secret rotation policies"
    echo "  • Enable comprehensive audit logging"
    echo "  • Integrate with cloud KMS (AWS KMS, Azure Key Vault)"
    echo "  • Test disaster recovery procedures"
    echo
    wait

    #############################################
    # Cleanup
    #############################################

    info "Cleaning up Secret Management demo resources..."
    kubectl delete pod app-with-secret --force --grace-period=0 --ignore-not-found=true &>/dev/null
    kubectl delete secret db-secret --ignore-not-found=true &>/dev/null
    kubectl delete pod app-with-csi --force --grace-period=0 --ignore-not-found=true &>/dev/null
    kubectl delete secretproviderclass vault-db-creds --ignore-not-found=true &>/dev/null
    kubectl delete serviceaccount demo-sa --ignore-not-found=true &>/dev/null
    kubectl delete statefulset vault --ignore-not-found=true &>/dev/null
    kubectl delete service vault --ignore-not-found=true &>/dev/null
    kubectl delete serviceaccount vault --ignore-not-found=true &>/dev/null
    kubectl delete configmap vault-config --ignore-not-found=true &>/dev/null

    # Wait for vault pod to be fully deleted
    kubectl wait --for=delete pod/vault-0 --timeout=30s &>/dev/null || true

    success "Done"
    echo

    # Return to original directory
    cd - &>/dev/null
}
