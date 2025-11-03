# Secret Management with Secrets Store CSI Driver

## Overview

This demo showcases the security implications of native Kubernetes Secrets and demonstrates how to use the Secrets Store CSI Driver with HashiCorp Vault for secure external secret management.

## The Problem

Native Kubernetes Secrets have significant security limitations:

1. **Plain-text Storage in etcd**: Even with encryption at rest (KMS), secrets must pass through etcd
2. **Broad Access**: Anyone with etcd access can potentially read all secrets
3. **Limited Lifecycle Management**: No secret rotation, versioning, or advanced access policies
4. **Audit Challenges**: Limited visibility into secret access patterns
5. **Blast Radius**: Compromising etcd means compromising all secrets

### Attack Scenario

Even with KMS encryption enabled:
1. Attacker gains access to a node or backup
2. Attacker extracts etcd data (even if encrypted, it's still in etcd)
3. With sufficient privileges, attacker can read encrypted secrets through API
4. Secrets are exposed in container environment variables or volumes
5. Lateral movement becomes easier with discovered credentials

## The Fix: Secrets Store CSI Driver

The Secrets Store CSI Driver provides:

- **External Secret Storage**: Secrets never stored in etcd
- **Direct Retrieval**: Pods fetch secrets directly from external provider (Vault, Azure Key Vault, AWS Secrets Manager)
- **Advanced Features**: Secret rotation, versioning, detailed audit logs
- **Reduced Blast Radius**: Compromising etcd doesn't expose secrets
- **Fine-grained Access**: Provider-native access controls and policies

## Demo Components

### 1. Vulnerable Configuration (`examples/vulnerable/`)

- **db-secret.yaml**: Native Kubernetes Secret with database credentials
- **app-with-secret.yaml**: Pod consuming native Secret (vulnerable to etcd exposure)

### 2. Vault Setup (`examples/vault-setup/`)

- **vault-dev.yaml**: HashiCorp Vault StatefulSet in dev mode
- **vault-config.sh**: Automated Vault configuration script
  - Enables KV secrets engine
  - Creates demo database credentials
  - Configures Kubernetes auth method
  - Sets up policies and roles
- **rbac.yaml**: ServiceAccount for demo application

### 3. CSI Driver Configuration (`examples/csi-driver/`)

- **secretproviderclass.yaml**: Maps Vault secrets to filesystem paths
- **app-with-csi.yaml**: Pod using CSI driver to mount secrets from Vault

## 5-Scene Demo Walkthrough

### Scene 1: The Mistake =4
Deploy a pod using native Kubernetes Secrets:
```bash
kubectl apply -f examples/vulnerable/db-secret.yaml
kubectl apply -f examples/vulnerable/app-with-secret.yaml
```

### Scene 2: Understanding the Impact =�
Show that secrets are stored in etcd (even with encryption):
```bash
# Access etcd and read secret data
ETCDCTL_API=3 etcdctl get /registry/secrets/default/db-secret
```

Result: Secret data visible in etcd (base64 encoded at minimum, encrypted if KMS enabled, but still in etcd)

### Scene 3: The Attack Scenario =�
Demonstrate the security risk:
```bash
# Secret is accessible to anyone with etcd or API access
kubectl get secret db-secret -o yaml
echo "cGFzc3dvcmQ=" | base64 -d  # SuperSecret123!
```

**Attack Vector**:
- Compromised node with etcd access
- Stolen admin kubeconfig
- Backup media exposure
- Supply chain attack on etcd backups

### Scene 4: The Fix =�
Deploy Vault and configure CSI driver:
```bash
# Deploy Vault
kubectl apply -f examples/vault-setup/vault-dev.yaml
kubectl wait --for=condition=ready pod/vault-0 --timeout=60s

# Configure Vault with demo secrets
bash examples/vault-setup/vault-config.sh

# Create ServiceAccount
kubectl apply -f examples/vault-setup/rbac.yaml

# Configure CSI driver with Vault provider
kubectl apply -f examples/csi-driver/secretproviderclass.yaml

# Deploy app using CSI driver
kubectl apply -f examples/csi-driver/app-with-csi.yaml
```

### Scene 5: Verification and Success 
Verify secrets are NOT in etcd:
```bash
# Check etcd - no secret stored there!
ETCDCTL_API=3 etcdctl get /registry/secrets/default/vault-db-creds
# (empty result)

# Verify secret is accessible to pod
kubectl exec app-with-csi -- ls -la /mnt/secrets-store
kubectl exec app-with-csi -- cat /mnt/secrets-store/username
kubectl exec app-with-csi -- cat /mnt/secrets-store/password

# Check Vault audit logs
kubectl exec vault-0 -- vault audit list
```

## Key Differences: Native Secrets vs CSI Driver

| Aspect | Native K8s Secrets | Secrets Store CSI Driver |
|--------|-------------------|-------------------------|
| **Storage Location** | etcd | External provider (Vault, etc.) |
| **Encryption** | At rest via KMS | Provider-native encryption |
| **Access Control** | K8s RBAC only | Provider policies + K8s RBAC |
| **Rotation** | Manual | Automated via provider |
| **Audit Logging** | Limited K8s audit | Detailed provider audit logs |
| **Blast Radius** | All secrets if etcd compromised | Per-secret provider access |
| **Secret Versioning** | None | Provider-native versioning |
| **Lifecycle Management** | Basic | Advanced (TTL, rotation, revocation) |

## Production Considerations

### 1. Provider Selection
- **HashiCorp Vault**: Full-featured, self-hosted
- **AWS Secrets Manager**: AWS-native integration
- **Azure Key Vault**: Azure-native integration
- **GCP Secret Manager**: GCP-native integration

### 2. High Availability
- Deploy Vault in HA mode (Raft or Consul backend)
- Configure CSI driver with provider replication
- Implement proper backup and disaster recovery

### 3. Security Hardening
- Use TLS for all Vault communication
- Enable Vault audit logging
- Implement proper Vault policies (least privilege)
- Rotate Vault tokens and credentials regularly
- Use Vault namespaces for multi-tenancy

### 4. Performance
- Monitor CSI driver pod performance
- Configure secret caching if appropriate
- Plan for secret refresh intervals
- Consider provider rate limits

### 5. Secret Rotation
```yaml
# Example: Configure automatic rotation
spec:
  secretObjects:
  - secretName: db-credentials
    type: Opaque
    data:
    - objectName: username
      key: username
    - objectName: password
      key: password
  parameters:
    rotation-poll-interval: "120s"  # Check for updates every 2 minutes
```

### 6. Migration Strategy
1. **Phase 1**: Deploy CSI driver and external provider (Vault)
2. **Phase 2**: Migrate non-critical secrets first
3. **Phase 3**: Update applications to use CSI volumes
4. **Phase 4**: Migrate critical secrets with proper testing
5. **Phase 5**: Decommission native Secrets
6. **Phase 6**: Monitor and optimize

## Best Practices

### Do's

- **Use CSI Driver for All Secrets**: Especially credentials, API keys, certificates
- **Enable Audit Logging**: Track all secret access in Vault
- **Implement Secret Rotation**: Automate credential rotation
- **Use Short-Lived Credentials**: Configure TTLs for dynamic secrets
- **Pod Identity Integration**: Use Workload Identity or IRSA for Vault auth
- **Monitor Secret Access**: Set up alerts for unusual access patterns
- **Test DR Procedures**: Regularly test Vault backup and recovery

### L Don'ts

- **Don't Use Native Secrets for Sensitive Data**: Use CSI driver instead
- **Don't Skip TLS**: Always encrypt Vault communication
- **Don't Over-Permission**: Follow least privilege for Vault policies
- **Don't Forget Backups**: Vault data loss means secret loss
- **Don't Ignore Rotation**: Stale credentials are security risks
- **Don't Mix Approaches**: Consistently use CSI driver across cluster

## Demo Setup Prerequisites

This demo requires:
- Secrets Store CSI Driver installed in cluster
- Vault provider for CSI driver installed
- HashiCorp Vault deployed (dev mode for demo)
- kubectl and helm installed

All prerequisites are automatically configured by `demo/setup-cluster.sh`.

## Quick Start

```bash
# Setup cluster with all prerequisites
cd demo
./setup-cluster.sh

# Run the secret management demo
./demo.sh  # Select "Secret Management" from menu

# Cleanup
./cleanup-cluster.sh
```

## Additional Resources

- [Secrets Store CSI Driver Documentation](https://secrets-store-csi-driver.sigs.k8s.io/)
- [Vault CSI Provider](https://developer.hashicorp.com/vault/docs/platform/k8s/csi)
- [Kubernetes Secrets Good Practices](https://kubernetes.io/docs/concepts/configuration/secret/#good-practices)
- [CNCF Secret Management Landscape](https://landscape.cncf.io/guide#provisioning--security--key-management)

## Security Warning �

The examples in this repository use:
- Vault in **dev mode** (not for production!)
- **TLS disabled** (enable TLS in production)
- **Root token** authentication (use proper auth in production)
- **Static secrets** (use dynamic secrets in production)

These configurations are ONLY for demonstration purposes!
