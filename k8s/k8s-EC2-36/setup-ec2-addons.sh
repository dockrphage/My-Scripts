#!/bin/bash
# setup-ec2-addons.sh
# Run this on the control plane node after Kubernetes is running

set -e

GREEN="\e[32m"
YELLOW="\e[33m"
RED="\e[31m"
NC="\e[0m"

log() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }

log "=========================================="
log "Setting up EC2 Kubernetes Add-ons"
log "=========================================="

# 1. Install Local Path Provisioner
log "Installing Local Path Provisioner..."
if ! kubectl get storageclass local-path &>/dev/null; then
    kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/master/deploy/local-path-storage.yaml
    kubectl patch storageclass local-path -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
    log "Local Path Provisioner installed and set as default"
else
    warn "Local Path Provisioner already exists"
fi

# 2. Install Metrics Server
log "Installing Metrics Server..."
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

# Patch for self-signed certificates (lab environment)
kubectl patch deployment metrics-server -n kube-system \
    --type='json' \
    -p='[{"op": "add", "path": "/spec/template/spec/containers/0/args/-", "value": "--kubelet-insecure-tls"}]' 2>/dev/null || true

log "Metrics Server installed (with insecure TLS for lab)"

# 3. Install AWS Load Balancer Controller (for LoadBalancer services)
log "Installing AWS Load Balancer Controller..."
if ! kubectl get deployment -n kube-system aws-load-balancer-controller &>/dev/null; then
    # Add Helm repo
    helm repo add eks https://aws.github.io/eks-charts
    helm repo update
    
    # Get VPC ID (requires AWS CLI configured)
    VPC_ID=$(aws ec2 describe-vpcs --filters "Name=is-default,Values=true" --query 'Vpcs[0].VpcId' --output text 2>/dev/null || echo "")
    
    if [ -n "$VPC_ID" ]; then
        helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
            -n kube-system \
            --set clusterName=my-cluster \
            --set serviceAccount.create=true \
            --set region=$(curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone | sed 's/[a-z]$//')
        log "AWS Load Balancer Controller installed"
    else
        warn "AWS CLI not configured or no VPC found. Skipping AWS Load Balancer Controller."
        warn "You can still use NodePort services or install manually."
    fi
else
    warn "AWS Load Balancer Controller already exists"
fi

# 4. Install ingress-nginx (NodePort mode for EC2 without AWS LB Controller)
log "Installing ingress-nginx (NodePort mode)..."
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx 2>/dev/null || true
helm repo update

helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
    --namespace ingress-nginx \
    --create-namespace \
    --set controller.service.type=NodePort \
    --set controller.service.nodePorts.http=30080 \
    --set controller.service.nodePorts.https=30443 \
    --set controller.hostNetwork=false

log "Ingress-NGINX installed with NodePort (30080/30443)"

# 5. Install autocompletion (optional)
if [ -f "install-devops-autocomplete.sh" ]; then
    log "Installing DevOps autocompletion..."
    bash install-devops-autocomplete.sh
fi

# 6. Verify installations
log "=========================================="
log "Verifying installations..."
log "=========================================="

echo ""
echo "Storage Classes:"
kubectl get storageclass

echo ""
echo "Metrics Server:"
kubectl get pods -n kube-system | grep metrics-server

echo ""
echo "Ingress Controller:"
kubectl get svc -n ingress-nginx

echo ""
echo "AWS Load Balancer Controller (if installed):"
kubectl get pods -n kube-system | grep aws-load-balancer-controller || echo "Not installed"

echo ""
log "=========================================="
log "Add-ons setup complete!"
log "=========================================="
log ""
log "To test ingress, create a test service:"
log "  kubectl create deployment nginx --image=nginx"
log "  kubectl expose deployment nginx --port=80 --type=NodePort"
log "  kubectl create ingress nginx-ingress --rule=\"nginx.local/*=nginx:80\""
log ""
log "Access ingress via: http://<NODE_IP>:30080"
log "(Use any worker or control plane node's public/private IP)"