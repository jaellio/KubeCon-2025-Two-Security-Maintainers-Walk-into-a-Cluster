#!/bin/bash

########################
# RBAC Security Demo Module
# Demonstrates the danger of overly permissive service account bindings
########################

demo_rbac() {
    local MODULE_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
    local REPO_ROOT="$(dirname "$(dirname "$MODULE_DIR")")"
    local EXAMPLES_DIR="${REPO_ROOT}/rbac/examples"

    #############################################
    # SCENE 1: The Mistake (Broken)
    #############################################

    clear
    section_header "RBAC: The Mistake 💥" "${RED}"
    echo
    info "A developer creates a ServiceAccount for testing..."
    info "They bind it to cluster-admin for 'convenience'"
    echo

    # Change to examples directory to use shorter paths
    p "cd rbac/examples"
    cd "${EXAMPLES_DIR}"
    echo

    pe "cat vulnerable-clusteradmin.yaml"
    echo
    danger "Notice: This ServiceAccount is bound to 'cluster-admin' ClusterRole!"
    echo
    wait

    info "Deploying the vulnerable configuration..."
    pe "kubectl apply -f vulnerable-clusteradmin.yaml"
    echo
    pe "kubectl get serviceaccount dev-service-account"
    pe "kubectl get clusterrolebinding dev-cluster-admin-binding"
    echo
    wait

    #############################################
    # SCENE 2: The Impact (What This Means)
    #############################################

    clear
    section_header "RBAC: Understanding the Impact 🔍" "${YELLOW}"
    echo
    info "Let's check what 'cluster-admin' actually grants..."
    echo

    pe "kubectl describe clusterrole cluster-admin | head -15"
    echo
    danger "This grants FULL access to ALL resources in ALL namespaces!"
    echo
    wait

    info "Testing what this ServiceAccount can do..."
    echo
    pe "kubectl auth can-i '*' '*' --as=system:serviceaccount:default:dev-service-account"
    echo
    pe "kubectl auth can-i delete nodes --as=system:serviceaccount:default:dev-service-account"
    echo
    pe "kubectl auth can-i get secrets --all-namespaces --as=system:serviceaccount:default:dev-service-account"
    echo
    pe "kubectl auth can-i create clusterrolebindings --as=system:serviceaccount:default:dev-service-account"
    echo
    danger "Every check returns 'yes' - total cluster control!"
    echo
    wait

    #############################################
    # SCENE 3: The Attack (Simulated)
    #############################################

    clear
    section_header "RBAC: The Attack Scenario 🎭" "${RED}"
    echo
    danger "An attacker finds an RCE vulnerability in your application..."
    danger "They deploy a pod using the overprivileged ServiceAccount..."
    echo

    pe "cat demo-pod.yaml"
    echo
    pe "kubectl apply -f demo-pod.yaml"
    pe "kubectl wait --for=condition=ready pod/demo-pod --timeout=60s"
    echo
    wait

    info "Now the attacker is inside the pod with cluster-admin privileges..."
    echo
    pe "kubectl exec demo-pod -- kubectl auth whoami"
    echo
    wait

    danger "They can steal all secrets from all namespaces..."
    echo
    pe "kubectl exec demo-pod -- kubectl get secrets -n kube-system"
    echo
    wait

    danger "They can list all nodes and potentially delete them..."
    echo
    pe "kubectl exec demo-pod -- kubectl get nodes"
    pe "kubectl exec demo-pod -- kubectl auth can-i delete nodes"
    echo
    wait

    danger "They can even create new admin accounts for persistence..."
    echo
    pe "kubectl exec demo-pod -- kubectl auth can-i create clusterrolebindings"
    pe "kubectl exec demo-pod -- kubectl auth can-i create serviceaccounts --all-namespaces"
    echo
    danger "🚨 COMPLETE CLUSTER COMPROMISE 🚨"
    echo
    wait

    #############################################
    # SCENE 4: The Fix (Implementing Least Privilege)
    #############################################

    clear
    section_header "RBAC: The Fix ✅" "${GREEN}"
    echo
    success "Let's implement the principle of least privilege..."
    echo

    info "Step 1: Remove the dangerous ClusterRoleBinding"
    pe "kubectl delete clusterrolebinding dev-cluster-admin-binding"
    echo
    wait

    info "Step 2: Create a scoped Role with ONLY necessary permissions"
    echo
    pe "cat scoped-role.yaml"
    echo
    wait

    info "Notice: This Role only grants access to pods, services, and configmaps"
    info "         - No access to secrets"
    info "         - No access to cluster resources"
    info "         - Limited to 'default' namespace only"
    echo
    wait

    pe "kubectl apply -f scoped-role.yaml"
    pe "kubectl apply -f scoped-rolebinding.yaml"
    echo
    wait

    #############################################
    # SCENE 5: The Result (Verification)
    #############################################

    clear
    section_header "RBAC: Verifying the Fix 🔒" "${GREEN}"
    echo
    info "Restarting the pod to pick up the new permissions..."
    echo

    pe "kubectl delete pod demo-pod --force --grace-period=0"
    pe "kubectl apply -f demo-pod.yaml"
    pe "kubectl wait --for=condition=ready pod/demo-pod --timeout=60s"
    echo
    wait

    success "Now let's test the attacker's capabilities with scoped permissions..."
    echo

    info "Can they list pods? (Yes - this is needed for the application)"
    pe "kubectl exec demo-pod -- kubectl auth can-i list pods"
    echo

    info "Can they list services? (Yes - this is needed for the application)"
    pe "kubectl exec demo-pod -- kubectl auth can-i list services"
    echo

    info "Can they get configmaps? (Yes - this is needed for the application)"
    pe "kubectl exec demo-pod -- kubectl auth can-i get configmaps"
    echo
    wait

    success "But now the dangerous permissions are blocked..."
    echo

    info "Can they get secrets? (No - secrets are protected!)"
    pe "kubectl exec demo-pod -- kubectl auth can-i get secrets"
    echo

    info "Can they access kube-system namespace? (No - scoped to default only!)"
    pe "kubectl exec demo-pod -- kubectl auth can-i list secrets -n kube-system"
    echo

    info "Can they delete nodes? (No - no cluster-wide access!)"
    pe "kubectl exec demo-pod -- kubectl auth can-i delete nodes"
    echo

    info "Can they create new admin bindings? (No - privilege escalation blocked!)"
    pe "kubectl exec demo-pod -- kubectl auth can-i create clusterrolebindings"
    echo
    wait

    clear
    section_header "RBAC: Summary 📋" "${CYAN}"
    echo
    success "✅ Removed cluster-admin binding"
    success "✅ Applied namespace-scoped Role with minimal permissions"
    success "✅ Granted only necessary access (pods, services, configmaps)"
    success "✅ Blocked secret access"
    success "✅ Prevented cluster-wide operations"
    success "✅ Eliminated privilege escalation paths"
    echo
    success "🎯 Blast radius significantly reduced!"
    success "   Even if compromised, attacker is contained to minimal permissions"
    echo
    wait

    #############################################
    # Cleanup
    #############################################

    info "Cleaning up RBAC demo resources..."
    kubectl delete -f demo-pod.yaml --force --grace-period=0 --ignore-not-found=true &>/dev/null
    kubectl delete -f scoped-rolebinding.yaml --ignore-not-found=true &>/dev/null
    kubectl delete -f scoped-role.yaml --ignore-not-found=true &>/dev/null
    kubectl delete -f vulnerable-clusteradmin.yaml --ignore-not-found=true &>/dev/null
    success "Done"
    echo

    # Return to original directory
    cd - &>/dev/null
}
