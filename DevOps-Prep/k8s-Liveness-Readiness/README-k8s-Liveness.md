## Lab Architecture Overview

Kubernetes cluster with MetalLB (my local setup) was already ready when I prompted for this lab to simulates real-world scenarios around livensess and readiness probes. With minior adjustments, you should be able to run this in any k8s/ k3s setup. 

If you are lazy to type, use the duplicate (heredoc) version instead; look for around line 500.

## Part 1: Foundation - Sample Application Setup

### 1.1 Deploy the Test Application

Create `app-deployment.yaml`:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: probe-demo-app
  labels:
    app: probe-demo
spec:
  replicas: 3
  selector:
    matchLabels:
      app: probe-demo
  template:
    metadata:
      labels:
        app: probe-demo
    spec:
      containers:
      - name: app
        image: nginx:alpine
        ports:
        - containerPort: 80
        # We'll add probes incrementally
```

Create service for external access:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: probe-demo-svc
spec:
  type: LoadBalancer
  selector:
    app: probe-demo
  ports:
  - port: 80
    targetPort: 80
```

Apply and test:
```bash
kubectl apply -f app-deployment.yaml
kubectl apply -f app-service.yaml
kubectl get svc probe-demo-svc
curl http://192.168.1.55  # Use your assigned IP
```

## Part 2: Liveness Probe - "Is the Container Alive?"

### 2.1 Basic Liveness Probe Implementation

Create `app-with-liveness.yaml`:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: liveness-demo
spec:
  replicas: 2
  selector:
    matchLabels:
      app: liveness-demo
  template:
    metadata:
      labels:
        app: liveness-demo
    spec:
      containers:
      - name: nginx
        image: nginx:alpine
        ports:
        - containerPort: 80
        livenessProbe:
          httpGet:
            path: /
            port: 80
          initialDelaySeconds: 15
          periodSeconds: 10
          timeoutSeconds: 5
          failureThreshold: 3
```

### 2.2 Liveness Probe Scenario - Simulated Failure

Create a custom image with a failing endpoint:

**Dockerfile**:
```dockerfile
FROM nginx:alpine
RUN apk add --no-cache curl bash
COPY health.sh /health.sh
RUN chmod +x /health.sh
COPY nginx.conf /etc/nginx/nginx.conf
CMD ["sh", "-c", "/health.sh & nginx -g 'daemon off;'"]
```

**health.sh**:
```bash
#!/bin/bash
COUNTER_FILE="/tmp/health_counter"
if [ ! -f "$COUNTER_FILE" ]; then
    echo 0 > $COUNTER_FILE
fi

while true; do
    COUNTER=$(cat $COUNTER_FILE)
    COUNTER=$((COUNTER + 1))
    echo $COUNTER > $COUNTER_FILE
    
    # Fail after 5 successful checks
    if [ $COUNTER -gt 15 ]; then
        # Simulate dead container by removing health endpoint
        rm -f /usr/share/nginx/html/health
    else
        # Create health endpoint
        echo "OK" > /usr/share/nginx/html/health
    fi
    sleep 10
done
```

Build and deploy:
```bash
docker build -t probe-test:latest .
kind load docker-image probe-test:latest  # If using kind
# Or push to your registry

kubectl apply -f app-with-liveness.yaml
```

### 2.3 Liveness Probe Interview Questions

**Q1: What happens when a liveness probe fails?**
```bash
# Watch pod restarts
kubectl get pods -w
kubectl describe pod <pod-name>
# Observe Restart Count increasing
```

**Q2: What's the difference between initialDelaySeconds and periodSeconds?**
- initialDelaySeconds: Time to wait before first probe
- periodSeconds: How often to check

**Q3: How do you choose probe thresholds?**
- failureThreshold: Number of failures before restart
- successThreshold: Number of successes before considered healthy (for readiness)

## Part 3: Readiness Probe - "Is the Container Ready for Traffic?"

### 3.1 Readiness Probe Implementation

Create `app-with-readiness.yaml`:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: readiness-demo
spec:
  replicas: 3
  selector:
    matchLabels:
      app: readiness-demo
  template:
    metadata:
      labels:
        app: readiness-demo
    spec:
      containers:
      - name: app
        image: nginx:alpine
        ports:
        - containerPort: 80
        readinessProbe:
          httpGet:
            path: /ready
            port: 80
          initialDelaySeconds: 5
          periodSeconds: 5
          failureThreshold: 3
          successThreshold: 2
```

