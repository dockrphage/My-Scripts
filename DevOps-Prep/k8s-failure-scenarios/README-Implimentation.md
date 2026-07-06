# DevOps Troubleshooting Lab - Complete Implementation Guide

## Prerequisites
- Kubernetes cluster (v1.25+) with kubectl configured
- MetalLB or similar LoadBalancer
- Ingress-NGINX Controller
- kubectl access to the cluster

---

## Step 1: Initial Setup

```bash
# Create project directory
mkdir -p ~/devops-lab
cd ~/devops-lab

# Create namespace and base resources
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: Namespace
metadata:
  name: lab-scenarios
---
apiVersion: v1
kind: ResourceQuota
metadata:
  name: lab-quota
  namespace: lab-scenarios
spec:
  hard:
    pods: "20"
    requests.cpu: "4"
    requests.memory: 4Gi
    limits.cpu: "8"
    limits.memory: 8Gi
    persistentvolumeclaims: "5"
---
apiVersion: v1
kind: LimitRange
metadata:
  name: lab-limits
  namespace: lab-scenarios
spec:
  limits:
  - max:
      cpu: "2"
      memory: 1Gi
    min:
      cpu: 100m
      memory: 128Mi
    default:
      cpu: 500m
      memory: 512Mi
    defaultRequest:
      cpu: 200m
      memory: 256Mi
    type: Container
EOF
```

---

## Step 2: Deploy Base Services

### Deploy Database and Supporting Services

```bash
cat <<'EOF' | kubectl apply -n lab-scenarios -f -
apiVersion: v1
kind: Secret
metadata:
  name: db-secrets
type: Opaque
data:
  username: YWRtaW4=
  password: cGFzc3dvcmQxMjM=
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: postgres-pvc
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 5Gi
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: postgres-db
  labels:
    app: postgres
spec:
  replicas: 1
  selector:
    matchLabels:
      app: postgres
  template:
    metadata:
      labels:
        app: postgres
    spec:
      containers:
      - name: postgres
        image: postgres:13-alpine
        env:
        - name: POSTGRES_USER
          value: admin
        - name: POSTGRES_PASSWORD
          value: password123
        - name: POSTGRES_DB
          value: appdb
        ports:
        - containerPort: 5432
        volumeMounts:
        - name: postgres-storage
          mountPath: /var/lib/postgresql/data
        resources:
          limits:
            memory: 512Mi
            cpu: 500m
          requests:
            memory: 256Mi
            cpu: 250m
      volumes:
      - name: postgres-storage
        persistentVolumeClaim:
          claimName: postgres-pvc
---
apiVersion: v1
kind: Service
metadata:
  name: postgres-service
spec:
  selector:
    app: postgres
  ports:
  - port: 5432
    targetPort: 5432
EOF
```

---

## Step 3: Deploy All Lab Scenarios

### 3.1 Memory Leak Scenario

```bash
cat <<'EOF' | kubectl apply -n lab-scenarios -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: memory-leak-app
  labels:
    scenario: memory-leak
    difficulty: medium
spec:
  replicas: 2
  selector:
    matchLabels:
      app: memory-leak
  template:
    metadata:
      labels:
        app: memory-leak
        scenario: memory-leak
      annotations:
        prometheus.io/scrape: "true"
        prometheus.io/port: "8080"
    spec:
      containers:
      - name: leaky-app
        image: python:3.9-slim
        command: ["python", "-c"]
        args:
          - |
            import time
            import sys
            import os
            data = []
            counter = 0
            print(f"Memory leak app started. PID: {os.getpid()}")
            sys.stdout.flush()
            while True:
                # Allocate 1MB per iteration
                data.append('x' * (1024 * 1024))
                counter += 1
                if counter % 10 == 0:
                    mem_mb = len(data)
                    print(f"Allocated {mem_mb}MB. Memory limit: 128Mi")
                    sys.stdout.flush()
                time.sleep(0.2)
        resources:
          limits:
            memory: "128Mi"
          requests:
            memory: "64Mi"
        env:
        - name: PYTHONUNBUFFERED
          value: "1"
---
apiVersion: v1
kind: Service
metadata:
  name: memory-leak-service
spec:
  selector:
    app: memory-leak
  ports:
  - port: 80
    targetPort: 8080
EOF
```

### 3.2 Disk Space Exhaustion Scenario

