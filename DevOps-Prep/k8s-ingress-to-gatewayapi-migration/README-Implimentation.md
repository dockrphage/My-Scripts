# Learn-by-Implementing Lab: Ingress-NGINX to Gateway API Migration

## Lab Overview

Usecase is to migrate from ingress-nginx to gateway api; this is the simplest lab articulation in a single README file.

## Architecture & Use Case Design

### Scenario: E-Commerce Microservices Platform

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         CLUSTER: 3-Node K8s v1.36                      │
│                                                                         │
│  ┌─────────────────────────────────────────────────────────────────┐    │
│  │                     METALLB (192.168.1.55-65)                   │    │
│  └────────────────────────┬────────────────────────────────────────┘    │
│                           │                                              │
│  ┌────────────────────────┴────────────────────────────────────────┐    │
│  │                                                                   │    │
│  │  ┌──────────────┐    ┌──────────────┐    ┌──────────────┐       │    │
│  │  │   Gateway    │    │   Gateway    │    │   Gateway    │       │    │
│  │  │  (192.168.1.55) │  │  (192.168.1.56) │  │  (192.168.1.57) │       │    │
│  │  │  Controller  │    │  Controller  │    │  Controller  │       │    │
│  │  └──────┬───────┘    └──────┬───────┘    └──────┬───────┘       │    │
│  │         │                   │                   │                │    │
│  │         └───────────────────┼───────────────────┘                │    │
│  │                             │                                    │    │
│  │  ┌──────────────────────────┼──────────────────────────────┐    │    │
│  │  │                          │                              │    │    │
│  │  │  ┌───────────────────────┴─────────────────────────┐   │    │    │
│  │  │  │          HTTPRoute /api/v1/*                    │   │    │    │
│  │  │  └───────────────────────┬─────────────────────────┘   │    │    │
│  │  │                          │                              │    │    │
│  │  │  ┌───────────────────────┴─────────────────────────┐   │    │    │
│  │  │  │  Service: api-gateway (NodePort)               │   │    │    │
│  │  │  └───────────────────────┬─────────────────────────┘   │    │    │
│  │  │                          │                              │    │    │
│  │  │  ┌───────────────────────┼─────────────────────────┐   │    │    │
│  │  │  │  HTTPRoute /store/*   │  HTTPRoute /cart/*      │   │    │    │
│  │  │  └───────┬───────────────┴────────────────┬────────┘   │    │    │
│  │  │          │                                │             │    │    │
│  │  │  ┌───────┴───────┐            ┌──────────┴──────────┐ │    │    │
│  │  │  │Service: store │            │ Service: cart       │ │    │    │
│  │  │  └───────────────┘            └─────────────────────┘ │    │    │
│  │  └──────────────────────────────────────────────────────────┘    │    │
│  └─────────────────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────────────────┘
```

---

# Complete Learn-by-Implementation: Manual Migration from Ingress-NGINX to Gateway API

## Phase 0: Environment Setup & Verification

### 0.1 Verify Your Cluster

```bash
# Check cluster health
kubectl get nodes
kubectl get pods -A

# Verify MetalLB is working
kubectl get ipaddresspools -n metallb-system
kubectl get pods -n metallb-system

# Note your MetalLB IP pool
echo "MetalLB IP Pool: 192.168.1.55-192.168.1.65"
```

---

## Phase 1: Deploy Sample Applications

### 1.1 Create Namespace

```bash
# Create namespace for our applications
kubectl create namespace ecommerce

# Verify
kubectl get namespaces
```

### 1.2 Deploy Services (Using HTTP Echo for Better Testing)

```bash
# Deploy API Gateway Service
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api-gateway
  namespace: ecommerce
spec:
  replicas: 2
  selector:
    matchLabels:
      app: api-gateway
  template:
    metadata:
      labels:
        app: api-gateway
    spec:
      containers:
      - name: http-echo
        image: hashicorp/http-echo:latest
        args:
        - "-listen=:80"
        - "-text=API Gateway Service\n"
        ports:
        - containerPort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: api-gateway
  namespace: ecommerce
spec:
  selector:
    app: api-gateway
  ports:
  - port: 80
    targetPort: 80
EOF

# Deploy Store Service
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: store-service
  namespace: ecommerce
spec:
  replicas: 2
  selector:
    matchLabels:
      app: store-service
  template:
    metadata:
      labels:
        app: store-service
    spec:
      containers:
      - name: http-echo
        image: hashicorp/http-echo:latest
        args:
        - "-listen=:80"
        - "-text=Store Service\n"
        ports:
        - containerPort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: store-service
  namespace: ecommerce
spec:
  selector:
    app: store-service
  ports:
  - port: 80
    targetPort: 80
EOF

# Deploy Cart Service
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: cart-service
  namespace: ecommerce
spec:
  replicas: 2
  selector:
    matchLabels:
      app: cart-service
  template:
    metadata:
      labels:
        app: cart-service
    spec:
      containers:
      - name: http-echo
        image: hashicorp/http-echo:latest
        args:
        - "-listen=:80"
        - "-text=Cart Service\n"
        ports:
        - containerPort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: cart-service
  namespace: ecommerce
spec:
  selector:
    app: cart-service
  ports:
  - port: 80
    targetPort: 80
EOF

# Verify deployments and services
kubectl get deployments -n ecommerce
kubectl get services -n ecommerce
kubectl get pods -n ecommerce
```

### 1.3 Test Direct Service Access

```bash
# Port-forward to test services directly
kubectl port-forward -n ecommerce svc/api-gateway 8080:80 &
kubectl port-forward -n ecommerce svc/store-service 8081:80 &
kubectl port-forward -n ecommerce svc/cart-service 8082:80 &

# Test each service
curl http://localhost:8080/
curl http://localhost:8081/
curl http://localhost:8082/

# Kill port-forwards when done
pkill -f "port-forward"
```

**📝 Observation Questions:**
- What response do you get from each service?
- How does http-echo work?
- What are the service ClusterIPs?

---

## Phase 2: Install & Configure Ingress-NGINX

### 2.1 Install Ingress-NGINX Controller

```bash
# Install Ingress-NGINX controller
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.11.1/deploy/static/provider/cloud/deploy.yaml

# Watch the installation
kubectl get pods -n ingress-nginx -w

# Verify controller is running
kubectl get pods -n ingress-nginx
kubectl get svc -n ingress-nginx
```

**📝 Observation Questions:**
- What pods are created in the ingress-nginx namespace?
- What type of service is created?

### 2.2 Configure Ingress-NGINX with MetalLB

```bash
# Patch the service to use MetalLB
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Service
metadata:
  name: ingress-nginx-controller
  namespace: ingress-nginx
  annotations:
    metallb.universe.tf/address-pool: bridged-pool
spec:
  type: LoadBalancer
  ports:
  - port: 80
    targetPort: 80
    protocol: TCP
    name: http
  - port: 443
    targetPort: 443
    protocol: TCP
    name: https
  selector:
    app.kubernetes.io/component: controller
    app.kubernetes.io/instance: ingress-nginx
    app.kubernetes.io/name: ingress-nginx
EOF

# Wait for LoadBalancer IP
sleep 10

# Get the external IP
INGRESS_IP=$(kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
echo "Ingress IP: $INGRESS_IP"

# Verify IP is in your MetalLB range
echo "MetalLB Range: 192.168.1.55-192.168.1.65"
echo "Ingress IP: $INGRESS_IP"
```

**📝 Observation Questions:**
- How does MetalLB assign IPs to services?
- What annotation is used to specify the IP pool?
- Why do we need to patch the service?

### 2.3 Create Ingress Resources

```bash
# Create Ingress with routing rules
cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: ecommerce-ingress
  namespace: ecommerce
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /\$2
    nginx.ingress.kubernetes.io/use-regex: "true"
    nginx.ingress.kubernetes.io/ssl-redirect: "false"
spec:
  ingressClassName: nginx
  rules:
  - host: ecommerce.local
    http:
      paths:
      - path: /api(/|$)(.*)
        pathType: ImplementationSpecific
        backend:
          service:
            name: api-gateway
            port:
              number: 80
      - path: /store(/|$)(.*)
        pathType: ImplementationSpecific
        backend:
          service:
            name: store-service
            port:
              number: 80
      - path: /cart(/|$)(.*)
        pathType: ImplementationSpecific
        backend:
          service:
            name: cart-service
            port:
              number: 80
EOF

# Verify Ingress
kubectl get ingress -n ecommerce
kubectl describe ingress ecommerce-ingress -n ecommerce
```

**📝 Observation Questions:**
- What do the annotations do?
- How does the rewrite-target work with regex?
- What is pathType: ImplementationSpecific?

### 2.4 Test Ingress

```bash
# Get Ingress IP
INGRESS_IP=$(kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
echo "Testing Ingress at IP: $INGRESS_IP"

# Test each endpoint
echo "=== Testing Ingress Routes ==="
for path in "api" "store" "cart"; do
    echo -n "GET /$path: "
    curl -s -H "Host: ecommerce.local" "http://$INGRESS_IP/$path/"
    echo ""
done

# Test path rewriting
echo -e "\n=== Testing Path Rewriting ==="
echo "GET /api/test:"
curl -s -H "Host: ecommerce.local" "http://$INGRESS_IP/api/test"
echo ""

# Test without host header (should fail)
echo -e "\n=== Testing Without Host Header ==="
curl -s -o /dev/null -w "Status: %{http_code}\n" "http://$INGRESS_IP/api/"
```

**📝 Observation Questions:**
- Why do we need the Host header?
- What happens if you access without the Host header?
- How does the rewrite work with /api/test?

---

## Phase 3: Install Gateway API CRDs

### 3.1 Install Gateway API CRDs

```bash
# Install the Gateway API CRDs
kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.2.0/standard-install.yaml

# Verify installation
kubectl get crd | grep gateway.networking.k8s.io

# Check the new API resources
kubectl api-resources | grep gateway

# Explore the CRDs
kubectl explain gatewayclass
kubectl explain gateway
kubectl explain httproute
```

**📝 Observation Questions:**
- What new CRDs were installed?
- What is the purpose of each Gateway API resource?
- How do these compare to Ingress resources?

---

## Phase 4: Install Gateway Controller (Contour)

### 4.1 Install Contour

```bash
# Install Contour with Gateway API support
kubectl apply -f https://projectcontour.io/quickstart/contour-gateway.yaml

# Watch Contour installation
kubectl get pods -n projectcontour -w

# Verify Contour is running
kubectl get pods -n projectcontour
kubectl get svc -n projectcontour
kubectl get gatewayclass
```

### 4.2 Verify Contour Installation

```bash
# Check GatewayClass created by Contour
kubectl get gatewayclass example -o yaml

# Check Contour deployment
kubectl describe deployment contour -n projectcontour

# Check Envoy daemonset
kubectl describe daemonset envoy -n projectcontour

# View logs
kubectl logs -n projectcontour deployment/contour --tail=20
kubectl logs -n projectcontour daemonset/envoy --tail=20
```

**📝 Observation Questions:**
- What is the role of Contour vs Envoy?
- Why is Envoy deployed as a DaemonSet?
- What GatewayClass did Contour create?

---

## Phase 5: Create Gateway Resources

### 5.1 Delete Example Gateway

```bash
# Remove the example gateway
kubectl delete gateway contour -n projectcontour

# Verify it's gone
kubectl get gateway -A
```

### 5.2 Create Gateway with MetalLB

```bash
# Create Gateway YAML
cat <<EOF | kubectl apply -f -
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: ecommerce-gateway
  namespace: ecommerce
  annotations:
    metallb.universe.tf/address-pool: bridged-pool
spec:
  gatewayClassName: example
  listeners:
  - name: http
    protocol: HTTP
    port: 80
    allowedRoutes:
      namespaces:
        from: Same
EOF

# Check Gateway status
kubectl get gateway -n ecommerce
kubectl describe gateway ecommerce-gateway -n ecommerce

# Wait for Gateway to get IP
sleep 10

# Get Gateway IP
GATEWAY_IP=$(kubectl get gateway ecommerce-gateway -n ecommerce -o jsonpath='{.status.addresses[0].value}')
echo "Gateway IP: $GATEWAY_IP"
```

**📝 Observation Questions:**
- What does the gatewayClassName refer to?
- How does the Gateway get an IP address?
- What are the conditions in Gateway status?
- Compare Gateway IP with Ingress IP

### 5.3 Examine Gateway Status

```bash
# View full Gateway YAML
kubectl get gateway ecommerce-gateway -n ecommerce -o yaml

# Check status conditions
kubectl get gateway ecommerce-gateway -n ecommerce -o jsonpath='{.status.conditions}' | jq

# Check addresses
kubectl get gateway ecommerce-gateway -n ecommerce -o jsonpath='{.status.addresses}'
```

---

## Phase 6: Create HTTPRoutes

### 6.1 Create API Route

```bash
# Create HTTPRoute for API
cat <<EOF | kubectl apply -f -
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: api-route
  namespace: ecommerce
spec:
  parentRefs:
  - name: ecommerce-gateway
  hostnames:
  - "ecommerce.local"
  rules:
  - matches:
    - path:
        type: PathPrefix
        value: /api/
    backendRefs:
    - name: api-gateway
      port: 80
EOF

# Verify route
kubectl get httproute -n ecommerce
kubectl describe httproute api-route -n ecommerce
```

### 6.2 Create Store Route

```bash
cat <<EOF | kubectl apply -f -
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: store-route
  namespace: ecommerce
spec:
  parentRefs:
  - name: ecommerce-gateway
  hostnames:
  - "ecommerce.local"
  rules:
  - matches:
    - path:
        type: PathPrefix
        value: /store/
    backendRefs:
    - name: store-service
      port: 80
EOF
```

### 6.3 Create Cart Route

```bash
cat <<EOF | kubectl apply -f -
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: cart-route
  namespace: ecommerce
spec:
  parentRefs:
  - name: ecommerce-gateway
  hostnames:
  - "ecommerce.local"
  rules:
  - matches:
    - path:
        type: PathPrefix
        value: /cart/
    backendRefs:
    - name: cart-service
      port: 80
EOF

# View all routes
kubectl get httproute -n ecommerce -o wide
```

**📝 Observation Questions:**
- How does HTTPRoute differ from Ingress rules?
- What is the purpose of parentRefs?
- How are hostnames handled?
- What is PathPrefix vs Exact?

---

## Phase 7: Test Gateway API

### 7.1 Basic Gateway Testing

```bash
# Get Gateway IP
GATEWAY_IP=$(kubectl get gateway ecommerce-gateway -n ecommerce -o jsonpath='{.status.addresses[0].value}')
echo "Gateway IP: $GATEWAY_IP"

# Test each route
echo "=== Testing Gateway Routes ==="
for path in "api" "store" "cart"; do
    echo -n "GET /$path via Gateway: "
    curl -s -H "Host: ecommerce.local" "http://$GATEWAY_IP/$path/"
    echo ""
done
```

### 7.2 Compare Ingress vs Gateway

```bash
# Get Ingress IP
INGRESS_IP=$(kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

echo "=== Comparison Test ==="
echo "Ingress IP: $INGRESS_IP"
echo "Gateway IP: $GATEWAY_IP"
echo ""

for path in "api" "store" "cart"; do
    echo "Testing /$path:"
    echo -n "  Ingress: "
    curl -s -H "Host: ecommerce.local" "http://$INGRESS_IP/$path/" | head -1
    echo -n "  Gateway: "
    curl -s -H "Host: ecommerce.local" "http://$GATEWAY_IP/$path/" | head -1
    echo ""
done
```

**📝 Observation Questions:**
- What differences do you notice between Ingress and Gateway responses?
- Are the paths preserved or rewritten?
- Which system is handling the routing better?

---

## Phase 8: Advanced Features - Manual Implementation

### 8.1 Create V2 Version for A/B Testing

```bash
# Create v2 deployment
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api-gateway-v2
  namespace: ecommerce
spec:
  replicas: 1
  selector:
    matchLabels:
      app: api-gateway-v2
  template:
    metadata:
      labels:
        app: api-gateway-v2
    spec:
      containers:
      - name: http-echo
        image: hashicorp/http-echo:latest
        args:
        - "-listen=:80"
        - "-text=API Gateway V2 (Beta)\n"
        ports:
        - containerPort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: api-gateway-v2
  namespace: ecommerce
spec:
  selector:
    app: api-gateway-v2
  ports:
  - port: 80
    targetPort: 80
EOF

# Verify v2 is running
kubectl get pods -n ecommerce | grep v2
kubectl get svc -n ecommerce | grep v2
```

### 8.2 Implement Header-Based Routing

```bash
# Create HTTPRoute with header matching
cat <<EOF | kubectl apply -f -
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: api-header-route
  namespace: ecommerce
spec:
  parentRefs:
  - name: ecommerce-gateway
  hostnames:
  - "ecommerce.local"
  rules:
  - matches:
    - path:
        type: PathPrefix
        value: /api/
      headers:
      - name: version
        value: v1
    backendRefs:
    - name: api-gateway
      port: 80
  - matches:
    - path:
        type: PathPrefix
        value: /api/
      headers:
      - name: version
        value: v2
    backendRefs:
    - name: api-gateway-v2
      port: 80
  - matches:
    - path:
        type: PathPrefix
        value: /api/
    backendRefs:
    - name: api-gateway
      port: 80
EOF

# Test header-based routing
echo "=== Testing Header-Based Routing ==="
echo "1. No header (should go to v1):"
curl -s -H "Host: ecommerce.local" "http://$GATEWAY_IP/api/"

echo -e "\n2. version=v1 header:"
curl -s -H "Host: ecommerce.local" -H "version: v1" "http://$GATEWAY_IP/api/"

echo -e "\n3. version=v2 header:"
curl -s -H "Host: ecommerce.local" -H "version: v2" "http://$GATEWAY_IP/api/"

echo -e "\n4. version=v3 header (should default):"
curl -s -H "Host: ecommerce.local" -H "version: v3" "http://$GATEWAY_IP/api/"
```

**📝 Observation Questions:**
- How does header-based routing work?
- What happens when no header matches?
- How would you add more header conditions?

### 8.3 Create Canary Deployment

```bash
# Create canary version of store service
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: store-service-canary
  namespace: ecommerce
spec:
  replicas: 1
  selector:
    matchLabels:
      app: store-service-canary
  template:
    metadata:
      labels:
        app: store-service-canary
    spec:
      containers:
      - name: http-echo
        image: hashicorp/http-echo:latest
        args:
        - "-listen=:80"
        - "-text=Store Service CANARY (New Version)\n"
        ports:
        - containerPort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: store-service-canary
  namespace: ecommerce
spec:
  selector:
    app: store-service-canary
  ports:
  - port: 80
    targetPort: 80
EOF

# Create split route with weights
cat <<EOF | kubectl apply -f -
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: store-split-route
  namespace: ecommerce
spec:
  parentRefs:
  - name: ecommerce-gateway
  hostnames:
  - "ecommerce.local"
  rules:
  - matches:
    - path:
        type: PathPrefix
        value: /store/
    backendRefs:
    - name: store-service
      port: 80
      weight: 90
    - name: store-service-canary
      port: 80
      weight: 10
EOF

# Test canary distribution
echo "=== Testing Canary (90/10 split) ==="
stable=0
canary=0
total=30

for i in $(seq 1 $total); do
    response=$(curl -s -H "Host: ecommerce.local" "http://$GATEWAY_IP/store/")
    if echo "$response" | grep -q "CANARY"; then
        ((canary++))
        echo -n "C"
    else
        ((stable++))
        echo -n "S"
    fi
    if [ $((i % 10)) -eq 0 ]; then
        echo ""
    fi
done
echo ""
echo "Stable: $stable ($((stable * 100 / total))%)"
echo "Canary: $canary ($((canary * 100 / total))%)"
```

**📝 Observation Questions:**
- How does weight-based routing work?
- What would you expect with 90/10 split?
- How would you implement gradual rollout?

---

## Phase 9: Manual Troubleshooting

### 9.1 Check Route Status

```bash
# Check conditions on routes
kubectl get httproute -n ecommerce -o custom-columns=NAME:.metadata.name,ACCEPTED:.status.conditions[?\(@.type==\"Accepted\"\)].status,RESOLVED:.status.conditions[?\(@.type==\"ResolvedRefs\"\)].status

# Check Gateway status
kubectl get gateway -n ecommerce -o custom-columns=NAME:.metadata.name,READY:.status.conditions[?\(@.type==\"Ready\"\)].status,IP:.status.addresses[0].value

# View logs
kubectl logs -n projectcontour deployment/contour --tail=20
kubectl logs -n projectcontour daemonset/envoy --tail=20
```

### 9.2 Manual Path Testing

```bash
# Create a test script
cat <<'EOF' > test-paths.sh
#!/bin/bash
GATEWAY_IP=$(kubectl get gateway ecommerce-gateway -n ecommerce -o jsonpath='{.status.addresses[0].value}')
INGRESS_IP=$(kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

echo "Testing path handling:"
echo "======================="

paths=("/" "/api" "/api/" "/api/test" "/api/anything" "/store" "/store/" "/store/products" "/cart" "/cart/" "/cart/checkout")

for path in "${paths[@]}"; do
    echo -n "Ingress $path: "
    status=$(curl -s -o /dev/null -w "%{http_code}" -H "Host: ecommerce.local" "http://$INGRESS_IP$path")
    echo "HTTP $status"
done

for path in "${paths[@]}"; do
    echo -n "Gateway $path: "
    status=$(curl -s -o /dev/null -w "%{http_code}" -H "Host: ecommerce.local" "http://$GATEWAY_IP$path")
    echo "HTTP $status"
done
EOF

chmod +x test-paths.sh
./test-paths.sh
```

---

## Phase 10: Clean Up

### 10.1 Clean Up All Resources

```bash
# Delete Gateway API resources
kubectl delete httproute -n ecommerce --all
kubectl delete gateway -n ecommerce ecommerce-gateway

# Delete Contour
kubectl delete -f https://projectcontour.io/quickstart/contour-gateway.yaml

# Delete Gateway API CRDs
kubectl delete -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.2.0/standard-install.yaml

# Delete Ingress
kubectl delete ingress -n ecommerce --all
kubectl delete -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.11.1/deploy/static/provider/cloud/deploy.yaml

# Delete sample applications
kubectl delete namespace ecommerce
```

---

## Summary Checklist

After completing this lab, you should be able to:

- [ ] Deploy sample applications with services
- [ ] Install and configure Ingress-NGINX with MetalLB
- [ ] Create Ingress resources with path routing
- [ ] Install Gateway API CRDs
- [ ] Install Contour Gateway controller
- [ ] Create Gateway resources with MetalLB
- [ ] Create HTTPRoutes for path routing
- [ ] Test and compare Ingress vs Gateway routing
- [ ] Implement header-based routing
- [ ] Implement weight-based traffic splitting
- [ ] Troubleshoot routing issues
- [ ] Understand the differences between Ingress and Gateway API

**📝 Final Observation Questions:**
1. What are the main advantages of Gateway API over Ingress?
2. When would you choose Ingress over Gateway API?
3. What is the migration path from Ingress to Gateway API?
4. How does role separation work in Gateway API?
5. What advanced features does Gateway API provide?
