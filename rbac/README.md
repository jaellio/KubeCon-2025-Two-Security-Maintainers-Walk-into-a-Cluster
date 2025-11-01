# Role-Based Access Control (RBAC)

## Overview

Role-Based Access Control (RBAC) is a critical security mechanism in Kubernetes that regulates access to cluster resources based on the roles assigned to users, service accounts, and groups. RBAC ensures that entities can only perform actions they are explicitly authorized to do, following the **principle of least privilege**.

### Why RBAC Matters

Without proper RBAC configuration:
- A compromised pod could gain full cluster control
- Developers might accidentally delete critical resources
- Lateral movement within the cluster becomes trivial for attackers
- Compliance requirements may be violated

### How RBAC Works

RBAC in Kubernetes uses four key resources:

1. **Role/ClusterRole**: Defines a set of permissions (what actions can be performed on which resources)
   - `Role`: Namespace-scoped permissions
   - `ClusterRole`: Cluster-wide permissions

2. **RoleBinding/ClusterRoleBinding**: Grants the permissions defined in a Role to a subject
   - `RoleBinding`: Grants permissions within a namespace
   - `ClusterRoleBinding`: Grants permissions cluster-wide

3. **Subjects**: Who the permissions apply to (users, groups, or service accounts)

4. **Service Accounts**: Identities for pods to authenticate with the API server

## Common Use Case: Overly Permissive Service Account Bindings

### The Scenario: Developer Convenience Gone Wrong

A common but dangerous pattern occurs when developers bind service accounts to `cluster-admin` for testing convenience and forget to remove it before going to production.

### Human Mistake

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: dev-service-account
  namespace: default
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: dev-cluster-admin-binding
subjects:
- kind: ServiceAccount
  name: dev-service-account
  namespace: default
roleRef:
  kind: ClusterRole
  name: cluster-admin  # DANGEROUS: Full cluster access!
  apiGroup: rbac.authorization.k8s.io
```

**Why this happens:**
- Developer needs quick access to test across multiple namespaces
- `cluster-admin` is the easiest way to "make things work"
- The binding is forgotten after testing
- Code gets promoted to production with the overly permissive binding intact

### Bad Actor Impact

If an attacker compromises a pod using this service account (through vulnerabilities like RCE, SSRF, or container escape), they gain **complete control** over the entire cluster:

**What attackers can do:**
- Read all Secrets across all namespaces (database credentials, API keys, certificates)
- Delete critical resources (deployments, nodes, persistent volumes)
- Deploy malicious workloads (cryptominers, backdoors)
- Modify cluster configurations (RBAC policies, admission controllers)
- Pivot to other systems using stolen credentials

### Live Demo Steps

#### 1. Deploy the Vulnerable Configuration

```bash
# Apply the vulnerable cluster-admin binding
kubectl apply -f examples/vulnerable-clusteradmin.yaml

# Deploy a pod using this service account
kubectl apply -f examples/demo-pod.yaml

# Wait for the pod to be ready
kubectl wait --for=condition=Ready pod/demo-pod -n default
```

#### 2. Check What the Service Account Can Do

```bash
# Test if the service account has full cluster access
kubectl auth can-i '*' '*' --as=system:serviceaccount:default:dev-service-account
# Output: yes L

# Test specific dangerous permissions
kubectl auth can-i delete nodes --as=system:serviceaccount:default:dev-service-account
# Output: yes L

kubectl auth can-i get secrets --all-namespaces --as=system:serviceaccount:default:dev-service-account
# Output: yes L

kubectl auth can-i create clusterrolebindings --as=system:serviceaccount:default:dev-service-account
# Output: yes L
```

#### 3. Simulate an Attack from Inside the Pod

```bash
# Exec into the pod to simulate attacker perspective
kubectl exec -it demo-pod -- bash

# Inside the pod, check your identity
kubectl auth whoami
# Shows: system:serviceaccount:default:dev-service-account

# List all secrets in all namespaces (credential theft)
kubectl get secrets --all-namespaces

