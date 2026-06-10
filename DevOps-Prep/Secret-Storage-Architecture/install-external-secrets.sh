#!/bin/bash
# install-external-secrets.sh

set -e

echo "=== Installing External Secrets Operator ==="

# Add ESO Helm repository
helm repo add external-secrets https://charts.external-secrets.io
helm repo update

# Install ESO
helm upgrade --install external-secrets external-secrets/external-secrets \
  --namespace external-secrets \
  --create-namespace \
  --set installCRDs=true \
  --set replicaCount=1

# Wait for ESO to be ready
kubectl wait --for=condition=available --timeout=120s deployment/external-secrets -n external-secrets

echo "=== Creating Vault token secret ==="

# Copy ESO token from secrets node
ESO_TOKEN=$(ssh vagrant@192.168.56.13 "sudo cat /home/vagrant/.eso-token" 2>/dev/null)

if [ -n "$ESO_TOKEN" ]; then
    kubectl create secret generic vault-token \
        --namespace default \
        --from-literal=token="$ESO_TOKEN" \
        --dry-run=client -o yaml | kubectl apply -f -
    echo "Vault token secret created"
else
    echo "ERROR: Could not get ESO token from secrets node"
    exit 1
fi

echo "=== Creating SecretStore ==="

# Use the pod network IP for Vault
VAULT_POD_IP="10.0.0.13"

cat << YAML | kubectl apply -f -
apiVersion: external-secrets.io/v1
kind: SecretStore
metadata:
  name: vault-backend
  namespace: default
spec:
  provider:
    vault:
      server: "http://${VAULT_POD_IP}:8200"
      path: "secret"
      version: "v2"
      auth:
        tokenSecretRef:
          name: vault-token
          key: token
      timeout: 30s
YAML

echo "=== Creating ExternalSecrets ==="

cat << YAML | kubectl apply -f -
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: payment-api-secrets
  namespace: default
spec:
  refreshInterval: 30s
  secretStoreRef:
    name: vault-backend
    kind: SecretStore
  target:
    name: payment-api-creds
    creationPolicy: Owner
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
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: redis-secrets
  namespace: default
spec:
  refreshInterval: 30s
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
YAML

echo "Waiting for secrets to sync..."
sleep 15

echo "=== Status ==="
kubectl get secretstore
kubectl get externalsecret
kubectl get secret | grep creds

echo "ESO installation complete"
