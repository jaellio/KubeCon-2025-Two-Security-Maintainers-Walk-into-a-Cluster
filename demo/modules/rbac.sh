#!/bin/bash

########################
# RBAC Security Demo Module
# Demonstrates the danger of overly permissive service account bindings
########################

shopt -s expand_aliases
alias k='kubecolor'

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
#    p "cd rbac/examples"
    cd "${EXAMPLES_DIR}"
    echo

    pei "cat vulnerable-clusteradmin.yaml"
    echo
    danger "Notice: This ServiceAccount is bound to 'cluster-admin' ClusterRole!"
    echo
    wait
    wait

    clear
    info "Deploying the vulnerable configuration..."
    pei "k apply -f vulnerable-clusteradmin.yaml"
    echo
    wait
    pei "k get serviceaccount dev-service-account"
    echo
    wait
    wait
    pei "k get clusterrolebinding dev-cluster-admin-binding"
    echo
    wait
    wait

    #############################################
    # SCENE 2: The Impact (What This Means)
    #############################################

    clear
    section_header "RBAC: Understanding the Impact 🔍" "${YELLOW}"
    echo
    info "Let's check what 'cluster-admin' actually grants..."
    echo

    pe "k describe clusterrole cluster-admin"
    echo
    danger "This grants FULL access to ALL resources in ALL namespaces!"
    echo
    wait
    wait

    clear
    info "Testing what this ServiceAccount can do..."
    echo
    pe "k auth can-i get secrets --all-namespaces --as=system:serviceaccount:default:dev-service-account"
    echo
    pe "k auth can-i create clusterrolebindings --as=system:serviceaccount:default:dev-service-account"
    echo
    danger "Every check returns 'yes' - total cluster control!"
    echo
    wait
    wait

    #############################################
    # SCENE 3: The Attack (Simulated)
    #############################################

    clear
    section_header "RBAC: The Attack Scenario 🎭" "${RED}"
    echo
    danger "An attacker finds a vulnerability in your application..."
    danger "They deploy a pod using the overprivileged ServiceAccount..."
    echo

    pe "cat demo-pod.yaml"
    echo
    k apply -f demo-pod.yaml
    k wait --for=condition=ready pod/demo-pod --timeout=60s
    echo
    wait

    clear
    info "Now the attacker is inside the pod with cluster-admin privileges..."
    echo
    pe "k exec demo-pod -- kubectl auth whoami"
    echo
    wait
    wait

    clear
    danger "They can steal all secrets from all namespaces..."
    echo
    pe "k exec demo-pod -- kubectl get secrets -n kube-system"
    echo
    wait
    wait

    clear
    danger "They can even create new admin accounts for persistence..."
    echo
    pe "k exec demo-pod -- kubectl auth can-i create clusterrolebindings"
    echo
    pe "k exec demo-pod -- kubectl auth can-i create serviceaccounts --all-namespaces"
    echo
    danger "🚨 COMPLETE CLUSTER COMPROMISE 🚨"
    echo
    wait
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
    pe "k delete clusterrolebinding dev-cluster-admin-binding"
    echo
    wait
    wait

    info "Step 2: Create a scoped Role with ONLY necessary permissions"
    echo
    pe "cat scoped-role.yaml"
    echo
    wait
    wait

    info "Notice: This Role only grants access to pods, services, and configmaps"
    info "         - No access to secrets"
    info "         - No access to cluster resources"
    info "         - Limited to 'default' namespace only"
    echo
    wait
    wait

    k apply -f scoped-role.yaml
    k apply -f scoped-rolebinding.yaml
    echo
    wait
    wait

    #############################################
    # SCENE 5: The Result (Verification)
    #############################################

    clear
    section_header "RBAC: Verifying the Fix 🔒" "${GREEN}"
    echo
    info "Restarting the pod to pick up the new permissions..."
    echo

    pe "k delete pod demo-pod --force --grace-period=0"
    pe "k apply -f demo-pod.yaml"
    pe "k wait --for=condition=ready pod/demo-pod --timeout=60s"
    echo
    wait
    wait

    clear
    success "Now let's test the attacker's capabilities with scoped permissions..."
    echo

    info "Can they list pods? (Yes - this is needed for the application)"
    pe "k exec demo-pod -- kubectl auth can-i list pods"
    echo
    wait
    wait

    info "Can they get configmaps? (Yes - this is needed for the application)"
    pe "k exec demo-pod -- kubectl auth can-i get configmaps"
    echo
    wait

    clear
    success "But now the dangerous permissions are blocked..."
    echo

    info "Can they access kube-system namespace? (No - scoped to default only!)"
    pe "k exec demo-pod -- kubectl auth can-i list secrets -n kube-system"
    echo
    wait
    wait

    info "Can they create new admin bindings? (No - privilege escalation blocked!)"
    pe "k exec demo-pod -- kubectl auth can-i create clusterrolebindings"
    echo
    wait
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

#    info "Cleaning up RBAC demo resources..."
    k delete -f demo-pod.yaml --force --grace-period=0 --ignore-not-found=true &>/dev/null
    k delete -f scoped-rolebinding.yaml --ignore-not-found=true &>/dev/null
    k delete -f scoped-role.yaml --ignore-not-found=true &>/dev/null
    k delete -f vulnerable-clusteradmin.yaml --ignore-not-found=true &>/dev/null
#    success "Done"
    echo

    # Return to original directory
    cd - &>/dev/null
}
