Usecase based on https://interlaye.red/kubernetes_002degress_002dsquid.html. Refactored to suit my existing 3 node vagrant cluster environment.

## Understanding Your Current Setup

You have a **3-node Kubernetes cluster** (1 control-plane, 2 workers) running on **Vagrant/VirtualBox** with:
- **MetalLB** configured for load balancing (IP pool: 192.168.1.55-192.168.1.65)
- **Containerd** as the container runtime
- **Ubuntu 22.04** nodes with internal IPs in the 192.168.56.0/24 network

## Refactored Architecture for Your Environment

Here's the plan to implement the Squid egress proxy pattern in your existing cluster:

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    Kubernetes Cluster (192.168.56.0/24)                     │
│                                                                             │
│  ┌──────────────────────────┐          ┌──────────────────────────┐        │
│  │  Workload Namespace      │          │  Egress-Proxy Namespace  │        │
│  │  (e.g., "horizons")      │          │                          │        │
│  │                          │          │  ┌────────────────────┐  │        │
│  │  ┌──────────────────┐   │  :3128   │  │     Squid Pod      │  │        │
│  │  │   Application    │   ├──────────┼─▶│  (ubuntu/squid)    │  │        │
│  │  │   Pod            │   │          │  │                    │  │        │
│  │  └──────────────────┘   │          │  └────────────────────┘  │        │
│  │         │               │          │         │                │        │
│  │         ✗               │          │         │ (logs)        │        │
│  │    (blocked direct)     │          │  ┌──────▼───────┐        │        │
│  └──────────────────────────┘          │  │ GoAccess     │        │        │
│                                         │  │ Dashboard   │        │        │
│                                         │  └──────────────┘        │        │
│                                         └──────────────────────────┘        │
│                                                         │                  │
│                                                         │ (Service)       │
│                                                         ▼                  │
│                                              ┌──────────────────┐        │
│                                              │  MetalLB Load    │        │
│                                              │  Balancer (VIP)  │        │
│                                              │  192.168.1.60    │        │
│                                              └──────────────────┘        │
└─────────────────────────────────────────────────────────────────────────────┘
```

## Implementation Steps

### 1. Prepare Your Cluster Context

First, ensure you're working with the right cluster:

```bash
# Verify your cluster is healthy
kubectl get nodes
kubectl get pods -A

# Note your cluster's pod CIDR (typically 10.42.0.0/16 for k3s)
kubectl cluster-info dump | grep -m 1 cluster-cidr
```

### 2. Create the Egress-Proxy Namespace

```bash
# Create the namespace with the label needed for network policies
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Namespace
metadata:
  name: egress-proxy
  labels:
    purpose: egress-control
EOF
```

### 3. Create Squid Configuration ConfigMap

```bash
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: squid-config
  namespace: egress-proxy
data:
  squid.conf: |
    http_port 3128

    # Logging
    access_log /var/log/squid/access.log combined
    cache_log /var/log/squid/cache.log

    # No caching for egress visibility
    cache deny all

    # Allow requests from private IP ranges (adjust to your pod CIDR)
    acl localnet src 10.0.0.0/8
    acl localnet src 172.16.0.0/12
    acl localnet src 192.168.0.0/16

    acl SSL_ports port 443
    acl Safe_ports port 80
    acl Safe_ports port 443
    acl CONNECT method CONNECT

    http_access deny !Safe_ports
    http_access deny CONNECT !SSL_ports
    http_access allow localnet
    http_access deny all
EOF
```

### 4. Deploy Squid with Log Streaming

```bash
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: squid
  namespace: egress-proxy
