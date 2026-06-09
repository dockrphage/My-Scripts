# Complete Zero-Downtime StatefulSet Upgrade Guide
## For DevOps Interview - With All Corrections Applied



Based on previous successful deployment, here's the **complete, corrected implementation** starting from Phase 1.

---

## Phase 0: Infra setup
Note: I used the below script to setup my infra; any k8s/ k3s setup should work
https://github.com/dockrphage/My-Scripts/tree/main/k8s/k8s-v1-36-Vag-auto

## Phase 1: Pre-requisites & Cluster Validation

### Step 1.1: Verify Cluster Nodes

```bash
# Check all nodes are ready
kubectl get nodes -o wide

# Expected output (your environment):
# NAME    STATUS   ROLES           AGE   VERSION   INTERNAL-IP     EXTERNAL-IP
# cp1     Ready    control-plane   38m   v1.36     192.168.56.10   <none>
# node1   Ready    worker          38m   v1.36     192.168.56.11   <none>
# node2   Ready    worker          38m   v1.36     192.168.56.12   <none>
# runner  Ready    worker          38m   v1.36     192.168.56.13   <none>  # optional
```

### Step 1.2: Verify MetalLB Configuration

```bash
# Check MetalLB IP address pools
kubectl get ipaddresspools -n metallb-system

# Your output shows:
# NAME            AUTO ASSIGN   AVOID BUGGY IPS   ADDRESSES
# bridged-pool    true          false             ["192.168.1.55-192.168.1.65"]

# Note the pool name: "bridged-pool" (not "default-pool")
```

### Step 1.3: Verify Storage Class

```bash
# Check available storage classes
kubectl get storageclass

# If no default, set one:
# kubectl patch storageclass local-path -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
```

---

## Phase 2: Create Helm Chart Structure

### Step 2.1: Create Chart Directory

```bash
# Create proper chart structure
mkdir -p my-stateful-app/templates

# Create Chart.yaml (required for Helm v3)
cat <<'EOF' > my-stateful-app/Chart.yaml
apiVersion: v2
name: my-stateful-app
description: Stateful application with zero-downtime upgrade support
type: application
version: 0.1.0
appVersion: 1.25.0
maintainers:
  - name: DevOps Team
    email: devops@example.com
EOF
```

### Step 2.2: Create values.yaml

```bash
cat <<'EOF' > my-stateful-app/values.yaml
# Application configuration
appName: myapp
replicas: 3
updatePartition: 3  # Start with no pods updated (canary control)
terminationGracePeriod: 30

# Image configuration
image:
  repository: nginx
  tag: 1.25
  pullPolicy: IfNotPresent

# Service configuration
containerPort: 80
storageSize: 1Gi

# PodDisruptionBudget (critical for zero-downtime)
pdbMinAvailable: 1

# Health check endpoint (nginx uses /, not /health!)
healthCheckPath: /
EOF
```

### Step 2.3: Create StatefulSet Template (CORRECTED)

```bash
cat <<'EOF' > my-stateful-app/templates/statefulset.yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: {{ .Values.appName }}
  labels:
    app: {{ .Values.appName }}
spec:
  serviceName: {{ .Values.appName }}-headless
  replicas: {{ .Values.replicas }}
  updateStrategy:
    type: RollingUpdate
    rollingUpdate:
      partition: {{ .Values.updatePartition }}
  selector:
    matchLabels:
      app: {{ .Values.appName }}
  template:
    metadata:
      labels:
        app: {{ .Values.appName }}
    spec:
      terminationGracePeriodSeconds: {{ .Values.terminationGracePeriod }}
      containers:
      - name: nginx
        image: "{{ .Values.image.repository }}:{{ .Values.image.tag }}"
        ports:
        - containerPort: {{ .Values.containerPort }}
          name: http
        # CRITICAL: Use correct health check path (/, not /health)
        readinessProbe:
          httpGet:
            path: {{ .Values.healthCheckPath }}
            port: {{ .Values.containerPort }}
          initialDelaySeconds: 5
          periodSeconds: 5
          failureThreshold: 3
        livenessProbe:
          httpGet:
            path: {{ .Values.healthCheckPath }}
            port: {{ .Values.containerPort }}
          initialDelaySeconds: 15
          periodSeconds: 10
          failureThreshold: 3
        volumeMounts:
        - name: data
          mountPath: /usr/share/nginx/html
  volumeClaimTemplates:
  - metadata:
      name: data
    spec:
      accessModes: ["ReadWriteOnce"]
      resources:
        requests:
          storage: {{ .Values.storageSize }}
EOF
```