### 3.2 Advanced Readiness Scenario

Create `readiness-with-init.yaml`:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: readiness-complex
spec:
  replicas: 2
  selector:
    matchLabels:
      app: readiness-complex
  template:
    metadata:
      labels:
        app: readiness-complex
    spec:
      initContainers:
      - name: init-db
        image: busybox
        command: ['sh', '-c', 'echo "Initializing..." && sleep 15']
      containers:
      - name: app
        image: nginx:alpine
        ports:
        - containerPort: 80
        readinessProbe:
          exec:
            command:
            - cat
            - /tmp/ready
          initialDelaySeconds: 10
          periodSeconds: 5
        lifecycle:
          postStart:
            exec:
              command:
              - sh
              - -c
              - 'echo "ready" > /tmp/ready && sleep 5'
```

### 3.3 Readiness Probe Interview Questions

**Q4: How does readiness probe affect pod status?**
```bash
# Check endpoint status
kubectl get endpoints readiness-demo
# Observe IPs added/removed based on readiness
```

**Q5: What's the difference between liveness and readiness?**
- Liveness: Restarts container (keeps app alive)
- Readiness: Removes from service endpoints (keeps traffic safe)

## Part 4: Combined Probes in Production

### 4.1 Complete Production Example

Create `production-app.yaml`:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: production-demo
spec:
  replicas: 3
  selector:
    matchLabels:
      app: production-demo
  template:
    metadata:
      labels:
        app: production-demo
    spec:
      containers:
      - name: app
        image: nginx:alpine
        ports:
        - containerPort: 80
        livenessProbe:
          httpGet:
            path: /healthz
            port: 80
          initialDelaySeconds: 30
          periodSeconds: 15
          timeoutSeconds: 5
          failureThreshold: 3
        readinessProbe:
          httpGet:
            path: /ready
            port: 80
          initialDelaySeconds: 5
          periodSeconds: 10
          timeoutSeconds: 3
          failureThreshold: 2
          successThreshold: 1
        startupProbe:  # Optional, for slow-starting apps
          httpGet:
            path: /startup
            port: 80
          initialDelaySeconds: 0
          periodSeconds: 5
          failureThreshold: 30
```

### 4.2 Testing Probe Scenarios

**Test 1: Liveness Failure**
```bash
# Create pod with failing liveness
kubectl run test-liveness --image=nginx --restart=Never -- \
  -- livenessProbe.exec.command=["sh","-c","exit 1"]

# Watch restart
kubectl get pod test-liveness -w
```

**Test 2: Readiness Failure**
```bash
# Service with readiness gate
kubectl create deployment test-readiness --image=nginx
kubectl expose deployment test-readiness --port=80
kubectl get endpoints test-readiness
# Scale and observe endpoints
kubectl scale deployment test-readiness --replicas=3
```

## Part 5: Advanced Interview Preparation

### 5.1 Performance Impact Questions

**Q6: What's the performance impact of probes?**
```bash
# Monitor probe overhead
kubectl top pods
kubectl logs <pod-name> | grep -i probe
```

**Q7: How do you tune probes for different workloads?**
- **API Services**: HTTP probes with 5-10s intervals
- **Data Processing**: Custom exec probes checking internal state
- **Message Consumers**: TCP probes checking port availability

### 5.2 Troubleshooting Scenarios

**Scenario 1: CrashLoopBackOff**
```bash
# Debug commands
kubectl describe pod <crashing-pod>
kubectl logs <crashing-pod> --previous
kubectl get events --field-selector involvedObject.name=<pod-name>
```

