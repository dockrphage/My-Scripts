#!/bin/bash
#
# MetalLB Installation & Configuration Script
# -------------------------------------------
# This script installs MetalLB (L2 mode), waits for readiness,
# configures an IPAddressPool + L2Advertisement, and deploys
# a test nginx LoadBalancer service.
#
# Designed for homelabs, VMs, and bridged‑interface setups.
#
# IMPORTANT:
#   - Update the interface name under L2Advertisement (default: enp0s9)
#   - Update the IP range to match your LAN
#   - Ensure the pool does NOT overlap with DHCP ranges
#

set -e

echo "=== [1/5] Installing MetalLB manifests ==="
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.13.10/config/manifests/metallb-native.yaml


echo "=== [2/5] Waiting for MetalLB pods to become Ready ==="
# Waits for all MetalLB pods to reach Ready condition
kubectl wait --namespace metallb-system \
  --for=condition=ready pod \
  --selector=app=metallb \
  --timeout=120s


echo "=== [3/5] Applying MetalLB IPAddressPool + L2Advertisement ==="
#
# NOTES:
# - IPAddressPool defines the range of IPs MetalLB can allocate.
# - L2Advertisement tells MetalLB which interface to broadcast ARP/NDP on.
# - The interface MUST match the bridged NIC inside your VM.
#   Run: ip a
#   Common names: enp0s8, enp0s9, eth1, eth2
#
cat << 'EOF' | kubectl apply -f -
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: bridged-pool
  namespace: metallb-system
spec:
  # Updated pool: 192.168.1.55–192.168.1.80
  # Ensure this range:
  #   - Is NOT used by DHCP
  #   - Does NOT overlap with node IPs
  addresses:
    - 192.168.1.55-192.168.1.80
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: bridged-adv
  namespace: metallb-system
spec:
  ipAddressPools:
    - bridged-pool
  interfaces:
    # CHANGE THIS to match your VM's bridged NIC
    - enp0s9
EOF


echo "=== [4/5] Deploying nginx test Pod + LoadBalancer Service ==="
#
# This creates:
#   - A simple nginx Pod
#   - A LoadBalancer Service that MetalLB will assign an IP to
#
cat << 'EOF' | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: nginx
  labels:
    app: nginx
spec:
  containers:
  - name: nginx
    image: nginx:latest
    ports:
    - containerPort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: nginx-svc
spec:
  type: LoadBalancer
  selector:
    app: nginx
  ports:
    - protocol: TCP
      port: 80
      targetPort: 80
EOF


echo "=== [5/5] Fetching nginx LoadBalancer service details ==="
kubectl get svc nginx-svc

echo "=== MetalLB installation complete ==="
echo "If the EXTERNAL-IP is <pending>, check:"
echo "  - Interface name in L2Advertisement"
echo "  - IP pool does not overlap with DHCP"
echo "  - metallb-system pods are Ready"

echo "=== [6/6] Verifying LoadBalancer IP functionality ==="

# Extract the assigned LoadBalancer IP
LB_IP=$(kubectl get svc nginx-svc -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

if [ -z "$LB_IP" ]; then
  echo "ERROR: No LoadBalancer IP assigned. MetalLB may not be advertising correctly."
  echo "Check:"
  echo "  - Interface name in L2Advertisement"
  echo "  - metallb-system pod logs"
  echo "  - IP pool overlaps with DHCP or node IPs"
  exit 1
fi

echo "LoadBalancer IP assigned: $LB_IP"

# Minimal internal connectivity test
echo "Testing internal connectivity with curl..."
if curl -s --max-time 3 http://$LB_IP | grep -qi 'nginx'; then
  echo "SUCCESS: nginx responded internally via LoadBalancer IP."
else
  echo "WARNING: Internal curl test failed."
  echo "This may indicate:"
  echo "  - Pod not ready"
  echo "  - Service misconfigured"
  echo "  - NetworkPolicy blocking traffic"
fi

echo
echo "=== External Test Required ==="
echo "Now test from your HOST machine (outside the VM):"
echo "  curl http://$LB_IP"
echo
echo "If the host cannot reach it, MetalLB is NOT advertising on the correct interface."


