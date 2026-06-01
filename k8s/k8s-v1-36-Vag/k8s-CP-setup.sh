#!/bin/bash
# setup-control-plane.sh
# Run this script on the control plane node (192.168.56.10)

set -e

CONTROL_PLANE_IP="192.168.56.10"
POD_NETWORK_CIDR="192.168.0.0/16"

# Detect platform
[ $(arch) = aarch64 ] && PLATFORM=arm64
[ $(arch) = x86_64 ] && PLATFORM=amd64

# Detect OS
MYOS=$(hostnamectl | awk '/Operating/ { print $3 }')
OSVERSION=$(hostnamectl | awk '/Operating/ { print $4 }')

echo "=========================================="
echo "Setting up Kubernetes Control Plane"
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
KUBELET_EXTRA_ARGS="--node-ip=${CONTROL_PLANE_IP}"
EOF

sudo systemctl daemon-reexec
sudo systemctl daemon-reload
sudo systemctl restart kubelet

# Step 5: Initialize kubeadm
echo "[Step 5] Initializing kubeadm..."
sudo kubeadm init \
  --apiserver-advertise-address=${CONTROL_PLANE_IP} \
  --pod-network-cidr=${POD_NETWORK_CIDR}

# Step 6: Setup kubeconfig
echo "[Step 6] Setting up kubeconfig..."
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

# Step 7: Install Calico CNI
echo "[Step 7] Installing Calico network plugin..."
kubectl apply -f https://docs.projectcalico.org/manifests/calico.yaml

# Step 8: Install Helm
echo "[Step 8] Installing Helm..."

ARCH=$(uname -m)
case "$ARCH" in
  x86_64) PLATFORM="amd64" ;;
  aarch64) PLATFORM="arm64" ;;
  *) echo "Unsupported architecture: $ARCH"; exit 1 ;;
esac

HELM_VERSION=$(curl -s https://api.github.com/repos/helm/helm/releases/latest | jq -r '.tag_name')

wget https://get.helm.sh/helm-${HELM_VERSION}-linux-${PLATFORM}.tar.gz
tar -zxvf helm-${HELM_VERSION}-linux-${PLATFORM}.tar.gz
sudo mv linux-${PLATFORM}/helm /usr/local/bin/helm

rm -rf linux-${PLATFORM} helm-${HELM_VERSION}-linux-${PLATFORM}.tar.gz

helm version


# Step 9: Install MetalLB
echo "[Step 9] Installing MetalLB..."

# # Install MetalLB components
# kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.14.5/config/manifests/metallb-native.yaml

# # Wait for MetalLB pods to be ready
# echo "Waiting for MetalLB controller to become ready..."
# kubectl wait --namespace metallb-system \
#   --for=condition=available deployment/controller \
#   --timeout=120s

# # Create MetalLB address pool
# cat <<EOF | kubectl apply -f -
# apiVersion: metallb.io/v1beta1
# kind: IPAddressPool
# metadata:
#   name: default-pool
#   namespace: metallb-system
# spec:
#   addresses:
#   - 192.168.56.240-192.168.56.250
# ---
# apiVersion: metallb.io/v1beta1
# kind: L2Advertisement
# metadata:
#   name: default-l2
#   namespace: metallb-system
# spec:
#   ipAddressPools:
#   - default-pool
# EOF

# # apply enable strict ARP mode, returns nonzero returncode on errors only
# kubectl get configmap kube-proxy -n kube-system -o yaml | \
# sed -e "s/strictARP: false/strictARP: true/" | \
# kubectl apply -f - -n kube-system


echo ""
echo "=========================================="
echo "Control Plane Setup Complete!"
echo "=========================================="
echo ""
echo "Run the following on your worker node(s):"
echo ""
kubeadm token create --print-join-command
echo ""