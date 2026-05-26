#!/bin/bash
# ec2-worker.sh - Simple EC2 worker node setup
# Usage: ./ec2-worker.sh "kubeadm join <ip>:6443 --token <token> --discovery-token-ca-cert-hash sha256:<hash>"

set -e

echo "=========================================="
echo "Kubernetes Worker Node Setup (EC2)"
echo "=========================================="

# Check if join command was provided
if [ -z "$1" ]; then
    echo ""
    echo "❌ Please provide the join command from control plane"
    echo ""
    echo "Usage: ./ec2-worker.sh \"join-command\""
    echo ""
    echo "Example:"
    echo "  ./ec2-worker.sh \"kubeadm join 172.31.12.73:6443 --token 1u1fxm.6xgbirwrrw9ymvbj --discovery-token-ca-cert-hash sha256:4ec0ff33de370fa3a4eebe2a628760a0193afd841bb2637724dcfa9d61cf9076\""
    echo ""
    exit 1
fi

JOIN_COMMAND="$1"

# Get EC2 instance IP
PRIVATE_IP=$(hostname -I | awk '{print $1}')
echo "Worker Private IP: $PRIVATE_IP"

# Step 1: Install dependencies
echo "[1/5] Installing dependencies..."
sudo apt update -y
sudo apt install -y curl wget vim jq apt-transport-https ca-certificates gnupg

# Step 2: Configure kernel modules
echo "[2/5] Configuring kernel modules..."
sudo tee /etc/modules-load.d/containerd.conf <<EOF
overlay
br_netfilter
EOF

sudo modprobe overlay
sudo modprobe br_netfilter

sudo tee /etc/sysctl.d/99-kubernetes-cri.conf <<EOF
net.bridge.bridge-nf-call-iptables  = 1
net.ipv4.ip_forward                 = 1
net.bridge.bridge-nf-call-ip6tables = 1
EOF

sudo sysctl --system

# Step 3: Install containerd
echo "[3/5] Installing containerd..."
sudo apt install -y containerd

sudo mkdir -p /etc/containerd
sudo containerd config default | sudo tee /etc/containerd/config.toml
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
sudo systemctl restart containerd
sudo systemctl enable containerd

# Step 4: Install Kubernetes v1.36
echo "[4/5] Installing Kubernetes v1.36..."

sudo mkdir -p /etc/apt/keyrings
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.36/deb/Release.key | \
    sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.36/deb/ /" | \
    sudo tee /etc/apt/sources.list.d/kubernetes.list

sudo apt update
sudo apt install -y kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl

# Disable swap
sudo swapoff -a
sudo sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab

# Step 5: Join the cluster
echo "[5/5] Joining cluster..."
sudo $JOIN_COMMAND

echo ""
echo "=========================================="
echo "✅ WORKER NODE SETUP COMPLETE!"
echo "=========================================="
echo ""
echo "Verify from control plane:"
echo "  kubectl get nodes"
echo ""
