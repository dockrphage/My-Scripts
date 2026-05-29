Excellent! You have a successful upgrade record. Let me provide you with **production-grade upgrade notes** tailored for your EC2 environment, incorporating DevOps interview perspectives (rollback strategies, health checks, and failure handling).

# 📋 Kubernetes Upgrade Guide: v1.33 → v1.35.3 (EC2 Production Practice)

## 🎯 DevOps Interview Talking Points

Before starting, understand these key concepts:
- **Why upgrade?** Security patches, API deprecations, new features
- **Upgrade strategy?** Rolling upgrade - control plane first, then workers
- **Rollback plan?** `kubeadm upgrade apply --force` to revert
- **Risk mitigation?** PodDisruptionBudgets, multiple replicas, drain cordon

---

## Phase 0: Pre-Upgrade Assessment (15 minutes)

### 0.1 Verify Current State
```bash
# Take a snapshot of current cluster state
kubectl get nodes -o wide > pre-upgrade-nodes.txt
kubectl get pods --all-namespaces > pre-upgrade-pods.txt
kubectl get deployments --all-namespaces > pre-upgrade-deployments.txt
kubectl get pv,pvc --all-namespaces > pre-upgrade-storage.txt

# Check API versions being used (critical for deprecated APIs)
kubectl get apiservice | grep -v "True"

# Backup critical manifests (if any)
kubectl get all --all-namespaces -o yaml > cluster-backup-$(date +%Y%m%d).yaml

# Verify cluster health
kubectl get cs  # Component status
kubectl top nodes  # Resource usage
```

### 0.2 Check Upgrade Compatibility
```bash
# Generate upgrade plan
sudo kubeadm upgrade plan

# Check version skew policy (max 2 minor versions)
kubectl version --short

# Verify container runtime compatibility
containerd --version
```

### 0.3 Prepare Rollback Strategy
```bash
# Save current kubeadm config
sudo kubeadm config view > kubeadm-config-$(date +%Y%m%d).yaml

# Backup etcd (critical for production)
sudo ETCDCTL_API=3 etcdctl snapshot save snapshot-$(date +%Y%m%d).db \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key
```

---

## Phase 1: Repository Setup (Both Nodes - 5 minutes)

### 1.1 Add Required Kubernetes Repositories

```bash
# Create a shared script (run on both cp1 and w1)
cat << 'EOF' | sudo bash
# Add v1.34 repository (intermediate version)
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.34/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-1.34-apt-keyring.gpg
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-1.34-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.34/deb/ /" | sudo tee /etc/apt/sources.list.d/kubernetes-1.34.list

# Add v1.35 repository (target version)
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.35/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-1.35-apt-keyring.gpg
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-1.35-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.35/deb/ /" | sudo tee /etc/apt/sources.list.d/kubernetes-1.35.list

# Update package list
sudo apt-get update

# Verify versions available
echo "Available kubeadm versions:"
apt-cache madison kubeadm | grep -E "1.34|1.35" | head -5
EOF
```

### 1.2 Unhold Packages (Both Nodes)
```bash
# Allow version upgrades
sudo apt-mark unhold kubeadm kubelet kubectl

# Verify they're unheld
apt-mark showhold  # Should show nothing
```

---

## Phase 2: Control Plane Upgrade (cp1 - 20 minutes)

### 2.1 Upgrade to v1.34.3 (Intermediate)

```bash
# ---- On cp1 node ----

# Step 1: Upgrade kubeadm first
echo "=== Upgrading kubeadm to v1.34.3 ==="
sudo apt-get install -y kubeadm=1.34.3-1.1
kubeadm version

# Step 2: Verify upgrade plan
sudo kubeadm upgrade plan

# Step 3: Apply control plane upgrade to v1.34
echo "=== Applying control plane upgrade to v1.34.3 ==="
sudo kubeadm upgrade apply v1.34.3 --yes

# Step 4: Upgrade kubelet and kubectl
sudo apt-get install -y kubelet=1.34.3-1.1 kubectl=1.34.3-1.1

# Step 5: Restart kubelet
sudo systemctl daemon-reload
sudo systemctl restart kubelet

# Step 6: Verify node is ready
kubectl get nodes -o wide

# Step 7: Check control plane pods
kubectl get pods -n kube-system
```

### 2.2 Upgrade to v1.35.3 (Target)

```bash
# ---- On cp1 node (continue) ----

# Step 1: Upgrade kubeadm to v1.35
echo "=== Upgrading kubeadm to v1.35.3 ==="
sudo apt-get install -y kubeadm=1.35.3-1.1

# Step 2: Verify upgrade plan again
sudo kubeadm upgrade plan

# Step 3: Apply final control plane upgrade
echo "=== Applying control plane upgrade to v1.35.3 ==="
sudo kubeadm upgrade apply v1.35.3 --yes

# Step 4: Upgrade kubelet and kubectl
sudo apt-get install -y kubelet=1.35.3-1.1 kubectl=1.35.3-1.1

# Step 5: Restart kubelet
sudo systemctl restart kubelet

# Step 6: Verify control plane
kubectl get nodes -o wide
kubectl version

# Step 7: Re-hold packages
sudo apt-mark hold kubeadm kubelet kubectl
```

