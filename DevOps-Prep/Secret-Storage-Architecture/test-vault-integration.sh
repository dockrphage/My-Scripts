#!/bin/bash
# test-vault-integration.sh - Test Vault integration from Kubernetes

set -e

echo "Testing Vault integration from Kubernetes..."

# Create test pod
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: vault-test
  namespace: default
spec:
  containers:
  - name: test
    image: curlimages/curl:latest
    command: ["sleep", "3600"]
    env:
    - name: VAULT_ADDR
      value: "http://192.168.56.13:8200"
    - name: VAULT_TOKEN
      valueFrom:
        secretKeyRef:
          name: vault-token
          key: token
          optional: true
EOF

# Wait for pod to be ready
echo "Waiting for test pod..."
kubectl wait --for=condition=ready pod/vault-test --timeout=60s

# Test Vault health
echo "Testing Vault health..."
kubectl exec vault-test -- curl -s http://192.168.56.13:8200/v1/sys/health | jq '.'

# Test secret access (if token is available)
echo "Testing secret access..."
kubectl exec vault-test -- curl -s -H "X-Vault-Token: $(cat /tmp/vault-token 2>/dev/null)" \
    http://192.168.56.13:8200/v1/secret/data/service/payment-api/prod | jq '.' 2>/dev/null || \
    echo "Need to configure Vault token secret first"

# Cleanup
kubectl delete pod vault-test

echo "Test complete"