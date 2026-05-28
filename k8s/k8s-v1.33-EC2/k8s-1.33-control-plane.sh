#!/bin/bash

# k8s-1.33-control-plane.sh

set -e

echo "=== Kubernetes 1.33 Control Plane Setup Script for EC2 ==="

# Detect IPs using IMDSv2
PRIVATE_IP=$(hostname -I | awk '{print $1}')

# Get IMDSv2 token
TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" \
  -H "X-aws-ec2-metadata-token-ttl-seconds: 21600" 2>/dev/null || echo "")

if [ -z "$TOKEN" ]; then
  echo "Warning: Could not get IMDSv2 token, public IP will not be available"
  PUBLIC_IP=""
else
  PUBLIC_IP=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" \
    http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null || echo "")
fi

# Set certificate SANs
if [ -z "$PUBLIC_IP" ]; then
  echo "Public IP not available, using private IP only"
  CERT_SANS="$PRIVATE_IP"
else
  echo "Public IP: $PUBLIC_IP"
  CERT_SANS="$PUBLIC_IP,$PRIVATE_IP"
fi

echo "Private IP: $PRIVATE_IP"
echo "Certificate SANs: $CERT_SANS"

# Detect OS and Architecture
MYOS=$(hostnamectl | awk '/Operating/ { print $3 }')
OSVERSION=$(hostnamectl | awk '/Operating/ { print $4 }')
[ $(arch) = aarch64 ] && PLATFORM=arm64
[ $(arch) = x86_64 ] && PLATFORM=amd64

echo "OS: $MYOS $OSVERSION"
echo "Platform: $PLATFORM"

# Disable swap (required for Kubernetes)
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
CONTAINERD_VERSION="1.7.24"  # Fixed stable version
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
RUNC_VERSION="v1.2.4"  # Fixed stable version
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

# Add Kubernetes GPG key for v1.33
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.33/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

# Add Kubernetes v1.33 repository
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.33/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list

# Install kubeadm, kubelet, kubectl
sudo apt-get update
sudo apt-get install -y kubelet=1.33.0-1.1 kubeadm=1.33.0-1.1 kubectl=1.33.0-1.1
sudo apt-mark hold kubelet kubeadm kubectl

# Enable kubelet
sudo systemctl enable kubelet

# Step 8: Initialize kubeadm with v1.33
echo "=== Initializing kubeadm v1.33 ==="
sudo kubeadm init \
  --apiserver-advertise-address=$PRIVATE_IP \
  --apiserver-cert-extra-sans=$CERT_SANS \
  --pod-network-cidr=10.244.0.0/16 \
  --kubernetes-version=v1.33.0

# Step 9: Setup kubeconfig
echo "=== Setting up kubeconfig ==="
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

# Step 10: Install CNI (Calico) with correct pod CIDR
echo "=== Installing Calico CNI ==="

# Install Tigera Operator first (this installs CRDs)
echo "Installing Tigera Operator..."
kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.29.0/manifests/tigera-operator.yaml

# Wait for CRDs to be registered
echo "Waiting for CRDs to be registered..."
sleep 15

# Verify CRDs are installed
kubectl get crd | grep operator.tigera.io || echo "Waiting for CRDs..."

# Now create the Installation and APIServer objects with correct CIDR
echo "Configuring Calico networking..."
cat <<EOF | kubectl apply -f -
apiVersion: operator.tigera.io/v1
kind: Installation
metadata:
  name: default
spec:
  calicoNetwork:
    bgp: Enabled
    ipPools:
    - blockSize: 26
      cidr: 10.244.0.0/16
      encapsulation: VXLANCrossSubnet
      natOutgoing: Enabled
      nodeSelector: all()
  controlPlaneReplicas: 1
  variant: Calico
---
apiVersion: operator.tigera.io/v1
kind: APIServer
metadata:
  name: default
spec: {}
EOF

# Wait for Calico to initialize
echo "Waiting for Calico to be ready (this may take 1-2 minutes)..."
sleep 30

# Wait for calico-node daemonset
kubectl wait --for=condition=ready pod -l k8s-app=calico-node -n calico-system --timeout=120s 2>/dev/null || true

echo "Calico CNI installation completed successfully"


# Step 11: Install Helm (using official script - most reliable method)
echo "=== Installing Helm ==="

# Download and run official Helm installation script
curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-4 -o get_helm.sh
chmod +x get_helm.sh
./get_helm.sh

# Verify installation
helm version

# Clean up
rm get_helm.sh

# Step 12: Generate join token for worker nodes
echo ""
echo "=== Generating Worker Node Join Token ==="
JOIN_COMMAND=$(sudo kubeadm token create --print-join-command)
echo "Worker nodes can join using:"
echo "$JOIN_COMMAND"
echo ""
echo "Save this token for adding worker nodes later"

# Save join command to file for reference
echo "$JOIN_COMMAND" > ~/join-command.txt
echo "Join command saved to ~/join-command.txt"

# Final verification
echo ""
echo "=== Setup Complete ==="
echo "Cluster initialized with:"
echo "  Private IP: $PRIVATE_IP"
echo "  Public IP: $PUBLIC_IP"
echo "  Certificate SANs: $CERT_SANS"
echo "  Kubernetes Version: v1.33.0"
echo ""
echo "Control Plane Setup Complete!"
echo ""
kubectl get nodes
kubectl get pods -A
echo ""
echo "=== Upgrade Notes ==="
echo "To upgrade to 1.35:"
echo "1. First upgrade control plane: sudo kubeadm upgrade plan"
echo "2. Apply upgrade: sudo kubeadm upgrade apply v1.35.3"
echo "3. Upgrade kubelet: sudo apt-get install kubelet=1.35.3-1.1"
echo "4. Drain and upgrade worker nodes"
echo "5. Verify: kubectl get nodes"