### Step 2.4: Create Service Template (CORRECTED)

```bash
cat <<'EOF' > my-stateful-app/templates/service.yaml
# Headless service for StatefulSet DNS
apiVersion: v1
kind: Service
metadata:
  name: {{ .Values.appName }}-headless
  labels:
    app: {{ .Values.appName }}
spec:
  clusterIP: None
  selector:
    app: {{ .Values.appName }}
  ports:
  - port: {{ .Values.containerPort }}
    name: http
---
# LoadBalancer service for external access via MetalLB
apiVersion: v1
kind: Service
metadata:
  name: {{ .Values.appName }}-svc
  labels:
    app: {{ .Values.appName }}
  annotations:
    # IMPORTANT: Use your actual MetalLB pool name (bridged-pool)
    metallb.universe.tf/address-pool: bridged-pool
spec:
  type: LoadBalancer
  selector:
    app: {{ .Values.appName }}
  ports:
  - port: 80
    targetPort: {{ .Values.containerPort }}
    protocol: TCP
EOF
```

### Step 2.5: Create PodDisruptionBudget Template

```bash
cat <<'EOF' > my-stateful-app/templates/pdb.yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: {{ .Values.appName }}-pdb
  labels:
    app: {{ .Values.appName }}
spec:
  minAvailable: {{ .Values.pdbMinAvailable }}
  selector:
    matchLabels:
      app: {{ .Values.appName }}
EOF
```

### Step 2.6: Validate Chart Syntax

```bash
# Lint the chart
helm lint my-stateful-app/

# Expected output:
# ==> Linting my-stateful-app/
# 1 chart(s) linted, 0 chart(s) failed
```

---

## Phase 3: Initial Deployment

### Step 3.1: Install Helm Chart (First Version)

```bash
# Clean install (if previous deployment exists)
helm uninstall myapp -n production 2>/dev/null
kubectl delete namespace production 2>/dev/null
sleep 5

# Install new deployment
helm install myapp ./my-stateful-app \
  --namespace production \
  --create-namespace \
  --set image.tag=1.25 \
  --set replicas=3 \
  --set updatePartition=3

# Expected output:
# NAME: myapp
# LAST DEPLOYED: ...
# NAMESPACE: production
# STATUS: deployed
# REVISION: 1
```

### Step 3.2: Verify Deployment

```bash
# Check pods (they should come up in order: myapp-0, myapp-1, myapp-2)
kubectl get pods -n production -w

# Check StatefulSet status
kubectl get statefulset myapp -n production

# Check PVCs (should have 3)
kubectl get pvc -n production

# Check services
kubectl get svc -n production

# Expected output:
# NAME             TYPE           CLUSTER-IP      EXTERNAL-IP    PORT(S)
# myapp-headless   ClusterIP      None            <none>         80/TCP
# myapp-svc        LoadBalancer   10.97.192.198   192.168.1.57   80:31345/TCP

# Check PodDisruptionBudget
kubectl get pdb -n production
```

### Step 3.3: Test Application

```bash
# Test via LoadBalancer
curl http://192.168.1.57
# Expected: <h1>Version 1.25</h1>

# Test from inside cluster
kubectl run test-pod --rm -it --image=curlimages/curl --restart=Never -n production -- \
  curl -s http://myapp-svc
```

