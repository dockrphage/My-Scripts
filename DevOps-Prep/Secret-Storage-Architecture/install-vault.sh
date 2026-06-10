#!/bin/bash
# install-vault.sh - Run on secrets node

set -e

echo "=== Installing HashiCorp Vault on secrets node ==="

# Add HashiCorp GPG key and repository
curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo apt-key add -
sudo apt-add-repository "deb [arch=amd64] https://apt.releases.hashicorp.com $(lsb_release -cs) main"

# Install Vault
sudo apt-get update
sudo apt-get install -y vault

# Create Vault configuration directory
sudo mkdir -p /etc/vault.d
sudo mkdir -p /opt/vault/data
sudo mkdir -p /var/log/vault

# Set permissions
sudo chown -R vault:vault /opt/vault/data 2>/dev/null || true
sudo chown -R vault:vault /var/log/vault 2>/dev/null || true

# Get the pod network IP (10.0.0.13)
POD_NET_IP=$(ip addr show enp0s8 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -1 || echo "10.0.0.13")

# Create Vault configuration file - Listen on all interfaces
sudo tee /etc/vault.d/vault.hcl > /dev/null <<VAULT_CONFIG
# Vault configuration
storage "raft" {
  path = "/opt/vault/data"
  node_id = "secrets-1"
  
  retry_join {
    leader_api_addr = "http://${POD_NET_IP}:8200"
  }
}

listener "tcp" {
  address     = "0.0.0.0:8200"
  tls_disable = true
}

# Enable UI
ui = true

# API address
api_addr = "http://${POD_NET_IP}:8200"
cluster_addr = "http://${POD_NET_IP}:8201"

# Log level
log_level = "Info"
log_file = "/var/log/vault/vault.log"

# Disable MLock (for development)
disable_mlock = true
VAULT_CONFIG

# Create systemd service file
sudo tee /etc/systemd/system/vault.service > /dev/null <<SERVICE
[Unit]
Description=HashiCorp Vault
Documentation=https://www.vaultproject.io/docs/
Requires=network-online.target
After=network-online.target

[Service]
User=vault
Group=vault
ExecStart=/usr/bin/vault server -config=/etc/vault.d/vault.hcl
ExecReload=/bin/kill -HUP \$MAINPID
KillMode=process
KillSignal=SIGINT
Restart=on-failure
RestartSec=5
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
SERVICE

# Create vault user if not exists
sudo useradd --system --home /etc/vault.d --shell /bin/false vault 2>/dev/null || true
sudo chown -R vault:vault /etc/vault.d
sudo chmod 640 /etc/vault.d/vault.hcl

# Enable and start Vault
sudo systemctl daemon-reload
sudo systemctl enable vault
sudo systemctl start vault

# Wait for Vault to start
sleep 5

echo "Vault service installed and started on ${POD_NET_IP}:8200"
