#!/bin/bash
# setup-worker-node.sh
# Run this script on worker nodes (192.168.56.11+)
# Pass the join command as an argument or set it manually
# Example usage:
#   sudo bash k8s-worker-setup.sh 192.168.56.11 "kubeadm join 192.168.56.10:6443 --token abcdef.0123456789abcdef --discovery-token-ca-cert-hash sha256:1234567890abcdef..."


set -e

WORKER_IP="${1:-192.168.56.11}"
JOIN_COMMAND="${2}"

# Detect platform
[ $(arch) = aarch64 ] && PLATFORM=arm64
[ $(arch) = x86_64 ] && PLATFORM=amd64

# Detect OS
MYOS=$(hostnamectl | awk '/Operating/ { print $3 }')
OSVERSION=$(hostnamectl | awk '/Operating/ { print $4 }')

echo "=========================================="
echo "Setting up Kubernetes Worker Node"
echo "=========================================="

# Step 1: Install dependencies
echo "[Step 1] Installing dependencies..."
sudo apt update -y
sudo apt install -y jq curl wget vim git apt-transport-https

# Step 2: Setup container runtime (containerd)
echo "[Step 2] Setting up container runtime..."

if [ $MYOS = "Ubuntu" ]; then

    # Load kernel modules
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

    # Install containerd (latest version)
    CONTAINERD_VERSION=$(curl -s https://api.github.com/repos/containerd/containerd/releases/latest | jq -r '.tag_name')
    CONTAINERD_VERSION=${CONTAINERD_VERSION#v}
    wget https://github.com/containerd/containerd/releases/download/v${CONTAINERD_VERSION}/containerd-${CONTAINERD_VERSION}-linux-${PLATFORM}.tar.gz
    sudo tar xvf containerd-${CONTAINERD_VERSION}-linux-${PLATFORM}.tar.gz -C /usr/local

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

    # Install runc
    RUNC_VERSION=$(curl -s https://api.github.com/repos/opencontainers/runc/releases/latest | jq -r '.tag_name')
    wget https://github.com/opencontainers/runc/releases/download/${RUNC_VERSION}/runc.${PLATFORM}
    sudo install -m 755 runc.${PLATFORM} /usr/local/sbin/runc

    # Setup containerd service
    wget https://raw.githubusercontent.com/containerd/containerd/main/containerd.service
    sudo mv containerd.service /usr/lib/systemd/system/
    sudo systemctl daemon-reload
    sudo systemctl enable --now containerd

fi

# Handle apparmor for runc
sudo ln -s /etc/apparmor.d/runc /etc/apparmor.d/disable/ 2>/dev/null || true
sudo apparmor_parser -R /etc/apparmor.d/runc 2>/dev/null || true

touch /tmp/container.txt

# Step 3: Install kubetools
echo "[Step 3] Installing kubetools..."

if [ $MYOS = "Ubuntu" ]; then

    # Load kernel module
    cat <<- EOF | sudo tee /etc/modules-load.d/k8s.conf
    br_netfilter
EOF

    # Detect latest Kubernetes version
    KUBEVERSION=$(curl -s https://api.github.com/repos/kubernetes/kubernetes/releases/latest | jq -r '.tag_name')
    KUBEVERSION=${KUBEVERSION%.*}

    echo "Installing Kubernetes version: ${KUBEVERSION}"

    sudo apt-get update && sudo apt-get install -y apt-transport-https curl
    curl -fsSL https://pkgs.k8s.io/core:/stable:/${KUBEVERSION}/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
    echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/${KUBEVERSION}/deb/ /" | sudo tee /etc/apt/sources.list.d/kubernetes.list

    sleep 2


    sudo apt-get update
    sudo apt-get install -y kubelet kubeadm kubectl
    sudo apt-mark hold kubelet kubeadm kubectl
    sudo swapoff -a
    sudo sed -i 's/\/swap/#\/swap/' /etc/fstab
   
    # Install crictl
    CRICTL_VERSION=$(curl -s https://api.github.com/repos/kubernetes-sigs/cri-tools/releases/latest | jq -r '.tag_name')
    CRICTL_VERSION=${CRICTL_VERSION#v}
    wget https://github.com/kubernetes-sigs/cri-tools/releases/download/v${CRICTL_VERSION}/crictl-v${CRICTL_VERSION}-linux-${PLATFORM}.tar.gz
    sudo tar zxvf crictl-v${CRICTL_VERSION}-linux-${PLATFORM}.tar.gz -C /usr/local/bin
    rm -f crictl-v${CRICTL_VERSION}-linux-${PLATFORM}.tar.gz

    # Configure crictl
    sudo crictl config --set runtime-endpoint=unix:///run/containerd/containerd.sock

fi

# Step 4: Configure kubelet with node IP
echo "[Step 4] Configuring kubelet..."
sudo tee /etc/default/kubelet > /dev/null << EOF
KUBELET_EXTRA_ARGS="--node-ip=${WORKER_IP}"
EOF

sudo systemctl daemon-reexec
sudo systemctl daemon-reload
sudo systemctl restart kubelet

# Step 5: Join the cluster
if [ -z "$JOIN_COMMAND" ]; then
    echo ""
    echo "=========================================="
    echo "Please provide the join command from the control plane"
    echo "=========================================="
    echo ""
    echo "Run on control plane to get the join command:"
    echo "  kubeadm token create --print-join-command"
    echo ""
    echo "Then run this script again with the join command:"
    echo "  sudo bash setup-worker-node.sh 192.168.56.11 '<join-command>'"
    echo ""
    exit 1
fi

echo "[Step 5] Joining the cluster..."
sudo bash -c "$JOIN_COMMAND"

# Step 6: Create kubeconfig directory and empty file with correct permissions
echo "[Step 6] Creating kubeconfig directory and file..."
mkdir -p $HOME/.kube
sudo touch $HOME/.kube/config
sudo chmod 600 $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

echo ""
echo "=========================================="
echo "Worker Node Setup Complete!"
echo "=========================================="
echo ""
echo "Now copy the kubeconfig from control plane:"
echo "  sudo cat $HOME/.kube/config  (on control plane)"
echo ""
echo "Then paste it into the worker node config file:"
echo "  sudo vi $HOME/.kube/config  (on this worker node)"
echo ""
echo "Waiting for node to be ready..."
sleep 10