**Scenario 2: Endless Restarts**
```yaml
# Solution: Adjust probe thresholds
livenessProbe:
  failureThreshold: 5  # Increase from default 3
  periodSeconds: 30    # Increase check interval
```

### 5.3 Probe Best Practices

Create `best-practices.yaml`:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: best-practices-app
spec:
  replicas: 3
  strategy:
    rollingUpdate:
      maxSurge: 1
      maxUnavailable: 0
  template:
    spec:
      containers:
      - name: app
        image: nginx:alpine
        ports:
        - containerPort: 80
        livenessProbe:
          httpGet:
            path: /healthz
            port: 80
          initialDelaySeconds: 30    # Wait for app start
          periodSeconds: 20          # Don't check too often
          timeoutSeconds: 5          # Reasonable timeout
          failureThreshold: 3        # Allow some flakiness
        readinessProbe:
          httpGet:
            path: /ready
            port: 80
          initialDelaySeconds: 5     # Fast to become ready
          periodSeconds: 5           # Quick updates
          failureThreshold: 2        # Sensitive to unreadiness
          successThreshold: 1        # Ready immediately
```

## Part 6: Lab Exercises

### Exercise 1: Custom Probe Commands
Create a pod with exec probes that check for file existence:
```bash
kubectl run exec-probe --image=nginx --restart=Never -- \
  --readinessProbe.exec.command=["test","-f","/usr/share/nginx/html/index.html"]
```

### Exercise 2: Service Discovery Impact
```bash
# Watch service endpoints change
watch "kubectl get endpoints probe-demo-svc"

# Simulate pod unreadiness
kubectl exec <pod-name> -- rm /usr/share/nginx/html/index.html
# Observe endpoints remove pod
```

### Exercise 3: Probe Log Analysis
```bash
# Monitor probe logs
kubectl logs <pod-name> -f | grep -E "health|ready|probe"
```

## Part 7: Interview Questions Mastery

### Comprehensive Q&A:

**Q1: How do liveness probes affect rolling updates?**
- During rolling updates, pods with failing readiness probes aren't considered ready, slowing down the update
- This is GOOD - prevents serving traffic to unhealthy pods

**Q2: What's the startupProbe and why use it?**
- Used for applications with long startup times
- Disables liveness/readiness probes during startup
- Prevents premature restarts

**Q3: How do you handle external dependencies in probes?**
```yaml
readinessProbe:
  exec:
    command:
    - sh
    - -c
    - "nc -z database-service 5432 && nc -z redis-service 6379"
```

**Q4: Can probes affect pod scheduling?**
- Not directly, but readiness affects load balancing
- Liveness affects pod lifecycle

**Q5: How to test probe configurations in CI/CD?**
```bash
# In CI pipeline
kubectl run test-pod --image=test-app --dry-run=client -o yaml | \
  kubectl apply -f - && kubectl wait --for=condition=ready pod/test-pod --timeout=60s
```

## Part 8: Validation Commands

```bash
# Validate your understanding
kubectl get pods -o wide
kubectl describe pod <pod-name> | grep -A 10 "Probe"
kubectl get events --sort-by='.lastTimestamp' | tail -20

# Monitor probe effects
watch "kubectl get pods && echo '---' && kubectl get endpoints"
```

## Summary Script

Create `probe-lab-validator.sh`:

```bash
#!/bin/bash
echo "=== Probes Lab Validation ==="

echo -e "\n1. Pod Status:"
kubectl get pods -o wide

echo -e "\n2. Probe Configurations:"
kubectl describe pods | grep -A 5 "Probe"

echo -e "\n3. Restart Counts:"
kubectl get pods -o json | jq '.items[] | {name: .metadata.name, restarts: .status.containerStatuses[].restartCount}'

echo -e "\n4. Service Endpoints:"
kubectl get endpoints

