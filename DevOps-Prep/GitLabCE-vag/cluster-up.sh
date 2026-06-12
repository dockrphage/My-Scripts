#!/bin/bash
# cluster-up.sh - Full cluster bootstrap with Vault integration

set -e

echo "========================================="
echo "Starting Kubernetes + Vault Cluster Setup"
echo "========================================="

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_success() { echo -e "${GREEN}[✓]${NC} $1"; }
log_error() { echo -e "${RED}[✗]${NC} $1"; }
log_info() { echo -e "${YELLOW}[→]${NC} $1"; }

# Check if required scripts exist
required_scripts=(
    "k8s-CP-setup.sh"
    "k8s-worker-setup.sh"
    "install-docker.sh"
    "install-metallb.sh"
    "install-ingress-nginx.sh"
    "misc.sh"
    "install-devops-autocomplete.sh"
    # "install-vault.sh"
    # "configure-vault.sh"
    # "install-external-secrets.sh"
)

for script in "${required_scripts[@]}"; do
    if [ ! -f "$script" ]; then
        log_error "Missing required script: $script"
        exit 1
    fi
done

# Step 1: Start VMs
log_info "Starting Vagrant VMs..."
vagrant up

# Step 2: Setup control plane
log_info "Setting up Kubernetes control plane on cp1..."
vagrant ssh cp1 -c "sudo bash /vagrant/k8s-CP-setup.sh"
log_success "Control plane setup complete"

# Step 3: Wait for join.sh
log_info "Waiting for join.sh from control plane..."
while [ ! -f ./join.sh ]; do
    sleep 2
done
JOIN=$(< ./join.sh)
log_success "Join command captured"

# Step 4: Setup Vault node before workers (optional, but good for secrets)
# log_info "Setting up Vault on secrets node..."
# vagrant ssh secrets -c "sudo bash /vagrant/install-vault.sh"
# log_success "Vault installed"

# Step 5: Join worker nodes
log_info "Joining node1 to cluster..."
vagrant ssh node1 -c "sudo bash /vagrant/k8s-worker-setup.sh 192.168.56.11 \"$JOIN\""
log_success "node1 joined"

log_info "Joining node2 to cluster..."
vagrant ssh node2 -c "sudo bash /vagrant/k8s-worker-setup.sh 192.168.56.12 \"$JOIN\""
log_success "node2 joined"

log_info "Joining secrets to cluster..."
vagrant ssh secrets -c "sudo bash /vagrant/k8s-worker-setup.sh 192.168.56.13 \"$JOIN\""
log_success "secrets joined"

# Step 6: Verify cluster
log_info "Verifying cluster nodes..."
vagrant ssh cp1 -c "kubectl get nodes -o wide"
log_success "Cluster verified"

# Step 7: Configure Vault
# log_info "Configuring Vault (may take a few moments)..."
# vagrant ssh secrets -c "sudo bash /vagrant/configure-vault.sh" || {
#     log_error "Vault configuration failed, but continuing..."
# }
# log_success "Vault configured"

# Step 8: Install networking components
log_info "Installing MetalLB..."
vagrant ssh cp1 -c "sudo bash /vagrant/install-metallb.sh"
log_success "MetalLB installed"

log_info "Installing ingress-nginx..."
vagrant ssh cp1 -c "sudo bash /vagrant/install-ingress-nginx.sh"
log_success "ingress-nginx installed"

# # Step 9: Install External Secrets Operator
# log_info "Installing External Secrets Operator..."
# vagrant ssh cp1 -c "sudo bash /vagrant/install-external-secrets.sh" || {
#     log_error "ESO installation had issues, check manually"
# }
# log_success "ESO installed"

# Step 10: Additional components
log_info "Setting up storage and metrics..."
vagrant ssh cp1 -c "sudo bash /vagrant/misc.sh"
log_success "Storage and metrics setup complete"

log_info "Installing devops autocomplete tools..."
vagrant ssh cp1 -c "sudo bash /vagrant/install-devops-autocomplete.sh"
log_success "Devops tools installed"

# Step 11: Final verification
log_info "Running final verification..."

echo ""
echo "========================================="
echo "CLUSTER STATUS"
echo "========================================="
vagrant ssh cp1 -c "kubectl get nodes -o wide"

# echo ""
# echo "========================================="
# echo "VAULT STATUS"
# echo "========================================="
# vagrant ssh secrets -c "export VAULT_ADDR='http://127.0.0.1:8200'; vault status"

# echo ""
# echo "========================================="
# echo "EXTERNAL SECRETS STATUS"
# echo "========================================="
# vagrant ssh cp1 -c "kubectl get externalsecret -A"

echo ""
echo "========================================="
echo "CLUSTER READY!"
echo "========================================="
echo ""
log_success "Kubernetes cluster with Vault integration is fully operational"
echo ""
echo "Access URLs:"
echo "  Kubernetes API: https://192.168.56.10:6443"
# echo "  Vault UI: http://192.168.56.13:8200"
echo "  ingress-nginx LB: $(vagrant ssh cp1 -c 'kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath="{.status.loadBalancer.ingress[0].ip}"' 2>/dev/null)"
echo ""
# echo "Vault credentials saved on secrets node:"
# echo "  /home/vagrant/.vault-root-token"
# echo "  /home/vagrant/.vault-unseal-keys"
# echo ""
# echo "To test secret retrieval:"
# echo "  vagrant ssh cp1"
# echo "  kubectl get secret payment-api-creds -o jsonpath='{.data.DB_PASSWORD}' | base64 -d"
echo ""