### 2.3 Control Plane Verification
```bash
# ---- Verification commands ----

# Check control plane component health
kubectl get componentstatuses

# Check all system pods
kubectl get pods -n kube-system -o wide

# Verify API server is responsive
kubectl cluster-info

# Test API version
kubectl api-versions | grep -E "v1.34|v1.35"
```

---

## Phase 3: Worker Node Upgrade (w1 - 15 minutes)

### 3.1 Drain Worker Node
```bash
# ---- On cp1 (or from your workstation) ----

# Mark node as unschedulable and drain pods
kubectl drain w1 --ignore-daemonsets --delete-emptydir-data

# Verify node is drained
kubectl get nodes
# Should show: SchedulingDisabled status
```

### 3.2 Upgrade Worker to v1.34.3
```bash
# ---- On w1 node ----

# Unhold packages
sudo apt-mark unhold kubeadm kubelet kubectl

# Upgrade kubeadm to v1.34
sudo apt-get install -y kubeadm=1.34.3-1.1

# Upgrade the node
sudo kubeadm upgrade node

# Upgrade kubelet and kubectl
sudo apt-get install -y kubelet=1.34.3-1.1 kubectl=1.34.3-1.1

# Restart kubelet
sudo systemctl restart kubelet
```

### 3.3 Upgrade Worker to v1.35.3
```bash
# ---- On w1 node (continue) ----

# Upgrade kubeadm to v1.35
sudo apt-get install -y kubeadm=1.35.3-1.1

# Upgrade the node again
sudo kubeadm upgrade node

# Upgrade kubelet and kubectl
sudo apt-get install -y kubelet=1.35.3-1.1 kubectl=1.35.3-1.1

# Restart kubelet
sudo systemctl restart kubelet

# Re-hold packages
sudo apt-mark hold kubeadm kubelet kubectl
```

### 3.4 Uncordon Worker Node
```bash
# ---- On cp1 ----

# Bring node back into service
kubectl uncordon w1

# Verify node is ready
kubectl get nodes -o wide
kubectl describe node w1 | grep -A 5 Conditions
```

---

## Phase 4: Post-Upgrade Validation (10 minutes)

### 4.1 Cluster Health Check
```bash
# Create validation script
cat << 'EOF' > validate-upgrade.sh
#!/bin/bash
echo "=== CLUSTER VALIDATION ==="
echo "1. Node Status:"
kubectl get nodes -o wide

echo -e "\n2. Component Status:"
kubectl get cs

echo -e "\n3. System Pods:"
kubectl get pods -n kube-system

echo -e "\n4. All Namespaces Pods:"
kubectl get pods --all-namespaces | grep -v Running

echo -e "\n5. API Versions:"
kubectl version --short

echo -e "\n6. Node Conditions:"
for node in $(kubectl get nodes -o name); do
  echo "--- $node ---"
  kubectl get $node -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}'
  echo ""
done

echo -e "\n7. Pod Distribution:"
kubectl get pods --all-namespaces -o wide | grep -v Running
EOF

chmod +x validate-upgrade.sh
./validate-upgrade.sh
```

### 4.2 Application Functionality Test
```bash
# Deploy test application
kubectl create deployment test-nginx --image=nginx:latest --replicas=2
kubectl expose deployment test-nginx --port=80 --type=ClusterIP

# Wait for pods to be ready
kubectl wait --for=condition=ready pod -l app=test-nginx --timeout=60s

# Test connectivity
kubectl run test-pod --rm -it --image=busybox --restart=Never -- wget -qO- http://test-nginx

# Clean up
kubectl delete deployment test-nginx
kubectl delete service test-nginx
```

### 4.3 Final Verification Commands
```bash
# Capture post-upgrade state
kubectl get nodes -o wide > post-upgrade-nodes.txt
kubectl get pods --all-namespaces > post-upgrade-pods.txt
kubectl version --short > post-upgrade-version.txt

# Compare pre and post upgrade
diff pre-upgrade-pods.txt post-upgrade-pods.txt
```

---

## 📊 DevOps Interview Q&A - Upgrade Scenarios

### Q1: What if the upgrade fails mid-way?

**A - Rollback Procedure:**
```bash
# Rollback control plane to previous version
sudo kubeadm upgrade apply v1.33.0 --force

# Rollback worker node
sudo apt-get install -y kubeadm=1.33.0-1.1 kubelet=1.33.0-1.1
sudo kubeadm upgrade node
sudo systemctl restart kubelet
```

### Q2: How do you ensure zero downtime?

**A - Multi-worker strategy:**
1. Have at least 3 worker nodes
2. Set PodDisruptionBudgets for critical apps
3. Use multiple replicas (min 2 per deployment)
4. Upgrade workers one by one
5. Use topology spread constraints

### Q3: What about application compatibility?

**A - API version check:**
```bash
# Check deprecated APIs in your cluster
kubectl get --raw /metrics | grep apiserver_requested_deprecated_apis

# Use kube-no-trouble tool
kubectl krew install deprecations
kubectl deprecations
```