echo -e "\n5. Recent Events:"
kubectl get events --sort-by='.lastTimestamp' | tail -10
```

This lab gives you hands-on experience with every aspect of Kubernetes probes while preparing you for deep interview questions on the topic. The MetalLB setup ensures you can test external access patterns, making the learning more comprehensive.

































# Kubernetes Probes Lab - Learning by Implementing (Duplicate)
This is the same lab as above in heredoc format for easy copy paste.
Useful if you plan to do this multiple iterations.

## Step 1: Setup Your Lab Environment

Copy and paste this to create your lab namespace:

```bash
cat << 'EOF' | kubectl apply -f -
apiVersion: v1
kind: Namespace
metadata:
  name: probe-lab
EOF

kubectl config set-context --current --namespace=probe-lab
```

**💡 Learning Point:** We're creating a separate namespace to keep our probe experiments isolated from other workloads.

---

## Step 2: Deploy Basic App (No Probes)

**Copy and paste this entire block:**

```bash
cat << 'EOF' | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app-no-probes
  namespace: probe-lab
  labels:
    app: no-probes
    experiment: baseline
spec:
  replicas: 2
  selector:
    matchLabels:
      app: no-probes
  template:
    metadata:
      labels:
        app: no-probes
    spec:
      containers:
      - name: nginx
        image: nginx:alpine
        ports:
        - containerPort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: app-no-probes-svc
  namespace: probe-lab
spec:
  type: LoadBalancer
  selector:
    app: no-probes
  ports:
  - port: 80
    targetPort: 80
EOF
```

**🔍 Observe:** 
```bash
# Check pod status
kubectl get pods -n probe-lab -o wide

# Get service IP
kubectl get svc -n probe-lab app-no-probes-svc

# Test access (use your IP)
curl http://192.168.1.55
```

---

## Step 3: Add Liveness Probe - "Keep It Alive"

**Copy and paste this entire block:**

```bash
cat << 'EOF' | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app-with-liveness
  namespace: probe-lab
  labels:
    app: liveness-test
    probe-type: liveness
spec:
  replicas: 2
  selector:
    matchLabels:
      app: liveness-test
  template:
    metadata:
      labels:
        app: liveness-test
    spec:
      containers:
      - name: nginx
        image: nginx:alpine
        ports:
        - containerPort: 80
        livenessProbe:
          httpGet:
            path: /
            port: 80
          initialDelaySeconds: 10
          periodSeconds: 10
          timeoutSeconds: 3
          failureThreshold: 3
---
apiVersion: v1
kind: Service
metadata:
  name: app-liveness-svc
  namespace: probe-lab
spec:
  type: LoadBalancer
  selector:
    app: liveness-test
  ports:
  - port: 80
    targetPort: 80
EOF
```

**🧪 Experiment - Simulate Container Freeze:**

```bash
# Get pod name
POD=$(kubectl get pods -n probe-lab -l app=liveness-test -o jsonpath='{.items[0].metadata.name}')
echo "Pod: $POD"

# Simulate frozen container (remove nginx process)
kubectl exec -it $POD -n probe-lab -- pkill nginx

# Watch what happens
kubectl get pods -n probe-lab -l app=liveness-test -w
```

**🤔 Think About:**
- Why does the pod restart?
- What would happen without liveness probe?
- How many times did it try before restarting?

---

## Step 4: Add Readiness Probe - "Ready for Traffic"

**Copy and paste this entire block:**

```bash
cat << 'EOF' | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app-with-readiness
  namespace: probe-lab
  labels:
    app: readiness-test
    probe-type: readiness
spec:
  replicas: 3
  selector:
    matchLabels:
      app: readiness-test
  template:
    metadata:
      labels:
        app: readiness-test
    spec:
      containers:
      - name: nginx
        image: nginx:alpine
        ports:
        - containerPort: 80
        readinessProbe:
          httpGet:
            path: /
            port: 80
          initialDelaySeconds: 5
          periodSeconds: 5
          timeoutSeconds: 2
          failureThreshold: 2
          successThreshold: 2
---
apiVersion: v1
kind: Service
metadata:
  name: app-readiness-svc
  namespace: probe-lab
spec:
  type: LoadBalancer
  selector:
    app: readiness-test
  ports:
  - port: 80
    targetPort: 80
