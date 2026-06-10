#!/bin/bash
echo "=== Final Solution for Vault-ESO Integration ==="

# Step 1: Get the token directly from secrets node
echo "Step 1: Retrieving Vault token..."
vagrant ssh secrets -c "sudo cat /home/vagrant/.eso-token | tr -d '\n\r'" > /tmp/eso-token.txt

# Step 2: Create Kubernetes secret properly
echo "Step 2: Creating Kubernetes secret..."
vagrant ssh cp1 << 'EOF'
kubectl delete secret vault-token -n default 2>/dev/null
kubectl create secret generic vault-token \
    --namespace default \
    --from-file=token=/vagrant/eso-token.txt 2>/dev/null || \
kubectl create secret generic vault-token \
    --namespace default \
    --from-literal=token=$(cat /tmp/eso-token.txt)
EOF

# Step 3: Test token
echo "Step 3: Testing token..."
vagrant ssh cp1 << 'EOF'
TOKEN=$(kubectl get secret vault-token -o jsonpath='{.data.token}' | base64 -d)
echo "Token length: ${#TOKEN}"
if curl -s -H "X-Vault-Token: $TOKEN" http://10.0.0.13:8200/v1/sys/health | grep -q "initialized"; then
    echo "✓ Token is valid"
else
    echo "✗ Token is invalid"
fi
EOF

# Step 4: Create SecretStore with inline token
echo "Step 4: Creating SecretStore..."
vagrant ssh cp1 << 'EOF'
TOKEN=$(kubectl get secret vault-token -o jsonpath='{.data.token}' | base64 -d)
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
        token:
          value: "$TOKEN"
YAML

sleep 5
echo "SecretStore status:"
kubectl get secretstore vault-backend
EOF

# Step 5: Wait and verify
echo "Step 5: Waiting for secrets to sync..."
sleep 20

vagrant ssh cp1 << 'EOF'
echo "=== Final Status ==="
kubectl get secretstore
kubectl get externalsecret
kubectl get secret | grep creds

if kubectl get secret payment-api-creds &>/dev/null; then
    echo -e "\n✓✓✓ SUCCESS! Integration is working! ✓✓✓"
    echo ""
    echo "Sample secret values:"
    echo "  DB_PASSWORD: $(kubectl get secret payment-api-creds -o jsonpath='{.data.DB_PASSWORD}' | base64 -d)"
    echo "  REDIS_HOST: $(kubectl get secret redis-creds -o jsonpath='{.data.REDIS_HOST}' | base64 -d)"
else
    echo -e "\n✗ Secrets not created. Please check:"
    echo "  1. Is Vault initialized on secrets node?"
    echo "  2. Does the token have proper permissions?"
    echo "  3. Are the secrets created in Vault?"
    
    echo -e "\nChecking Vault secrets..."
    TOKEN=$(kubectl get secret vault-token -o jsonpath='{.data.token}' | base64 -d)
    curl -s -H "X-Vault-Token: $TOKEN" http://10.0.0.13:8200/v1/secret/data/service/payment-api/prod | jq '.data.data.keys'
fi
EOF
