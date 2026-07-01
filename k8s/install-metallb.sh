#!/bin/bash
set -e

echo "[1] Detecting bridged network interface..."

# Detect the interface used for the default route (LAN)
echo "[1] Detecting bridged network interface..."

# Detect interface with LAN IP (192.168.1.x)
BR_IF=$(ip -o -4 addr show | awk '/192\.168\.1\./ {print $2}' | head -n1)

if [ -z "$BR_IF" ]; then
  echo "ERROR: Could not detect bridged interface."
  ip -o -4 addr show
  exit 1
fi

echo "Detected bridged interface: $BR_IF"


echo "[2] Installing MetalLB CRDs + Controllers..."
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.16.1/config/manifests/metallb-frr-k8s.yaml

echo "[3] Waiting for MetalLB pods to become ready..."
kubectl wait --namespace metallb-system \
  --for=condition=ready pod \
  --selector=component=controller \
  --timeout=90s

kubectl wait --namespace metallb-system \
  --for=condition=ready pod \
  --selector=component=speaker \
  --timeout=90s

echo "[4] Applying L2 IPAddressPool + L2Advertisement..."
cat <<EOF | kubectl apply -f -
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: bridged-pool
  namespace: metallb-system
spec:
  addresses:
    - 192.168.1.55-192.168.1.65
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
    - $BR_IF
EOF

echo "[5] Deploying test nginx pod + LoadBalancer service..."
cat <<EOF | kubectl apply -f -
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

echo "[6] Waiting for LoadBalancer IP..."
sleep 3
kubectl get svc nginx-svc

echo "MetalLB installation complete."
echo "Using interface: $BR_IF"
echo "You should see an external IP in the range 192.168.1.55-192.168.1.65"