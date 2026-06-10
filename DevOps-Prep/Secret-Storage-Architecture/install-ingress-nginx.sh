#!/bin/bash
# install-ingress-nginx.sh
# This script installs the ingress-nginx controller using Helm and configures it to work with MetalLB. Run this script on the control plane node after installing MetalLB.
set -e

echo "[1] Detecting bridged network interface..."

# Detect the interface used for the default route (LAN)
BR_IF=$(ip route | awk '/default/ {print $5}' | head -n1)

if [ -z "$BR_IF" ]; then
  echo "ERROR: Could not detect bridged interface."
  ip route
  exit 1
fi

echo "Detected bridged interface: $BR_IF"

echo "[2] Adding ingress-nginx Helm repo..."
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update

echo "[3] Installing ingress-nginx with MetalLB LoadBalancer..."
helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --create-namespace \
  --set controller.service.type=LoadBalancer \
  --set controller.service.externalTrafficPolicy=Local \
  --set controller.service.annotations."metallb\.universe\.tf/address-pool"="bridged-pool" \
  --set controller.service.annotations."metallb\.universe\.tf/allow-shared-ip"="ingress" \
  --set controller.hostNetwork=false

echo "[4] Waiting for ingress-nginx controller pod to be ready..."
kubectl wait --namespace ingress-nginx \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=120s

echo "[5] Checking LoadBalancer IP assigned by MetalLB..."
sleep 3
kubectl get svc -n ingress-nginx ingress-nginx-controller

echo "Ingress-NGINX installation complete."
echo "Using interface: $BR_IF"