```bash
cat <<'EOF' | kubectl apply -n lab-scenarios -f -
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: disk-filler
  labels:
    scenario: disk-usage
    difficulty: medium
spec:
  selector:
    matchLabels:
      app: disk-filler
  template:
    metadata:
      labels:
        app: disk-filler
        scenario: disk-usage
    spec:
      tolerations:
      - key: node-role.kubernetes.io/control-plane
        operator: Exists
        effect: NoSchedule
      containers:
      - name: filler
        image: busybox:latest
        command: ["/bin/sh", "-c"]
        args:
          - |
            echo "Starting disk filler on node: $(hostname)"
            while true; do
              echo "Creating 200MB file at $(date)"
              dd if=/dev/zero of=/host/logs/bigfile bs=1M count=200 2>/dev/null
              echo "File created. Sleeping 2 minutes..."
              sleep 120
              echo "Removing file..."
              rm -f /host/logs/bigfile
              sleep 60
            done
        volumeMounts:
        - name: host-logs
          mountPath: /host/logs
        resources:
          limits:
            cpu: 100m
            memory: 128Mi
          requests:
            cpu: 50m
            memory: 64Mi
      volumes:
      - name: host-logs
        hostPath:
          path: /var/log
          type: Directory
---
apiVersion: v1
kind: Pod
metadata:
  name: disk-monitor
  labels:
    scenario: disk-usage
spec:
  containers:
  - name: monitor
    image: busybox:latest
    command: ["/bin/sh", "-c"]
    args:
      - |
        while true; do
          echo "=== Disk Usage Report $(date) ==="
          df -h /host
          echo "Top large files:"
          find /host -type f -size +50M -exec ls -lh {} \; 2>/dev/null | head -5
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

### 3.3 CrashLoopBackOff Scenario

```bash
cat <<'EOF' | kubectl apply -n lab-scenarios -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: crash-loop-app
  labels:
    scenario: crash-loop
    difficulty: easy
spec:
  replicas: 3
  selector:
    matchLabels:
      app: crash-loop
  template:
    metadata:
      labels:
        app: crash-loop
        scenario: crash-loop
    spec:
      containers:
      - name: app
        image: alpine:latest
        command: ["/bin/sh", "-c"]
        args:
          - |
            echo "Application starting at $(date)"
            echo "Will crash after random time..."
            SLEEP_TIME=$((RANDOM % 15 + 5))
            echo "Running for ${SLEEP_TIME} seconds"
            sleep ${SLEEP_TIME}
            echo "CRASHING NOW! Simulating application failure..."
            exit 1
        livenessProbe:
          httpGet:
            path: /health
            port: 8080
          initialDelaySeconds: 5
          periodSeconds: 10
          failureThreshold: 3
        ports:
        - containerPort: 8080
        resources:
          limits:
            cpu: 100m
            memory: 128Mi
          requests:
            cpu: 50m
            memory: 64Mi
---
apiVersion: v1
kind: Service
metadata:
  name: crash-loop-service
spec:
  selector:
    app: crash-loop
  ports:
  - port: 80
    targetPort: 8080
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: crash-loop-ingress
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /
spec:
  rules:
  - host: crash-loop.local
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: crash-loop-service
            port:
              number: 80
EOF
```

### 3.4 CPU Resource Exhaustion Scenario

```bash
cat <<'EOF' | kubectl apply -n lab-scenarios -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: cpu-hog
  labels:
    scenario: cpu-exhaustion
    difficulty: easy
spec:
  replicas: 2
  selector:
    matchLabels:
      app: cpu-hog
  template:
    metadata:
      labels:
        app: cpu-hog
        scenario: cpu-exhaustion
    spec:
      containers:
      - name: hog
        image: polinux/stress:latest
        command: ["stress"]
        args:
          - "--cpu"
          - "4"
          - "--timeout"
          - "3600"
          - "--vm"
          - "2"
          - "--vm-bytes"
          - "128M"
        resources:
          limits:
            cpu: "2"
            memory: 512Mi
          requests:
            cpu: "1"
            memory: 256Mi
---
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: cpu-hog-hpa
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: cpu-hog
  minReplicas: 2
  maxReplicas: 10
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 50
  - type: Resource
    resource:
      name: memory
      target:
        type: Utilization
        averageUtilization: 70
EOF
```

### 3.5 Database Connectivity Issues Scenario

```bash
cat <<'EOF' | kubectl apply -n lab-scenarios -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: db-issue-app
  labels:
    scenario: database
    difficulty: medium
spec:
  replicas: 2
  selector:
    matchLabels:
      app: db-issue
  template:
    metadata:
      labels:
        app: db-issue
        scenario: database
    spec:
      containers:
      - name: app
        image: postgres:13-alpine
        command: ["/bin/sh", "-c"]
        args:
          - |
            echo "Database connectivity test app starting..."
            while true; do
              echo "Attempting database connection at $(date)..."
              if psql -h postgres-service -U admin -d appdb -c "SELECT 1" 2>/dev/null; then
                echo "✓ Database connection successful!"
              else
                echo "✗ Database connection failed! Check credentials or connectivity."
              fi
              sleep 10
            done
        env:
        - name: PGPASSWORD
          value: "wrong-password"
        resources:
          limits:
            cpu: 100m
            memory: 128Mi
          requests:
            cpu: 50m
            memory: 64Mi
