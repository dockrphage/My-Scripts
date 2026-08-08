# Kubernetes Probes Lab - KillerCoda Sandbox Edition

KillerCoda [https://killercoda.com/playgrounds/scenario/cka] gives a browser-based Kubernetes cluster with no local setup required.
This lab explores to learn-by-implimentation k8s liveness and readiness probe.

## Quick Start: Launch Your Lab Environment

Copy and paste each block sequentially into the Killercoda terminal. The cluster is ready to go with `kubectl` pre-installed.

---

## Step 1: Create Your Lab Namespace

```bash
cat << 'EOF' | kubectl apply -f -
apiVersion: v1
kind: Namespace
metadata:
  name: probe-lab
EOF

kubectl config set-context --current --namespace=probe-lab
```

**💡 Learning Point:** Isolating our experiments in a separate namespace keeps things clean and makes cleanup easy. In production, namespaces help separate environments (dev, staging, prod) or teams.

---

## Step 2: Deploy Baseline App (No Probes)

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
  type: ClusterIP
  selector:
    app: no-probes
  ports:
  - port: 80
    targetPort: 80
EOF
```

**🔍 Observe:**
```bash
kubectl get pods -n probe-lab -o wide
kubectl get svc -n probe-lab
```

**🤔 Think About:**
- What happens if the nginx process inside the container crashes?
- How would Kubernetes know the application is unhealthy?
- Can users access the application if the container is running but the app is broken?

---

## Step 3: Add Liveness Probe - "Keep It Alive"

Liveness probes tell Kubernetes when to restart a container. If the probe fails, Kubernetes kills the container and creates a new one .

**Copy and paste:**

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
EOF
```

**🧪 Experiment - Simulate Container Freeze:**

```bash
# Get pod name
POD=$(kubectl get pods -n probe-lab -l app=liveness-test -o jsonpath='{.items[0].metadata.name}')
echo "Pod: $POD"

# Simulate frozen container (kill nginx process)
kubectl exec -it $POD -n probe-lab -- pkill nginx

# Watch what happens
kubectl get pods -n probe-lab -l app=liveness-test -w
```

**📊 Check the Results:**
```bash
kubectl describe pod $POD -n probe-lab | grep -A 10 "Events"
kubectl get pod $POD -n probe-lab -o yaml | grep -A 5 "restartPolicy"
```

**💡 What You Learned:**
- Liveness probe detected the failure when nginx stopped responding
- Kubernetes restarted the container automatically
- Without the liveness probe, the pod would show "Running" but serve no traffic 

---

## Step 4: Add Readiness Probe - "Ready for Traffic"

Readiness probes tell Kubernetes when a container is ready to accept traffic. If it fails, the pod is removed from the service endpoints .

**Copy and paste:**

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
  type: ClusterIP
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

# Check endpoint status - the pod should be removed!
kubectl get endpoints -n probe-lab app-readiness-svc
```

**📊 Check What Happened:**
```bash
kubectl describe pod $POD -n probe-lab | grep -A 10 "Events"
```

**💡 What You Learned:**
- Readiness probe detected the application failure
- Pod was removed from the service endpoints
- Traffic continues to flow to healthy pods only
- The pod is NOT restarted (unlike liveness) - it just sits in "Running" state but receives no traffic 

---

## Step 5: Both Probes Together - Production Style

In production, you typically use both probes to handle different scenarios .

**Copy and paste:**

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
  type: ClusterIP
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

Some applications don't have HTTP endpoints. For these, you can use an exec probe that runs a command inside the container .

**Copy and paste:**

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

## Step 7: Startup Probe - For Slow Startups

Startup probes are specifically for applications that take a long time to start. They disable liveness and readiness probes until the startup probe succeeds .

**Copy and paste:**

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
# Check startup probe configuration
kubectl describe pod -l app=startup-test -n probe-lab | grep -A 5 "Startup"

# Notice the high failureThreshold - this gives the app time to start
kubectl get pod -l app=startup-test -n probe-lab -o yaml | grep -A 5 "startupProbe"
```

---

## Step 8: Rolling Update With Probes

Probes are crucial during rolling updates. They ensure new pods are ready before they receive traffic .

**Copy and paste:**

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
  type: ClusterIP
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

## Step 9: TCP Socket Probe

For services that listen on TCP ports, you can use a TCP socket probe.

**Copy and paste:**

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

---

## Step 10: Troubleshooting Probe Failures

When probes fail, Kubernetes provides detailed events to help you debug .

**Common Scenarios:**

### Scenario 1: CrashLoopBackOff

```bash
# Create a pod with a failing liveness probe
cat << 'EOF' | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: crash-loop-pod
  namespace: probe-lab
spec:
  containers:
  - name: test
    image: busybox
    command: ["sh", "-c", "touch /tmp/healthy; sleep 5; rm -f /tmp/healthy; sleep 3600"]
    livenessProbe:
      exec:
        command:
        - cat
        - /tmp/healthy
      initialDelaySeconds: 5
      periodSeconds: 5
EOF

# Watch what happens
kubectl get pod crash-loop-pod -n probe-lab -w
```

### Debug Commands:

```bash
# Check pod status
kubectl get pods -n probe-lab

# View detailed pod info
kubectl describe pod <pod-name> -n probe-lab

# Check logs (especially helpful for exec probes)
kubectl logs <pod-name> -n probe-lab

# Check previous container logs if restarted
kubectl logs <pod-name> -n probe-lab --previous

# View events
kubectl get events -n probe-lab --sort-by='.lastTimestamp'
```

---

## Interview Questions & Answers

```bash
cat << 'EOF'
=========================================
KUBERNETES PROBES - INTERVIEW Q&A
=========================================

Q1: What's the difference between liveness and readiness probes?
A1: Liveness determines if the container is alive. Failure = container restart.
    Readiness determines if the container can serve traffic. Failure = removed from service endpoints .

Q2: What are the three probe types?
A2: HTTP GET, TCP Socket, and Exec command probes .

Q3: What is a startup probe and when would you use it?
A3: Startup probes are for slow-starting applications. They disable liveness/readiness 
    probes until the app is fully started, preventing premature restarts .

Q4: What happens during rolling updates with probes?
A4: New pods must pass readiness probes before receiving traffic. 
    Old pods continue serving until new ones are ready. This prevents downtime .

Q5: What probe configuration parameters can you tune?
A5: initialDelaySeconds (first probe delay), periodSeconds (check frequency), 
    timeoutSeconds (probe timeout), failureThreshold (consecutive failures before action), 
    successThreshold (consecutive successes required) .

Q6: How do you troubleshoot probe failures?
A6: Use kubectl describe pod to see events, kubectl logs to check application logs, 
    and kubectl logs --previous to see logs from crashed containers .

Q7: Can probes impact performance?
A7: Yes, set reasonable intervals (periodSeconds) and avoid heavy operations in probes. 
    Too frequent checks can add overhead .

=========================================
HANDS-ON EXERCISES:
=========================================

1. Observe liveness restart:
   kubectl get pods -n probe-lab -w &
   kubectl exec -it <pod-name> -n probe-lab -- pkill nginx

2. Test readiness removal:
   kubectl get endpoints -n probe-lab -w &
   kubectl exec -it <pod-name> -n probe-lab -- rm -rf /usr/share/nginx/html

3. Debug pod failure:
   kubectl describe pod <pod-name> -n probe-lab
   kubectl logs <pod-name> -n probe-lab --previous

4. Modify probe parameters:
   kubectl edit deployment app-with-liveness -n probe-lab
   # Change periodSeconds and observe behavior

5. Force CrashLoopBackOff:
   kubectl edit deployment app-with-liveness -n probe-lab
   # Change liveness path to "/non-existent" and watch restarts

=========================================
QUICK REFERENCE COMMANDS:
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
kubectl delete namespace probe-lab
```

---

## Summary: What You've Learned

| Step | Topic | Key Takeaway |
|------|-------|--------------|
| 1-2 | Baseline | Pods can be "Running" but application broken |
| 3 | Liveness Probe | Detects crashes, restarts containers |
| 4 | Readiness Probe | Removes pods from service when unhealthy |
| 5 | Combined Probes | Production-ready configuration |
| 6 | Exec Probe | Custom health check logic |
| 7 | Startup Probe | Handles slow-starting applications |
| 8 | Rolling Update | Probes ensure zero-downtime deployments |
| 9 | TCP Probe | Check TCP port availability |
| 10 | Troubleshooting | Debug probe failures effectively |

**🎯 Key Interview Takeaway:** Liveness probes keep your application alive by restarting failed containers. Readiness probes keep your service reliable by removing unhealthy pods from traffic. Together, they make your Kubernetes applications self-healing and resilient .


===================

# 🚨 CRASHLOOPBACKOFF - PERFECT INTERVIEW SCENARIO!

This is **exactly** what you'll face in production and interviews! Let's systematically debug and fix this.

## What's Happening?

```
Readiness probe failed: 404 (endpoint doesn't exist)
Liveness probe failed: 404 (endpoint doesn't exist)
→ Container killed and restarted
→ CrashLoopBackOff
```

The probes are looking for `/healthz` and `/ready` but nginx doesn't have these files!

---

## Step 1: Stop the Madness First!

**Copy and paste - scale down to stop the restarts:**

```bash
# Stop the restart loop
kubectl scale deployment app-both-probes -n probe-lab --replicas=0

# Verify it's stopped
kubectl get pods -n probe-lab -l app=both-probes
```

---

## Step 2: Create the Health Endpoints (The Fix)

**Copy and paste - update the deployment with health endpoints:**

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
        # STARTUP COMMAND: Create health endpoints before nginx starts
        command: ["/bin/sh"]
        args:
        - -c
        - |
          # Create health check files
          mkdir -p /usr/share/nginx/html
          echo "OK" > /usr/share/nginx/html/healthz
          echo "Ready" > /usr/share/nginx/html/ready
          echo "Starting nginx with health endpoints..."
          # Start nginx
          nginx -g "daemon off;"
        livenessProbe:
          httpGet:
            path: /healthz
            port: 80
          initialDelaySeconds: 10
          periodSeconds: 10
          timeoutSeconds: 5
          failureThreshold: 3
        readinessProbe:
          httpGet:
            path: /ready
            port: 80
          initialDelaySeconds: 5
          periodSeconds: 5
          timeoutSeconds: 3
          failureThreshold: 2
          successThreshold: 1
EOF
```

---

## Step 3: Scale Back Up

**Copy and paste:**

```bash
# Scale back to 3 replicas
kubectl scale deployment app-both-probes -n probe-lab --replicas=3

# Watch it come up!
kubectl get pods -n probe-lab -l app=both-probes -w
```

**✅ It should now show 3/3 READY!**

---

## Step 4: Verify It's Working

**Copy and paste:**

```bash
# Check all pods are ready
kubectl get pods -n probe-lab -l app=both-probes

# Check endpoints are populated
kubectl get endpoints -n probe-lab app-both-probes-svc

# Test the health endpoints directly
POD=$(kubectl get pods -n probe-lab -l app=both-probes -o jsonpath='{.items[0].metadata.name}')
kubectl exec -it $POD -n probe-lab -- curl -s http://localhost/healthz
kubectl exec -it $POD -n probe-lab -- curl -s http://localhost/ready

# Check probe status
kubectl describe pod $POD -n probe-lab | grep -A 5 "Probe"
```

---

## Step 5: Create a Service to Test

**Copy and paste:**

```bash
cat << 'EOF' | kubectl apply -f -
apiVersion: v1
kind: Service
metadata:
  name: app-both-probes-svc
  namespace: probe-lab
spec:
  type: NodePort
  selector:
    app: both-probes
  ports:
  - port: 80
    targetPort: 80
    nodePort: 30080
EOF

# Get node IP and test
kubectl get nodes -o wide
curl http://<node-ip>:30080/healthz
```

---

## Step 6: Break It on Purpose! (Learning Exercise)

**Test 1: Break Liveness Probe**

```bash
# Get a pod
POD=$(kubectl get pods -n probe-lab -l app=both-probes -o jsonpath='{.items[0].metadata.name}')

# Watch pod status
kubectl get pods -n probe-lab -l app=both-probes -w &

# Delete the healthz file (this will cause liveness failure)
kubectl exec -it $POD -n probe-lab -- rm -f /usr/share/nginx/html/healthz

# After 30 seconds, the pod will restart
kubectl get pods -n probe-lab -l app=both-probes
```

**Test 2: Break Readiness Probe**

```bash
# Get a pod
POD=$(kubectl get pods -n probe-lab -l app=both-probes -o jsonpath='{.items[0].metadata.name}')

# Watch endpoints
kubectl get endpoints -n probe-lab app-both-probes-svc -w &

# Delete the ready file (this will remove from service)
kubectl exec -it $POD -n probe-lab -- rm -f /usr/share/nginx/html/ready

# Check endpoints - pod should be removed!
kubectl get endpoints -n probe-lab app-both-probes-svc
```

---

## Step 7: Alternative Fix - Use TCP Probes

If your app doesn't have HTTP endpoints, use TCP probes:

**Copy and paste:**

```bash
cat << 'EOF' | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app-tcp-fix
  namespace: probe-lab
  labels:
    app: tcp-fix
spec:
  replicas: 2
  selector:
    matchLabels:
      app: tcp-fix
  template:
    metadata:
      labels:
        app: tcp-fix
    spec:
      containers:
      - name: nginx
        image: nginx:alpine
        ports:
        - containerPort: 80
        livenessProbe:
          tcpSocket:
            port: 80
          initialDelaySeconds: 10
          periodSeconds: 10
          failureThreshold: 3
        readinessProbe:
          tcpSocket:
            port: 80
          initialDelaySeconds: 5
          periodSeconds: 5
          failureThreshold: 2
---
apiVersion: v1
kind: Service
metadata:
  name: app-tcp-fix-svc
  namespace: probe-lab
spec:
  type: NodePort
  selector:
    app: tcp-fix
  ports:
  - port: 80
    targetPort: 80
    nodePort: 30081
EOF
```

---

## Step 8: Interview Questions - CrashLoopBackOff

**Copy and paste to review:**

```bash
cat << 'EOF'

=========================================
CRASHLOOPBACKOFF - INTERVIEW Q&A
=========================================

Q: What is CrashLoopBackOff?
A: A state where a pod keeps crashing and Kubernetes is backing off 
   with exponential delays between restart attempts.

Q: What causes CrashLoopBackOff?
A: Common causes:
   1. Liveness probe failure (404, timeout, etc.)
   2. Application crashes on startup
   3. Missing dependencies (configmaps, secrets)
   4. Resource limits (OOMKilled)

Q: How do you debug CrashLoopBackOff?
A: Step-by-step:
   1. kubectl describe pod <pod> - look at Events
   2. kubectl logs <pod> - check application logs
   3. kubectl logs <pod> --previous - check previous container logs
   4. Check if probes are correctly configured

Q: In our case, what was the problem?
A: Liveness and readiness probes were looking for /healthz and /ready,
   but nginx doesn't serve those by default. The probe failed with 404,
   causing the container to be killed and restarted repeatedly.

Q: How did we fix it?
A: Two options:
   1. Created the health endpoints in the container
   2. Changed to TCP probes instead of HTTP

Q: What's the difference between CrashLoopBackOff and Pending?
A: CrashLoopBackOff = container starts then crashes
   Pending = container hasn't started yet (scheduling issues)

Q: What command shows why a pod crashed?
A: kubectl logs <pod> --previous

=========================================
QUICK FIX COMMANDS
=========================================

# 1. Stop the restarts
kubectl scale deployment <deployment> -n <namespace> --replicas=0

# 2. Fix the issue (create endpoints or adjust probes)
kubectl edit deployment <deployment> -n <namespace>

# 3. Scale back up
kubectl scale deployment <deployment> -n <namespace> --replicas=3

# 4. Watch recovery
kubectl get pods -n <namespace> -w

=========================================
EOF
```

---

## Step 9: The "Real" Production Fix

In production, you'd have proper health endpoints in your application code:

**Example Go app with health endpoints:**
```go
package main

import (
    "fmt"
    "net/http"
)

func main() {
    http.HandleFunc("/healthz", func(w http.ResponseWriter, r *http.Request) {
        w.WriteHeader(http.StatusOK)
        fmt.Fprintf(w, "OK")
    })
    
    http.HandleFunc("/ready", func(w http.ResponseWriter, r *http.Request) {
        // Check database, external services, etc.
        if isAppReady() {
            w.WriteHeader(http.StatusOK)
            fmt.Fprintf(w, "Ready")
        } else {
            w.WriteHeader(http.StatusServiceUnavailable)
        }
    })
    
    http.ListenAndServe(":8080", nil)
}
```

---

## Step 10: Final Cleanup

```bash
# Clean up everything
kubectl delete namespace probe-lab

# Or just the problem deployment
kubectl delete deployment app-both-probes -n probe-lab
```

---

## 🎯 Key Takeaways

| Symptom | Root Cause | Solution |
|---------|------------|----------|
| **CrashLoopBackOff** | Liveness probe failing | Fix probe endpoint or application |
| **0/3 READY** | Readiness probe failing | Fix readiness endpoint |
| **404 errors** | Endpoint doesn't exist | Create endpoint or adjust probe path |
| **Container restarts** | Liveness failure | Fix the app or relax probe config |

**💡 Pro Interview Tip:**
> "When I see CrashLoopBackOff, I always check `kubectl describe pod` first to see the Events. If I see probe failures, I check if the health endpoints exist. If it's a new deployment, I often add the health endpoints in the container's startup command as a quick fix."

**✅ YOUR FIX IS COMPLETE!** The deployment should now be running smoothly! 🚀




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

# DevOps Probes Lab: Liveness & Readiness Deep Dive (for interviews)

See below **interview‑ready breakdown** of **all scenarios + benefits** of **liveness** and **readiness** probes.



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