EOF
```

**🧪 Experiment - Remove from Service:**

```bash
# Watch endpoints in real-time
kubectl get endpoints -n probe-lab app-readiness-svc -w &

# Kill one pod's nginx
POD=$(kubectl get pods -n probe-lab -l app=readiness-test -o jsonpath='{.items[0].metadata.name}')
kubectl exec -it $POD -n probe-lab -- rm -rf /usr/share/nginx/html

# Check endpoint status
kubectl get endpoints -n probe-lab app-readiness-svc
```

---

## Step 5: Both Probes Together - Production Style

**Copy and paste this entire block:**

```bash
cat << 'EOF' | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app-both-probes
  namespace: probe-lab
  labels:
    app: both-probes
    probe-type: combined
spec:
  replicas: 3
  strategy:
    rollingUpdate:
      maxSurge: 1
      maxUnavailable: 0
  selector:
    matchLabels:
      app: both-probes
  template:
    metadata:
      labels:
        app: both-probes
    spec:
      containers:
      - name: nginx
        image: nginx:alpine
        ports:
        - containerPort: 80
        livenessProbe:
          httpGet:
            path: /healthz
            port: 80
          initialDelaySeconds: 30
          periodSeconds: 15
          timeoutSeconds: 5
          failureThreshold: 3
        readinessProbe:
          httpGet:
            path: /ready
            port: 80
          initialDelaySeconds: 5
          periodSeconds: 10
          timeoutSeconds: 3
          failureThreshold: 2
          successThreshold: 1
---
apiVersion: v1
kind: Service
metadata:
  name: app-both-probes-svc
  namespace: probe-lab
spec:
  type: LoadBalancer
  selector:
    app: both-probes
  ports:
  - port: 80
    targetPort: 80
EOF
```

**🔍 Investigate:**
```bash
# Check probe configuration
kubectl describe pod -l app=both-probes -n probe-lab | grep -A 10 "Probe"

# Watch rollout behavior
kubectl rollout status deployment/app-both-probes -n probe-lab
```

---

## Step 6: Custom Exec Probe - Advanced

**Copy and paste this entire block:**

```bash
cat << 'EOF' | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: exec-probe-demo
  namespace: probe-lab
  labels:
    experiment: exec-probe
spec:
  containers:
  - name: app
    image: alpine
    command:
    - /bin/sh
    - -c
    - |
      touch /tmp/healthy
      while true; do
        if [ -f /tmp/healthy ]; then
          echo "healthy" > /dev/null
        else
          echo "unhealthy" > /dev/null
        fi
        sleep 5
      done
    livenessProbe:
      exec:
        command:
        - test
        - -f
        - /tmp/healthy
      initialDelaySeconds: 5
      periodSeconds: 10
EOF
```

**🧪 Experiment - Make It Fail:**
```bash
# Watch pod status
kubectl get pod exec-probe-demo -n probe-lab -w &

# Make probe fail
kubectl exec -it exec-probe-demo -n probe-lab -- rm -f /tmp/healthy

# Observe the restart
kubectl get pod exec-probe-demo -n probe-lab
```

---

## Step 7: TCP Socket Probe

**Copy and paste this entire block:**

```bash
cat << 'EOF' | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app-tcp-probe
  namespace: probe-lab
  labels:
    app: tcp-test
    probe-type: tcp
spec:
  replicas: 2
  selector:
    matchLabels:
      app: tcp-test
  template:
    metadata:
      labels:
        app: tcp-test
    spec:
      containers:
      - name: nginx
        image: nginx:alpine
        ports:
        - containerPort: 80
        readinessProbe:
          tcpSocket:
            port: 80
          initialDelaySeconds: 5
          periodSeconds: 10
        livenessProbe:
          tcpSocket:
            port: 80
          initialDelaySeconds: 15
          periodSeconds: 20
EOF
```

**🔍 Observe:**
```bash
# Check probe details
kubectl describe pod -l app=tcp-test -n probe-lab | grep -A 5 "Probe"

