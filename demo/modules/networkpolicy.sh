#!/bin/bash

########################
# Network Policy Security Demo Module
# Demonstrates the danger of missing network policies
########################

shopt -s expand_aliases
alias k='kubecolor'

demo_networkpolicy() {
    local MODULE_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
    local REPO_ROOT="$(dirname "$(dirname "$MODULE_DIR")")"
    local EXAMPLES_DIR="${REPO_ROOT}/networkpolicy/examples"

    #############################################
    # SCENE 1: The Mistake (Broken)
    #############################################

    clear
    section_header "Network Policy: The Mistake 💥" "${RED}"
    echo
    info "A team deploys applications without any NetworkPolicy..."
    info "Kubernetes default: ALL traffic is allowed!"
    echo

    # Change to examples directory to use shorter paths
    cd "${EXAMPLES_DIR}"

    info "Demo pods were pre-created during cluster setup..."
    echo
    info "Checking the pods..."
    echo
    pe "k get pods -n demo-app"
    pe "k get pods -n demo-sensitive"
    echo
    wait
    wait

    info "Checking for NetworkPolicies..."
    pe "k get networkpolicies -A"
    echo
    danger "No NetworkPolicies found - everything is wide open!"
    echo
    wait
    wait

    #############################################
    # SCENE 2: The Impact (What This Means)
    #############################################

    clear
    section_header "Network Policy: Understanding the Impact 🔍" "${YELLOW}"
    echo
    info "Without NetworkPolicies, pods can communicate with ANYTHING..."
    echo
    wait

    info "Test 1: Can we access pods in other namespaces?"
    pe "k exec -n demo-app client-pod -- curl -s -m 3 sensitive-service.demo-sensitive.svc.cluster.local"
    echo
    danger "YES - Cross-namespace access works!"
    echo
    wait

    clear
    info "Test 2: Can we access external websites?"
    pe "k exec -n demo-app client-pod -- curl -s -m 3 -I google.com | head -1"
    echo
    danger "YES - Internet access unrestricted!"
    echo
    wait
    wait

    clear
    info "Test 3: Can we make unrestricted DNS queries?"
    pe "k exec -n demo-app client-pod -- nslookup google.com | grep -A2 'Name:'"
    echo
    danger "YES - DNS queries unrestricted (DNS tunneling possible)!"
    danger "🚨 NO NETWORK ISOLATION - COMPLETE LATERAL MOVEMENT 🚨"
    echo
    wait
    wait

    #############################################
    # SCENE 3: The Fix (Implementing Network Policies)
    #############################################

    clear
    section_header "Network Policy: The Fix ✅" "${GREEN}"
    echo
    success "Let's implement proper network segmentation..."
    echo

    info "Step 1: Apply default deny-all for both ingress and egress"
    echo
    pe "cat defaultdenyall.yaml"
    echo
    wait
    wait

    clear
    k apply -f defaultdenyall.yaml -n demo-app
    echo
    success "All ingress and egress traffic blocked by default!"
    echo
    wait
    wait

    info "Step 2: Allow demo-app internal communication and cluster egress"
    echo
    pe "cat allow-demo-app.yaml"
    echo
    wait
    wait

    clear
    k apply -f allow-demo-app.yaml
    echo
    success "Allowed client → server communication + cluster internal egress"
    echo
    wait
    wait

    info "Step 3: Allow DNS to CoreDNS only"
    echo
    pe "cat allow-coredns.yaml"
    echo
    wait
    wait

    clear
    k apply -f allow-coredns.yaml
    echo
    success "DNS restricted to kube-system CoreDNS only!"
    echo
    wait
    wait

    #############################################
    # SCENE 4: The Result (Verification)
    #############################################

    clear
    section_header "Network Policy: Verifying the Fix 🔒" "${GREEN}"
    echo
    success "Now let's verify the attacks are blocked..."
    echo
    wait

    info "Test 1: Can we still access our internal server? (Should work)"
    pe "k exec -n demo-app client-pod -- curl -s -m 3 server-service.demo-app.svc.cluster.local | grep '<title>'"
    echo
    success "Internal communication still works!"
    echo
    wait
    wait

    clear
    info "Test 2: Can we access external websites? (Should be blocked)"
    pe "k exec -n demo-app client-pod -- curl -s -m 3 --connect-timeout 1 google.com || echo 'BLOCKED ✓'"
    echo
    success "External internet access blocked!"
    echo
    wait
    wait

    clear
    info "Test 3: Can we query arbitrary DNS servers? (Should be blocked)"
    pe "k exec -n demo-app client-pod -- timeout 1 nslookup google.com 8.8.8.8 2>&1 || echo 'BLOCKED ✓'"
    echo
    success "Arbitrary DNS queries blocked!"
    echo
    wait
    wait

    #############################################
    # Cleanup
    #############################################

#    info "Cleaning up network policy demo resources..."
    # Only cleanup the network policies created during the demo
    # Demo pods are NOT deleted as they were created during cluster setup
    k delete -f defaultdenyall.yaml -n demo-app --ignore-not-found=true &>/dev/null
    k delete -f allow-demo-app.yaml --ignore-not-found=true &>/dev/null
    k delete -f allow-coredns.yaml --ignore-not-found=true &>/dev/null
#    success "Done"
    echo

    # Return to original directory
    cd - &>/dev/null
}