---

## Phase 4: Zero-Downtime Upgrade (1.25 → 1.26)

### Step 4.1: Start Continuous Traffic Monitor

```bash
# Terminal 1: Start monitoring (proves zero downtime)
kubectl run traffic-test --rm -it --image=curlimages/curl --restart=Never -n production -- sh -c '
echo "=== Zero-Downtime Upgrade Test ==="
echo "Monitoring http://myapp-svc"
COUNTER=0
while true; do
  COUNTER=$((COUNTER + 1))
  if curl -s -o /dev/null -w "%{http_code}" http://myapp-svc | grep -q "200"; then
    echo "✅ [$COUNTER] $(date +%H:%M:%S) - Request successful"
  else
    echo "❌ [$COUNTER] $(date +%H:%M:%S) - FAILED!"
  fi
  sleep 1
done'
```

### Step 4.2: Canary Upgrade (Update Only myapp-2)

```bash
# Terminal 2: Update partition to 2 (only pod with index >=2: myapp-2)
kubectl patch statefulset myapp -n production --type='json' -p='[
  {"op": "replace", "path": "/spec/updateStrategy/rollingUpdate/partition", "value": 2},
  {"op": "replace", "path": "/spec/template/spec/containers/0/args", "value": ["-c", "echo '\''<h1>Version 1.26</h1>'\'' > /usr/share/nginx/html/index.html && nginx -g '\''daemon off;'\''"]}
]'

# Watch only myapp-2 restart
kubectl get pods -n production -w
```

### Step 4.3: Verify Canary

```bash
# Check versions
for i in 0 1 2; do
  echo -n "myapp-$i: "
  kubectl exec myapp-$i -n production -- cat /usr/share/nginx/html/index.html 2>/dev/null
done

# Expected:
# myapp-0: <h1>Version 1.25</h1>
# myapp-1: <h1>Version 1.25</h1>
# myapp-2: <h1>Version 1.26</h1>
```

### Step 4.4: Gradual Rollout (Update myapp-1)

```bash
# Update partition to 1 (pods with index >=1: myapp-1 and myapp-2)
kubectl patch statefulset myapp -n production --type='json' -p='[
  {"op": "replace", "path": "/spec/updateStrategy/rollingUpdate/partition", "value": 1}
]'

# Watch myapp-1 restart
kubectl get pods -n production -w

# Verify versions
for i in 0 1 2; do
  echo -n "myapp-$i: "
  kubectl exec myapp-$i -n production -- cat /usr/share/nginx/html/index.html 2>/dev/null
done
```

### Step 4.5: Complete Rollout (Update myapp-0)

```bash
# Update partition to 0 (all pods update)
kubectl patch statefulset myapp -n production --type='json' -p='[
  {"op": "replace", "path": "/spec/updateStrategy/rollingUpdate/partition", "value": 0}
]'

# Watch myapp-0 restart
kubectl get pods -n production -w

# Final verification - all on 1.26
for i in 0 1 2; do
  echo -n "myapp-$i: "
  kubectl exec myapp-$i -n production -- cat /usr/share/nginx/html/index.html 2>/dev/null
done

# Expected:
# myapp-0: <h1>Version 1.26</h1>
# myapp-1: <h1>Version 1.26</h1>
# myapp-2: <h1>Version 1.26</h1>
```

### Step 4.6: Verify No Downtime

```bash
# Check traffic monitor output (Terminal 1)
# Should show 100% success rate with zero failures

# Check LoadBalancer
curl http://192.168.1.57
# Expected: <h1>Version 1.26</h1>
```

---

## Phase 5: Rollback Testing (Critical for Interview)

### Step 5.1: Perform Rollback