# Simulate port closed
POD=$(kubectl get pods -n probe-lab -l app=tcp-test -o jsonpath='{.items[0].metadata.name}')
kubectl exec -it $POD -n probe-lab -- pkill nginx
```

---

## Step 8: Startup Probe - For Slow Startups

**Copy and paste this entire block:**

```bash
cat << 'EOF' | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app-startup-probe
  namespace: probe-lab
  labels:
    app: startup-test
    probe-type: startup
spec:
  replicas: 2
  selector:
    matchLabels:
      app: startup-test
  template:
    metadata:
      labels:
        app: startup-test
    spec:
      containers:
      - name: app
        image: nginx:alpine
        ports:
        - containerPort: 80
        startupProbe:
          httpGet:
            path: /
            port: 80
          initialDelaySeconds: 0
          periodSeconds: 5
          failureThreshold: 30
        livenessProbe:
          httpGet:
            path: /
            port: 80
          initialDelaySeconds: 10
          periodSeconds: 10
EOF
```

**💡 Learning:**
```bash
# Check startup probe
kubectl describe pod -l app=startup-test -n probe-lab | grep -A 5 "Startup"

# See difference - startup probe has high failureThreshold
kubectl get pod -l app=startup-test -n probe-lab -o yaml | grep -A 5 "startupProbe"
```

---

## Step 9: Rolling Update With Probes

**Copy and paste this entire block:**

```bash
cat << 'EOF' | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app-rolling-update
  namespace: probe-lab
spec:
  replicas: 4
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1
      maxUnavailable: 0
  selector:
    matchLabels:
      app: rolling-test
  template:
    metadata:
      labels:
        app: rolling-test
    spec:
      containers:
      - name: nginx
        image: nginx:alpine
        ports:
        - containerPort: 80
        readinessProbe:
          httpGet:
            path: /
            port: 80
          initialDelaySeconds: 5
          periodSeconds: 3
          failureThreshold: 2
---
apiVersion: v1
kind: Service
metadata:
  name: app-rolling-svc
  namespace: probe-lab
spec:
  type: LoadBalancer
  selector:
    app: rolling-test
  ports:
  - port: 80
    targetPort: 80
EOF
```

**🧪 Test Rolling Update:**
```bash
# Watch endpoints
kubectl get endpoints -n probe-lab app-rolling-svc -w &

# Update image
kubectl set image deployment/app-rolling-update -n probe-lab nginx=nginx:1.19

# Monitor rollout
kubectl rollout status deployment/app-rolling-update -n probe-lab

# View rollout history
kubectl rollout history deployment/app-rolling-update -n probe-lab
```

---

## Step 10: Complete Production Example

**Copy and paste this entire block:**

```bash
cat << 'EOF' | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: production-app
  namespace: probe-lab
  annotations:
    description: "Production-ready app with all probes"
spec:
  replicas: 3
  strategy:
    rollingUpdate:
      maxSurge: 1
      maxUnavailable: 0
  selector:
    matchLabels:
      app: production-app
  template:
    metadata:
      labels:
        app: production-app
      annotations:
        prometheus.io/probe: "true"
    spec:
      containers:
      - name: app
        image: nginx:alpine
        ports:
        - name: http
          containerPort: 80
        - name: metrics
          containerPort: 8080
        env:
        - name: POD_NAME
          valueFrom:
            fieldRef:
              fieldPath: metadata.name
        livenessProbe:
          httpGet:
            path: /healthz
            port: 80
            httpHeaders:
            - name: X-Custom-Header
              value: liveness
          initialDelaySeconds: 30
          periodSeconds: 20
          timeoutSeconds: 5
          failureThreshold: 3
          successThreshold: 1
        readinessProbe:
          httpGet:
            path: /ready
            port: 80
            httpHeaders:
            - name: X-Custom-Header
              value: readiness
          initialDelaySeconds: 5
          periodSeconds: 10
          timeoutSeconds: 3
          failureThreshold: 2
          successThreshold: 1
        startupProbe:
          httpGet:
            path: /startup
            port: 80
          initialDelaySeconds: 0
          periodSeconds: 5
          failureThreshold: 30
        resources:
          requests:
            memory: "64Mi"
            cpu: "100m"
          limits:
            memory: "128Mi"
            cpu: "200m"
