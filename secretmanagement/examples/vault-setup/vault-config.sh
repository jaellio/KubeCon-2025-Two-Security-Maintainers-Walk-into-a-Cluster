#!/bin/bash

# Script to configure Vault with demo secrets
# This should be run after Vault is deployed and ready

set -e

VAULT_POD="vault-0"
NAMESPACE="default"

echo "Configuring Vault with demo secrets..."

# Wait for Vault to be ready
echo "Waiting for Vault pod to be ready..."
kubectl wait --for=condition=ready pod/${VAULT_POD} -n ${NAMESPACE} --timeout=60s

# Enable KV secrets engine
echo "Enabling KV secrets engine..."
kubectl exec -n ${NAMESPACE} ${VAULT_POD} -- vault secrets enable -path=secret kv-v2 || true

# Create database credentials in Vault
echo "Creating database credentials in Vault..."
kubectl exec -n ${NAMESPACE} ${VAULT_POD} -- vault kv put secret/db-creds \
  username=admin \
  password=SuperSecret123! \
  host=postgres.production.svc.cluster.local \
  port=5432

# Enable Kubernetes auth method
echo "Enabling Kubernetes auth method..."
kubectl exec -n ${NAMESPACE} ${VAULT_POD} -- vault auth enable kubernetes || true

# Configure Kubernetes auth
echo "Configuring Kubernetes auth..."
kubectl exec -n ${NAMESPACE} ${VAULT_POD} -- sh -c '
  vault write auth/kubernetes/config \
    kubernetes_host="https://$KUBERNETES_PORT_443_TCP_ADDR:443"
'

# Create policy for reading secrets
echo "Creating Vault policy..."
kubectl exec -n ${NAMESPACE} ${VAULT_POD} -- sh -c '
  vault policy write demo-app - <<EOF
path "secret/data/db-creds" {
  capabilities = ["read"]
}
EOF
'

# Create Kubernetes role
echo "Creating Kubernetes role..."
kubectl exec -n ${NAMESPACE} ${VAULT_POD} -- vault write auth/kubernetes/role/demo-role \
  bound_service_account_names=demo-sa \
  bound_service_account_namespaces=default \
  policies=demo-app \
  ttl=24h

echo "✅ Vault configuration complete!"
echo ""
echo "Vault is ready at: http://vault.default.svc.cluster.local:8200"
echo "Root token: root"
echo ""
echo "Test secret access:"
echo "  kubectl exec vault-0 -- vault kv get secret/db-creds"
