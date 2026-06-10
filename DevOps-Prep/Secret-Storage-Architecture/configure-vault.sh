#!/bin/bash
# configure-vault.sh - Initialize and configure Vault

set -e

export VAULT_ADDR='http://127.0.0.1:8200'

echo "=== Initializing Vault ==="

# Check if Vault is already initialized
if vault status 2>&1 | grep -q "Sealed"; then
    echo "Vault is initialized but sealed. Unsealing..."
    if [ -f /home/vagrant/.vault-unseal-keys ]; then
        for i in {1..3}; do
            KEY=$(sed -n "${i}p" /home/vagrant/.vault-unseal-keys)
            vault operator unseal "$KEY"
        done
    fi
elif vault status 2>&1 | grep -q "Initialized"; then
    echo "Vault is already initialized and unsealed"
else
    # Initialize Vault with 5 keys, threshold 3
    vault operator init -key-shares=5 -key-threshold=3 > /home/vagrant/.vault-keys.txt
    
    # Extract unseal keys and root token
    grep "Unseal Key" /home/vagrant/.vault-keys.txt | awk '{print $4}' > /home/vagrant/.vault-unseal-keys
    grep "Initial Root Token" /home/vagrant/.vault-keys.txt | awk '{print $4}' > /home/vagrant/.vault-root-token
    
    # Unseal Vault with first 3 keys
    for i in {1..3}; do
        KEY=$(sed -n "${i}p" /home/vagrant/.vault-unseal-keys)
        vault operator unseal "$KEY"
    done
    
    # Set root token for CLI
    ROOT_TOKEN=$(cat /home/vagrant/.vault-root-token)
    vault login "$ROOT_TOKEN" > /dev/null 2>&1
    
    echo "Vault initialized and unsealed"
fi

# Login if not already
if ! vault token lookup > /dev/null 2>&1; then
    ROOT_TOKEN=$(cat /home/vagrant/.vault-root-token)
    vault login "$ROOT_TOKEN" > /dev/null 2>&1
fi

echo "=== Configuring Vault ==="

# Enable KV v2 engine
vault secrets enable -version=2 -path=secret kv-v2

# Create policy for Kubernetes
vault policy write k8s-policy - <<POLICY
path "secret/data/*" {
  capabilities = ["read", "list"]
}
path "secret/metadata/*" {
  capabilities = ["list"]
}
path "auth/token/renew" {
  capabilities = ["update"]
}
POLICY

# Create admin policy for ESO
vault policy write eso-policy - <<POLICY2
path "secret/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}
path "auth/token/create" {
  capabilities = ["create", "update"]
}
POLICY2

# Create a long-lived token for ESO
vault token create -policy=eso-policy -ttl=8760h -use-limit=0 -format=json | jq -r '.auth.client_token' > /home/vagrant/.eso-token

echo "=== Creating sample secrets ==="

# Create sample secrets
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

# Create service-specific secrets
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

echo "=== Vault configuration complete ==="
echo ""
echo "=========================================="
echo "Vault is ready"
echo "Root token: $(cat /home/vagrant/.vault-root-token)"
echo "ESO token: $(cat /home/vagrant/.eso-token)"
echo "=========================================="