---
apiVersion: v1
kind: Service
metadata:
  name: production-app-svc
  namespace: probe-lab
spec:
  type: LoadBalancer
  selector:
    app: production-app
  ports:
  - name: http
    port: 80
    targetPort: 80
  - name: metrics
    port: 8080
    targetPort: 8080
EOF
```

**📊 Monitoring Production:**
```bash
# Full pod details
kubectl describe pod -l app=production-app -n probe-lab

# Check service endpoints
kubectl get endpoints -n probe-lab production-app-svc

# Test load balancer
kubectl get svc -n probe-lab production-app-svc

# Monitor everything
kubectl get all -n probe-lab
```

---

## Interview Questions & Hands-On Tasks

Copy and paste this to get your interview prep:

```bash
cat << 'EOF'
=========================================
KUBERNETES PROBES - INTERVIEW PREP
=========================================

🔴 TASK 1: Liveness vs Readiness
Try to explain:
- Which probe causes restart?
- Which probe removes from service?
- When would you use each?

🔴 TASK 2: Probe Types
For each scenario, choose the right probe:
- Check if database connection exists
- Verify application is responding to HTTP
- Check if a specific file exists

🔴 TASK 3: Configuration Parameters
What do these mean?
- initialDelaySeconds: ___
- periodSeconds: ___
- failureThreshold: ___
- successThreshold: ___

🔴 TASK 4: Troubleshooting
Fix these scenarios:
1. Pod keeps restarting every 30 seconds
2. New pods not receiving traffic
3. Application takes 2 minutes to start

🔴 TASK 5: Production Best Practices
What's wrong with:
livenessProbe:
  httpGet:
    path: /heavy-endpoint
    port: 80
  periodSeconds: 1
  timeoutSeconds: 30
  failureThreshold: 1

=========================================
HANDS-ON EXERCISES:
=========================================

1. Observe liveness restart:
   kubectl get pods -n probe-lab -w &
   kubectl exec -it <pod-name> -n probe-lab -- pkill nginx

2. Test readiness removal:
   kubectl get endpoints -n probe-lab -w &
   kubectl exec -it <pod-name> -n probe-lab -- rm -rf /usr/share/nginx/html

3. Change probe parameters:
   kubectl edit deployment app-with-liveness -n probe-lab
   # Change periodSeconds to 5 and observe

4. Rolling update with probe:
   kubectl set image deployment/app-both-probes -n probe-lab nginx=nginx:1.19
   kubectl rollout status deployment/app-both-probes -n probe-lab

5. Debug pod failure:
   kubectl describe pod <pod-name> -n probe-lab
   kubectl logs <pod-name> -n probe-lab --previous

=========================================
QUICK REFERENCE:
=========================================

# Check probe configuration
kubectl describe pod <pod> -n probe-lab | grep -A 10 "Probe"

# Watch pod restarts
kubectl get pods -n probe-lab -w

# Check service endpoints
kubectl get endpoints -n probe-lab

# View events
kubectl get events -n probe-lab --sort-by='.lastTimestamp'

# Clean everything
kubectl delete namespace probe-lab
EOF
```

---

## Final Cleanup

When you're done learning:

```bash
cat << 'EOF' | kubectl delete -f -
apiVersion: v1
kind: Namespace
metadata:
  name: probe-lab
