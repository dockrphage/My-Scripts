# Complete B2B Keycloak Deployment on 3-Node Kubernetes Cluster

## Architecture Overview

This document provides a complete, step-by-step guide for deploying Keycloak on a 3-node Kubernetes cluster using Vagrant, MetalLB, Ingress-Nginx, Helm, and ArgoCD for a B2B application with 40 users.

### Infrastructure Components
- **Kubernetes**: 3-node cluster (1 control-plane, 2 workers)
- **MetalLB**: LoadBalancer for ingress-nginx (IP range: 192.168.1.55-192.168.1.65)
- **Ingress-Nginx**: External routing with host `keycloak.b2b.local`
- **ArgoCD**: GitOps continuous deployment
- **Helm**: Package management for PostgreSQL and Keycloak
- **PostgreSQL**: Database for Keycloak
- **Keycloak**: Identity and Access Management (version 26.0.7)

### Resource Allocation
| Node | Role | IP | CPU | Memory |
|------|------|-----|-----|--------|
| cp1 | Control Plane | 192.168.56.10 | 2 | 2048 MB |
| node1 | Worker | 192.168.56.11 | 2 | 6144 MB |
| node2 | Worker | 192.168.56.12 | 2 | 6144 MB |

---

## Table of Contents

1. [Prerequisites](#1-prerequisites)
2. [Vagrant Cluster Setup](#2-vagrant-cluster-setup)
3. [Kubernetes Installation](#3-kubernetes-installation)
4. [MetalLB Configuration](#4-metallb-configuration)
5. [Ingress-Nginx Deployment](#5-ingress-nginx-deployment)
6. [ArgoCD Installation](#6-argocd-installation)
7. [PostgreSQL Deployment](#7-postgresql-deployment)
8. [Keycloak Deployment](#8-keycloak-deployment)
9. [Ingress Configuration](#9-ingress-configuration)
10. [ArgoCD GitOps Integration](#10-argocd-gitops-integration)
11. [Keycloak Configuration](#11-keycloak-configuration)
12. [Troubleshooting Guide](#12-troubleshooting-guide)
13. [Maintenance and Operations](#13-maintenance-and-operations)
14. [Security Considerations](#14-security-considerations)

---

## 1. Prerequisites

### Software Requirements
```bash
# Required tools
- Vagrant 2.3.0+
- VirtualBox 7.0+
- kubectl 1.28.0+
- Helm 3.0+
- Git
- curl, jq
```

### Hardware Requirements
- **Minimum**: 16GB RAM, 4 CPU cores, 50GB disk space
- **Recommended**: 32GB RAM, 8 CPU cores, 100GB disk space

---

## 2. Vagrant Cluster Setup

### 2.1 Create Vagrantfile

Create a `Vagrantfile` with the following configuration:

```ruby
# Vagrantfile
Vagrant.configure("2") do |config|
  config.vm.box = "ubuntu/jammy64"
  
  # Node definitions
  nodes = {
    "cp1"   => { ip: "192.168.56.10", bridged_ip: "192.168.1.50", cpu: 2, mem: 2048, role: "control-plane" },
    "node1" => { ip: "192.168.56.11", bridged_ip: "192.168.1.51", cpu: 2, mem: 6144, role: "worker" },
    "node2" => { ip: "192.168.56.12", bridged_ip: "192.168.1.52", cpu: 2, mem: 6144, role: "worker" }
  }

  nodes.each do |name, cfg|
    config.vm.define name do |node|
      node.vm.hostname = name
      node.vm.network "private_network", ip: cfg[:ip]
      node.vm.network "public_network", ip: cfg[:bridged_ip], bridge: "en0: Wi-Fi (AirPort)"
      
      node.vm.provider "virtualbox" do |vb|
        vb.memory = cfg[:mem]
        vb.cpus = cfg[:cpu]
        vb.name = name
      end

      # Install Kubernetes only on first run
      if name == "cp1"
        node.vm.provision "shell", path: "scripts/master-setup.sh"
      else
        node.vm.provision "shell", path: "scripts/worker-setup.sh"
      end
    end
  end
end
```

### 2.2 Create Setup Scripts

**`scripts/common-setup.sh`**:
```bash
#!/bin/bash
# Common setup for all nodes

# Disable swap
sudo swapoff -a
sudo sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab

# Install container runtime (containerd)
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update
sudo apt-get install -y containerd.io

# Configure containerd
sudo mkdir -p /etc/containerd
containerd config default | sudo tee /etc/containerd/config.toml
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/g' /etc/containerd/config.toml
sudo systemctl restart containerd

# Install Kubernetes components
curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add -
echo "deb https://apt.kubernetes.io/ kubernetes-xenial main" | sudo tee /etc/apt/sources.list.d/kubernetes.list
sudo apt-get update
sudo apt-get install -y kubelet=1.28.0-00 kubeadm=1.28.0-00 kubectl=1.28.0-00
sudo apt-mark hold kubelet kubeadm kubectl

# Enable kubelet
sudo systemctl enable kubelet
```

**`scripts/master-setup.sh`**:
```bash
#!/bin/bash
source /vagrant/scripts/common-setup.sh

# Initialize cluster
sudo kubeadm init --pod-network-cidr=10.244.0.0/16 --apiserver-advertise-address=192.168.56.10

# Setup kubectl for vagrant user
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

# Install Calico network plugin
kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.26.1/manifests/calico.yaml

# Generate join command for workers
kubeadm token create --print-join-command > /vagrant/join-command.sh
chmod +x /vagrant/join-command.sh

# Install Helm
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
```

**`scripts/worker-setup.sh`**:
```bash
#!/bin/bash
source /vagrant/scripts/common-setup.sh

# Wait for master to generate join command
while [ ! -f /vagrant/join-command.sh ]; do
  sleep 5
done

# Join the cluster
sudo /vagrant/join-command.sh
```

### 2.3 Start the Cluster

```bash
# Start all VMs
vagrant up

# Check cluster status
vagrant ssh cp1
kubectl get nodes
kubectl get pods -n kube-system
```

**Expected Output:**
```
NAME   STATUS   ROLES           AGE   VERSION
cp1    Ready    control-plane   5m    v1.28.0
node1  Ready    <none>          4m    v1.28.0
node2  Ready    <none>          4m    v1.28.0
```

---

## 3. Kubernetes Installation

### 3.1 Verify Cluster Health

```bash
# Check all nodes
kubectl get nodes

# Check system pods
kubectl get pods -n kube-system

# Check Calico network
kubectl get pods -n kube-system | grep calico
```

### 3.2 Configure kubectl on Host

```bash
# Copy kubeconfig to host
vagrant scp cp1:/home/vagrant/.kube/config ~/.kube/config

# Test connectivity
kubectl cluster-info
```

---

## 4. MetalLB Configuration

### 4.1 Install MetalLB

```bash
# Install MetalLB
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.13.10/config/manifests/metallb-native.yaml

# Wait for MetalLB to be ready
kubectl wait --namespace metallb-system --for=condition=ready pod --selector=app=metallb --timeout=300s
```

### 4.2 Configure IP Address Pool

```bash
# Create IP address pool
cat <<EOF | kubectl apply -f -
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: b2b-pool
  namespace: metallb-system
spec:
  addresses:
  - 192.168.1.55-192.168.1.65
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: b2b-l2
  namespace: metallb-system
spec:
  ipAddressPools:
  - b2b-pool
  interfaces:
  - enp0s8
  - enp0s9
EOF

# Verify MetalLB
kubectl get ipaddresspools -n metallb-system
kubectl get l2advertisements -n metallb-system
```

**Note:** The interfaces `enp0s8` and `enp0s9` correspond to the host-only and bridged networks respectively. Adjust based on your VM network configuration.

---

## 5. Ingress-Nginx Deployment

### 5.1 Deploy Ingress-Nginx with Helm

```bash
# Add Helm repository
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update

# Deploy ingress-nginx
helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --create-namespace \
  --set controller.service.type=LoadBalancer \
  --set controller.service.loadBalancerIP=192.168.1.56 \
  --set controller.ingressClassResource.name=nginx \
  --set controller.watchIngressWithoutClass=true \
  --wait

# Verify ingress-nginx
kubectl get pods -n ingress-nginx
kubectl get svc -n ingress-nginx
```

**Expected Output:**
```
NAME                                         READY   STATUS    RESTARTS   AGE
ingress-nginx-controller-xxxxxxxxxx-xxxxx   1/1     Running   0          2m

NAME                                 TYPE           CLUSTER-IP     EXTERNAL-IP    PORT(S)
ingress-nginx-controller             LoadBalancer   10.107.202.161 192.168.1.56   80:32514/TCP
```

### 5.2 Update Hosts File

```bash
# Add entry to /etc/hosts
echo "192.168.1.56 keycloak.b2b.local" | sudo tee -a /etc/hosts

# Verify
ping keycloak.b2b.local
```

---

## 6. ArgoCD Installation

### 6.1 Install ArgoCD

```bash
# Install ArgoCD
kubectl create namespace argocd
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update

helm upgrade --install argocd argo/argo-cd \
  --namespace argocd \
  --set server.service.type=LoadBalancer \
  --set server.service.loadBalancerIP=192.168.1.57 \
  --wait

# Get admin password
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
echo ""
```

### 6.2 Access ArgoCD UI

```bash
# Port-forward to access ArgoCD
kubectl port-forward svc/argocd-server -n argocd 8080:443

# Open: https://localhost:8080
# Username: admin
# Password: [from above]
```

### 6.3 Install ArgoCD CLI

```bash
# Install ArgoCD CLI
curl -sSL -o argocd https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
chmod +x argocd
sudo mv argocd /usr/local/bin/

# Login
argocd login 192.168.1.57:443 --username admin --password $(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d) --insecure
```

---

## 7. PostgreSQL Deployment

### 7.1 Deploy PostgreSQL

```bash
# Create namespace
kubectl create namespace keycloak

# Deploy PostgreSQL with custom configuration
cat <<'EOF' | kubectl apply -n keycloak -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: postgresql
  namespace: keycloak
spec:
  replicas: 1
  selector:
    matchLabels:
      app: postgresql
  template:
    metadata:
      labels:
        app: postgresql
    spec:
      containers:
      - name: postgresql
        image: bitnami/postgresql:latest
        env:
        - name: POSTGRESQL_USERNAME
          value: "keycloak"
        - name: POSTGRESQL_PASSWORD
          value: "keycloak-db-pass-2024!"
        - name: POSTGRESQL_DATABASE
          value: "keycloak"
        - name: POSTGRESQL_POSTGRES_PASSWORD
          value: "keycloak-db-pass-2024!"
        ports:
        - containerPort: 5432
        resources:
          requests:
            memory: "512Mi"
            cpu: "250m"
          limits:
            memory: "1Gi"
            cpu: "500m"
---
apiVersion: v1
kind: Service
metadata:
  name: postgresql
  namespace: keycloak
spec:
  selector:
    app: postgresql
  ports:
  - port: 5432
    targetPort: 5432
EOF

# Wait for PostgreSQL to be ready
kubectl wait --for=condition=ready pod -l app=postgresql -n keycloak --timeout=120s
```

### 7.2 Verify PostgreSQL

```bash
# Check PostgreSQL status
kubectl get pods -n keycloak

# Test connection
kubectl run test-psql -n keycloak --image=bitnami/postgresql:latest --rm -it --restart=Never -- \
  psql -h postgresql -U keycloak -d keycloak -c "SELECT version();"
```

---

## 8. Keycloak Deployment

### 8.1 Deploy Keycloak

```bash
# Deploy Keycloak with minimal configuration
cat <<'EOF' | kubectl apply -n keycloak -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: keycloak
  namespace: keycloak
spec:
  replicas: 1
  selector:
    matchLabels:
      app: keycloak
  template:
    metadata:
      labels:
        app: keycloak
    spec:
      containers:
      - name: keycloak
        image: quay.io/keycloak/keycloak:26.0.7
        ports:
        - containerPort: 8080
        env:
        - name: KEYCLOAK_ADMIN
          value: "admin"
        - name: KEYCLOAK_ADMIN_PASSWORD
          value: "B2B-Admin-2024!"
        - name: KC_DB
          value: "postgres"
        - name: KC_DB_URL
          value: "jdbc:postgresql://postgresql:5432/keycloak"
        - name: KC_DB_USERNAME
          value: "keycloak"
        - name: KC_DB_PASSWORD
          value: "keycloak-db-pass-2024!"
        - name: KC_HTTP_ENABLED
          value: "true"
        - name: KC_HEALTH_ENABLED
          value: "true"
        - name: KC_METRICS_ENABLED
          value: "true"
        args:
        - "start-dev"
        - "--http-port=8080"
        - "--http-enabled=true"
        - "--hostname-strict=false"
        resources:
          requests:
            memory: "1024Mi"
            cpu: "500m"
          limits:
            memory: "2048Mi"
            cpu: "1000m"
---
apiVersion: v1
kind: Service
metadata:
  name: keycloak
  namespace: keycloak
spec:
  selector:
    app: keycloak
  ports:
  - port: 8080
    targetPort: 8080
EOF

# Wait for Keycloak to be ready
kubectl wait --for=condition=ready pod -l app=keycloak -n keycloak --timeout=180s
```

### 8.2 Verify Keycloak

```bash
# Check Keycloak logs
kubectl logs -n keycloak deployment/keycloak --tail=20

# Check service endpoints
kubectl get endpoints keycloak -n keycloak

# Test Keycloak from inside the cluster
kubectl run test-keycloak -n keycloak --image=curlimages/curl --rm -it --restart=Never -- \
  curl -s -o /dev/null -w "%{http_code}\n" http://keycloak:8080/health
```

**Expected Output:** `404` (Keycloak is responding but health endpoint requires specific path)

---

## 9. Ingress Configuration

### 9.1 Create Ingress

```bash
# Create ingress for Keycloak
cat <<'EOF' | kubectl apply -n keycloak -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: keycloak
  namespace: keycloak
  annotations:
    nginx.ingress.kubernetes.io/proxy-body-size: "50m"
    nginx.ingress.kubernetes.io/proxy-read-timeout: "300"
    nginx.ingress.kubernetes.io/proxy-send-timeout: "300"
    nginx.ingress.kubernetes.io/ssl-redirect: "false"
    nginx.ingress.kubernetes.io/backend-protocol: "HTTP"
spec:
  ingressClassName: nginx
  rules:
  - host: keycloak.b2b.local
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: keycloak
            port:
              number: 8080
EOF

# Verify ingress
kubectl get ingress keycloak -n keycloak
```

### 9.2 Test Ingress

```bash
# Test via curl
curl -H "Host: keycloak.b2b.local" http://192.168.1.56/ -v

# Should return 302 Found
curl http://keycloak.b2b.local/admin/ -v

# Should return 302 Found
```

**Expected Output:**
```
HTTP/1.1 302 Found
Location: http://keycloak.b2b.local/admin/master/console/
```

---

## 10. ArgoCD GitOps Integration

### 10.1 Create Git Repository Structure

```bash
# Create Git repository structure
mkdir -p ~/projects/b2b-keycloak-gitops
cd ~/projects/b2b-keycloak-gitops

# Create directory structure
mkdir -p kubernetes/{keycloak,postgresql,ingress}

# Create Keycloak manifest
cat > kubernetes/keycloak/deployment.yaml <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: keycloak
  namespace: keycloak
spec:
  replicas: 1
  selector:
    matchLabels:
      app: keycloak
  template:
    metadata:
      labels:
        app: keycloak
    spec:
      containers:
      - name: keycloak
        image: quay.io/keycloak/keycloak:26.0.7
        ports:
        - containerPort: 8080
        env:
        - name: KEYCLOAK_ADMIN
          value: "admin"
        - name: KEYCLOAK_ADMIN_PASSWORD
          value: "B2B-Admin-2024!"
        - name: KC_DB
          value: "postgres"
        - name: KC_DB_URL
          value: "jdbc:postgresql://postgresql:5432/keycloak"
        - name: KC_DB_USERNAME
          value: "keycloak"
        - name: KC_DB_PASSWORD
          value: "keycloak-db-pass-2024!"
        - name: KC_HTTP_ENABLED
          value: "true"
        - name: KC_HEALTH_ENABLED
          value: "true"
        - name: KC_METRICS_ENABLED
          value: "true"
        args:
        - "start-dev"
        - "--http-port=8080"
        - "--http-enabled=true"
        - "--hostname-strict=false"
        resources:
          requests:
            memory: "1024Mi"
            cpu: "500m"
          limits:
            memory: "2048Mi"
            cpu: "1000m"
---
apiVersion: v1
kind: Service
metadata:
  name: keycloak
  namespace: keycloak
spec:
  selector:
    app: keycloak
  ports:
  - port: 8080
    targetPort: 8080
EOF

# Create PostgreSQL manifest
cat > kubernetes/postgresql/deployment.yaml <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: postgresql
  namespace: keycloak
spec:
  replicas: 1
  selector:
    matchLabels:
      app: postgresql
  template:
    metadata:
      labels:
        app: postgresql
    spec:
      containers:
      - name: postgresql
        image: bitnami/postgresql:latest
        env:
        - name: POSTGRESQL_USERNAME
          value: "keycloak"
        - name: POSTGRESQL_PASSWORD
          value: "keycloak-db-pass-2024!"
        - name: POSTGRESQL_DATABASE
          value: "keycloak"
        - name: POSTGRESQL_POSTGRES_PASSWORD
          value: "keycloak-db-pass-2024!"
        ports:
        - containerPort: 5432
---
apiVersion: v1
kind: Service
metadata:
  name: postgresql
  namespace: keycloak
spec:
  selector:
    app: postgresql
  ports:
  - port: 5432
    targetPort: 5432
EOF

# Create Ingress manifest
cat > kubernetes/ingress/ingress.yaml <<'EOF'
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: keycloak
  namespace: keycloak
  annotations:
    nginx.ingress.kubernetes.io/proxy-body-size: "50m"
    nginx.ingress.kubernetes.io/proxy-read-timeout: "300"
    nginx.ingress.kubernetes.io/proxy-send-timeout: "300"
    nginx.ingress.kubernetes.io/ssl-redirect: "false"
    nginx.ingress.kubernetes.io/backend-protocol: "HTTP"
spec:
  ingressClassName: nginx
  rules:
  - host: keycloak.b2b.local
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: keycloak
            port:
              number: 8080
EOF

# Initialize Git repository
git init
git add .
git commit -m "Initial Keycloak GitOps configuration"
```

### 10.2 Create ArgoCD Application

```bash
# Create ArgoCD Application
cat <<'EOF' | kubectl apply -f -
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: keycloak
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  source:
    repoURL: https://github.com/your-org/b2b-keycloak.git
    targetRevision: main
    path: kubernetes
  destination:
    server: https://kubernetes.default.svc
    namespace: keycloak
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
      - PruneLast=true
      - Validate=true
    retry:
      limit: 5
      backoff:
        duration: 5s
        factor: 2
        maxDuration: 3m
EOF

# Check ArgoCD status
kubectl get application keycloak -n argocd
```

---

## 11. Keycloak Configuration

### 11.1 Access Keycloak Admin Console

```bash
# Port-forward for admin access (recommended)
kubectl port-forward svc/keycloak -n keycloak 8080:8080

# Then open: http://localhost:8080
# Username: admin
# Password: B2B-Admin-2024!
```

### 11.2 Create B2B Realm

1. **Login** to Keycloak admin console (`http://localhost:8080`)
2. **Hover over "master"** in the top-left corner
3. **Click "Create Realm"**
4. **Name:** `b2b-enterprise`
5. **Click "Create"**

### 11.3 Configure Clients

```
# In Keycloak UI (b2b-enterprise realm):
# 1. Go to "Clients"
# 2. Click "Create client"
# 3. Client ID: b2b-app
# 4. Client protocol: OpenID Connect
# 5. Root URL: http://your-b2b-app.com
# 6. Click "Save"
```

### 11.4 Create Roles

```
# 1. Go to "Realm roles"
# 2. Click "Create role"
# 3. Create these roles:
#    - b2b-admin (administrators)
#    - b2b-manager (business managers)
#    - b2b-user (standard users)
# 4. Click "Save" after each
```

### 11.5 Create Users (40 Users)

```
# 1. Go to "Users"
# 2. Click "Add user"
# 3. Fill in:
#    - Username: user1, user2, etc.
#    - Email: user1@b2b.com
#    - First name: User
#    - Last name: 1
# 4. Click "Create"
# 5. Go to "Credentials" tab
# 6. Set password (temporary or permanent)
# 7. Go to "Role mapping" tab
# 8. Assign appropriate roles
# 9. Repeat for all 40 users
```

### 11.6 API-Based Configuration (Optional)

```bash
# Get access token
TOKEN=$(curl -s -X POST http://localhost:8080/realms/master/protocol/openid-connect/token \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "client_id=admin-cli" \
  -d "username=admin" \
  -d "password=B2B-Admin-2024!" \
  -d "grant_type=password" | jq -r '.access_token')

# Create b2b-enterprise realm
curl -X POST http://localhost:8080/admin/realms \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "realm": "b2b-enterprise",
    "enabled": true,
    "displayName": "B2B Enterprise Portal",
    "loginWithEmailAllowed": true,
    "duplicateEmailsAllowed": false,
    "resetPasswordAllowed": true,
    "editUsernameAllowed": false
  }'

# Create client
curl -X POST http://localhost:8080/admin/realms/b2b-enterprise/clients \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "clientId": "b2b-app",
    "name": "B2B Application",
    "protocol": "openid-connect",
    "publicClient": true,
    "standardFlowEnabled": true,
    "implicitFlowEnabled": false,
    "directAccessGrantsEnabled": true
  }'

# Create roles
for role in "b2b-admin" "b2b-manager" "b2b-user"; do
  curl -X POST http://localhost:8080/admin/realms/b2b-enterprise/roles \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d "{\"name\": \"$role\"}"
done
```

---

## 12. Troubleshooting Guide

### 12.1 Common Issues and Solutions

#### Issue 1: Image Pull Errors
```bash
# Check if image exists
docker manifest inspect quay.io/keycloak/keycloak:26.0.7

# Use specific image tag
kubectl set image deployment/keycloak keycloak=quay.io/keycloak/keycloak:26.0.7 -n keycloak
```

#### Issue 2: Service Endpoints Missing
```bash
# Check service selector
kubectl get svc keycloak -n keycloak -o yaml | grep selector

# Check pod labels
kubectl get pods -n keycloak -l app=keycloak --show-labels

# Fix selector if needed
kubectl patch svc keycloak -n keycloak -p '{"spec":{"selector":{"app":"keycloak"}}}'
```

#### Issue 3: 503 Service Unavailable
```bash
# Check if endpoints exist
kubectl get endpoints keycloak -n keycloak

# If no endpoints, manually set them
POD_IP=$(kubectl get pods -n keycloak -l app=keycloak -o jsonpath='{.items[0].status.podIP}')
kubectl patch endpoints keycloak -n keycloak --type='json' -p='[{"op":"add","path":"/subsets","value":[{"addresses":[{"ip":"'$POD_IP'"}],"ports":[{"port":8080,"protocol":"TCP"}]}]}]'
```

#### Issue 4: Keycloak Admin Console Not Loading
```bash
# Use port-forward instead of ingress
kubectl port-forward svc/keycloak -n keycloak 8080:8080
# Access: http://localhost:8080
```

#### Issue 5: Port 8080 Already in Use
```bash
# Kill existing port-forward
pkill -f "port-forward.*keycloak"

# Check what's using port 8080
sudo lsof -i :8080

# Use a different port
kubectl port-forward svc/keycloak -n keycloak 8081:8080
# Access: http://localhost:8081
```

### 12.2 Logs and Debugging

```bash
# Check Keycloak logs
kubectl logs -n keycloak deployment/keycloak --tail=50

# Follow logs in real-time
kubectl logs -f -n keycloak deployment/keycloak

# Check pod events
kubectl describe pod -n keycloak -l app=keycloak

# Check all events in namespace
kubectl get events -n keycloak --sort-by='.lastTimestamp'
```

### 12.3 Reset Deployment

```bash
# Delete namespace and redeploy
kubectl delete namespace keycloak
kubectl create namespace keycloak

# Redeploy PostgreSQL
kubectl apply -n keycloak -f kubernetes/postgresql/deployment.yaml

# Redeploy Keycloak
kubectl apply -n keycloak -f kubernetes/keycloak/deployment.yaml

# Redeploy Ingress
kubectl apply -n keycloak -f kubernetes/ingress/ingress.yaml
```

---

## 13. Maintenance and Operations

### 13.1 Backup PostgreSQL

```bash
# Backup PostgreSQL database
kubectl exec -n keycloak deployment/postgresql -- \
  pg_dump -U keycloak keycloak > keycloak_backup_$(date +%Y%m%d).sql

# Restore from backup
kubectl exec -n keycloak deployment/postgresql -i -- \
  psql -U keycloak keycloak < keycloak_backup_20260123.sql
```

### 13.2 Backup Keycloak Configuration

```bash
# Export Keycloak realm
kubectl exec -n keycloak deployment/keycloak -- \
  /opt/keycloak/bin/kc.sh export \
  --dir /tmp/export \
  --realm b2b-enterprise \
  --users realm

# Copy export to local
kubectl cp keycloak/$(kubectl get pods -n keycloak -l app=keycloak -o jsonpath='{.items[0].metadata.name}'):/tmp/export ./keycloak-export
```

### 13.3 Scaling

```bash
# Scale Keycloak
kubectl scale deployment keycloak -n keycloak --replicas=3

# Scale PostgreSQL (requires StatefulSet)
kubectl scale statefulset postgresql -n keycloak --replicas=2
```

### 13.4 Updates

```bash
# Update Keycloak image
kubectl set image deployment/keycloak keycloak=quay.io/keycloak/keycloak:26.0.8 -n keycloak

# Rollback if needed
kubectl rollout undo deployment/keycloak -n keycloak

# Check rollout status
kubectl rollout status deployment/keycloak -n keycloak
```

### 13.5 Monitoring

```bash
# Check resource usage
kubectl top pods -n keycloak

# Check events
kubectl get events -n keycloak --sort-by='.lastTimestamp'

# Check pod health
kubectl get pods -n keycloak -o wide
```

---

## 14. Security Considerations

### 14.1 Production Hardening

1. **Enable TLS/SSL**
   ```bash
   # Install cert-manager
   kubectl apply -f https://github.com/cert-manager/cert-manager/releases/latest/download/cert-manager.yaml

   # Create Certificate resource
   cat <<'EOF' | kubectl apply -n keycloak -f -
   apiVersion: cert-manager.io/v1
   kind: Certificate
   metadata:
     name: keycloak-tls
     namespace: keycloak
   spec:
     secretName: keycloak-tls-secret
     dnsNames:
     - keycloak.b2b.local
     issuerRef:
       name: letsencrypt-prod
       kind: ClusterIssuer
   EOF
   ```

2. **Change Default Passwords**
   ```bash
   # Update Keycloak admin password
   kubectl set env deployment/keycloak -n keycloak \
     KEYCLOAK_ADMIN_PASSWORD="NewStrongPassword123!"

   # Update PostgreSQL password
   kubectl set env deployment/postgresql -n keycloak \
     POSTGRESQL_PASSWORD="NewDbPassword123!"
   ```

3. **Network Policies**
   ```bash
   # Apply network policy
   cat <<'EOF' | kubectl apply -n keycloak -f -
   apiVersion: networking.k8s.io/v1
   kind: NetworkPolicy
   metadata:
     name: keycloak-network-policy
   spec:
     podSelector:
       matchLabels:
         app: keycloak
     policyTypes:
     - Ingress
     - Egress
     ingress:
     - from:
       - namespaceSelector:
           matchLabels:
             name: ingress-nginx
   EOF
   ```

4. **Resource Limits**
   ```yaml
   # Ensure resource limits are set
   resources:
     requests:
       memory: "1024Mi"
       cpu: "500m"
     limits:
       memory: "2048Mi"
       cpu: "1000m"
   ```

5. **Audit Logging**
   ```bash
   # Enable audit logging
   kubectl set env deployment/keycloak -n keycloak \
     KC_LOG_LEVEL="INFO" \
     KC_AUDIT_LOG_ENABLED="true"
   ```

---

## 15. Complete Status Verification

### 15.1 Final Checklist

```bash
# 1. Verify all pods are running
kubectl get pods -n keycloak

# 2. Verify services
kubectl get svc -n keycloak

# 3. Verify ingress
kubectl get ingress -n keycloak

# 4. Verify connectivity
curl -I http://keycloak.b2b.local/

# 5. Verify admin console
curl -I http://keycloak.b2b.local/admin/

# 6. Check ArgoCD sync status
kubectl get application keycloak -n argocd

# 7. Test authentication
curl -X POST http://keycloak.b2b.local/realms/master/protocol/openid-connect/token \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "client_id=admin-cli" \
  -d "username=admin" \
  -d "password=B2B-Admin-2024!" \
  -d "grant_type=password"
```

### 15.2 Access Methods Summary

| Access Method | URL | Purpose |
|--------------|-----|---------|
| **Keycloak Admin** | `http://localhost:8080` | Admin console (via port-forward) |
| **Keycloak Application** | `http://keycloak.b2b.local` | Application access (via ingress) |
| **ArgoCD** | `https://localhost:8080` | GitOps management (via port-forward) |
| **Keycloak API** | `http://keycloak.b2b.local/realms/master/protocol/openid-connect/token` | Token endpoint |

---

## 16. Quick Reference Commands

### 16.1 Deploy Commands

```bash
# Start cluster
vagrant up

# Deploy Keycloak
kubectl apply -f kubernetes/postgresql/deployment.yaml
kubectl apply -f kubernetes/keycloak/deployment.yaml
kubectl apply -f kubernetes/ingress/ingress.yaml

# Deploy ArgoCD application
kubectl apply -f argocd-apps/keycloak.yaml
```

### 16.2 Access Commands

```bash
# Keycloak admin (port-forward)
kubectl port-forward svc/keycloak -n keycloak 8080:8080

# ArgoCD UI (port-forward)
kubectl port-forward svc/argocd-server -n argocd 8080:443

# Ingress test
curl http://keycloak.b2b.local/admin/
```

### 16.3 Debug Commands

```bash
# Check logs
kubectl logs -n keycloak deployment/keycloak --tail=50

# Check endpoints
kubectl get endpoints keycloak -n keycloak

# Restart deployment
kubectl rollout restart deployment/keycloak -n keycloak

# Scale deployment
kubectl scale deployment/keycloak -n keycloak --replicas=2
```

---

## Appendix A: Environment Variables

### Keycloak Environment Variables

| Variable | Value | Purpose |
|----------|-------|---------|
| `KEYCLOAK_ADMIN` | `admin` | Admin username |
| `KEYCLOAK_ADMIN_PASSWORD` | `B2B-Admin-2024!` | Admin password |
| `KC_DB` | `postgres` | Database type |
| `KC_DB_URL` | `jdbc:postgresql://postgresql:5432/keycloak` | Database URL |
| `KC_DB_USERNAME` | `keycloak` | Database username |
| `KC_DB_PASSWORD` | `keycloak-db-pass-2024!` | Database password |
| `KC_HTTP_ENABLED` | `true` | Enable HTTP |
| `KC_HEALTH_ENABLED` | `true` | Enable health endpoints |
| `KC_METRICS_ENABLED` | `true` | Enable metrics |

### PostgreSQL Environment Variables

| Variable | Value | Purpose |
|----------|-------|---------|
| `POSTGRESQL_USERNAME` | `keycloak` | Database username |
| `POSTGRESQL_PASSWORD` | `keycloak-db-pass-2024!` | Database password |
| `POSTGRESQL_DATABASE` | `keycloak` | Database name |
| `POSTGRESQL_POSTGRES_PASSWORD` | `keycloak-db-pass-2024!` | PostgreSQL superuser password |

---

## Appendix B: Troubleshooting Commands

### Quick Debug Commands

```bash
# Complete status check
kubectl get all -n keycloak

# Check pod logs with timestamps
kubectl logs -n keycloak deployment/keycloak --timestamps

# Check ingress controller logs
kubectl logs -n ingress-nginx deployment/ingress-nginx-controller --tail=50

# Check MetalLB logs
kubectl logs -n metallb-system daemonset/speaker --tail=20

# Test DNS resolution
kubectl run test-dns -n keycloak --image=busybox --rm -it --restart=Never -- nslookup keycloak

# Test network connectivity
kubectl run test-net -n keycloak --image=busybox --rm -it --restart=Never -- wget -q -O- keycloak:8080

# Get detailed pod information
kubectl describe pod -n keycloak -l app=keycloak
```

---

## Conclusion

Congratulations! You now have a fully functional Keycloak deployment on a 3-node Kubernetes cluster for your B2B application with 40 users. The deployment includes:

- ✅ High-availability Kubernetes cluster
- ✅ LoadBalancer with MetalLB
- ✅ Ingress routing with Nginx
- ✅ GitOps management with ArgoCD
- ✅ PostgreSQL database
- ✅ Keycloak IAM with 40-user capacity
- ✅ Admin console accessible via port-forward
- ✅ Application access via ingress

### Next Steps

1. **Configure your B2B application** to use Keycloak for authentication
2. **Set up SSO** for your applications
3. **Create users** and assign appropriate roles
4. **Monitor** the deployment with your favorite tools
5. **Enable TLS** for production use
6. **Set up automated backups** for PostgreSQL
7. **Implement CI/CD pipelines** using ArgoCD
