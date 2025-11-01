# Kubernetes Encryption at Rest (KMS)

## Overview

By default, Kubernetes stores all resource data, including **Secrets**, in **plain text** in etcd. This means anyone with read access to etcd can view all sensitive data in your clusterdatabase passwords, API keys, certificates, and more.

**Encryption at Rest** protects data stored in etcd by encrypting it before it's written to disk. Kubernetes supports multiple encryption providers, with **KMS (Key Management Service)** being the most secure option for production environments.

### Why Encryption at Rest Matters

- **etcd access = root access**: Write access to etcd gives complete control over your entire cluster
- **Backup security**: Without encryption, etcd backup files contain plain-text secrets
- **Compliance**: Many regulatory frameworks (PCI-DSS, HIPAA, SOC 2) require encryption at rest
- **Defense in depth**: Protects against etcd compromise, insider threats, and backup theft
- **Audit trail**: External KMS providers log all key access for security monitoring

## The Problem: Plain Text Storage

### Human Mistake

Teams deploy Kubernetes clusters without configuring encryption, leaving the default behavior intact:
- Secrets stored in plain text in etcd
- No encryption configuration file
- Assumption that "Secrets" are inherently encrypted (they're not!)

### Bad Actor Impact

If an attacker gains access to etcd (through node compromise, backup theft, or insider threat), they can:

- **Read ALL secrets** across all namespaces
- **Extract credentials** (databases, APIs, cloud providers)
- **Steal certificates** and private keys
- **Access sensitive ConfigMaps**
- **Exfiltrate data** from backups without detection

**Impact**: Complete credential theft, compliance violations, data breaches.

### Live Demo: Reading Plain Text Secrets

```bash
# Create a secret
kubectl create secret generic db-creds \
  --from-literal=username=admin \
  --from-literal=password=SuperSecret123

# Access etcd from the control plane
docker exec -it <control-plane-container> bash

# Read the secret directly from etcd
ETCDCTL_API=3 etcdctl \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key \
  get /registry/secrets/default/db-creds

# Result: Password visible in PLAIN TEXT! =�
```

## The Fix: Enable Encryption at Rest

### Option 1: aescbc (Local Encryption - Demo/Dev)

**Use for**: Development, testing, demos
**Pros**: Simple to set up, no external dependencies
**Cons**: Key stored locally, no key rotation, no audit trail

```yaml
apiVersion: apiserver.config.k8s.io/v1
kind: EncryptionConfiguration
resources:
  - resources:
      - secrets
    providers:
      - aescbc:
          keys:
            - name: key1
              secret: <base64-encoded-32-byte-key>
      - identity: {}
```

**Generate a key**:
```bash
head -c 32 /dev/urandom | base64
```

### Option 2: KMS v2 (External Key Management - Production)

**Use for**: Production environments
**Pros**: External key management, key rotation, audit trails, compliance-friendly
**Cons**: Requires external KMS provider setup

```yaml
apiVersion: apiserver.config.k8s.io/v1
kind: EncryptionConfiguration
resources:
  - resources:
      - secrets
      - configmaps  # Optional
    providers:
      - kms:
          apiVersion: v2  # Use v2 (faster, recommended)
          name: my-kms-provider
          endpoint: unix:///var/run/kmsplugin/socket.sock
          timeout: 3s
      - identity: {}
```

**Supported KMS Providers**:
- AWS KMS
- Azure Key Vault
- Google Cloud KMS
- HashiCorp Vault
- Any provider implementing the KMS plugin API

### Applying Encryption Configuration

1. **Create the EncryptionConfiguration file**
2. **Mount it into the API server**
3. **Add API server flag**: `--encryption-provider-config=/path/to/config.yaml`
4. **Restart the API server**
5. **Re-encrypt existing secrets**:
   ```bash
   kubectl get secrets --all-namespaces -o json | kubectl replace -f -
   ```

### Verification

After enabling encryption, verify it works:

```bash
# Read from etcd again
etcdctl get /registry/secrets/default/db-creds

# Result: Encrypted blob (k8s:enc:aescbc:v1:key1:...)
# Password is NO LONGER readable! 
```

## Encryption Providers Comparison

| Provider | Security | Performance | Complexity | Production Ready |
|----------|----------|-------------|------------|--------------|
| **identity** | None (plain text) | Fast | Simple | No |
| **aescbc** | Local key | Fast | Simple | Dev/Test only |
| **aesgcm** | Local key | Fast | Simple | Dev/Test only |
| **secretbox** | Local key | Fast | Simple | Dev/Test only |
| **KMS v1** | External | Slow | Complex | Deprecated |
| **KMS v2** | External | Fast | Complex |  **Recommended** |

## Best Practices

1. **Use KMS v2 in production** with an external key management service
2. **Rotate keys regularly** (recommended: every 90 days)
3. **Encrypt Secrets at minimum** (consider ConfigMaps and custom resources)
4. **Keep identity provider as fallback** during migration
5. **Test encryption** by reading from etcd directly
6. **Monitor KMS operations** for security anomalies
7. **Secure the EncryptionConfiguration file** (permissions 600, owned by root)
8. **Backup encryption keys separately** from etcd backups
9. **Document your encryption strategy** for compliance audits
10. **Plan for key rotation** before deploying to production

## Common Pitfalls

### 1. **Forgetting to Re-encrypt Existing Secrets**
- **Problem**: After enabling encryption, old secrets remain unencrypted
- **Fix**: Run `kubectl get secrets --all-namespaces -o json | kubectl replace -f -`

### 2. **Losing the Encryption Key**
- **Problem**: Lost key = lost access to ALL secrets
- **Fix**: Backup keys securely, use external KMS with key recovery

### 3. **Using "identity" Provider Alone**
- **Problem**: Provides NO encryption, despite being in the config
- **Fix**: Ensure identity is only used as a fallback, not primary

### 4. **Not Testing Encryption**
- **Problem**: Think encryption is working when it's not
- **Fix**: Verify by reading etcd directly or checking the key prefix (k8s:enc:)

### 5. **Local Keys in Production**
- **Problem**: aescbc/aesgcm don't protect against host compromise
- **Fix**: Use KMS v2 with external key management

### 6. **Incorrect API Server Configuration**
- **Problem**: Config file not mounted or flag not set
- **Fix**: Verify API server logs for encryption provider initialization

### 7. **Performance Issues with KMS v1**
- **Problem**: KMS v1 is slow (generates DEK per resource)
- **Fix**: Use KMS v2 (generates DEK per API server, much faster)

## Migration Strategy

### Enabling Encryption on an Existing Cluster

1. **Start with identity as fallback**:
   ```yaml
   providers:
     - aescbc: {...}
     - identity: {}  # Allows reading old unencrypted data
   ```

2. **Enable encryption** and restart API server

3. **Re-encrypt existing secrets**:
   ```bash
   kubectl get secrets --all-namespaces -o json | kubectl replace -f -
   ```

4. **Verify all secrets are encrypted** by checking etcd

5. **Remove identity provider** after migration complete (optional)

### Rotating Encryption Keys

1. **Add new key** to the configuration (keep old key):
   ```yaml
   providers:
     - aescbc:
         keys:
           - name: key2  # New key (used for writes)
             secret: <new-key>
           - name: key1  # Old key (used for reads)
             secret: <old-key>
   ```

2. **Restart API server**

3. **Re-encrypt all secrets** (writes use new key)

4. **Remove old key** from configuration after verification

## Resources

- [Official Kubernetes Encryption at Rest Documentation](https://kubernetes.io/docs/tasks/administer-cluster/encrypt-data/)
- [KMS Encryption Provider](https://kubernetes.io/docs/tasks/administer-cluster/kms-provider/)
- [Encrypting Confidential Data at Rest (Kubernetes Tasks)](https://kubernetes.io/docs/tasks/administer-cluster/encrypt-data/)
- [KMS v2 Improvements](https://kubernetes.io/blog/2022/09/09/kms-v2-improvements/)
- [NSA/CISA Kubernetes Hardening Guide](https://media.defense.gov/2022/Aug/29/2003066362/-1/-1/0/CTR_KUBERNETES_HARDENING_GUIDANCE_1.2_20220829.PDF)
- [CNCF Security Best Practices](https://www.cncf.io/blog/2022/06/07/kubernetes-security-best-practices/)

## Examples

See the `examples/` directory for:
- `encryption-config-aescbc.yaml` - Local encryption (demo/dev)
- `encryption-config-kms-v2.yaml` - Production KMS configuration
- `demo-secret.yaml` - Test secret for demonstrations
