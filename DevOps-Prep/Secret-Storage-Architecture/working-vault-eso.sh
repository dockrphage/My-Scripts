#!/bin/bash
set -e

echo "========================================="
echo "Vault to Kubernetes Secret Sync"
echo "========================================="

# Step 1: Get token from secrets node
echo "Step 1: Retrieving Vault token..."
TOKEN=$(vagrant ssh secrets -c "sudo cat /home/vagrant/.eso-token" 2>/dev/null | tr -d '\n\r')
if [ -z "$TOKEN" ]; then
    echo "ERROR: Failed to get token from secrets node"
    exit 1
fi
echo "✓ Token obtained (length: ${#TOKEN})"

# Step 2: Create secret in Kubernetes
echo "Step 2: Creating Kubernetes secret..."
vagrant ssh cp1 << EOF > /dev/null 2>&1
kubectl delete secret vault-token -n default 2>/dev/null
kubectl create secret generic vault-token --namespace default --from-literal=token="$TOKEN"
EOF
echo "✓ Secret created"

# Step 3: Create SecretStore
echo "Step 3: Creating SecretStore..."
vagrant ssh cp1 << 'EOF' > /dev/null 2>&1
kubectl delete secretstore vault-backend 2>/dev/null
cat << YAML | kubectl apply -f -
apiVersion: external-secrets.io/v1
kind: SecretStore
metadata:
  name: vault-backend
  namespace: default
spec:
  provider:
    vault:
      server: "http://10.0.0.13:8200"
      path: "secret"
      version: "v2"
      auth:
        tokenSecretRef:
          name: vault-token
          key: token
YAML
EOF
echo "✓ SecretStore created"

# Step 4: Check SecretStore status
echo "Step 4: Checking SecretStore status..."
sleep 8
vagrant ssh cp1 << 'EOF'
READY=$(kubectl get secretstore vault-backend -o jsonpath='{.status.conditions[0].status}' 2>/dev/null)
if [ "$READY" = "True" ]; then
    echo "✓ SecretStore is ready"
else
    echo "⚠️  SecretStore status: $READY"
    kubectl get secretstore
fi
EOF

# Step 5: Check ExternalSecrets and generated secrets
echo "Step 5: Checking ExternalSecrets..."
sleep 10
vagrant ssh cp1 << 'EOF'
echo ""
echo "=== ExternalSecrets ==="
kubectl get externalsecret

echo ""
echo "=== Generated Secrets ==="
kubectl get secret | grep -E "payment-api-creds|redis-creds"

if kubectl get secret payment-api-creds &>/dev/null; then
    echo ""
    echo "✅✅✅ SUCCESS! ✅✅✅"
    echo ""
    echo "Secret values retrieved from Vault:"
    echo "  DB_PASSWORD: $(kubectl get secret payment-api-creds -o jsonpath='{.data.DB_PASSWORD}' | base64 -d)"
    echo "  API_KEY: $(kubectl get secret payment-api-creds -o jsonpath='{.data.API_KEY}' | base64 -d | cut -c1-20)..."
    echo "  JWT_SECRET: $(kubectl get secret payment-api-creds -o jsonpath='{.data.JWT_SECRET}' | base64 -d | cut -c1-20)..."
    echo ""
    echo "  REDIS_HOST: $(kubectl get secret redis-creds -o jsonpath='{.data.REDIS_HOST}' | base64 -d)"
    echo "  REDIS_PASSWORD: $(kubectl get secret redis-creds -o jsonpath='{.data.REDIS_PASSWORD}' | base64 -d | cut -c1-20)..."
    echo ""
    echo "🎉 Vault to Kubernetes secret synchronization is WORKING!"
else
    echo ""
    echo "❌ Secrets not yet created. Waiting longer..."
    echo "Checking SecretStore details:"
    kubectl describe secretstore vault-backend | grep -A8 "Status:"
    echo ""
    echo "ESO logs:"
    kubectl logs -n external-secrets deployment/external-secrets --tail=10
fi
EOF

echo ""
echo "========================================="
echo "To test secret rotation:"
echo "  vagrant ssh secrets"
echo "  export VAULT_ADDR='http://127.0.0.1:8200'"
echo "  vault login \$(cat /home/vagrant/.vault-root-token)"
echo "  vault kv put secret/service/payment-api/prod db_password=newpassword123"
echo "  # Wait 30 seconds, then check:"
echo "  kubectl get secret payment-api-creds -o jsonpath='{.data.DB_PASSWORD}' | base64 -d"
echo "========================================="