---
apiVersion: v1
kind: Service
metadata:
  name: db-issue-service
spec:
  selector:
    app: db-issue
  ports:
  - port: 80
    targetPort: 5432
EOF
```

### 3.6 Network Policy Issues Scenario

```bash
cat <<'EOF' | kubectl apply -n lab-scenarios -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: restrictive-policy
  labels:
    scenario: network
spec:
  podSelector:
    matchLabels:
      app: restricted
  policyTypes:
  - Ingress
  - Egress
  ingress: []
  egress: []
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: network-issues-app
  labels:
    scenario: network
    difficulty: hard
spec:
  replicas: 2
  selector:
    matchLabels:
      app: network-issues
  template:
    metadata:
      labels:
        app: network-issues
        restricted: "true"
    spec:
      containers:
      - name: app
        image: nginx:alpine
        command: ["/bin/sh", "-c"]
        args:
          - |
            echo "Network connectivity test app started"
            while true; do
              echo "Testing connectivity to services..."
              wget -q --timeout=2 --spider http://crash-loop-service && echo "✓ crash-loop-service reachable" || echo "✗ crash-loop-service unreachable"
              wget -q --timeout=2 --spider http://postgres-service:5432 && echo "✓ postgres-service reachable" || echo "✗ postgres-service unreachable"
              sleep 10
            done
        resources:
          limits:
            cpu: 100m
            memory: 128Mi
          requests:
            cpu: 50m
            memory: 64Mi
---
apiVersion: v1
kind: Service
metadata:
  name: network-issues-service
spec:
  selector:
    app: network-issues
  ports:
  - port: 80
    targetPort: 80
EOF
```

### 3.7 Monitoring & Alerts

```bash
cat <<'EOF' | kubectl apply -n lab-scenarios -f -
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: lab-alerts
  labels:
    prometheus: kube-prometheus
    role: alert-rules
spec:
  groups:
  - name: lab-scenario-alerts
    rules:
    - alert: PodCrashLooping
      expr: kube_pod_container_status_restarts_total{namespace="lab-scenarios"} > 5
      for: 2m
      labels:
        severity: warning
        scenario: crash-loop
      annotations:
        summary: "Pod {{ $labels.pod }} is crash looping"
        description: "Pod {{ $labels.pod }} in namespace {{ $labels.namespace }} has restarted {{ $value }} times"
        runbook_url: "https://docs.google.com/document/d/1xYzZzZzZzZzZzZzZzZzZzZzZzZzZzZ"

    - alert: OOMKilledPods
      expr: kube_pod_container_status_last_terminated_reason{reason="OOMKilled",namespace="lab-scenarios"} > 0
      for: 1m
      labels:
        severity: critical
        scenario: memory-leak
      annotations:
        summary: "Pod was OOMKilled"
        description: "Pod {{ $labels.pod }} was terminated due to Out of Memory"
        
    - alert: HighMemoryUsage
      expr: (sum(container_memory_usage_bytes{namespace="lab-scenarios"}) by (pod) / sum(kube_pod_container_resource_limits_memory_bytes{namespace="lab-scenarios"}) by (pod)) > 0.85
      for: 5m
      labels:
        severity: critical
      annotations:
        summary: "High memory usage detected"
        description: "Pod {{ $labels.pod }} is using {{ $value | humanizePercentage }} of its memory limit"

    - alert: NodeDiskPressure
      expr: kube_node_status_condition{condition="DiskPressure",status="true"} == 1
      for: 5m
      labels:
        severity: warning
        scenario: disk-usage
      annotations:
        summary: "Node under disk pressure"
        description: "Node {{ $labels.node }} is experiencing disk pressure"

    - alert: PodNotReady
      expr: kube_pod_status_ready{namespace="lab-scenarios",condition="false"} > 0
      for: 3m
      labels:
        severity: warning
      annotations:
        summary: "Pod not ready"
        description: "Pod {{ $labels.pod }} is not ready for more than 3 minutes"

    - alert: JobFailed
      expr: kube_job_status_failed{namespace="lab-scenarios"} > 0
      for: 1m
      labels:
        severity: warning
      annotations:
        summary: "Job failed"
        description: "Job {{ $labels.job_name }} failed in namespace {{ $labels.namespace }}"
EOF
```

### 3.8 Auto-Remediation

```bash
cat <<'EOF' | kubectl apply -n lab-scenarios -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: remediator-role
rules:
- apiGroups: [""]
  resources: ["pods"]
  verbs: ["get", "list", "delete"]
- apiGroups: ["apps"]
  resources: ["deployments"]
  verbs: ["get", "list", "patch", "update"]
- apiGroups: [""]
  resources: ["nodes"]
  verbs: ["get", "list", "patch"]
