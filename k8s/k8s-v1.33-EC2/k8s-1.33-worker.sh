#!/bin/bash
# k8s-1.33-worker.sh
# Paste the join command when prompted

set -e

echo "=== Kubernetes 1.33 Worker Node Setup Script for EC2 ==="

# Detect OS and Architecture
MYOS=$(hostnamectl | awk '/Operating/ { print $3 }')
OSVERSION=$(hostnamectl | awk '/Operating/ { print $4 }')
[ $(arch) = aarch64 ] && PLATFORM=arm64
[ $(arch) = x86_64 ] && PLATFORM=amd64

echo "OS: $MYOS $OSVERSION"
echo "Platform: $PLATFORM"

# Disable swap
echo "=== Disabling swap ==="
sudo swapoff -a
sudo sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab

# Step 1: Install basic tools
echo "=== Installing basic tools ==="
sudo apt update -y
sudo apt-get install -y curl wget git vim jq apt-transport-https ca-certificates gnupg lsb-release

# Step 2: Setup container runtime prerequisites
echo "=== Setting up container runtime prerequisites ==="
cat <<- EOF | sudo tee /etc/modules-load.d/containerd.conf
overlay
br_netfilter
EOF

sudo modprobe overlay
sudo modprobe br_netfilter

# Setup required sysctl params
cat <<- EOF | sudo tee /etc/sysctl.d/99-kubernetes-cri.conf
net.bridge.bridge-nf-call-iptables  = 1
net.ipv4.ip_forward                 = 1
net.bridge.bridge-nf-call-ip6tables = 1
EOF

sudo sysctl --system

# Step 3: Install containerd
echo "=== Installing containerd ==="
CONTAINERD_VERSION="1.7.24"
echo "Containerd version: $CONTAINERD_VERSION"

cd /tmp
wget https://github.com/containerd/containerd/releases/download/v${CONTAINERD_VERSION}/containerd-${CONTAINERD_VERSION}-linux-${PLATFORM}.tar.gz
sudo tar xvf containerd-${CONTAINERD_VERSION}-linux-${PLATFORM}.tar.gz -C /usr/local
rm containerd-${CONTAINERD_VERSION}-linux-${PLATFORM}.tar.gz

# Configure containerd
sudo mkdir -p /etc/containerd
cat <<- TOML | sudo tee /etc/containerd/config.toml
version = 2
[plugins]
  [plugins."io.containerd.grpc.v1.cri"]
    [plugins."io.containerd.grpc.v1.cri".containerd]
      discard_unpacked_layers = true
      [plugins."io.containerd.grpc.v1.cri".containerd.runtimes]
        [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc]
          runtime_type = "io.containerd.runc.v2"
          [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc.options]
            SystemdCgroup = true
TOML

# Step 4: Install runc
echo "=== Installing runc ==="
RUNC_VERSION="v1.2.4"
echo "Runc version: $RUNC_VERSION"

wget https://github.com/opencontainers/runc/releases/download/${RUNC_VERSION}/runc.${PLATFORM}
sudo install -m 755 runc.${PLATFORM} /usr/local/sbin/runc
rm runc.${PLATFORM}

# Step 5: Setup containerd systemd service
echo "=== Setting up containerd systemd service ==="
wget https://raw.githubusercontent.com/containerd/containerd/main/containerd.service
sudo mv containerd.service /usr/lib/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now containerd

# Step 6: Setup AppArmor
echo "=== Setting up AppArmor ==="
sudo ln -sf /etc/apparmor.d/runc /etc/apparmor.d/disable/ 2>/dev/null || true
sudo apparmor_parser -R /etc/apparmor.d/runc 2>/dev/null || true

# Step 7: Install Kubernetes tools (v1.33)
echo "=== Installing Kubernetes tools v1.33 ==="

# Add Kubernetes GPG key
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.33/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

# Add Kubernetes v1.33 repository
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.33/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list

# Install kubeadm, kubelet, kubectl
sudo apt-get update
sudo apt-get install -y kubelet=1.33.0-1.1 kubeadm=1.33.0-1.1 kubectl=1.33.0-1.1
sudo apt-mark hold kubelet kubeadm kubectl

# Enable kubelet
sudo systemctl enable kubelet

# Step 8: Prompt for join command
echo ""
echo "=== Ready to Join Cluster ==="
echo "Please provide the join command from the control plane node."
echo "It should look like:"
echo "  kubeadm join <CONTROL_PLANE_IP>:6443 --token <TOKEN> --discovery-token-ca-cert-hash sha256:<HASH>"
echo ""
echo "The join command is saved as 'join-command.txt' on the control plane node"
echo ""
read -p "Paste the join command (without 'sudo'): " JOIN_COMMAND

# Step 9: Join the cluster
echo "=== Joining Kubernetes Cluster ==="
sudo $JOIN_COMMAND

# Step 10: Verify
echo ""
echo "=== Worker Node Setup Complete ==="
echo "Waiting for node to be ready..."
sleep 10

# Get node name
NODE_NAME=$(hostname)
echo "Node name: $NODE_NAME"
echo ""
echo "Run the following on the control plane to verify:"
echo "  kubectl get nodes"
echo "  kubectl get nodes -o wide"
