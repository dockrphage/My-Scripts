# DevOps Troubleshooting Lab - Complete Runbook

## Table of Contents
1. [Prerequisites](#prerequisites)
2. [General Commands](#general-commands)
3. [Scenario 1: Memory Leak (OOMKilled)](#scenario-1-memory-leak-oomkilled)
4. [Scenario 2: Disk Space Exhaustion](#scenario-2-disk-space-exhaustion)
5. [Scenario 3: CrashLoopBackOff](#scenario-3-crashloopbackoff)
6. [Scenario 4: CPU Resource Exhaustion](#scenario-4-cpu-resource-exhaustion)
7. [Scenario 5: Database Connectivity](#scenario-5-database-connectivity)
8. [Scenario 6: Network Policy Issues](#scenario-6-network-policy-issues)
9. [Lab Management](#lab-management)
10. [Complete Cleanup](#complete-cleanup)

---

## Prerequisites

```bash
# Ensure you're in the right context
kubectl config current-context
kubectl get nodes

# Set namespace alias for convenience
alias kl='kubectl -n lab-scenarios'
```

---

## General Commands

### Quick Status Checks
```bash
# View all resources
kubectl get all -n lab-scenarios

# View pods with details
kubectl get pods -n lab-scenarios -o wide

# Check resource usage
kubectl top pods -n lab-scenarios

# Check events
kubectl get events -n lab-scenarios --sort-by='.lastTimestamp'

# Check resource quota
kubectl describe resourcequota lab-quota -n lab-scenarios

# Watch pods in real-time
watch -n 2 'kubectl get pods -n lab-scenarios'
```

### Debugging Tools
```bash
# Generic pod debugging
debug_pod() {
    local pod=$1
    echo "=== Debugging Pod: $pod ==="
    echo "--- Status ---"
    kubectl get pod $pod -n lab-scenarios
    echo "--- Description ---"
    kubectl describe pod $pod -n lab-scenarios
    echo "--- Logs ---"
    kubectl logs $pod -n lab-scenarios --tail=50
    echo "--- Previous Logs (if any) ---"
    kubectl logs $pod -n lab-scenarios --previous --tail=20 2>/dev/null || echo "No previous logs"
}

# Use: debug_pod <pod-name>
```

---

## Scenario 1: Memory Leak (OOMKilled)

### Symptoms
- Pod status: `OOMKilled` or `CrashLoopBackOff`
- Events show: `Container killed due to memory limit`
- Pod restarts frequently

### Troubleshooting Steps

```bash
# Step 1: Identify affected pods
kubectl get pods -n lab-scenarios | grep -E "(OOMKilled|memory-leak)"

# Step 2: Check pod details
kubectl describe pod <memory-leak-pod> -n lab-scenarios

# Step 3: Check memory usage
kubectl top pods -n lab-scenarios | grep memory-leak

# Step 4: View logs before crash
kubectl logs <memory-leak-pod> -n lab-scenarios --previous

# Step 5: Check memory limits
kubectl get deployment memory-leak-app -n lab-scenarios -o yaml | grep -A 5 resources
```

### Fix Solutions

#### Solution A: Increase Memory Limits
```bash
# Increase memory limit
kubectl patch deployment memory-leak-app -n lab-scenarios --type='json' -p='[
  {"op": "replace", "path": "/spec/template/spec/containers/0/resources/limits/memory", "value": "512Mi"},
  {"op": "replace", "path": "/spec/template/spec/containers/0/resources/requests/memory", "value": "256Mi"}
]'

# Restart deployment
kubectl rollout restart deployment memory-leak-app -n lab-scenarios
```

#### Solution B: Fix the Application Code
```bash
# Deploy fixed version with slower memory leak
kubectl apply -n lab-scenarios -f - <<YAML
apiVersion: apps/v1
kind: Deployment
metadata:
  name: memory-leak-app
  labels:
    scenario: memory-leak
spec:
  replicas: 1
  selector:
    matchLabels:
      app: memory-leak
  template:
    metadata:
      labels:
        app: memory-leak
        scenario: memory-leak
    spec:
      containers:
      - name: leaky-app
        image: python:3.9-slim
        command: ["python", "-c"]
        args:
          - |
            import time, sys
            data = []
            counter = 0
            print("Starting controlled memory leak...")
            while True:
                # Leak 100KB per iteration (slower)
                data.append('x' * (100 * 1024))
                counter += 1
                if counter % 100 == 0:
                    mem_mb = len(data) * 100 / 1024
                    print(f"Memory allocated: {mem_mb:.1f}MB")
                    sys.stdout.flush()
                time.sleep(0.1)
        resources:
          limits:
            memory: "512Mi"
          requests:
            memory: "256Mi"
        env:
        - name: PYTHONUNBUFFERED
          value: "1"
YAML
```

### Reset Scenario
```bash
# Reset to initial broken state
kubectl delete deployment memory-leak-app -n lab-scenarios
kubectl apply -n lab-scenarios -f - <<YAML
apiVersion: apps/v1
kind: Deployment
metadata:
  name: memory-leak-app
  labels:
    scenario: memory-leak
spec:
  replicas: 2
  selector:
    matchLabels:
      app: memory-leak
  template:
    metadata:
      labels:
        app: memory-leak
    spec:
      containers:
      - name: leaky-app
        image: python:3.9-slim
        command: ["python", "-c"]
        args:
          - |
            import time
            data = []
            while True:
                data.append('x' * (1024 * 1024))
                time.sleep(0.1)
        resources:
          limits:
            memory: "128Mi"
          requests:
            memory: "64Mi"
YAML
```

---

## Scenario 2: Disk Space Exhaustion

### Symptoms
- Node status shows `DiskPressure`
- Pods fail to schedule
- `/var/log` filling up
- DaemonSet pods showing disk full errors

### Troubleshooting Steps

```bash
# Step 1: Check node disk pressure
kubectl describe nodes | grep -A 5 "Conditions:" | grep DiskPressure

# Step 2: Find disk filler pods
kubectl get pods -n lab-scenarios | grep disk-filler

# Step 3: Check disk usage on nodes
kubectl get nodes -o wide
# SSH to node and check: df -h

# Step 4: Check disk usage in pods
kubectl exec -it <disk-filler-pod> -n lab-scenarios -- df -h

# Step 5: Find large files
kubectl exec -it <disk-filler-pod> -n lab-scenarios -- du -sh /* 2>/dev/null | sort -h
```

### Fix Solutions

#### Solution A: Remove Disk Filler DaemonSet
```bash
# Delete the disk filler
kubectl delete daemonset disk-filler -n lab-scenarios

# Clean up large files
kubectl exec -it <disk-filler-pod> -n lab-scenarios -- rm -rf /tmp/bigfile 2>/dev/null
```

#### Solution B: Limit Disk Usage
```bash
# Deploy disk filler with smaller files
kubectl apply -n lab-scenarios -f - <<YAML
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: disk-filler
  labels:
    scenario: disk-usage
spec:
  selector:
    matchLabels:
      app: disk-filler
  template:
    metadata:
      labels:
        app: disk-filler
    spec:
      containers:
      - name: filler
        image: busybox
        command: ["/bin/sh", "-c"]
        args:
          - |
            while true; do
              # Create 50MB file instead of 200MB
              dd if=/dev/zero of=/tmp/bigfile bs=1M count=50
              sleep 300
              rm /tmp/bigfile
              sleep 60
            done
        volumeMounts:
        - name: host-root
          mountPath: /host
      volumes:
      - name: host-root
        hostPath:
          path: /var/log
YAML
```

#### Solution C: Add Disk Pressure Monitoring
```bash
cat <<'EOF' | kubectl apply -n lab-scenarios -f -
apiVersion: v1
kind: Pod
metadata:
  name: disk-monitor
spec:
  containers:
  - name: monitor
    image: busybox
    command: ["/bin/sh", "-c"]
    args:
      - |
        while true; do
          echo "=== Disk Usage Report \$(date) ==="
          df -h /host
          echo "Top 10 large files:"
          find /host -type f -size +10M -exec ls -lh {} \; 2>/dev/null | head -10
          sleep 60
        done
    volumeMounts:
    - name: host-root
      mountPath: /host
      readOnly: true
  volumes:
  - name: host-root
    hostPath:
      path: /
  restartPolicy: Always
EOF
```

### Reset Scenario
```bash
# Reset disk filler
kubectl delete daemonset disk-filler -n lab-scenarios
kubectl apply -n lab-scenarios -f - <<YAML
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: disk-filler
  labels:
    scenario: disk-usage
spec:
  selector:
    matchLabels:
      app: disk-filler
  template:
    metadata:
      labels:
        app: disk-filler
    spec:
      containers:
      - name: filler
        image: busybox
        command: ["/bin/sh", "-c"]
        args:
          - |
            while true; do
              dd if=/dev/zero of=/tmp/bigfile bs=1M count=200
              sleep 120
              rm /tmp/bigfile
            done
        volumeMounts:
        - name: host-root
          mountPath: /host
      volumes:
      - name: host-root
        hostPath:
          path: /var/log
YAML
```

---

## Scenario 3: CrashLoopBackOff

### Symptoms
- Pod status: `CrashLoopBackOff`
- Pod restarts repeatedly
- Events show: `Back-off restarting failed container`

### Troubleshooting Steps

```bash
# Step 1: Find crash-looping pods
kubectl get pods -n lab-scenarios | grep CrashLoopBackOff

# Step 2: Check logs
kubectl logs <crash-loop-pod> -n lab-scenarios

# Step 3: Check previous logs (before crash)
kubectl logs <crash-loop-pod> -n lab-scenarios --previous

# Step 4: Check pod events
kubectl describe pod <crash-loop-pod> -n lab-scenarios

# Step 5: Check container exit code
kubectl get pod <crash-loop-pod> -n lab-scenarios -o yaml | grep -A 3 "containerStatuses"

# Step 6: Check if probes are failing
kubectl describe pod <crash-loop-pod> -n lab-scenarios | grep -A 10 "Liveness"
```

### Fix Solutions

#### Solution A: Fix Application Code
```bash
# Deploy stable version
kubectl apply -n lab-scenarios -f - <<YAML
apiVersion: apps/v1
kind: Deployment
metadata:
  name: crash-loop-app
  labels:
    scenario: crash-loop
spec:
  replicas: 2
  selector:
    matchLabels:
      app: crash-loop
  template:
    metadata:
      labels:
        app: crash-loop
    spec:
      containers:
      - name: app
        image: alpine:latest
        command: ["/bin/sh", "-c"]
        args:
          - |
            echo "Stable application running..."
            while true; do
              echo "Health check passed at \$(date)"
              sleep 10
            done
        livenessProbe:
          exec:
            command:
            - /bin/sh
            - -c
            - "exit 0"
          initialDelaySeconds: 5
          periodSeconds: 10
        resources:
          limits:
            cpu: 100m
            memory: 128Mi
          requests:
            cpu: 50m
            memory: 64Mi
YAML
```

#### Solution B: Remove Liveness Probe Temporarily
```bash
# Remove liveness probe to keep pod running
kubectl patch deployment crash-loop-app -n lab-scenarios --type='json' -p='[
  {"op": "remove", "path": "/spec/template/spec/containers/0/livenessProbe"}
]'

# Restart deployment
kubectl rollout restart deployment crash-loop-app -n lab-scenarios
```

#### Solution C: Increase Probe Timeout
```bash
# Increase initial delay and timeout
kubectl patch deployment crash-loop-app -n lab-scenarios --type='json' -p='[
  {"op": "replace", "path": "/spec/template/spec/containers/0/livenessProbe/initialDelaySeconds", "value": "30"},
  {"op": "replace", "path": "/spec/template/spec/containers/0/livenessProbe/timeoutSeconds", "value": "10}
]'
```

### Reset Scenario
```bash
# Reset to crashing state
kubectl delete deployment crash-loop-app -n lab-scenarios
kubectl apply -n lab-scenarios -f - <<YAML
apiVersion: apps/v1
kind: Deployment
metadata:
  name: crash-loop-app
  labels:
    scenario: crash-loop
spec:
  replicas: 3
  selector:
    matchLabels:
      app: crash-loop
  template:
    metadata:
      labels:
        app: crash-loop
    spec:
      containers:
      - name: app
        image: alpine
        command: ["/bin/sh", "-c"]
        args:
          - |
            echo "Starting..."
            sleep \$((RANDOM % 10 + 5))
            exit 1
        livenessProbe:
          httpGet:
            path: /health
            port: 8080
          initialDelaySeconds: 5
YAML
```

---

## Scenario 4: CPU Resource Exhaustion

### Symptoms
- Pods in `Pending` state
- Events show: `Insufficient cpu`
- Node CPU usage high
- Resource quota exceeded

### Troubleshooting Steps

```bash
# Step 1: Check pod status
kubectl get pods -n lab-scenarios | grep Pending

# Step 2: Check node resources
kubectl describe nodes | grep -A 5 "Allocated resources"

# Step 3: Check resource quota
kubectl describe resourcequota lab-quota -n lab-scenarios

# Step 4: Check CPU usage
kubectl top pods -n lab-scenarios

# Step 5: Check pod events
kubectl describe pod <cpu-hog-pod> -n lab-scenarios | grep -A 10 "Events"
```

### Fix Solutions

#### Solution A: Scale Down CPU Usage
```bash
# Scale down CPU hog
kubectl patch deployment cpu-hog -n lab-scenarios --type='json' -p='[
  {"op": "replace", "path": "/spec/template/spec/containers/0/resources/limits/cpu", "value": "200m"},
  {"op": "replace", "path": "/spec/template/spec/containers/0/resources/requests/cpu", "value": "100m"}
]'

# Scale down replicas
kubectl scale deployment cpu-hog -n lab-scenarios --replicas=1
```

#### Solution B: Temporarily Scale Down Other Apps
```bash
# Scale down non-critical apps
kubectl scale deployment crash-loop-app -n lab-scenarios --replicas=0
kubectl scale deployment db-issue-app -n lab-scenarios --replicas=0
kubectl scale deployment network-issues-app -n lab-scenarios --replicas=0

# Wait for resources to free up
sleep 10

# Scale CPU hog back up
kubectl scale deployment cpu-hog -n lab-scenarios --replicas=2
```

#### Solution C: Increase Resource Quota
```bash
# Increase quota
kubectl patch resourcequota lab-quota -n lab-scenarios --type='json' -p='[
  {"op": "replace", "path": "/spec/hard/requests.cpu", "value": "6"},
  {"op": "replace", "path": "/spec/hard/limits.cpu", "value": "12"}
]'
```

### Reset Scenario
```bash
# Reset CPU hog
kubectl delete deployment cpu-hog -n lab-scenarios
kubectl apply -n lab-scenarios -f - <<YAML
apiVersion: apps/v1
kind: Deployment
metadata:
  name: cpu-hog
  labels:
    scenario: cpu-exhaustion
spec:
  replicas: 2
  selector:
    matchLabels:
      app: cpu-hog
  template:
    metadata:
      labels:
        app: cpu-hog
    spec:
      containers:
      - name: hog
        image: polinux/stress
        command: ["stress"]
        args: ["--cpu", "4", "--timeout", "3600"]
        resources:
          limits:
            cpu: "2"
          requests:
            cpu: "1"
YAML
```

---

## Scenario 5: Database Connectivity

### Symptoms
- Application logs show connection errors
- Pods fail to start or crash
- Database connections timeout

### Troubleshooting Steps

```bash
# Step 1: Check database pod
kubectl get pods -n lab-scenarios | grep postgres

# Step 2: Check database logs
kubectl logs <postgres-pod> -n lab-scenarios

# Step 3: Check app logs
kubectl logs <db-issue-app-pod> -n lab-scenarios

# Step 4: Test connectivity from app pod
kubectl exec -it <db-issue-app-pod> -n lab-scenarios -- psql -h postgres-service -U admin -d appdb -c "SELECT 1"

# Step 5: Check secrets
kubectl get secrets -n lab-scenarios
```

### Fix Solutions

#### Solution A: Fix Database Credentials
```bash
# Update secret with correct credentials
kubectl delete secret db-secrets -n lab-scenarios
kubectl create secret generic db-secrets -n lab-scenarios \
  --from-literal=username=admin \
  --from-literal=password=password123

# Restart app
kubectl rollout restart deployment db-issue-app -n lab-scenarios
```

#### Solution B: Deploy Working Database App
```bash
# Deploy working version
kubectl apply -n lab-scenarios -f - <<YAML
apiVersion: apps/v1
kind: Deployment
metadata:
  name: db-issue-app
  labels:
    scenario: database
spec:
  replicas: 1
  selector:
    matchLabels:
      app: db-issue
  template:
    metadata:
      labels:
        app: db-issue
    spec:
      containers:
      - name: app
        image: postgres:13-alpine
        command: ["/bin/sh", "-c"]
        args:
          - |
            while true; do
              if psql -h postgres-service -U admin -d appdb -c "SELECT 1" 2>/dev/null; then
                echo "Database connection successful!"
              else
                echo "Database connection failed! Retrying..."
              fi
              sleep 10
            done
        env:
        - name: PGPASSWORD
          value: "password123"
        resources:
          limits:
            cpu: 100m
            memory: 128Mi
          requests:
            cpu: 50m
            memory: 64Mi
YAML
```

### Reset Scenario
```bash
# Reset database issue
kubectl delete deployment db-issue-app -n lab-scenarios
kubectl apply -n lab-scenarios -f - <<YAML
apiVersion: apps/v1
kind: Deployment
metadata:
  name: db-issue-app
  labels:
    scenario: database
spec:
  replicas: 2
  selector:
    matchLabels:
      app: db-issue
  template:
    metadata:
      labels:
        app: db-issue
    spec:
      containers:
      - name: app
        image: postgres:13-alpine
        command: ["/bin/sh", "-c"]
        args:
          - |
            while true; do
              psql -h postgres-service -U admin -d appdb -c "SELECT 1" || echo "Database connection failed!"
              sleep 10
            done
        env:
        - name: PGPASSWORD
          value: "wrong-password"
YAML
```

---

## Scenario 6: Network Policy Issues

### Symptoms
- Pods can't communicate
- Service endpoints unreachable
- Connection timeouts

### Troubleshooting Steps

```bash
# Step 1: Check network policies
kubectl get networkpolicies -n lab-scenarios

# Step 2: Describe network policy
kubectl describe networkpolicy restrictive-policy -n lab-scenarios

# Step 3: Test connectivity
kubectl exec -it <pod> -n lab-scenarios -- curl -v http://crash-loop-service

# Step 4: Check pod labels
kubectl get pods -n lab-scenarios --show-labels

# Step 5: Check service endpoints
kubectl get endpoints -n lab-scenarios
```

### Fix Solutions

#### Solution A: Allow Traffic with Proper Labels
```bash
# Add labels to pods that need access
kubectl label pods -n lab-scenarios -l app=crash-loop allowed-client=true

# Update network policy to allow traffic
kubectl apply -n lab-scenarios -f - <<YAML
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: restrictive-policy
spec:
  podSelector:
    matchLabels:
      app: restricted
  policyTypes:
  - Ingress
  - Egress
  ingress:
  - from:
    - podSelector:
        matchLabels:
          allowed-client: "true"
    ports:
    - protocol: TCP
      port: 80
  egress:
  - to:
    - podSelector:
        matchLabels:
          app: postgres
    ports:
    - protocol: TCP
      port: 5432
  - to:
    - podSelector:
        matchLabels:
          app: allowed-target
    ports:
    - protocol: TCP
      port: 80
YAML
```

#### Solution B: Remove Restrictive Policy
```bash
# Delete network policy
kubectl delete networkpolicy restrictive-policy -n lab-scenarios

# Apply permissive policy for testing
kubectl apply -n lab-scenarios -f - <<YAML
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: permissive-policy
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  - Egress
  ingress:
  - {}
  egress:
  - {}
YAML
```

### Reset Scenario
```bash
# Reset network policy
kubectl delete networkpolicy restrictive-policy -n lab-scenarios
kubectl apply -n lab-scenarios -f - <<YAML
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: restrictive-policy
spec:
  podSelector:
    matchLabels:
      app: restricted
  policyTypes:
  - Ingress
  - Egress
  ingress: []
  egress: []
YAML
```

---

## Lab Management

### Complete Reset Script
```bash
cat <<'EOF' > reset-all-scenarios.sh
#!/bin/bash

echo "=== Resetting All Scenarios ==="

# Delete all deployments
echo "Deleting all deployments..."
kubectl delete deployment --all -n lab-scenarios 2>/dev/null

# Delete daemonsets
echo "Deleting daemonsets..."
kubectl delete daemonset --all -n lab-scenarios 2>/dev/null

# Delete network policies
echo "Deleting network policies..."
kubectl delete networkpolicy --all -n lab-scenarios 2>/dev/null

# Delete pods
echo "Deleting remaining pods..."
kubectl delete pod --all -n lab-scenarios 2>/dev/null

# Delete PVCs
echo "Deleting PVCs..."
kubectl delete pvc --all -n lab-scenarios 2>/dev/null

# Delete jobs and cronjobs
echo "Deleting jobs..."
kubectl delete job --all -n lab-scenarios 2>/dev/null
kubectl delete cronjob --all -n lab-scenarios 2>/dev/null

# Wait for cleanup
sleep 5

echo ""
echo "=== All scenarios reset ==="
echo "Run ./lab-exercises.sh to start fresh"
EOF

chmod +x reset-all-scenarios.sh
```

### Health Check Script
```bash
cat <<'EOF' > health-check.sh
#!/bin/bash

echo "=== Lab Health Check ==="
echo ""

echo "📊 Pod Status:"
kubectl get pods -n lab-scenarios -o wide
echo ""

echo "📈 Resource Usage:"
kubectl top pods -n lab-scenarios 2>/dev/null || echo "Metrics not available"
echo ""

echo "💾 Resource Quota:"
kubectl describe resourcequota lab-quota -n lab-scenarios | grep -E "(Used|Hard)" | head -4
echo ""

echo "🚨 Problematic Pods:"
kubectl get pods -n lab-scenarios | grep -E "(CrashLoopBackOff|OOMKilled|Error|Pending|ImagePullBackOff|Evicted)" || echo "✅ No problematic pods"
echo ""

echo "📝 Recent Events:"
kubectl get events -n lab-scenarios --sort-by='.lastTimestamp' | tail -5
echo ""

echo "🔧 Quick fixes:"
echo "1. ./reset-all-scenarios.sh - Reset all scenarios"
echo "2. ./fix-scenario.sh <scenario-number> - Fix specific scenario"
echo "3. kubectl describe pod <pod-name> -n lab-scenarios - Check pod details"
echo "4. kubectl logs <pod-name> -n lab-scenarios - Check pod logs"
EOF

chmod +x health-check.sh
```

---

## Complete Cleanup

### Full Cleanup Script
```bash
cat <<'EOF' > cleanup-all.sh
#!/bin/bash

echo "=== Complete Lab Cleanup ==="

# Delete namespace
echo "Deleting lab-scenarios namespace..."
kubectl delete namespace lab-scenarios --ignore-not-found

# Delete cluster-wide resources
echo "Deleting cluster-wide resources..."
kubectl delete clusterrole remediator-role --ignore-not-found
kubectl delete clusterrolebinding remediator-binding --ignore-not-found

# Delete Prometheus rules
echo "Deleting Prometheus rules..."
kubectl delete prometheusrule lab-alerts -n lab-scenarios --ignore-not-found 2>/dev/null

# Delete local files
echo "Deleting local scripts..."
rm -f lab-exercises.sh quick-start.sh reset-all-scenarios.sh health-check.sh fix-all-deployments.sh auto-fix.sh status.sh

echo ""
echo "=== Cleanup Complete ==="
echo "To recreate the lab:"
echo "1. ./quick-start.sh"
echo "2. ./lab-exercises.sh"
EOF

chmod +x cleanup-all.sh
```

### Scenario-Specific Fix Scripts

#### Fix Memory Leak
```bash
cat <<'EOF' > fix-memory-leak.sh
#!/bin/bash
echo "Fixing Memory Leak Scenario..."
kubectl delete deployment memory-leak-app -n lab-scenarios
kubectl apply -n lab-scenarios -f - <<YAML
apiVersion: apps/v1
kind: Deployment
metadata:
  name: memory-leak-app
  labels:
    scenario: memory-leak
spec:
  replicas: 1
  selector:
    matchLabels:
      app: memory-leak
  template:
    metadata:
      labels:
        app: memory-leak
    spec:
      containers:
      - name: leaky-app
        image: python:3.9-slim
        command: ["python", "-c"]
        args:
          - |
            import time, sys
            data = []
            while True:
                data.append('x' * (100 * 1024))
                if len(data) % 50 == 0:
                    print(f"Memory: {len(data)*100/1024:.1f}MB")
                    sys.stdout.flush()
                time.sleep(0.1)
        resources:
          limits:
            memory: "512Mi"
          requests:
            memory: "256Mi"
        env:
        - name: PYTHONUNBUFFERED
          value: "1"
YAML
echo "Memory leak fixed! Check: kubectl get pods -n lab-scenarios"
EOF
chmod +x fix-memory-leak.sh
```

#### Fix All Scenarios
```bash
cat <<'EOF' > fix-all-scenarios.sh
#!/bin/bash
echo "=== Fixing All Scenarios ==="

# Fix memory leak
./fix-memory-leak.sh

# Fix crash loop
kubectl delete deployment crash-loop-app -n lab-scenarios
kubectl apply -n lab-scenarios -f - <<YAML
apiVersion: apps/v1
kind: Deployment
metadata:
  name: crash-loop-app
  labels:
    scenario: crash-loop
spec:
  replicas: 2
  selector:
    matchLabels:
      app: crash-loop
  template:
    metadata:
      labels:
        app: crash-loop
    spec:
      containers:
      - name: app
        image: alpine:latest
        command: ["/bin/sh", "-c"]
        args:
          - |
            echo "Stable app running..."
            while true; do sleep 10; done
        resources:
          limits:
            cpu: 100m
            memory: 128Mi
          requests:
            cpu: 50m
            memory: 64Mi
YAML

# Fix CPU hog
kubectl delete deployment cpu-hog -n lab-scenarios
kubectl apply -n lab-scenarios -f - <<YAML
apiVersion: apps/v1
kind: Deployment
metadata:
  name: cpu-hog
  labels:
    scenario: cpu-exhaustion
spec:
  replicas: 1
  selector:
    matchLabels:
      app: cpu-hog
  template:
    metadata:
      labels:
        app: cpu-hog
    spec:
      containers:
      - name: hog
        image: polinux/stress:latest
        command: ["stress"]
        args: ["--cpu", "1", "--timeout", "3600"]
        resources:
          limits:
            cpu: "200m"
            memory: 128Mi
          requests:
            cpu: "100m"
            memory: 64Mi
YAML

echo ""
echo "All scenarios fixed!"
kubectl get pods -n lab-scenarios
EOF
chmod +x fix-all-scenarios.sh
```

---

## Quick Reference Card

```bash
# Quick Commands Card
cat <<'EOF' > quick-ref.txt
=== DevOps Lab Quick Reference ===

STATUS CHECKS:
  kubectl get all -n lab-scenarios
  kubectl get pods -n lab-scenarios -w
  kubectl top pods -n lab-scenarios
  kubectl describe resourcequota lab-quota -n lab-scenarios

SCENARIO FIXES:
  ./fix-memory-leak.sh       # Fix OOMKilled
  ./fix-all-scenarios.sh      # Fix everything

RESET:
  ./reset-all-scenarios.sh   # Reset all scenarios

CLEANUP:
  ./cleanup-all.sh           # Complete cleanup

DEBUGGING:
  kubectl logs <pod> -n lab-scenarios
  kubectl describe pod <pod> -n lab-scenarios
  kubectl exec -it <pod> -n lab-scenarios -- /bin/sh

EVENTS:
  kubectl get events -n lab-scenarios --sort-by='.lastTimestamp'
  kubectl get events -n lab-scenarios --watch
EOF

cat quick-ref.txt
```

---

## Usage Instructions

```bash
# 1. Initial setup
./quick-start.sh

# 2. Run lab exercises
./lab-exercises.sh

# 3. Check health
./health-check.sh

# 4. Fix specific issue
./fix-memory-leak.sh     # Fix memory leak
./fix-all-scenarios.sh   # Fix all scenarios

# 5. Reset lab
./reset-all-scenarios.sh

# 6. Complete cleanup
./cleanup-all.sh
```

This runbook provides everything needed to troubleshoot, fix, reset, and clean up each scenario in this lab!