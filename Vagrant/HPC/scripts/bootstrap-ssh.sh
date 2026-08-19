#!/bin/bash
# scripts/bootstrap-ssh.sh
# Unified OS-aware SSH + package installation

set -e

echo "Setting password for vagrant user..."
echo "vagrant:ss" | sudo chpasswd

# Detect OS family
OS=$(source /etc/os-release && echo "$ID")

case "$OS" in
    ubuntu)
        PKG_UPDATE="sudo apt update -y"
        PKG_INSTALL="sudo apt install -y vim git curl wget net-tools htop tree"
        SSH_CONFIG="/etc/ssh/sshd_config.d/60-cloudimg-settings.conf"
        SSH_SERVICE="ssh"
        ;;
    debian)
        PKG_UPDATE="sudo apt update -y"
        PKG_INSTALL="sudo apt install -y vim git curl wget net-tools htop tree"
        SSH_CONFIG="/etc/ssh/sshd_config"
        SSH_SERVICE="sshd"
        ;;
    rocky|rhel|centos|almalinux|fedora)
        PKG_UPDATE="sudo dnf update -y"
        PKG_INSTALL="sudo dnf install -y vim git curl wget net-tools htop tree"
        SSH_CONFIG="/etc/ssh/sshd_config"
        SSH_SERVICE="sshd"
        ;;
    *)
        echo "Unknown OS ($OS), using default SSH config and skipping package install."
        PKG_UPDATE="true"
        PKG_INSTALL="true"
        SSH_CONFIG="/etc/ssh/sshd_config"
        SSH_SERVICE="sshd"
        ;;
esac

echo "Using SSH config: $SSH_CONFIG"
echo "Restarting service: $SSH_SERVICE"
echo "Updating packages..."
eval "$PKG_UPDATE"
echo "Installing common packages..."
eval "$PKG_INSTALL"

# Ensure PasswordAuthentication yes is present and uncommented
sudo sed -i \
    -e 's/^#PasswordAuthentication.*/PasswordAuthentication yes/' \
    -e 's/^PasswordAuthentication.*/PasswordAuthentication yes/' \
    "$SSH_CONFIG"

# If not present at all, append it
if ! grep -q "^PasswordAuthentication yes" "$SSH_CONFIG"; then
    echo "PasswordAuthentication yes" | sudo tee -a "$SSH_CONFIG"
fi

# Restart SSH service
sudo systemctl restart "$SSH_SERVICE"

echo "Bootstrap complete."