EOF
```

---

## Learning Path Summary

| Step | Topic | Key Learning |
|------|-------|--------------|
| 1-2 | Baseline | Understanding default behavior |
| 3 | Liveness | Container resurrection |
| 4 | Readiness | Traffic management |
| 5 | Combined | Production patterns |
| 6 | Exec | Custom logic probes |
| 7 | TCP | Network-level checks |
| 8 | Startup | Slow application handling |
| 9 | Rolling Update | Deployment safety |
| 10 | Production | Complete configuration |

**💡 Pro Tip:** Each step builds on the previous. Run each block, observe behavior, and try to break things intentionally. That's how you truly learn probes!


# DevOps Probes Lab: Liveness & Readiness Deep Dive (for interviews)

See below **interview‑ready breakdown** of **all scenarios + benefits** of **liveness** and **readiness** probes.


---

# 🧩 **Liveness Probe — Scenarios & Benefits**
Liveness = *“Is the container alive?”*  
If it fails → **Kubernetes restarts the container automatically**.

---

## ⭐ **Scenario 1 — Application Crash / Deadlock**
Your app crashes, hangs, or gets stuck in an infinite loop.

**What happens:**  
- Liveness probe fails  
- Kubelet kills the container  
- Pod restarts automatically

**Benefit:**  
- **Self‑healing**  
- No manual intervention  
- Prevents long outages

---

## ⭐ **Scenario 2 — App Running but Internal Logic Broken**
Example:  
- Thread pool exhausted  
- DB connection pool stuck  
- Internal state corrupted

App still responds, but incorrectly.

**Benefit:**  
- Liveness probe detects “bad health”  
- Restarts container → resets internal state  
- Restores service automatically

---

## ⭐ **Scenario 3 — Memory Leak / Resource Exhaustion**
App becomes unresponsive due to memory leak or CPU starvation.

**Benefit:**  
- Liveness probe catches unresponsiveness  
- Restarts container before full node meltdown  
- Protects cluster stability

---

## ⭐ **Scenario 4 — Misconfigured Startup**
App starts but fails to initialize properly.

**Benefit:**  
- Liveness probe prevents zombie pods  
- Ensures only healthy pods remain running

---

# 🎯 **Liveness Probe — Summary of Benefits**
- **Automatic recovery** from crashes  
- **No manual restarts** needed  
- **Prevents cascading failures**  
- **Keeps pods healthy long‑term**  
- **Improves reliability & uptime**

---

# 🧩 **Readiness Probe — Scenarios & Benefits**
Readiness = *“Can this pod serve traffic?”*  
If it fails → **Pod is removed from Service endpoints**.

---

## ⭐ **Scenario 1 — Slow Startup / Warm‑Up**
App needs time to:
- load configs  
- initialize DB connections  
- warm caches  
- run migrations

**Benefit:**  
- Pod stays **NotReady**  
- No traffic sent until fully ready  
- Prevents 503 errors during startup

---

## ⭐ **Scenario 2 — Rolling Updates**
During deployment:
- New pods start  
- Old pods terminate

**Benefit:**  
- New pods only receive traffic when ready  
- Old pods stop receiving traffic before shutdown  
- **Zero‑downtime deployments**

---

## ⭐ **Scenario 3 — Temporary Overload**
App becomes overloaded:
- high latency  
- queue backlog  
- dependency slowdown

Your readiness probe can detect this.

**Benefit:**  
- Pod marked **NotReady**  
- Removed from load balancer  
- Traffic routed to healthy pods  
- Prevents cascading failures

---

## ⭐ **Scenario 4 — Dependency Failure**
Example:
- DB down  
- Redis unreachable  
- API dependency offline

Your readiness probe checks dependency health.

**Benefit:**  
- Pod stops receiving traffic  
- Prevents bad responses  
- Allows graceful degradation

---

## ⭐ **Scenario 5 — Graceful Shutdown**
When pod is terminating:
- readinessProbe fails automatically  
- pod removed from Service endpoints

**Benefit:**  
- No traffic sent to terminating pods  
- Prevents dropped requests  
- Enables graceful shutdown

---

# 🎯 **Readiness Probe — Summary of Benefits**
- **No bad traffic** during startup  
- **Zero‑downtime deployments**  
- **Protects users from errors**  
- **Handles overload gracefully**  
- **Ensures dependency‑aware routing**  
- **Supports graceful shutdown**

---

# 🧠 **Combined Benefits (Liveness + Readiness Together)**  

> “Liveness probes provide self‑healing by restarting unhealthy containers.  
> Readiness probes ensure only healthy pods receive traffic.  
> Together, they guarantee high availability, graceful rollouts, and resilient workloads.”