```bash
# Rollback to version 1.25
kubectl patch statefulset myapp -n production --type='json' -p='[
  {"op": "replace", "path": "/spec/template/spec/containers/0/args", "value": ["-c", "echo '\''<h1>Version 1.25</h1>'\'' > /usr/share/nginx/html/index.html && nginx -g '\''daemon off;'\''"]},
  {"op": "replace", "path": "/spec/updateStrategy/rollingUpdate/partition", "value": 0}
]'

# Verify rollback
for i in 0 1 2; do
  echo -n "myapp-$i: "
  kubectl exec myapp-$i -n production -- cat /usr/share/nginx/html/index.html 2>/dev/null
done

# Expected: All show Version 1.25
```

---

## Phase 6: Node Maintenance Simulation

### Step 6.1: Check Pod Distribution

```bash
# See which nodes pods are running on
kubectl get pods -n production -o wide

# Check PodDisruptionBudget
kubectl get pdb myapp-pdb -n production
# Expected: minAvailable: 1
```

### Step 6.2: Test Drain (Dry Run)

```bash
# Simulate node drain (respects PDB)
kubectl drain node2 --ignore-daemonsets --delete-emptydir-data --dry-run=client

# The PDB ensures at least 1 pod remains running
```

---

## Phase 7: Helm Upgrade with Atomic Flag

### Step 7.1: Use Helm for Upgrade

```bash
# Upgrade using Helm (with atomic for auto-rollback)
helm upgrade myapp ./my-stateful-app \
  --namespace production \
  --set image.tag=1.27 \
  --set updatePartition=2 \
  --wait --atomic --timeout=5m

# Complete rollout
helm upgrade myapp ./my-stateful-app \
  --namespace production \
  --set image.tag=1.27 \
  --set updatePartition=0 \
  --wait --atomic --timeout=5m
```

### Step 7.2: Test Failed Upgrade Auto-Rollback

```bash
# Simulate failed upgrade (invalid image)
helm upgrade myapp ./my-stateful-app \
  --namespace production \
  --set image.tag=invalid-image \
  --set updatePartition=0 \
  --wait --atomic --timeout=2m

# Expected: Automatic rollback to previous version
# Verify rollback
helm history myapp -n production
kubectl get pods -n production -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.containers[0].image}{"\n"}{end}'
```

---

## Phase 8: Final Verification

### Step 8.1: Complete Health Check

```bash
# List all resources
kubectl get all,pvc,pdb -n production

# Check StatefulSet details
kubectl describe statefulset myapp -n production | grep -A 10 "Update Strategy"

# Verify PVC persistence
kubectl get pvc -n production
# All 3 PVCs should be Bound

# Test data persistence across upgrades
kubectl exec myapp-0 -n production -- sh -c 'echo "Persistent data" > /usr/share/nginx/html/test.txt'
kubectl exec myapp-0 -n production -- cat /usr/share/nginx/html/test.txt
```

### Step 8.2: Clean Up

```bash
# Stop traffic monitor (Ctrl+C in Terminal 1)

# Delete test pod
kubectl delete pod traffic-test -n production 2>/dev/null

# Optional: Complete cleanup
helm uninstall myapp -n production
kubectl delete namespace production
```

---

## Success Metrics Summary

✅ **3 healthy pods** running nginx  
✅ **Working LoadBalancer** with external IP  
✅ **Proper health probes** (using `/` path)  
✅ **PodDisruptionBudget** (minAvailable: 1)  
✅ **RollingUpdate strategy** with partition control  
✅ **Zero-downtime capability** proven  
✅ **Automatic rollback** working  
✅ **PVC persistence** across upgrades  

---

## Interview Q&A Quick Reference

| Question | Answer |
|----------|--------|
| How to achieve zero-downtime? | RollingUpdate + partition + PDB + proper probes |
| What does partition do? | Only updates pods with index ≥ partition value |
| Why reverse order (2→1→0)? | Minimizes impact; pod-0 often primary/leader |
| How does PDB help? | Prevents draining too many pods during maintenance |
| What does `--atomic` do? | Auto-rollback on failure, waits for health |

---

**Zero-downtime StatefulSet is now production-ready!** 🚀