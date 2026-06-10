#!/bin/bash
# configure-vault.sh - Initialize and configure Vault (run manually or automated)

set -e

export VAULT_ADDR='http://127.0.0.1:8200'

echo "=== Initializing Vault ==="

# Check if Vault is already initialized
if vault status 2>&1 | grep -q "Sealed"; then
    echo "Vault is already initialized but sealed. Unsealing..."
    # If we have unseal keys saved, unseal here
    if [ -f /home/vagrant/.vault-unseal-keys ]; then
        for i in {1..3}; do
            KEY=$(sed -n "${i}p" /home/vagrant/.vault-unseal-keys | cut -d':' -f2 | xargs)
            vault operator unseal "$KEY"
        done
    fi
elif vault status 2>&1 | grep -q "Vault is sealed"; then
    echo "Vault is sealed. Unsealing..."
    if [ -f /home/vagrant/.vault-unseal-keys ]; then
        for i in {1..3}; do
            KEY=$(sed -n "${i}p" /home/vagrant/.vault-unseal-keys | cut -d':' -f2 | xargs)
            vault operator unseal "$KEY"
        done
    fi
elif vault status 2>&1 | grep -q "Initialized"; then
    echo "Vault is already initialized and unsealed"
else
    # Initialize Vault with 5 keys, threshold 3
    vault operator init -key-shares=5 -key-threshold=3 > /home/vagrant/.vault-keys.txt
    
    # Extract unseal keys and root token
    grep "Unseal Key" /home/vagrant/.vault-keys.txt | cut -d' ' -f4 > /home/vagrant/.vault-unseal-keys
    grep "Initial Root Token" /home/vagrant/.vault-keys.txt | cut -d' ' -f4 > /home/vagrant/.vault-root-token
    
    # Unseal Vault with first 3 keys
    for i in {1..3}; do
        KEY=$(sed -n "${i}p" /home/vagrant/.vault-unseal-keys)
        vault operator unseal "$KEY"
    done
    
    # Set root token for CLI
    ROOT_TOKEN=$(cat /home/vagrant/.vault-root-token)
    vault login "$ROOT_TOKEN" > /dev/null 2>&1
    
    echo "Vault initialized and unsealed"
    echo "Root token saved to /home/vagrant/.vault-root-token"
    echo "Unseal keys saved to /home/vagrant/.vault-unseal-keys"
fi

# Login if not already
if ! vault token lookup > /dev/null 2>&1; then
    ROOT_TOKEN=$(cat /home/vagrant/.vault-root-token)
    vault login "$ROOT_TOKEN" > /dev/null 2>&1
fi

echo "=== Configuring Vault for Kubernetes ==="

# Enable KV v2 engine
vault secrets enable -version=2 -path=secret kv-v2

# Create policy for Kubernetes service accounts
vault policy write k8s-policy - <<EOF
path "secret/data/*" {
  capabilities = ["read", "list"]
}
path "secret/metadata/*" {
  capabilities = ["list"]
}
path "sys/renew/*" {
  capabilities = ["update"]
}
path "auth/token/renew" {
  capabilities = ["update"]
}
EOF

# Enable Kubernetes auth
vault auth enable kubernetes

# Get Kubernetes API server endpoint (from cp1 node)
K8S_HOST=$(vagrant ssh cp1 -c "kubectl cluster-info | grep 'Kubernetes control plane' | awk '{print \$NF}'" 2>/dev/null | tr -d '\r')
if [ -z "$K8S_HOST" ]; then
    K8S_HOST="https://192.168.56.10:6443"
fi

# Get Kubernetes CA certificate from cp1
K8S_CA_CERT=$(vagrant ssh cp1 -c "sudo cat /etc/kubernetes/pki/ca.crt" 2>/dev/null | base64 | tr -d '\n')

# Configure Kubernetes auth
vault write auth/kubernetes/config \
    kubernetes_host="$K8S_HOST" \
    kubernetes_ca_cert="$K8S_CA_CERT" \
    disable_iss_validation=true

echo "=== Creating sample secrets for demo ==="

# Create sample service secrets
vault kv put secret/shared/postgres-prod \
    username="postgres_admin" \
    password="$(openssl rand -base64 32)" \
    database="appdb" \
    host="postgres.database.svc.cluster.local" \
    port="5432"

vault kv put secret/shared/redis-cache \
    password="$(openssl rand -base64 32)" \
    host="redis-master.cache.svc.cluster.local" \
    port="6379"

# Create service-specific secrets for 3 example services
for service in payment-api inventory-svc user-auth; do
    vault kv put secret/service/${service}/prod \
        api_key="$(openssl rand -base64 32 | tr -d '=' | head -c 32)" \
        db_password="$(openssl rand -base64 32)" \
        jwt_secret="$(openssl rand -base64 48)"
    
    vault kv put secret/service/${service}/staging \
        api_key="staging_$(openssl rand -base64 16 | tr -d '=' | head -c 16)" \
        db_password="staging_$(openssl rand -base64 16)" \
        jwt_secret="staging_$(openssl rand -base64 24)"
done

echo "=== Creating service accounts in Kubernetes ==="

# Create service accounts for each service
vagrant ssh cp1 -c "kubectl create namespace prod --dry-run=client -o yaml | kubectl apply -f -" 2>/dev/null
vagrant ssh cp1 -c "kubectl create namespace staging --dry-run=client -o yaml | kubectl apply -f -" 2>/dev/null

for service in payment-api inventory-svc user-auth; do
    # Create service account
    vagrant ssh cp1 -c "kubectl create sa ${service}-sa -n prod --dry-run=client -o yaml | kubectl apply -f -" 2>/dev/null
    
    # Create Vault role for this service account
    vault write auth/kubernetes/role/${service} \
        bound_service_account_names="${service}-sa" \
        bound_service_account_namespaces=prod \
        policies=k8s-policy \
        ttl=24h
done

echo "=== Vault configuration complete ==="
echo ""
echo "=========================================="
echo "Vault is ready at: http://192.168.56.13:8200"
echo "UI can be accessed at the same address"
echo "Root token: $(cat /home/vagrant/.vault-root-token)"
echo "=========================================="
echo ""
echo "To test Vault access from Kubernetes:"
echo "  vagrant ssh cp1"
echo "  kubectl run test-pod --image=curlimages/curl -i --tty --rm -- sh"
echo "  # Then inside pod: curl http://vault.secrets.svc.cluster.local:8200/v1/sys/health"