# Read a specific secret (e.g., database credentials)
kubectl get secret -n production db-credentials -o jsonpath='{.data.password}' | base64 -d

# List all nodes in the cluster
kubectl get nodes

# Simulate malicious action: Delete a node (DON'T actually do this in production!)
# kubectl delete node <node-name>

# Create a new cluster-admin binding for persistence
# kubectl create clusterrolebinding attacker-admin \
#   --clusterrole=cluster-admin \
#   --serviceaccount=default:attacker-sa
```

### The Fix: Scoped Role with Least Privilege

Replace the cluster-admin binding with a namespace-scoped Role that grants **only** the permissions actually needed:

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: dev-service-account
  namespace: default
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: dev-role
  namespace: default
rules:
# Allow getting, listing, and watching pods
- apiGroups: [""]
  resources: ["pods"]
  verbs: ["get", "list", "watch"]
# Allow getting and listing services
- apiGroups: [""]
  resources: ["services"]
  verbs: ["get", "list"]
# Allow reading ConfigMaps (but NOT Secrets!)
- apiGroups: [""]
  resources: ["configmaps"]
  verbs: ["get", "list"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: dev-rolebinding
  namespace: default
subjects:
- kind: ServiceAccount
  name: dev-service-account
  namespace: default
roleRef:
  kind: Role
  name: dev-role
  apiGroup: rbac.authorization.k8s.io
```

#### Apply the Fix and Verify

```bash
# Remove the vulnerable binding
kubectl delete -f examples/vulnerable-clusteradmin.yaml

# Apply the scoped role and binding
kubectl apply -f examples/scoped-role.yaml
kubectl apply -f examples/scoped-rolebinding.yaml

# Verify the service account now has limited permissions
kubectl auth can-i '*' '*' --as=system:serviceaccount:default:dev-service-account
# Output: no 

kubectl auth can-i get pods --as=system:serviceaccount:default:dev-service-account
# Output: yes  (only what's needed)

kubectl auth can-i get secrets --as=system:serviceaccount:default:dev-service-account
# Output: no  (secrets are protected)

kubectl auth can-i delete nodes --as=system:serviceaccount:default:dev-service-account
# Output: no  (cluster resources are protected)
```

**Benefits of the fix:**
-  Limits blast radius if the pod is compromised
-  Follows the principle of least privilege
-  Scoped to a single namespace
-  No access to Secrets or sensitive resources
-  Cannot modify cluster-level resources

## Common RBAC Pitfalls

### 1. **Binding cluster-admin to Default Service Accounts**
- **Why it's bad**: The `default` service account exists in every namespace and is automatically mounted to pods that don't specify a service account
- **Impact**: Every pod in the namespace gets cluster-admin privileges
- **Fix**: Never bind `cluster-admin` to default service accounts. Create dedicated service accounts with minimal permissions.

### 2. **Using Wildcard Permissions (`*`) Unnecessarily**
- **Why it's bad**: Grants access to all resources and verbs, including future ones
- **Impact**: Overly broad access that violates least privilege
- **Fix**: Explicitly list only the resources and verbs needed:
  ```yaml
  # L Bad
  - apiGroups: ["*"]
    resources: ["*"]
    verbs: ["*"]

  #  Good
  - apiGroups: [""]
    resources: ["pods", "services"]
    verbs: ["get", "list"]
  ```

### 3. **Forgetting to Remove Test Permissions**
- **Why it's bad**: Temporary elevated privileges for debugging often become permanent
- **Impact**: Production workloads run with unnecessary permissions
- **Fix**:
  - Use separate test clusters for development
  - Implement code review processes for RBAC changes
  - Use tools like `kubectl rbac-tool` or `kubectl who-can` to audit permissions
  - Automate RBAC audits in CI/CD pipelines

### 4. **Using ClusterRoles When Roles Are Sufficient**
- **Why it's bad**: ClusterRoles grant permissions across all namespaces, increasing risk
- **Impact**: Namespace isolation is broken; compromised service account affects entire cluster
- **Fix**: Default to namespace-scoped `Role` and `RoleBinding` unless cluster-wide access is genuinely required

