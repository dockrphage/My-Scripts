#!/bin/bash
# setup-cp-v1.36.sh - Using latest Kubernetes v1.36

set -e

echo "=========================================="
echo "Kubernetes Control Plane Setup (v1.36)"
echo "=========================================="

# Get EC2 instance IPs
PRIVATE_IP=$(hostname -I | awk '{print $1}')
echo "Private IP: $PRIVATE_IP"

# Get public IP if available
TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600" 2>/dev/null || echo "")
if [ -n "$TOKEN" ]; then
    PUBLIC_IP=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null || echo "")
    echo "Public IP: ${PUBLIC_IP:-None}"
fi

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

# Step 5: Initialize cluster with v1.36
echo "[5/5] Initializing Kubernetes cluster..."

CERT_SANS="$PRIVATE_IP"
if [ -n "$PUBLIC_IP" ]; then
    CERT_SANS="$CERT_SANS,$PUBLIC_IP"
fi

# Use v1.36 for initialization
sudo kubeadm init \
    --apiserver-advertise-address=$PRIVATE_IP \
    --apiserver-cert-extra-sans=$CERT_SANS \
    --pod-network-cidr=10.244.0.0/16

# Setup kubeconfig
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

# Install Calico
echo "Installing Calico CNI..."
kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.27/manifests/calico.yaml

# Generate join token
JOIN_CMD=$(sudo kubeadm token create --print-join-command)
echo "$JOIN_CMD" > /tmp/worker-join-command.txt

echo ""
echo "=========================================="
echo "✅ CONTROL PLANE SETUP COMPLETE!"
echo "=========================================="
echo ""
echo "📋 Worker join command:"
echo "   $JOIN_CMD"
echo ""
echo "Join command saved to: /tmp/worker-join-command.txt"