spec:
  replicas: 1
  selector:
    matchLabels:
      app: squid
  template:
    metadata:
      labels:
        app: squid
    spec:
      initContainers:
        - name: fix-permissions
          image: busybox:latest
          command: ["sh", "-c", "chown -R 13:13 /var/log/squid"]
          volumeMounts:
            - name: logs
              mountPath: /var/log/squid
      containers:
        - name: squid
          image: ubuntu/squid:latest
          ports:
            - containerPort: 3128
          volumeMounts:
            - name: config
              mountPath: /etc/squid/squid.conf
              subPath: squid.conf
            - name: logs
              mountPath: /var/log/squid

        - name: log-streamer
          image: busybox:latest
          command: ["sh", "-c", "touch /var/log/squid/access.log && tail -F /var/log/squid/access.log"]
          volumeMounts:
            - name: logs
              mountPath: /var/log/squid

      volumes:
        - name: config
          configMap:
            name: squid-config
        - name: logs
          hostPath:
            path: /var/log/squid-egress
            type: DirectoryOrCreate
EOF
```

### 5. Expose Squid via MetalLB LoadBalancer

```bash
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Service
metadata:
  name: squid
  namespace: egress-proxy
spec:
  selector:
    app: squid
  ports:
    - port: 3128
      targetPort: 3128
  type: LoadBalancer
EOF

# Get the external IP (should be from your MetalLB pool)
kubectl get svc -n egress-proxy squid
```

### 6. Create a Test Namespace with NetworkPolicy Enforcement

```bash
# Create a test namespace
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Namespace
metadata:
  name: egress-test
EOF

# Apply the NetworkPolicy that enforces egress through the proxy
cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: enforce-egress-proxy
  namespace: egress-test
spec:
  podSelector: {}
  policyTypes:
    - Egress
  egress:
    # Allow DNS resolution
    - to:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: kube-system
      ports:
        - protocol: UDP
          port: 53
        - protocol: TCP
          port: 53

    # Allow traffic only to Squid proxy
    - to:
        - namespaceSelector:
            matchLabels:
              purpose: egress-control
      ports:
        - protocol: TCP
          port: 3128
