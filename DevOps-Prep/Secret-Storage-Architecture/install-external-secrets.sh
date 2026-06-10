#!/bin/bash
# install-external-secrets.sh - Install ESO on Kubernetes cluster

set -e

echo "=== Installing External Secrets Operator ==="

# Add ESO Helm repository
helm repo add external-secrets https://charts.external-secrets.io
helm repo update

# Install ESO
helm install external-secrets external-secrets/external-secrets \
  --namespace external-secrets \
  --create-namespace \
  --set installCRDs=true \
  --set replicaCount=2

# Wait for ESO to be ready
kubectl wait --for=condition=available --timeout=300s deployment/external-secrets -n external-secrets
kubectl wait --for=condition=available --timeout=300s deployment/external-secrets-cert-controller -n external-secrets
kubectl wait --for=condition=available --timeout=300s deployment/external-secrets-webhook -n external-secrets

echo "=== Creating SecretStore pointing to Vault ==="

# Get Vault service IP
VAULT_IP="192.168.56.13"

# Create SecretStore
cat <<EOF | kubectl apply -f -
apiVersion: external-secrets.io/v1beta1
kind: SecretStore
metadata:
  name: vault-backend
  namespace: default
spec:
  provider:
    vault:
      server: "http://${VAULT_IP}:8200"
      path: "secret"
      version: "v2"
      auth:
        tokenSecretRef:
          name: vault-token
          key: token
          namespace: default
---
# Example ExternalSecret for payment-api
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: payment-api-secrets
  namespace: default
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: vault-backend
    kind: SecretStore
  target:
    name: payment-api-creds
    creationPolicy: Owner
    template:
      type: Opaque
  data:
    - secretKey: DB_PASSWORD
      remoteRef:
        key: service/payment-api/prod
        property: db_password
    - secretKey: API_KEY
      remoteRef:
        key: service/payment-api/prod
        property: api_key
    - secretKey: JWT_SECRET
      remoteRef:
        key: service/payment-api/prod
        property: jwt_secret
---
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: redis-secrets
  namespace: default
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: vault-backend
    kind: SecretStore
  target:
    name: redis-creds
    creationPolicy: Owner
  data:
    - secretKey: REDIS_PASSWORD
      remoteRef:
        key: shared/redis-cache
        property: password
    - secretKey: REDIS_HOST
      remoteRef:
        key: shared/redis-cache
        property: host
EOF

echo "External Secrets Operator installed and configured"
kubectl get externalsecret -A
kubectl get secretstore -A