### Q4: How to test upgrade in CI/CD?

**A - Staged approach:**
1. Non-production cluster first
2. Canary worker node upgrade
3. % rollout (upgrade 10% workers)
4. Full production rollout
5. Automated health checks between steps

---

## 🚨 Troubleshooting Common Issues

| Issue | Solution |
|-------|----------|
| `kubeadm upgrade plan` shows old version | Upgrade kubeadm first: `sudo apt-get install kubeadm=1.34.3-1.1` |
| Node stuck in NotReady | Check kubelet logs: `journalctl -u kubelet -f` |
| Pods stuck in Terminating | Force delete: `kubectl delete pod <name> --grace-period=0 --force` |
| Calico pods not running | Check Calico version compatibility with Kubernetes version |
| API server not responding | Check certificates: `sudo kubeadm certs renew all` |
| DNS resolution failing | Restart CoreDNS: `kubectl rollout restart deployment/coredns -n kube-system` |

---

## 📝 Automation Scripts

### Master Upgrade Automation Script
```bash
#!/bin/bash
# upgrade-master.sh - Run on cp1

set -e

echo "🚀 Starting Control Plane Upgrade v1.33 → v1.35.3"

# Unhold packages
sudo apt-mark unhold kubeadm kubelet kubectl

# Add repositories
for v in 1.34 1.35; do
  curl -fsSL https://pkgs.k8s.io/core:/stable:/v${v}/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-${v}-apt-keyring.gpg
  echo "deb [signed-by=/etc/apt/keyrings/kubernetes-${v}-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v${v}/deb/ /" | sudo tee /etc/apt/sources.list.d/kubernetes-${v}.list
done
sudo apt-get update

# Upgrade to 1.34
echo "📦 Upgrading to v1.34.3"
sudo apt-get install -y kubeadm=1.34.3-1.1
sudo kubeadm upgrade apply v1.34.3 -y
sudo apt-get install -y kubelet=1.34.3-1.1 kubectl=1.34.3-1.1
sudo systemctl restart kubelet

# Verify 1.34
kubectl get nodes

# Upgrade to 1.35
echo "📦 Upgrading to v1.35.3"
sudo apt-get install -y kubeadm=1.35.3-1.1
sudo kubeadm upgrade apply v1.35.3 -y
sudo apt-get install -y kubelet=1.35.3-1.1 kubectl=1.35.3-1.1
sudo systemctl restart kubelet

# Re-hold packages
sudo apt-mark hold kubeadm kubelet kubectl

echo "✅ Control plane upgrade complete!"
kubectl get nodes -o wide
```

### Worker Upgrade Automation Script
```bash
#!/bin/bash
# upgrade-worker.sh - Run on worker node

NODE_NAME=$(hostname)

echo "🚀 Upgrading worker node: $NODE_NAME"

# Unhold packages
sudo apt-mark unhold kubeadm kubelet kubectl

# Add repositories (if not already done)
for v in 1.34 1.35; do
  curl -fsSL https://pkgs.k8s.io/core:/stable:/v${v}/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-${v}-apt-keyring.gpg
  echo "deb [signed-by=/etc/apt/keyrings/kubernetes-${v}-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v${v}/deb/ /" | sudo tee /etc/apt/sources.list.d/kubernetes-${v}.list
done
sudo apt-get update

# Upgrade to 1.34
sudo apt-get install -y kubeadm=1.34.3-1.1
sudo kubeadm upgrade node
sudo apt-get install -y kubelet=1.34.3-1.1 kubectl=1.34.3-1.1
sudo systemctl restart kubelet

# Upgrade to 1.35
sudo apt-get install -y kubeadm=1.35.3-1.1
sudo kubeadm upgrade node
sudo apt-get install -y kubelet=1.35.3-1.1 kubectl=1.35.3-1.1
sudo systemctl restart kubelet

# Re-hold packages
sudo apt-mark hold kubeadm kubelet kubectl

echo "✅ Worker $NODE_NAME upgrade complete!"
```

---

## ✅ Success Criteria Checklist

- [ ] All nodes show `Ready` status with v1.35.3
- [ ] CoreDNS pods are running
- [ ] Calico CNI pods are healthy
- [ ] Existing deployments continue to work
- [ ] New deployments can be created
- [ ] kubectl version shows v1.35.3
- [ ] No pod restarts due to upgrade
- [ ] API server is responsive
- [ ] etcd cluster is healthy
- [ ] Backup is verified (if taken)

---

## 🎯 Key DevOps Takeaways for Interview

1. **Always test in non-production first**
2. **Have a rollback plan** - snapshot etcd, backup manifests
3. **Monitor during upgrade** - use `kubectl get nodes -w` in separate terminal
4. **Upgrade incrementally** - don't skip minor versions (1.33→1.34→1.35)
5. **Check API deprecations** before upgrading
6. **Use PodDisruptionBudgets** for critical workloads
7. **Verify CNI compatibility** - Calico version must support k8s version
8. **Document everything** - commands, timing, issues encountered

Your cluster is now ready for the upgrade! 🚀
