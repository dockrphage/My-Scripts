#!/usr/bin/env bash
set -euo pipefail

# ---------------------------------------------
# CONFIGURATION
# ---------------------------------------------
NAMESPACE="kube-system"
RELEASE="my-headlamp"
SERVICE_TYPE="${SERVICE_TYPE:-LoadBalancer}"   # LoadBalancer or NodePort
NODEPORT="${NODEPORT:-32000}"                  # Only used if SERVICE_TYPE=NodePort
LOADBALANCER_IP="${LOADBALANCER_IP:-}"         # Optional fixed MetalLB IP

# ---------------------------------------------
# FUNCTIONS
# ---------------------------------------------

header() {
  echo
  echo "============================================="
  echo "  Headlamp Installer"
  echo "============================================="
  echo
}

install_repo() {
  echo "[+] Adding official Headlamp Helm repo"
  helm repo add headlamp https://kubernetes-sigs.github.io/headlamp/ >/dev/null
  helm repo update >/dev/null
}

install_headlamp() {
  echo "[+] Installing Headlamp into namespace: $NAMESPACE"

  helm install "$RELEASE" headlamp/headlamp \
    --namespace "$NAMESPACE" \
    --create-namespace \
    --set service.type="$SERVICE_TYPE" \
    $( [[ "$SERVICE_TYPE" == "NodePort" ]] && echo "--set service.nodePort=$NODEPORT" ) \
    $( [[ -n "$LOADBALANCER_IP" ]] && echo "--set service.loadBalancerIP=$LOADBALANCER_IP" )
}

upgrade_headlamp() {
  echo "[+] Upgrading existing Headlamp release"
  helm upgrade "$RELEASE" headlamp/headlamp \
    --namespace "$NAMESPACE" \
    --set service.type="$SERVICE_TYPE" \
    $( [[ "$SERVICE_TYPE" == "NodePort" ]] && echo "--set service.nodePort=$NODEPORT" ) \
    $( [[ -n "$LOADBALANCER_IP" ]] && echo "--set service.loadBalancerIP=$LOADBALANCER_IP" )
}

get_service_info() {
  echo "[+] Fetching service details"
  kubectl get svc "$RELEASE" -n "$NAMESPACE"
}

get_token() {
  echo "[+] Generating login token"
  kubectl create token "$RELEASE" --namespace "$NAMESPACE"
}

print_access() {
  echo
  echo "============================================="
  echo "  Headlamp Access Information"
  echo "============================================="
  echo

  if [[ "$SERVICE_TYPE" == "LoadBalancer" ]]; then
    EXTERNAL_IP=$(kubectl get svc "$RELEASE" -n "$NAMESPACE" -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
    echo "URL: http://$EXTERNAL_IP"
  else
    NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
    echo "URL: http://$NODE_IP:$NODEPORT"
  fi

  echo
  echo "Token:"
  get_token
  echo
}

# ---------------------------------------------
# MAIN LOGIC
# ---------------------------------------------

header
install_repo

if helm status "$RELEASE" -n "$NAMESPACE" >/dev/null 2>&1; then
  upgrade_headlamp
else
  install_headlamp
fi

get_service_info
print_access

