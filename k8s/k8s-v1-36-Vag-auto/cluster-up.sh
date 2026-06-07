#!/bin/bash
# cluster-up.sh
# Full cluster bootstrap: VMs → kubeadm → workers → MetalLB → ingress-nginx

set -e

echo "[1] Starting VMs..."
vagrant up

echo "[2] Running control plane setup..."
vagrant ssh cp1 -c "sudo bash /home/vagrant/k8s-CP-setup.sh"

echo "[3] Waiting for join.sh to appear..."
while [ ! -f ./join.sh ]; do
  echo "  join.sh not found yet... waiting..."
  sleep 2
done

echo "[4] Reading join command..."
JOIN=$(< ./join.sh)

echo "[5] Joining node1..."
vagrant ssh node1 -c "sudo bash /home/vagrant/k8s-worker-setup.sh 192.168.56.11 \"$JOIN\""

echo "[6] Joining node2..."
vagrant ssh node2 -c "sudo bash /home/vagrant/k8s-worker-setup.sh 192.168.56.12 \"$JOIN\""

echo "[7] Checking cluster status..."
vagrant ssh cp1 -c "kubectl get nodes -o wide"

echo "[8] Installing MetalLB..."
vagrant ssh cp1 -c "sudo bash /home/vagrant/install-metallb.sh"

echo "[9] Installing ingress-nginx..."
vagrant ssh cp1 -c "sudo bash /home/vagrant/install-ingress-nginx.sh"

echo "[10] Verifying ingress-nginx LoadBalancer..."
vagrant ssh cp1 -c "kubectl get svc -n ingress-nginx ingress-nginx-controller -o wide"

echo "Cluster fully ready: Control plane, workers, MetalLB, ingress-nginx."
