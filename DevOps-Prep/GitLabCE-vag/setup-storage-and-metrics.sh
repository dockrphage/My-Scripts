#!/usr/bin/env bash
set -euo pipefail

# Colors for readability
GREEN="\e[32m"
RED="\e[31m"
YELLOW="\e[33m"
NC="\e[0m"

log() {
  echo -e "${GREEN}[INFO]${NC} $1"
}

warn() {
  echo -e "${YELLOW}[WARN]${NC} $1"
}

error() {
  echo -e "${RED}[ERROR]${NC} $1" >&2
}

# Ensure kubectl is available
if ! command -v kubectl &>/dev/null; then
  error "kubectl not found. Install kubectl first."
  exit 1
fi

# Ensure cluster is reachable
if ! kubectl version --short &>/dev/null; then
  error "Cannot reach Kubernetes cluster. Check kubeconfig."
  exit 1
fi

log "Cluster reachable."

###############################################
# 1. Install Local Path Provisioner
###############################################

if ! kubectl get storageclass local-path &>/dev/null; then
  log "Installing Rancher Local Path Provisioner..."
  if ! kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/master/deploy/local-path-storage.yaml; then
    error "Failed to install local-path-provisioner."
    exit 1
  fi
else
  warn "local-path StorageClass already exists. Skipping installation."
fi

# Patch as default
log "Setting local-path as default StorageClass..."
if ! kubectl patch storageclass local-path \
  -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}' &>/dev/null; then
  error "Failed to patch local-path as default StorageClass."
  exit 1
fi

# Verify
if kubectl get storageclass | grep -q "(default)"; then
  log "local-path is now the default StorageClass."
else
  warn "local-path is installed but NOT default. Check manually."
fi

###############################################
# 2. Install Metrics Server
###############################################

log "Installing metrics-server..."
if ! kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml; then
  error "Failed to install metrics-server."
  exit 1
fi

# Patch insecure TLS for lab clusters
log "Patching metrics-server to allow insecure TLS..."
if ! kubectl patch deployment metrics-server -n kube-system \
  --type='json' \
  -p='[{"op": "add", "path": "/spec/template/spec/containers/0/args/-", "value": "--kubelet-insecure-tls"}]' &>/dev/null; then
  warn "Patch may already exist or failed. Continuing."
fi

###############################################
# 3. Wait for metrics-server to be ready
###############################################

log "Waiting for metrics-server pod to become Ready..."

ATTEMPTS=20
SLEEP=5

for i in $(seq 1 $ATTEMPTS); do
  if kubectl get pods -n kube-system | grep metrics-server | grep -q "Running"; then
    log "metrics-server is running."
    break
  fi
  warn "metrics-server not ready yet... ($i/$ATTEMPTS)"
  sleep $SLEEP
done

if ! kubectl get pods -n kube-system | grep metrics-server | grep -q "Running"; then
  error "metrics-server failed to become ready."
  exit 1
fi

log "Setup complete!"