### 5. **Not Disabling Automatic Service Account Token Mounting**
- **Why it's bad**: Every pod automatically gets a service account token mounted at `/var/run/secrets/kubernetes.io/serviceaccount/token`
- **Impact**: Applications that don't need API access still get credentials that attackers can steal
- **Fix**: Disable automatic mounting when not needed:
  ```yaml
  apiVersion: v1
  kind: ServiceAccount
  metadata:
    name: my-sa
  automountServiceAccountToken: false  #  Disable automatic mounting
  ---
  apiVersion: v1
  kind: Pod
  metadata:
    name: my-pod
  spec:
    serviceAccountName: my-sa
    automountServiceAccountToken: false  #  Can also disable per-pod
    containers:
    - name: app
      image: myapp:latest
  ```

### 6. **Granting `list` or `watch` on Secrets**
- **Why it's bad**: Even without `get`, attackers can enumerate secret names and watch for changes
- **Impact**: Information disclosure about what sensitive data exists
- **Fix**: Only grant `get` on specific named secrets if absolutely necessary:
  ```yaml
  # L Bad - can list all secrets
  - apiGroups: [""]
    resources: ["secrets"]
    verbs: ["list"]

  #  Better - can only get specific secrets by name
  - apiGroups: [""]
    resources: ["secrets"]
    resourceNames: ["app-config"]
    verbs: ["get"]
  ```

### 7. **Not Using RBAC Aggregation for Complex Permissions**
- **Why it's bad**: Duplicating RBAC rules across many roles leads to inconsistencies
- **Impact**: Hard to maintain, easy to make mistakes
- **Fix**: Use ClusterRole aggregation with labels for reusable permission sets:
  ```yaml
  apiVersion: rbac.authorization.k8s.io/v1
  kind: ClusterRole
  metadata:
    name: aggregate-read-pods
    labels:
      rbac.example.com/aggregate-to-monitoring: "true"
  rules:
  - apiGroups: [""]
    resources: ["pods"]
    verbs: ["get", "list", "watch"]
  ---
  apiVersion: rbac.authorization.k8s.io/v1
  kind: ClusterRole
  metadata:
    name: monitoring-role
  aggregationRule:
    clusterRoleSelectors:
    - matchLabels:
        rbac.example.com/aggregate-to-monitoring: "true"
  ```

## Best Practices

1. **Start with No Access**: Begin with no permissions and add only what's needed
2. **Use Namespace-Scoped Roles**: Default to `Role` instead of `ClusterRole`
3. **Avoid cluster-admin**: Reserve `cluster-admin` only for break-glass scenarios and cluster administrators
4. **Regular Audits**: Use `kubectl rbac-tool`, `kubectl who-can`, or `rbac-lookup` to review permissions
5. **Implement Pod Security Policies/Standards**: Combine RBAC with Pod Security Standards for defense in depth
6. **Service Account Per Application**: Each application should have its own service account
7. **Document Permission Requirements**: Clearly document why each permission is needed
8. **Test in Non-Production**: Validate RBAC changes in dev/staging before production
9. **Automate RBAC Management**: Use tools like Helm, Kustomize, or operators to manage RBAC consistently
10. **Monitor RBAC Changes**: Alert on modifications to critical RBAC resources

## Resources

- [Official Kubernetes RBAC Documentation](https://kubernetes.io/docs/reference/access-authn-authz/rbac/)
- [Using RBAC Authorization (Kubernetes Tasks)](https://kubernetes.io/docs/reference/access-authn-authz/rbac/)
- [RBAC Best Practices (NSA/CISA Kubernetes Hardening Guide)](https://media.defense.gov/2022/Aug/29/2003066362/-1/-1/0/CTR_KUBERNETES_HARDENING_GUIDANCE_1.2_20220829.PDF)
- [Kubernetes Security Best Practices](https://kubernetes.io/docs/concepts/security/security-checklist/)
