#!/bin/bash

########################
# Pod Security Standards Demo Module
# Demonstrates the danger of not enforcing Pod Security Standards
########################

demo_podsecuritystandard() {
    local MODULE_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
    local REPO_ROOT="$(dirname "$(dirname "$MODULE_DIR")")"
    local EXAMPLES_DIR="${REPO_ROOT}/podsecuritystandard/examples"

    #############################################
    # SCENE 1: The Mistake (Broken)
    #############################################

    clear
    section_header "Pod Security Standards: The Mistake 💥" "${RED}"
    echo
    info "Teams often create namespaces without Pod Security Standards..."
    info "Kubernetes allows ANY pod configuration by default"
    info "Developers can deploy highly privileged, dangerous pods"
    echo

    # Change to examples directory
    cd "${EXAMPLES_DIR}/vulnerable"
    echo

    info "Let's create a namespace without any Pod Security Standards..."
    echo
    pe "cat namespace-no-pss.yaml"
    echo
    wait
    kubectl apply -f namespace-no-pss.yaml
    echo
    wait

    clear
    info "Now let's deploy a HIGHLY PRIVILEGED pod with dangerous settings..."
    echo
    pe "cat privileged-pod.yaml"
    echo
    wait

    clear
    info "Deploying the privileged pod..."
    kubectl apply -f privileged-pod.yaml
    kubectl wait --for=condition=ready pod/privileged-pod -n demo-pss --timeout=60s
    echo
    success "Pod deployed successfully..."
    echo
    danger "But this pod has FULL access to the host system!"
    danger "  • hostPID: true (can see all host processes)"
    danger "  • hostNetwork: true (uses host networking)"
    danger "  • privileged: true (no security restrictions)"
    danger "  • runAsUser: 0 (running as root)"
    danger "  • Mounted host root filesystem at /host"
    echo
    wait
    sleep 1

    #############################################
    # SCENE 2: The Impact (What This Means)
    #############################################

    clear
    section_header "Pod Security Standards: Understanding the Impact 🔍" "${YELLOW}"
    echo
    info "Let's see what this privileged pod can access..."
    echo
    wait

    info "Check 1: What user is the container running as?"
    echo
    pe "kubectl exec -n demo-pss privileged-pod -- whoami"
    echo
    danger "Running as ROOT!"
    echo
    wait

    clear
    info "Check 2: Can we see host processes? (hostPID: true)"
    echo
    pe "kubectl exec -n demo-pss privileged-pod -- ps aux | head -15"
    echo
    danger "YES - We can see ALL host processes!"
    danger "This is NOT normal container isolation!"
    echo
    wait

    clear
    info "Check 3: Can we access the host filesystem? (hostPath volume)"
    echo
    pe "kubectl exec -n demo-pss privileged-pod -- ls -la /host/etc | head -10"
    echo
    danger "YES - Full access to host's /etc directory!"
    echo
    wait

    clear
    info "Check 4: Can we read sensitive host files?"
    echo
    pe "kubectl exec -n demo-pss privileged-pod -- cat /host/etc/passwd | head -5"
    echo
    danger "YES - Can read /etc/passwd and other sensitive files!"
    danger "This privileged pod has COMPLETE host access!"
    echo
    wait
    sleep 1

    #############################################
    # SCENE 3: The Attack (Simulated)
    #############################################

    clear
    section_header "Pod Security Standards: The Attack Scenario 🎭" "${RED}"
    echo
    danger "An attacker compromises this privileged pod..."
    danger "They now have a path to escape the container!"
    echo
    wait

    danger "Attack 1: Access Host Processes"
    echo
    info "  • With hostPID, attacker can see all processes"
    info "  • Can identify and target other workloads"
    info "  • Can inject into host processes"
    echo
    wait

    danger "Attack 2: Host Filesystem Access"
    echo
    info "  • Mounted host root at /host"
    info "  • Can read SSH keys: /host/root/.ssh/"
    info "  • Can read kubeconfig: /host/etc/kubernetes/"
    info "  • Can modify system files"
    echo
    wait

    danger "Attack 3: Network Hijacking"
    echo
    info "  • hostNetwork gives access to host network"
    info "  • Can sniff all node traffic"
    info "  • Can bind to privileged ports"
    info "  • Man-in-the-middle attacks"
    echo
    wait

    danger "Attack 4: Complete Node Takeover"
    echo
    info "  • Privileged container = root on host"
    info "  • Can load kernel modules"
    info "  • Can escape to host completely"
    info "  • Compromise all pods on the node"
    echo
    danger "🚨 ONE PRIVILEGED POD = ENTIRE NODE COMPROMISED 🚨"
    echo
    wait
    sleep 1

    #############################################
    # SCENE 4: The Fix (Pod Security Standards)
    #############################################

    clear
    section_header "Pod Security Standards: The Fix ✅" "${GREEN}"
    echo
    success "Solution: Enforce Pod Security Standards (PSS) on namespaces"
    echo
    info "Kubernetes offers 3 PSS levels:"
    echo "  • Privileged: Unrestricted (no enforcement)"
    echo "  • Baseline: Minimally restrictive (prevents known privilege escalations)"
    echo "  • Restricted: Heavily restricted (follows pod hardening best practices)"
    echo
    wait

    clear
    info "Let's create a namespace with RESTRICTED Pod Security Standard..."
    echo
    cd "${EXAMPLES_DIR}/restricted"
    pe "cat namespace-restricted.yaml"
    echo
    wait
    kubectl apply -f namespace-restricted.yaml
    echo
    success "Namespace created with Restricted PSS enforcement!"
    echo
    wait

    clear
    info "Now let's try to deploy the same privileged pod..."
    echo
    pe "kubectl apply -f ../vulnerable/privileged-pod.yaml -n demo-pss-restricted || echo ''"
    echo
    success "✅ BLOCKED! Privileged pod violates Restricted PSS"
    echo
    wait

    clear
    info "Let's deploy a SECURE pod that complies with Restricted PSS..."
    echo
    pe "cat secure-pod.yaml"
    echo
    wait
    kubectl apply -f secure-pod.yaml
    kubectl wait --for=condition=ready pod/secure-pod -n demo-pss-restricted --timeout=60s
    echo
    success "✅ Secure pod deployed successfully!"
    echo
    wait
    sleep 1

    #############################################
    # SCENE 5: The Result (Verification)
    #############################################

    clear
    section_header "Pod Security Standards: Verifying the Fix 🔒" "${GREEN}"
    echo
    success "Let's verify the security improvements..."
    echo

    info "Check 1: What user is the secure pod running as?"
    echo
    pe "kubectl exec -n demo-pss-restricted secure-pod -- whoami"
    echo
    success "✅ Running as non-root user (UID 1000)!"
    echo
    wait

    clear
    info "Check 2: Can it see host processes?"
    echo
    pe "kubectl exec -n demo-pss-restricted secure-pod -- ps aux | head -10"
    echo
    success "✅ Only sees container processes - proper isolation!"
    echo
    wait

    clear
    info "Check 3: Can it access host filesystem?"
    echo
    pe "kubectl exec -n demo-pss-restricted secure-pod -- ls -la /host 2>&1 || echo 'No /host mount'"
    echo
    success "✅ No host filesystem access!"
    echo
    wait

    clear
    info "Let's compare the security contexts..."
    echo
    echo "Privileged Pod (DANGEROUS):"
    echo "  • hostPID: true"
    echo "  • hostNetwork: true"
    echo "  • privileged: true"
    echo "  • runAsUser: 0 (root)"
    echo "  • All capabilities"
    echo "  • Host filesystem mounted"
    echo
    echo "Secure Pod (PROTECTED):"
    echo "  • No host namespace sharing"
    echo "  • privileged: false"
    echo "  • runAsNonRoot: true"
    echo "  • runAsUser: 1000"
    echo "  • All capabilities dropped"
    echo "  • Seccomp: RuntimeDefault"
    echo "  • No host mounts"
    echo
    wait

    clear
    section_header "Pod Security Standards: Summary 📋" "${CYAN}"
    echo
    success "✅ Demonstrated privileged pod with dangerous host access"
    success "✅ Showed container escape possibilities"
    success "✅ Applied Restricted Pod Security Standard"
    success "✅ Blocked privileged pod deployment"
    success "✅ Deployed compliant secure pod"
    success "✅ Verified proper isolation"
    echo
    success "🎯 Pod Security Standards enforce secure pod configurations!"
    success "   Privileged pods are now blocked at admission time"

    #############################################
    # Cleanup
    #############################################

#    info "Cleaning up Pod Security Standards demo resources..."
    kubectl delete namespace demo-pss --ignore-not-found=true &>/dev/null
    kubectl delete namespace demo-pss-restricted --ignore-not-found=true &>/dev/null

    # Wait for namespace deletion
    kubectl wait --for=delete namespace/demo-pss --timeout=30s &>/dev/null || true
    kubectl wait --for=delete namespace/demo-pss-restricted --timeout=30s &>/dev/null || true

#    success "Done"
    echo

    # Return to original directory
    cd - &>/dev/null
}