EOF
```

### 7. Deploy a Test Pod with Proxy Configuration

```bash
# Get the Squid service IP
SQUID_IP=$(kubectl get svc -n egress-proxy squid -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
echo "Squid proxy IP: $SQUID_IP"

# Deploy a test pod with proxy environment variables
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: test-client
  namespace: egress-test
  labels:
    app: test-client
spec:
  containers:
    - name: test-client
      image: curlimages/curl:latest
      command: ["sleep", "3600"]
      env:
        - name: HTTP_PROXY
          value: "http://$SQUID_IP:3128"
        - name: HTTPS_PROXY
          value: "http://$SQUID_IP:3128"
        - name: NO_PROXY
          value: "localhost,127.0.0.1,.svc,.svc.cluster.local,10.0.0.0/8,192.168.0.0/16"
EOF
```

### 8. Test the Setup

```bash
# Exec into the test pod
kubectl exec -it -n egress-test test-client -- sh

# Test external access (should work through proxy)
curl -I http://google.com

# Check the Squid logs
kubectl logs -n egress-proxy deploy/squid -c log-streamer

# Test internal cluster access (should work via NO_PROXY)
curl -I http://kubernetes.default.svc.cluster.local
```

## Advanced: Add GoAccess Dashboard

```bash
# Update the Squid deployment with GoAccess sidecar
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: squid
  namespace: egress-proxy
spec:
  replicas: 1
  selector:
    matchLabels:
      app: squid
  template:
    metadata:
      labels:
        app: squid
    spec:
      initContainers:
        - name: fix-permissions
          image: busybox:latest
          command: ["sh", "-c", "chown -R 13:13 /var/log/squid"]
          volumeMounts:
            - name: logs
              mountPath: /var/log/squid
      containers:
        - name: squid
          image: ubuntu/squid:latest
          ports:
            - containerPort: 3128
          volumeMounts:
            - name: config
              mountPath: /etc/squid/squid.conf
              subPath: squid.conf
            - name: logs
              mountPath: /var/log/squid

        - name: log-streamer
          image: busybox:latest
          command: ["sh", "-c", "touch /var/log/squid/access.log && tail -F /var/log/squid/access.log"]
          volumeMounts:
            - name: logs
              mountPath: /var/log/squid

        - name: goaccess
          image: allinurl/goaccess:latest
          command:
            - sh
            - -c
            - |
              while [ ! -f /var/log/squid/access.log ]; do sleep 1; done
              goaccess /var/log/squid/access.log \
                --log-format=SQUID \
                --real-time-html \
                --output=/var/www/goaccess/index.html \
                --port=7890
          ports:
            - containerPort: 7890
          volumeMounts:
            - name: logs
              mountPath: /var/log/squid

      volumes:
        - name: config
          configMap:
            name: squid-config
        - name: logs
          hostPath:
            path: /var/log/squid-egress
            type: DirectoryOrCreate
EOF

# Expose GoAccess dashboard via LoadBalancer
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Service
metadata:
  name: goaccess
  namespace: egress-proxy
spec:
  selector:
    app: squid
  ports:
    - port: 7890
      targetPort: 7890
  type: LoadBalancer
EOF

# Access the dashboard
kubectl get svc -n egress-proxy goaccess
# Open in browser: http://<EXTERNAL-IP>:7890
```

## What This Gives You

| Feature | Benefit |
|---------|---------|
| **Egress visibility** | All outbound HTTP/HTTPS traffic logged |
| **Enforcement** | NetworkPolicy blocks direct egress |
| **Simplicity** | No CNI plugins, service mesh, or CRDs |
| **Real-time dashboard** | GoAccess shows traffic patterns |
| **Persistence** | Logs stored on node at `/var/log/squid-egress/` |
| **MetalLB integration** | Proxy accessible via stable VIP |

## Interview Talking Points

**Q: How did you implement egress control in Kubernetes?**

> "I deployed a Squid proxy in a dedicated namespace and used NetworkPolicies to enforce that all outbound traffic from workloads must go through it. The proxy logs all egress traffic, providing visibility into what the cluster is talking to. I used MetalLB to expose the proxy externally for testing."

**Q: Why Squid instead of a service mesh?**

> "For this use case, Squid is simpler and more lightweight. It handles HTTP/HTTPS egress perfectly, provides detailed logging, and doesn't require injecting sidecars. It's a good first step toward egress control without the operational overhead of a full service mesh."

**Q: What are the limitations?**

> "It only handles HTTP/HTTPS - raw TCP or protocols like gRPC need different handling. Applications must be configured to use the proxy via environment variables, and the configuration is centralized. These limitations help explain why more advanced solutions exist for complex scenarios."

## Verification Runbook

### Quick Test
```bash
# 1. Check if Squid is running
kubectl get pods -n egress-proxy

# 2. Get proxy IP
kubectl get svc -n egress-proxy squid

# 3. Test from a pod in egress-test namespace
kubectl run -it --rm test-curl -n egress-test --image=curlimages/curl --restart=Never -- curl -I http://google.com

# 4. Check logs
kubectl logs -n egress-proxy deploy/squid -c log-streamer

# 5. Verify NetworkPolicy is enforced
kubectl run -it --rm test-direct -n egress-test --image=curlimages/curl --restart=Never -- curl -I http://1.1.1.1
# Should time out or fail
```

### Troubleshooting

| Issue | Check | Fix |
|-------|-------|-----|
| Pods can't reach proxy | `kubectl describe networkpolicy -n egress-test` | Verify namespace labels match |
| Proxy logs empty | `kubectl logs -n egress-proxy deploy/squid -c squid` | Check Squid is running |
| MetalLB not assigning IP | `kubectl get ipaddresspools -n metallb-system` | Verify pool configuration |
| DNS resolution failing | `kubectl get svc -n kube-system` | Check CoreDNS is running |

This architecture gives you a practical, interview-ready demonstration of egress control in Kubernetes that builds directly on the skills you've already developed!
