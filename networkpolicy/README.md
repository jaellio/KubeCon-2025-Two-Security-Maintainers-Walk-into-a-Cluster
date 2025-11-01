# Network Policy Application

## Overview

A Kubernetes NetworkPolicy is a resource that defines and controls how pods communicate with each other and with external endpoints. By default, Kubernetes allows all pods in a cluster to send and receive traffic from pods and external sources. NetworkPolicies allow you to enforce fine-grained ingress (incoming) and egress (outgoing) rules for pods based on labels, namespaces, and IP blocks. These policies enable isolation and enhance security within a Kubernetes cluster.

Defined policies are applied by the network plugin (CNI plugin) in use within the cluster. The CNI plugin watches for NetworkPolicy resources, translates the policies into dataplane rules like iptables or eBPF, and enforces them at the nodes network level when traffic enters or leaves the pods virtual network interfaces. Enforcing these rules at the node level ensures persistent (pods are ephemeral), centralized, and consistent application of network policies across all pods on the node cluster.

## Common Use Cases and Pitfalls

### Default Deny All Policy

Without a default deny policy, all pods can communicate freely. Implementing a default deny all policy ensures the following:
- only explicitly allowed traffic can reach the pods
- pods are not unintentionally exported to other entities (pods or external networks)
- reduces the chance of lateral movement in case of a compromised pod

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-all
spec:
  podSelector: {} # Selects all pods in all namespaces
  policyTypes:
  - Ingress # By not defining any ingress rules (via the ingress field), all ingress traffic is denied
  - Egress # By not defining any egress rules (via the egress field), all egress traffic is denied
```

#### Resources
1. [Default Deny All Policy](https://kubernetes.io/docs/concepts/services-networking/network-policies/#default-deny-all-ingress-and-all-egress-traffic)

### Namespace Isolation Policy

Applying NetworkPolicy is one part of achieving namespace isolation. This policy restricts traffic so that pods in one namespace cannot communicate with pods in another namespace unless explicitly allowed. Namespace isolation policies can be applied to achieve secure configuration for multi-tenant clusters, maintain segmented environments for dev/staging/prod namespaces, and enforce compliance and regulatory requirements by isolating sensitive workloads.

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: deny-cross-namespace # Ensure traffic to and from other namespaces is denied, isolating the 'team-a' namespace.
  namespace: team-a
spec:
  podSelector: {}
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          name: team-a # For pods in namespace 'team-a', only allow ingress from pods in namespace 'team-a'
  - to:
    - namespaceSelector:
        matchLabels:
          name: team-a # For pods in namespace 'team-a', only allow egress to pods in namespace 'team-a'
```

### Egress Restriction Policy

Egress restriction policies control outbound traffic from pods to other entities (external services or other networks). This is crucial for preventing data exfiltration (unauthorized transfer of data from a system or network to an external location), limiting access to only necessary external services, and reducing the attack surface by blocking unnecessary outbound connections.

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: restrict-egress
  namespace: app
spec:
  podSelector: {}
  egress:
  - to:
    - ipBlock:
        cidr: 10.0.0.0/8 # Allow egress only to the internal network range
```
#### Resources
1. [Guide to Kubernetes Egress Network Policies](https://www.redhat.com/en/blog/guide-to-kubernetes-egress-network-policies)

### DNS Access Policy

Firewalls often allow unrestricted DNS traffic, which can lead to security vulnerabilities and DNS tunneling attacks. A NetworkPolicy can be created to restrict DNS queries to only the cluster's DNS service (e.g., CoreDNS) or other trusted DNS servers. This minimizes exposure to potential DNS-based attacks.

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: restrict-dns
  namespace: my-namespace
spec:
  podSelector: {}  # Apply to all pods in this namespace
  policyTypes:
    - Egress
  egress:
    # Allow DNS to CoreDNS pods
    - to:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: kube-system
        - podSelector:
            matchLabels:
              k8s-app: kube-dns
      ports:
        - protocol: UDP
          port: 53
    # Allow DNS to trusted external servers
    - to:
        - ipBlock:
            cidr: 8.8.8.8/32 # Google DNS
        - ipBlock:
            cidr: 1.1.1.1/32 # Cloudflare DNS
      ports:
        - protocol: UDP
          port: 53
```

#### Resources
1. [DNS Tunneling](https://www.paloaltonetworks.com/cyberpedia/what-is-dns-tunneling)

## Common Pitfalls
1. Assuming Policies Apply by Default
    - **Pitfall**: Creating a NetworkPolicy without realizing that pods not selected by any policy remain unrestricted.
    - **Why**: NetworkPolicies only affect pods that match podSelector. Others still allow all traffic.
    - **Fix**: Apply a default deny-all policy for ingress and egress in each namespace.
2. Forgetting Egress Rules
    - **Pitfall**: Developers often secure ingress but leave egress open, allowing pods to reach the internet or external DNS.
    - **Impact**: Enables data exfiltration or malicious outbound traffic.
    - **Fix**: Add policyTypes: [Ingress, Egress] and restrict egress to trusted destinations.
3. Additive functionality
    - **Pitfall**: Thinking policies are evaluated in order or that one policy overrides another.
    - **Reality**: Policies are additive—if any policy allows traffic, it’s permitted.
    - **Fix**: Design policies carefully and avoid overlapping rules that unintentionally open access.
4. Using IPs instead of selectors
    - **Pitfall**: Hardcoding IPs for CoreDNS or API server.
    - **Impact**: IPs can change, breaking policies.
    - **Fix**: Use namespaceSelector and podSelector for cluster services.
5. Not testing policies
    - **Pitfall**: Deploying policies without verifying their effectiveness.
    - **Impact**: May inadvertently block legitimate traffic or leave gaps.
    - **Fix**: Use tools like `kubectl exec` to test connectivity and validate policies.

## Resources
1. [Kubernetes NetworkPolicy Documentation](https://kubernetes.io/docs/concepts/services-networking/network-policies/)
2. [Network Policy Examples](https://kubernetes.io/docs/concepts/services-networking/network-policies/#network-policy-examples)
3. [CNI Plugins](https://kubernetes.io/docs/concepts/extend-kubernetes/extend-cluster/#container-network-interface)
4. [KubeCon 2017- Securing Cluster Networking with Network Policies](https://www.youtube.com/watch?v=3gGpMmYeEO8)