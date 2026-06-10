#!/bin/bash
# install-vault.sh - Run on secrets node (192.168.56.13)

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
sudo chown -R vault:vault /opt/vault/data
sudo chown -R vault:vault /var/log/vault

# Create Vault configuration file
sudo tee /etc/vault.d/vault.hcl > /dev/null <<EOF
# Vault configuration for dev/test (RAID storage)
storage "raft" {
  path = "/opt/vault/data"
  node_id = "secrets-1"
  
  retry_join {
    leader_api_addr = "http://192.168.56.13:8200"
  }
}

listener "tcp" {
  address     = "0.0.0.0:8200"
  tls_disable = true
}

# Enable UI
ui = true

# API address
api_addr = "http://192.168.56.13:8200"
cluster_addr = "http://192.168.56.13:8201"

# Log level
log_level = "Info"
log_file = "/var/log/vault/vault.log"
log_rotate_bytes = 104857600  # 100 MB
log_rotate_max_files = 5

# Disable MLock (for development)
disable_mlock = true
EOF

# Create systemd service file
sudo tee /etc/systemd/system/vault.service > /dev/null <<EOF
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
LimitMEMLOCK=infinity

[Install]
WantedBy=multi-user.target
EOF

# Create vault user if not exists
sudo useradd --system --home /etc/vault.d --shell /bin/false vault || true
sudo chown -R vault:vault /etc/vault.d
sudo chmod 640 /etc/vault.d/vault.hcl

# Enable and start Vault
sudo systemctl daemon-reload
sudo systemctl enable vault
sudo systemctl start vault

# Wait for Vault to start
sleep 5

echo "Vault service installed and started"
echo "Initialize Vault by running: sudo bash /home/vagrant/configure-vault.sh"