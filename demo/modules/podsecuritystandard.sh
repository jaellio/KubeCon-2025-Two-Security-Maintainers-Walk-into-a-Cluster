#!/bin/bash

########################
# Pod Security Standards Demo Module
# Demonstrates a production incident: developer mistake + security fix
########################

shopt -s expand_aliases
alias k='kubecolor'

demo_podsecuritystandard() {
    local MODULE_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
    local REPO_ROOT="$(dirname "$(dirname "$MODULE_DIR")")"
    local EXAMPLES_DIR="${REPO_ROOT}/podsecuritystandard/examples"

    #############################################
    # SCENE 1: The Mistake
    #############################################

    clear
    section_header "Pod Security Standards: Production Incident 🚨" "${RED}"
    echo
    info "Security team discovered a privileged pod running in production..."
    info "A developer deployed a new payment service without proper security review"
    info "They needed some privileges but weren't sure which ones - so they added ALL of them"
    echo
    wait

    info "Let's check the production namespace configuration..."
    echo
    pe "k get namespace prod --show-labels"
    echo
    danger "⚠️  No Pod Security Standards configured!"
    danger "Any pod configuration is allowed in this namespace"
    echo
    wait
    wait

    clear
    info "Let's examine the pod that's currently running in production..."
    echo
    cd "${EXAMPLES_DIR}/setup"
    pe "cat privileged-app.yaml"
    echo
    wait
    wait
    wait
    wait

    #############################################
    # SCENE 2: Understanding the Risk
    #############################################

    clear
    section_header "Pod Security Standards: Understanding the Risk 🔍" "${YELLOW}"
    echo
    info "Let's verify what this pod can actually access..."
    echo
    wait

    info "Check 1: What user is the container running as?"
    echo
    pe "k exec -n prod privileged-app -- whoami"
    echo
    danger "⚠️  Running as ROOT!"
    echo
    wait
    wait

    clear
    info "Check 2: Can we see host processes? (hostPID: true)"
    echo
    pe "k exec -n prod privileged-app -- ps aux | head -15"
    echo
    danger "⚠️  We can see ALL host processes!"
    danger "This is NOT normal container isolation!"
    echo
    wait
    wait

    clear
    info "Check 3: Can we access the host filesystem? (hostPath volume)"
    echo
    pe "k exec -n prod privileged-app -- ls -la /host/etc | head -10"
    echo
    danger "⚠️  Full access to host's /etc directory!"
    echo
    wait
    wait

    clear
    info "Check 4: Can we read sensitive host files?"
    echo
    pe "k exec -n prod privileged-app -- cat /host/etc/passwd | head -5"
    echo
    danger "⚠️  Can read /etc/passwd and other sensitive files!"
    danger "This privileged pod has COMPLETE host access!"
    echo
    wait
    wait

    #############################################
    # SCENE 3: Applying the Fix (Enable PSS)
    #############################################

    clear
    section_header "Pod Security Standards: Applying the Fix 🔧" "${GREEN}"
    echo
    success "Solution: Enable Pod Security Standards on the production namespace"
    echo
    info "We'll update the namespace to enforce the Restricted standard..."
    echo
    wait
    wait

    cd "${EXAMPLES_DIR}/restricted"
    info "Here's the updated namespace configuration:"
    echo
    pe "cat prod-namespace-restricted.yaml"
    echo
    wait
    wait
    wait
    wait

    clear
    info "Applying the updated namespace configuration..."
    echo
    k apply -f prod-namespace-restricted.yaml
    echo
    success "✅ Restricted PSS now enforced on production namespace!"
    echo
    wait
    wait
    wait
    wait

    clear
    info "Let's verify the namespace now has PSS labels..."
    echo
    pe "k get namespace prod --show-labels"
    echo
    success "✅ Pod Security Standards are now enforced!"
    echo
    wait
    wait

    #############################################
    # SCENE 4: Testing Enforcement
    #############################################

    clear
    section_header "Pod Security Standards: Testing Enforcement 🧪" "${CYAN}"
    echo
    info "Now that PSS is enforced, let's verify privileged pods are blocked..."
    echo
    wait
    wait

    info "Attempting to deploy a privileged pod..."
    echo
    pe "k apply -f privileged-pod-test.yaml || echo ''"
    echo
    success "✅ BLOCKED! Privileged pods can no longer be deployed"
    echo
    wait
    wait

    #############################################
    # SCENE 5: Fixing the Application
    #############################################

    clear
    section_header "Pod Security Standards: Fixing the Application 🔒" "${GREEN}"
    echo
    info "Now we need to update the privileged-app to comply with security standards..."
    echo
    wait
    wait

    info "Here's the updated pod configuration that complies with Restricted PSS:"
    echo
    pe "cat privileged-app-fixed.yaml"
    echo
    wait
    wait
    wait
    wait

    clear
    info "Let's delete the old privileged pod and deploy the secure version..."
    echo
    k delete pod privileged-app -n prod --grace-period=0 --force &>/dev/null
    echo "Deploying secure version..."
    k apply -f privileged-app-fixed.yaml
    k wait --for=condition=ready pod/privileged-app -n prod --timeout=60s
    echo
    success "✅ Secure pod deployed successfully!"
    echo
    wait
    wait

    #############################################
    # SCENE 6: Verification
    #############################################

    clear
    section_header "Pod Security Standards: Verifying the Fix ✅" "${GREEN}"
    echo
    success "Let's verify the security improvements..."
    echo

    info "Check 1: What user is the secure pod running as?"
    echo
    pe "k exec -n prod privileged-app -- whoami"
    echo
    success "✅ Running as non-root user (UID 1000)!"
    echo
    wait
    wait

    clear
    info "Check 2: Can it see host processes?"
    echo
    pe "k exec -n prod privileged-app -- ps aux | head -10"
    echo
    success "✅ Only sees container processes - proper isolation!"
    echo
    wait
    wait

    clear
    info "Check 3: Can it access host filesystem?"
    echo
    pe "k exec -n prod privileged-app -- ls -la /host 2>&1 || echo 'No /host mount'"
    echo
    success "✅ No host filesystem access!"
    echo
    wait
    wait

    #############################################
    # Cleanup
    #############################################

    info "Cleaning up Pod Security Standards demo resources..."
    k delete namespace prod --ignore-not-found=true &>/dev/null

    success "Done"
    echo

    # Return to original directory
    cd - &>/dev/null
}