- apiGroups: [""]
  resources: ["events"]
  verbs: ["get", "list"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: remediator-binding
subjects:
- kind: ServiceAccount
  name: remediator-sa
  namespace: lab-scenarios
roleRef:
  kind: ClusterRole
  name: remediator-role
  apiGroup: rbac.authorization.k8s.io
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: remediator-sa
  namespace: lab-scenarios
---
apiVersion: batch/v1
kind: CronJob
metadata:
  name: auto-remediator
  labels:
    scenario: auto-remediation
spec:
  schedule: "*/5 * * * *"
  successfulJobsHistoryLimit: 3
  failedJobsHistoryLimit: 3
  jobTemplate:
    spec:
      template:
        spec:
          serviceAccountName: remediator-sa
          containers:
          - name: remediator
            image: bitnami/kubectl:latest
            command:
            - /bin/sh
            - -c
            - |
              echo "=== Auto-Remediation Started at $(date) ==="
              
              # Fix CrashLoopBackOff
              echo "Checking for CrashLoopBackOff pods..."
              kubectl get pods -n lab-scenarios --no-headers | grep CrashLoopBackOff | awk '{print $1}' | while read pod; do
                echo "✓ Restarting crash-looping pod: $pod"
                kubectl delete pod $pod -n lab-scenarios
              done
              
              # Fix OOMKilled
              echo "Checking for OOMKilled pods..."
              kubectl get pods -n lab-scenarios --no-headers | grep OOMKilled | awk '{print $1}' | while read pod; do
                echo "✓ Pod OOMKilled: $pod"
                deploy=$(kubectl get pod $pod -n lab-scenarios -o jsonpath='{.metadata.ownerReferences[0].name}' 2>/dev/null)
                if [ ! -z "$deploy" ] && [ "$deploy" != "null" ]; then
                  echo "  Scaling down deployment $deploy"
                  kubectl scale deployment $deploy -n lab-scenarios --replicas=1
                  sleep 5
                  echo "  Scaling up deployment $deploy"
                  kubectl scale deployment $deploy -n lab-scenarios --replicas=2
                fi
              done
              
              # Clean up completed jobs
              echo "Cleaning up old jobs..."
              kubectl delete jobs -n lab-scenarios --field-selector status.successful=True --ignore-not-found
              
              echo "=== Auto-Remediation Completed at $(date) ==="
          restartPolicy: OnFailure
---
apiVersion: v1
kind: Pod
metadata:
  name: debug-pod
  labels:
    scenario: troubleshooting
spec:
  containers:
  - name: debug
    image: busybox:latest
    command: ["/bin/sh", "-c"]
    args:
      - |
        echo "Debug pod ready for troubleshooting"
        echo "Use: kubectl exec -it debug-pod -n lab-scenarios -- sh"
        while true; do sleep 3600; done
  restartPolicy: Always
EOF
```

---

## Step 4: Deploy Troubleshooting Tools

```bash
cat <<'EOF' | kubectl apply -n lab-scenarios -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: troubleshooting-tools
  labels:
    app: troubleshooting-tools
spec:
  replicas: 1
  selector:
    matchLabels:
      app: troubleshooting-tools
  template:
    metadata:
      labels:
        app: troubleshooting-tools
    spec:
      containers:
      - name: tools
        image: nicolaka/netshoot:latest
        command: ["sleep", "3600"]
        resources:
          limits:
            cpu: 500m
            memory: 256Mi
          requests:
            cpu: 100m
            memory: 128Mi
---
apiVersion: v1
kind: Service
metadata:
  name: troubleshooting-service
spec:
  selector:
    app: troubleshooting-tools
  ports:
  - name: web
    port: 80
    targetPort: 80
  - name: metrics
    port: 9113
    targetPort: 9113
---
apiVersion: v1
kind: Pod
metadata:
  name: kubectl-debug
  labels:
    app: kubectl-debug
spec:
  containers:
  - name: kubectl
    image: bitnami/kubectl:latest
    command: ["sleep", "3600"]
    resources:
      limits:
        cpu: 100m
        memory: 64Mi
      requests:
        cpu: 50m
        memory: 32Mi
  restartPolicy: Always
EOF
```

---

## Step 5: Create Management Scripts

### 5.1 Main Lab Controller Script

```bash
cat <<'EOF' > lab-controller.sh
#!/bin/bash

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

show_menu() {
    clear
    echo -e "${BLUE}╔════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║    DevOps Troubleshooting Lab Controller   ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${YELLOW}📊 Status:${NC}"
    kubectl get pods -n lab-scenarios -o wide 2>/dev/null | head -10
    echo ""
    echo -e "${YELLOW}📈 Resource Usage:${NC}"
    kubectl top pods -n lab-scenarios 2>/dev/null | head -5 || echo "Metrics not available"
    echo ""
    echo -e "${GREEN}Available Commands:${NC}"
    echo "1.  Show all pods"
    echo "2.  Show problem pods"
    echo "3.  Show resource usage"
    echo "4.  Show events"
    echo "5.  Deploy scenario"
    echo "6.  Fix scenario"
    echo "7.  Reset scenario"
    echo "8.  Run auto-remediation"
    echo "9.  View logs"
    echo "10. Cleanup all"
    echo "11. Exit"
    echo ""
    read -p "Select option (1-11): " choice
}

deploy_scenario() {
    echo -e "${GREEN}Available scenarios:${NC}"
    echo "1. Memory Leak (OOMKilled)"
    echo "2. Disk Space Exhaustion"
    echo "3. CrashLoopBackOff"
    echo "4. CPU Resource Exhaustion"
    echo "5. Database Connectivity"
    echo "6. Network Policy Issues"
    echo "7. All scenarios"
    read -p "Select scenario (1-7): " scenario
    
    case $scenario in
        1) kubectl apply -n lab-scenarios -f scenarios/memory-leak.yaml ;;
        2) kubectl apply -n lab-scenarios -f scenarios/disk-space.yaml ;;
        3) kubectl apply -n lab-scenarios -f scenarios/crash-loop.yaml ;;
        4) kubectl apply -n lab-scenarios -f scenarios/cpu-hog.yaml ;;
        5) kubectl apply -n lab-scenarios -f scenarios/database.yaml ;;
        6) kubectl apply -n lab-scenarios -f scenarios/network-policy.yaml ;;
        7) 
            for file in scenarios/*.yaml; do
                kubectl apply -n lab-scenarios -f $file
            done
            ;;
        *) echo -e "${RED}Invalid choice${NC}" ;;
    esac
}

fix_scenario() {
    echo -e "${GREEN}Fixing scenarios...${NC}"
    case $1 in
        memory-leak)
            kubectl patch deployment memory-leak-app -n lab-scenarios --type='json' -p='[
                {"op": "replace", "path": "/spec/template/spec/containers/0/resources/limits/memory", "value": "512Mi"},
                {"op": "replace", "path": "/spec/template/spec/containers/0/resources/requests/memory", "value": "256Mi"}
            ]'
            ;;
        crash-loop)
            kubectl patch deployment crash-loop-app -n lab-scenarios --type='json' -p='[
                {"op": "remove", "path": "/spec/template/spec/containers/0/livenessProbe"}
            ]'
            ;;
        cpu-hog)
            kubectl patch deployment cpu-hog -n lab-scenarios --type='json' -p='[
                {"op": "replace", "path": "/spec/template/spec/containers/0/resources/limits/cpu", "value": "500m"},
                {"op": "replace", "path": "/spec/template/spec/containers/0/resources/requests/cpu", "value": "200m"}
            ]'
            ;;
        database)
            kubectl patch deployment db-issue-app -n lab-scenarios --type='json' -p='[
                {"op": "replace", "path": "/spec/template/spec/containers/0/env/0/value", "value": "password123"}
            ]'
            ;;
        network)
            kubectl delete networkpolicy restrictive-policy -n lab-scenarios
            ;;
        all)
            for fix in memory-leak crash-loop cpu-hog database network; do
                fix_scenario $fix
            done
            ;;
        *) echo -e "${RED}Unknown scenario${NC}" ;;
    esac
}

reset_scenario() {
    echo -e "${YELLOW}Resetting scenario...${NC}"
    kubectl delete deployment -n lab-scenarios --all 2>/dev/null
    kubectl delete daemonset -n lab-scenarios --all 2>/dev/null
    kubectl delete networkpolicy -n lab-scenarios --all 2>/dev/null
    sleep 5
    echo -e "${GREEN}Reset complete. Re-deploy scenarios to start fresh.${NC}"
}

view_logs() {
    echo -e "${GREEN}Select pod to view logs:${NC}"
    kubectl get pods -n lab-scenarios
    read -p "Enter pod name: " pod_name
    if [ ! -z "$pod_name" ]; then
        kubectl logs -f $pod_name -n lab-scenarios
    fi
}

# Main loop
while true; do
    show_menu
    case $choice in
        1) kubectl get pods -n lab-scenarios -o wide ;;
        2) kubectl get pods -n lab-scenarios | grep -E "(CrashLoopBackOff|OOMKilled|Error|Pending|ImagePullBackOff)" || echo "No problems found" ;;
        3) kubectl top pods -n lab-scenarios 2>/dev/null || echo "Metrics not available" ;;
        4) kubectl get events -n lab-scenarios --sort-by='.lastTimestamp' | tail -20 ;;
        5) deploy_scenario ;;
        6) 
            echo "Select scenario to fix:"
            echo "1. Memory Leak"
            echo "2. CrashLoopBackOff"
            echo "3. CPU Hog"
            echo "4. Database"
            echo "5. Network"
            echo "6. All"
            read -p "Choice: " fix_choice
            case $fix_choice in
                1) fix_scenario memory-leak ;;
                2) fix_scenario crash-loop ;;
                3) fix_scenario cpu-hog ;;
                4) fix_scenario database ;;
                5) fix_scenario network ;;
                6) fix_scenario all ;;
                *) echo "Invalid choice" ;;
            esac
            ;;
        7) reset_scenario ;;
        8) kubectl create job --from=cronjob/auto-remediator manual-remediation -n lab-scenarios ;;
        9) view_logs ;;
        10) 
            read -p "Are you sure you want to cleanup all? (y/n): " confirm
            if [ "$confirm" = "y" ]; then
                kubectl delete namespace lab-scenarios
                echo -e "${RED}Cleanup complete${NC}"
                exit 0
            fi
            ;;
        11) exit 0 ;;
        *) echo -e "${RED}Invalid option${NC}" ;;
    esac
    read -p "Press Enter to continue..."
done
EOF

chmod +x lab-controller.sh
```

### 5.2 Health Check Script

```bash
cat <<'EOF' > health-check.sh
#!/bin/bash

echo "╔════════════════════════════════════════════════╗"
echo "║         Lab Health Check Report               ║"
echo "╚════════════════════════════════════════════════╝"
echo ""

echo "📊 Pod Status:"
echo "─────────────────────────────────────────────"
kubectl get pods -n lab-scenarios -o wide
echo ""

echo "📈 Resource Usage:"
echo "─────────────────────────────────────────────"
kubectl top pods -n lab-scenarios 2>/dev/null || echo "Metrics not available"
echo ""

echo "💾 Resource Quota:"
echo "─────────────────────────────────────────────"
kubectl describe resourcequota lab-quota -n lab-scenarios | grep -E "(Used|Hard)" | head -6
echo ""

echo "🚨 Problematic Pods:"
echo "─────────────────────────────────────────────"
PROBLEMS=$(kubectl get pods -n lab-scenarios | grep -E "(CrashLoopBackOff|OOMKilled|Error|Pending|ImagePullBackOff|Evicted)" || echo "✅ No problematic pods found")
echo "$PROBLEMS"
echo ""

echo "📝 Recent Events:"
echo "─────────────────────────────────────────────"
kubectl get events -n lab-scenarios --sort-by='.lastTimestamp' | tail -10
echo ""

echo "📊 Node Status:"
echo "─────────────────────────────────────────────"
kubectl get nodes
echo ""

echo "🔧 Quick Actions:"
echo "─────────────────────────────────────────────"
echo "1. ./lab-controller.sh - Interactive lab controller"
echo "2. kubectl describe pod <pod-name> -n lab-scenarios"
echo "3. kubectl logs <pod-name> -n lab-scenarios"
echo "4. kubectl exec -it debug-pod -n lab-scenarios -- sh"
EOF

chmod +x health-check.sh
```

### 5.3 Quick Fix Script

```bash
cat <<'EOF' > quick-fix.sh
#!/bin/bash

echo "=== Quick Fix All Scenarios ==="

# Fix Memory Leak
echo "Fixing memory leak..."
kubectl patch deployment memory-leak-app -n lab-scenarios --type='json' -p='[
  {"op": "replace", "path": "/spec/template/spec/containers/0/resources/limits/memory", "value": "512Mi"},
  {"op": "replace", "path": "/spec/template/spec/containers/0/resources/requests/memory", "value": "256Mi"}
]' 2>/dev/null

# Fix Crash Loop
echo "Fixing crash loop..."
kubectl patch deployment crash-loop-app -n lab-scenarios --type='json' -p='[
  {"op": "remove", "path": "/spec/template/spec/containers/0/livenessProbe"}
]' 2>/dev/null

# Fix CPU Hog
echo "Fixing CPU hog..."
kubectl patch deployment cpu-hog -n lab-scenarios --type='json' -p='[
  {"op": "replace", "path": "/spec/template/spec/containers/0/resources/limits/cpu", "value": "500m"},
  {"op": "replace", "path": "/spec/template/spec/containers/0/resources/requests/cpu", "value": "200m"}
]' 2>/dev/null

# Fix Database
echo "Fixing database connectivity..."
kubectl patch deployment db-issue-app -n lab-scenarios --type='json' -p='[
  {"op": "replace", "path": "/spec/template/spec/containers/0/env/0/value", "value": "password123"}
]' 2>/dev/null

# Fix Network
echo "Fixing network policy..."
kubectl delete networkpolicy restrictive-policy -n lab-scenarios 2>/dev/null

# Restart all deployments
echo "Restarting deployments..."
kubectl rollout restart deployment -n lab-scenarios --all 2>/dev/null

echo ""
echo "Waiting for pods to stabilize..."
sleep 10

echo ""
echo "=== Current Status ==="
kubectl get pods -n lab-scenarios
EOF

chmod +x quick-fix.sh
```

### 5.4 Complete Reset Script

```bash
cat <<'EOF' > reset-lab.sh
#!/bin/bash

echo "╔════════════════════════════════════════════════╗"
echo "║         Resetting Lab Environment             ║"
echo "╚════════════════════════════════════════════════╝"

read -p "This will delete all lab resources. Continue? (y/n): " confirm
if [ "$confirm" != "y" ]; then
    echo "Aborted."
    exit 0
fi

echo "Deleting all lab resources..."
kubectl delete namespace lab-scenarios --ignore-not-found

echo "Deleting cluster-wide resources..."
kubectl delete clusterrole remediator-role --ignore-not-found
kubectl delete clusterrolebinding remediator-binding --ignore-not-found

echo "Waiting for cleanup..."
sleep 5

echo ""
echo "✅ Lab reset complete!"
echo ""
echo "To recreate the lab:"
echo "1. Create namespace: kubectl create namespace lab-scenarios"
echo "2. Run setup: ./setup-lab.sh"
EOF

chmod +x reset-lab.sh
```

---

## Step 6: Create Complete Setup Script

```bash
cat <<'EOF' > setup-lab.sh
#!/bin/bash

echo "╔════════════════════════════════════════════════╗"
echo "║     DevOps Troubleshooting Lab Setup          ║"
echo "╚════════════════════════════════════════════════╝"
echo ""

# Check prerequisites
echo "Checking prerequisites..."
if ! command -v kubectl &> /dev/null; then
    echo "❌ kubectl not found. Please install kubectl."
    exit 1
fi

if ! kubectl get nodes &> /dev/null; then
    echo "❌ Cannot connect to Kubernetes cluster."
    exit 1
fi

echo "✅ Prerequisites met."

# Create namespace
echo ""
echo "Creating namespace..."
kubectl create namespace lab-scenarios 2>/dev/null || echo "Namespace already exists"

# Apply base resources
echo ""
echo "Applying base resources..."
cat <<'YAML' | kubectl apply -f -
apiVersion: v1
kind: ResourceQuota
metadata:
  name: lab-quota
  namespace: lab-scenarios
spec:
  hard:
    pods: "20"
    requests.cpu: "4"
    requests.memory: 4Gi
    limits.cpu: "8"
    limits.memory: 8Gi
---
apiVersion: v1
kind: LimitRange
metadata:
  name: lab-limits
  namespace: lab-scenarios
spec:
  limits:
  - max:
      cpu: "2"
      memory: 1Gi
    min:
      cpu: 100m
      memory: 128Mi
    default:
      cpu: 500m
      memory: 512Mi
    defaultRequest:
      cpu: 200m
      memory: 256Mi
    type: Container
YAML

# Deploy all scenarios
echo ""
echo "Deploying all scenarios..."

# Memory Leak
echo "  - Memory Leak Scenario"
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

# Disk Filler
echo "  - Disk Space Scenario"
kubectl apply -n lab-scenarios -f - <<YAML
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: disk-filler
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

# Crash Loop
echo "  - CrashLoopBackOff Scenario"
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
YAML

# CPU Hog
echo "  - CPU Exhaustion Scenario"
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

# Database
echo "  - Database Scenario"
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

# Network Policy
echo "  - Network Policy Scenario"
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

# Troubleshooting Tools
echo "  - Troubleshooting Tools"
kubectl apply -n lab-scenarios -f - <<YAML
apiVersion: apps/v1
kind: Deployment
metadata:
  name: troubleshooting-tools
spec:
  replicas: 1
  selector:
    matchLabels:
      app: troubleshooting-tools
  template:
    metadata:
      labels:
        app: troubleshooting-tools
    spec:
      containers:
      - name: tools
        image: nicolaka/netshoot
        command: ["sleep", "3600"]
---
apiVersion: v1
kind: Pod
metadata:
  name: debug-pod
spec:
  containers:
  - name: debug
    image: busybox
    command: ["/bin/sh", "-c"]
    args:
      - |
        echo "Debug pod ready"
        while true; do sleep 3600; done
  restartPolicy: Always
YAML

echo ""
echo "✅ Setup complete!"
echo ""
echo "📊 Check status: ./health-check.sh"
echo "🎮 Launch controller: ./lab-controller.sh"
echo "🔧 Quick fix: ./quick-fix.sh"
echo "🔄 Reset lab: ./reset-lab.sh"
EOF

chmod +x setup-lab.sh
```

---

## Step 7: Create Documentation

```bash
cat <<'EOF' > README.md
# DevOps Troubleshooting Lab

## Overview
A comprehensive Kubernetes-based lab for learning DevOps troubleshooting skills with real-world scenarios.

## Prerequisites
- Kubernetes cluster (v1.25+) with kubectl configured
- MetalLB or LoadBalancer
- Ingress-NGINX Controller

## Quick Start
```bash
# Setup the lab
./setup-lab.sh

# Check health
./health-check.sh

# Launch interactive controller
./lab-controller.sh
```

## Available Scenarios

| Scenario | Difficulty | Symptoms | Skills Learned |
|----------|------------|----------|----------------|
| Memory Leak | Medium | OOMKilled pods | Resource limits, memory profiling |
| Disk Space | Medium | DiskPressure nodes | Volume management, log rotation |
| CrashLoopBackOff | Easy | Pods restarting | Liveness probes, debugging |
| CPU Exhaustion | Easy | Pending pods | Resource quotas, autoscaling |
| Database | Medium | Connection errors | Secrets, connectivity testing |
| Network Policy | Hard | Connectivity issues | Network policies, troubleshooting |

## Commands

### Status Checks
```bash
# View all pods
kubectl get pods -n lab-scenarios

# Check resource usage
kubectl top pods -n lab-scenarios

# View events
kubectl get events -n lab-scenarios --sort-by='.lastTimestamp'

# Check resource quota
kubectl describe resourcequota lab-quota -n lab-scenarios
```

### Debugging
```bash
# Check pod logs
kubectl logs <pod-name> -n lab-scenarios

# Check pod details
kubectl describe pod <pod-name> -n lab-scenarios

# Access debug pod
kubectl exec -it debug-pod -n lab-scenarios -- sh

# Access netshoot tools
kubectl exec -it <tools-pod> -n lab-scenarios -- /bin/bash
```

### Fixing Issues
```bash
# Quick fix all scenarios
./quick-fix.sh

# Interactive fixes
./lab-controller.sh

# Reset lab
./reset-lab.sh
```

## Troubleshooting Guide

### Memory Leak
```bash
# Increase memory limit
kubectl patch deployment memory-leak-app -n lab-scenarios --type='json' -p='[
  {"op": "replace", "path": "/spec/template/spec/containers/0/resources/limits/memory", "value": "512Mi"}
]'
```

### CrashLoopBackOff
```bash
# Remove liveness probe
kubectl patch deployment crash-loop-app -n lab-scenarios --type='json' -p='[
  {"op": "remove", "path": "/spec/template/spec/containers/0/livenessProbe"}
]'
```

### CPU Exhaustion
```bash
# Reduce CPU limits
kubectl patch deployment cpu-hog -n lab-scenarios --type='json' -p='[
  {"op": "replace", "path": "/spec/template/spec/containers/0/resources/limits/cpu", "value": "500m"}
]'
```

### Database Issues
```bash
# Fix credentials
kubectl patch deployment db-issue-app -n lab-scenarios --type='json' -p='[
  {"op": "replace", "path": "/spec/template/spec/containers/0/env/0/value", "value": "password123"}
]'
```

### Network Issues
```bash
# Remove restrictive policy
kubectl delete networkpolicy restrictive-policy -n lab-scenarios
```

## Cleanup
```bash
./reset-lab.sh
```

## License
MIT
EOF
```

---

## Step 8: Final Setup Commands

```bash
# Make all scripts executable
chmod +x *.sh

# Create scenarios directory
mkdir -p scenarios

# Move YAML files to scenarios directory (optional)
# This helps keep things organized

# Run initial setup
./setup-lab.sh

# Verify everything is working
./health-check.sh

# Launch interactive controller
./lab-controller.sh
```

---

## Summary of Files Created

```
~/devops-lab/
├── setup-lab.sh              # Main setup script
├── lab-controller.sh         # Interactive controller
├── health-check.sh           # Health check utility
├── quick-fix.sh             # Quick fix all issues
├── reset-lab.sh             # Complete reset
├── README.md                # Documentation
└── scenarios/               # Scenario YAML files (optional)
    ├── memory-leak.yaml
    ├── disk-space.yaml
    ├── crash-loop.yaml
    ├── cpu-hog.yaml
    ├── database.yaml
    └── network-policy.yaml
```

## Usage Workflow

```bash
# 1. Initial setup
cd ~/devops-lab
./setup-lab.sh

# 2. Check lab health
./health-check.sh

# 3. Explore scenarios
kubectl get pods -n lab-scenarios

# 4. Interactive troubleshooting
./lab-controller.sh

# 5. Quick fixes
./quick-fix.sh

# 6. Reset and start over
./reset-lab.sh
```

This complete implementation guide provides everything needed to set up and run the DevOps troubleshooting lab, including all scenarios, management scripts, and documentation!