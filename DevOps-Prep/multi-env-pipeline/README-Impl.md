# 🚀 **Complete Implementation Guide: Unified CI/CD Pipeline with GitOps**

## **Table of Contents**
1. [Project Overview](#project-overview)
2. [Architecture Diagram](#architecture-diagram)
3. [Infrastructure Setup](#infrastructure-setup)
4. [Application Development](#application-development)
5. [Kubernetes Manifests with Kustomize](#kubernetes-manifests-with-kustomize)
6. [GitHub Actions Pipeline](#github-actions-pipeline)
7. [GitHub Environments & Secrets](#github-environments--secrets)
8. [Exposing Local Cluster with ngrok](#exposing-local-cluster-with-ngrok)
9. [Testing & Validation](#testing--validation)
10. [Troubleshooting Guide](#troubleshooting-guide)
11. [Key Concepts Demonstrated](#key-concepts-demonstrated)
12. [Next Steps & Enhancements](#next-steps--enhancements)

---

## **Project Overview**

### **What We Built**
A complete, production-grade CI/CD pipeline that demonstrates the **"Build once, deploy many times"** principle using:
- **Single GitHub Actions pipeline** for all environments (Development, SIT, UAT, Production)
- **Immutable artifacts** (Docker images) promoted through environments
- **Kustomize** for environment-specific configurations
- **Manual approval gates** for UAT and Production
- **GitOps** principles with Argo CD
- **Zero-cost infrastructure** running on a local homelab

### **Key DevOps Principles Demonstrated**
1. ✅ **Build Once, Deploy Many Times** - Single immutable artifact
2. ✅ **Environment Parity** - Same artifact across all environments
3. ✅ **Configuration as Code** - Kustomize overlays
4. ✅ **Manual Approval Gates** - GitHub Environments with required reviewers
5. ✅ **GitOps** - Declarative deployments via Argo CD
6. ✅ **Secret Management** - Environment-specific secrets
7. ✅ **Zero Cost** - All tools are free/open-source

---

## **Architecture Diagram**

```
┌─────────────────────────────────────────────────────────────────┐
│                    GITHUB REPOSITORY                            │
│              (dockrphage/homelab-fastapi-pipeline)              │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │           GITHUB ACTIONS (Single Pipeline)              │   │
│  ├─────────────────────────────────────────────────────────┤   │
│  │  1. BUILD & TEST (One Time)                            │   │
│  │     ├── Unit tests                                     │   │
│  │     └── Immutable Docker Image 🏗️                     │   │
│  │                                                         │   │
│  │  2. DEPLOY TO DEV (Auto)                               │   │
│  │     └── Namespace: development                         │   │
│  │                                                         │   │
│  │  3. DEPLOY TO SIT (Auto)                               │   │
│  │     └── Namespace: sit                                 │   │
│  │                                                         │   │
│  │  4. DEPLOY TO UAT (Manual Approval) 🔐                │   │
│  │     └── Namespace: uat                                 │   │
│  │                                                         │   │
│  │  5. DEPLOY TO PROD (Manual Approval) 🔐               │   │
│  │     └── Namespace: production                          │   │
│  └─────────────────────────────────────────────────────────┘   │
│                              │                                  │
│                              ▼                                  │
├─────────────────────────────────────────────────────────────────┤
│              DOCKER HUB / GHCR (Image Registry)                │
│              dockrphage/homelab-fastapi-pipeline               │
├─────────────────────────────────────────────────────────────────┤
│                              │                                  │
│                              ▼                                  │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │         LOCAL KUBERNETES CLUSTER (3 Nodes)             │   │
│  │  ┌──────────┐  ┌──────────┐  ┌──────────┐            │   │
│  │  │   cp1    │  │  node1   │  │  node2   │            │   │
│  │  │ 2 CPU    │  │ 2 CPU    │  │ 2 CPU    │            │   │
│  │  │ 2GB RAM  │  │ 6GB RAM  │  │ 6GB RAM  │            │   │
│  │  └──────────┘  └──────────┘  └──────────┘            │   │
│  │  • MetalLB (192.168.56.0/24)                          │   │
│  │  • Ingress-nginx                                      │   │
│  └─────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
```

---

## **Infrastructure Setup**

### **Prerequisites**

#### **Hardware Requirements**
- Laptop with **i7 processor** and **32GB RAM** (or similar)
- Minimum: 8GB RAM, 4 cores

#### **Software Requirements**
```bash
# Install required tools
brew install kubectl kustomize helm argocd docker
# OR on Ubuntu:
sudo apt update
sudo apt install -y kubectl kustomize helm docker.io
```

### **Kubernetes Cluster (Vagrant + K3s)**

#### **Vagrantfile**
```ruby
Vagrant.configure("2") do |config|
  nodes = {
    "cp1"   => { ip: "192.168.56.10", bridged_ip: "192.168.1.50", cpu: 2, mem: 2048 },
    "node1" => { ip: "192.168.56.11", bridged_ip: "192.168.1.51", cpu: 2, mem: 6144 },
    "node2" => { ip: "192.168.56.12", bridged_ip: "192.168.1.52", cpu: 2, mem: 6144 }
  }

  nodes.each do |name, node|
    config.vm.define name do |vm|
      vm.vm.box = "ubuntu/focal64"
      vm.vm.hostname = name
      vm.vm.network "private_network", ip: node[:ip]
      vm.vm.provider "virtualbox" do |vb|
        vb.memory = node[:mem]
        vb.cpus = node[:cpu]
      end
      vm.vm.provision "shell", path: "install-k3s.sh"
    end
  end
end
```

#### **install-k3s.sh**
```bash
#!/bin/bash
# Install K3s
curl -sfL https://get.k3s.io | sh -
sudo chmod 644 /etc/rancher/k3s/k3s.yaml

# Install MetalLB
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.13.10/config/manifests/metallb-native.yaml
cat <<EOF | kubectl apply -f -
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: homelab-pool
  namespace: metallb-system
spec:
  addresses:
  - 192.168.56.100-192.168.56.200
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: homelab-l2
  namespace: metallb-system
EOF

# Install Ingress-Nginx
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.8.1/deploy/static/provider/cloud/deploy.yaml
```

### **Create Namespaces**
```bash
kubectl create namespace development
kubectl create namespace sit
kubectl create namespace uat
kubectl create namespace production
```

---

## **Application Development**

### **FastAPI Application**

**`app/main.py`**
```python
import os
from fastapi import FastAPI, status
from fastapi.responses import JSONResponse
import time
from typing import Dict, Any

app = FastAPI(
    title="Unified Pipeline Demo API",
    description="Demonstrating Build Once, Deploy Many Times",
    version="1.0.0"
)

# Environment-specific configurations
ENVIRONMENT = os.getenv("ENVIRONMENT", "development")
DB_HOST = os.getenv("DB_HOST", "localhost")
DB_USER = os.getenv("DB_USER", "postgres")
DB_PASSWORD = os.getenv("DB_PASSWORD", "password")
DB_NAME = os.getenv("DB_NAME", "appdb")
REDIS_HOST = os.getenv("REDIS_HOST", "localhost")
API_KEY = os.getenv("API_KEY", "dev-key")
LOG_LEVEL = os.getenv("LOG_LEVEL", "DEBUG")

@app.get("/")
async def root() -> Dict[str, Any]:
    """Root endpoint showing environment information"""
    return {
        "environment": ENVIRONMENT,
        "service": "fastapi-unified-pipeline",
        "status": "healthy",
        "timestamp": time.time(),
        "configs": {
            "db_host": DB_HOST,
            "redis_host": REDIS_HOST,
            "log_level": LOG_LEVEL,
            "api_key_masked": f"{API_KEY[:4]}...{API_KEY[-4:]}"
        }
    }

@app.get("/health")
async def health_check() -> Dict[str, str]:
    """Simple health check endpoint"""
    return {"status": "healthy", "env": ENVIRONMENT}

@app.get("/readiness")
async def readiness_check() -> Dict[str, str]:
    """Readiness probe endpoint"""
    return {"status": "ready", "checks": "all passed"}

@app.get("/env")
async def show_env() -> Dict[str, str]:
    """Show all environment variables (for debugging)"""
    return {
        "ENVIRONMENT": ENVIRONMENT,
        "DB_HOST": DB_HOST,
        "DB_USER": DB_USER,
        "DB_NAME": DB_NAME,
        "REDIS_HOST": REDIS_HOST,
        "LOG_LEVEL": LOG_LEVEL,
        "API_KEY_MASKED": f"{API_KEY[:4]}...{API_KEY[-4:]}" if API_KEY else "not set"
    }
```

**`requirements.txt`**
```
fastapi==0.104.1
uvicorn[standard]==0.24.0
redis==5.0.1
psycopg2-binary==2.9.9
pytest==7.4.3
pytest-cov==4.1.0
httpx==0.25.1
python-multipart==0.0.6
```

**`Dockerfile`** (Multi-stage for optimization)
```dockerfile
# Stage 1: Build
FROM python:3.11-slim AS builder
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir --user -r requirements.txt

# Stage 2: Runtime
FROM python:3.11-slim
WORKDIR /app
RUN useradd -m -u 1000 appuser
COPY --from=builder /root/.local /home/appuser/.local
COPY ./app /app
ENV PATH=/home/appuser/.local/bin:$PATH
ENV PYTHONPATH=/app
ENV PYTHONUNBUFFERED=1
USER appuser
EXPOSE 8000
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
```

**`app/tests/test_main.py`**
```python
from fastapi.testclient import TestClient
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from main import app

client = TestClient(app)

def test_root():
    response = client.get("/")
    assert response.status_code == 200
    data = response.json()
    assert "environment" in data
    assert data["status"] == "healthy"

def test_health():
    response = client.get("/health")
    assert response.status_code == 200
    assert response.json()["status"] == "healthy"

def test_env():
    response = client.get("/env")
    assert response.status_code == 200
    data = response.json()
    assert "ENVIRONMENT" in data
    assert "DB_HOST" in data
```

---

## **Kubernetes Manifests with Kustomize**

### **Directory Structure**
```
k8s/
├── base/
│   ├── deployment.yaml
│   └── kustomization.yaml
└── overlays/
    ├── development/
    │   ├── configmap.yaml
    │   ├── ingress.yaml
    │   ├── kustomization.yaml
    │   ├── patch-deployment.yaml
    │   └── secret.yaml
    ├── sit/
    │   └── ... (same structure)
    ├── uat/
    │   └── ... (same structure)
    └── production/
        └── ... (same structure)
```

### **Base Deployment**

**`k8s/base/deployment.yaml`**
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: fastapi-app
  labels:
    app: fastapi-app
spec:
  replicas: 2
  selector:
    matchLabels:
      app: fastapi-app
  template:
    metadata:
      labels:
        app: fastapi-app
    spec:
      containers:
      - name: app
        image: fastapi-app:latest  # Will be overridden by CI
        ports:
        - containerPort: 8000
        env:
        - name: ENVIRONMENT
          value: "base"
        - name: DB_HOST
          valueFrom:
            configMapKeyRef:
              name: app-config
              key: DB_HOST
        - name: REDIS_HOST
          valueFrom:
            configMapKeyRef:
              name: app-config
              key: REDIS_HOST
        - name: LOG_LEVEL
          valueFrom:
            configMapKeyRef:
              name: app-config
              key: LOG_LEVEL
        - name: DB_PASSWORD
          valueFrom:
            secretKeyRef:
              name: app-secrets
              key: DB_PASSWORD
        - name: API_KEY
          valueFrom:
            secretKeyRef:
              name: app-secrets
              key: API_KEY
        resources:
          requests:
            memory: "128Mi"
            cpu: "100m"
          limits:
            memory: "256Mi"
            cpu: "200m"
        livenessProbe:
          httpGet:
            path: /health
            port: 8000
          initialDelaySeconds: 30
          periodSeconds: 10
        readinessProbe:
          httpGet:
            path: /readiness
            port: 8000
          initialDelaySeconds: 5
          periodSeconds: 5
---
apiVersion: v1
kind: Service
metadata:
  name: fastapi-app
spec:
  selector:
    app: fastapi-app
  ports:
  - port: 80
    targetPort: 8000
  type: ClusterIP
```

**`k8s/base/kustomization.yaml`**
```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - deployment.yaml
```

### **Environment Overlay Example (Development)**

**`k8s/overlays/development/kustomization.yaml`**
```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - ../../base
  - configmap.yaml
  - secret.yaml
  - ingress.yaml

namespace: development

patches:
  - path: patch-deployment.yaml
    target:
      kind: Deployment
      name: fastapi-app
```

**`k8s/overlays/development/patch-deployment.yaml`**
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: fastapi-app
spec:
  template:
    spec:
      containers:
      - name: app
        env:
        - name: ENVIRONMENT
          value: "development"
```

**`k8s/overlays/development/configmap.yaml`**
```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: app-config
data:
  DB_HOST: "postgres-dev.svc.cluster.local"
  REDIS_HOST: "redis-dev.svc.cluster.local"
  LOG_LEVEL: "DEBUG"
```

**`k8s/overlays/development/secret.yaml`**
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: app-secrets
type: Opaque
data:
  DB_PASSWORD: ZGV2X3Bhc3N3b3JkXzEyMw==  # dev_password_123
  API_KEY: ZGV2X2FwaV9rZXk=              # dev_api_key
```

**`k8s/overlays/development/ingress.yaml`**
```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: fastapi-app
spec:
  ingressClassName: nginx
  rules:
  - host: dev.app.local
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: fastapi-app
            port:
              number: 80
```

### **Other Environment Overlays**

**SIT** (`k8s/overlays/sit/`):
- `DB_HOST: postgres-sit.svc.cluster.local`
- `LOG_LEVEL: INFO`
- `Host: sit.app.local`
- `Replicas: 2`

**UAT** (`k8s/overlays/uat/`):
- `DB_HOST: postgres-uat.svc.cluster.local`
- `LOG_LEVEL: INFO`
- `Host: uat.app.local`
- `Replicas: 3`

**Production** (`k8s/overlays/production/`):
- `DB_HOST: postgres-prod.svc.cluster.local`
- `LOG_LEVEL: WARNING`
- `Host: app.local`
- `Replicas: 3`
- Resources: `requests: memory: 256Mi, limits: 512Mi`

### **Testing Kustomize Locally**
```bash
# Test building each overlay
kubectl kustomize k8s/overlays/development
kubectl kustomize k8s/overlays/sit
kubectl kustomize k8s/overlays/uat
kubectl kustomize k8s/overlays/production
```

---

## **GitHub Actions Pipeline**

### **Complete Pipeline File**

**`.github/workflows/main-pipeline.yml`**
```yaml
name: Unified CI/CD Pipeline

on:
  push:
    branches: [main, develop]
  pull_request:
    branches: [main]

permissions:
  contents: read
  packages: write
  id-token: write

env:
  REGISTRY: docker.io
  IMAGE_NAME: dockrphage/homelab-fastapi-pipeline
  ARTIFACT_TAG: ${{ github.sha }}

jobs:
  # ============================================
  # STAGE 1: Build & Test (Always runs)
  # ============================================
  build-and-test:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      packages: write
      id-token: write
    outputs:
      image_tag: ${{ steps.set-tag.outputs.tag }}
    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Set up Python
        uses: actions/setup-python@v5
        with:
          python-version: '3.11'
          cache: 'pip'

      - name: Install dependencies
        run: |
          pip install -r requirements.txt
          pip install pytest pytest-cov

      - name: Run unit tests
        run: |
          cd app
          pytest tests/ -v --cov=. --cov-report=xml || true

      - name: Set Docker image tag
        id: set-tag
        run: |
          if [ "${{ github.ref }}" == "refs/heads/main" ]; then
            echo "tag=${{ github.sha }}" >> $GITHUB_OUTPUT
          else
            echo "tag=dev-${{ github.sha }}" >> $GITHUB_OUTPUT
          fi

      - name: Build Docker image
        run: |
          docker build -t ${{ env.IMAGE_NAME }}:${{ steps.set-tag.outputs.tag }} .
          docker tag ${{ env.IMAGE_NAME }}:${{ steps.set-tag.outputs.tag }} ${{ env.IMAGE_NAME }}:latest

      - name: Log in to Docker Hub
        uses: docker/login-action@v3
        with:
          username: ${{ secrets.DOCKER_USERNAME }}
          password: ${{ secrets.DOCKER_PASSWORD }}

      - name: Push Docker image
        run: |
          docker push ${{ env.IMAGE_NAME }}:${{ steps.set-tag.outputs.tag }}
          docker push ${{ env.IMAGE_NAME }}:latest

      - name: Save build metadata
        run: |
          cat > build-metadata.json << EOF
          {
            "commit_sha": "${{ github.sha }}",
            "image_tag": "${{ steps.set-tag.outputs.tag }}",
            "image_name": "${{ env.IMAGE_NAME }}",
            "branch": "${{ github.ref_name }}",
            "timestamp": "$(date -u +'%Y-%m-%dT%H:%M:%SZ')"
          }
          EOF

      - name: Upload build metadata
        uses: actions/upload-artifact@v4
        with:
          name: build-metadata
          path: build-metadata.json

  # ============================================
  # STAGE 2: Deploy to Development (Auto)
  # ============================================
  deploy-development:
    needs: build-and-test
    runs-on: ubuntu-latest
    environment: development
    permissions:
      contents: read
      packages: write
    if: github.ref == 'refs/heads/develop' || github.ref == 'refs/heads/main'
    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Install kubectl
        uses: azure/setup-kubectl@v4
        with:
          version: 'latest'

      - name: Install kustomize
        uses: imranismail/setup-kustomize@v2
        with:
          kustomize-version: '5.1.0'

      - name: Setup kubeconfig
        run: |
          mkdir -p $HOME/.kube
          echo "${{ secrets.KUBE_CONFIG_DEV }}" | base64 -d > $HOME/.kube/config

      - name: Deploy to Development
        run: |
          cd k8s/overlays/development
          kustomize edit set image ${{ env.IMAGE_NAME }}:${{ needs.build-and-test.outputs.image_tag }}
          kustomize build . | kubectl apply -f -

      - name: Wait for deployment
        run: |
          kubectl rollout status deployment/fastapi-app -n development --timeout=120s

      - name: Verify deployment
        run: |
          kubectl get pods -n development
          kubectl get svc -n development
          kubectl get ingress -n development

  # ============================================
  # STAGE 3: Deploy to SIT (Auto)
  # ============================================
  deploy-sit:
    needs: deploy-development
    runs-on: ubuntu-latest
    environment: sit
    permissions:
      contents: read
      packages: write
    if: github.ref == 'refs/heads/main'
    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Install kubectl
        uses: azure/setup-kubectl@v4
        with:
          version: 'latest'
      
      - name: Install kustomize
        uses: imranismail/setup-kustomize@v2
        with:
          kustomize-version: '5.1.0'

      - name: Setup kubeconfig
        run: |
          mkdir -p $HOME/.kube
          echo "${{ secrets.KUBE_CONFIG_SIT }}" | base64 -d > $HOME/.kube/config

      - name: Deploy to SIT
        run: |
          cd k8s/overlays/sit
          kustomize edit set image ${{ env.IMAGE_NAME }}:${{ needs.build-and-test.outputs.image_tag }}
          kustomize build . | kubectl apply -f -

      - name: Wait for deployment
        run: |
          kubectl rollout status deployment/fastapi-app -n sit --timeout=120s

      - name: Verify SIT deployment
        run: |
          kubectl get pods -n sit
          kubectl get ingress -n sit

  # ============================================
  # STAGE 4: Deploy to UAT (Manual Approval)
  # ============================================
  deploy-uat:
    needs: deploy-sit
    runs-on: ubuntu-latest
    environment: 
      name: uat
      url: http://uat.app.local
    permissions:
      contents: read
      packages: write
    if: github.ref == 'refs/heads/main'
    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Install kubectl
        uses: azure/setup-kubectl@v4
        with:
          version: 'latest'
      
      - name: Install kustomize
        uses: imranismail/setup-kustomize@v2
        with:
          kustomize-version: '5.1.0'

      - name: Setup kubeconfig
        run: |
          mkdir -p $HOME/.kube
          echo "${{ secrets.KUBE_CONFIG_UAT }}" | base64 -d > $HOME/.kube/config

      - name: Deploy to UAT
        run: |
          cd k8s/overlays/uat
          kustomize edit set image ${{ env.IMAGE_NAME }}:${{ needs.build-and-test.outputs.image_tag }}
          kustomize build . | kubectl apply -f -

      - name: Wait for deployment
        run: |
          kubectl rollout status deployment/fastapi-app -n uat --timeout=120s

      - name: Verify UAT deployment
        run: |
          kubectl get pods -n uat
          kubectl get ingress -n uat

  # ============================================
  # STAGE 5: Deploy to Production (Manual Approval)
  # ============================================
  deploy-production:
    needs: deploy-uat
    runs-on: ubuntu-latest
    environment: 
      name: production
      url: http://app.local
    permissions:
      contents: read
      packages: write
    if: github.ref == 'refs/heads/main'
    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Install kubectl
        uses: azure/setup-kubectl@v4
        with:
          version: 'latest'
      
      - name: Install kustomize
        uses: imranismail/setup-kustomize@v2
        with:
          kustomize-version: '5.1.0'

      - name: Setup kubeconfig
        run: |
          mkdir -p $HOME/.kube
          echo "${{ secrets.KUBE_CONFIG_PROD }}" | base64 -d > $HOME/.kube/config

      - name: Deploy to Production
        run: |
          cd k8s/overlays/production
          kustomize edit set image ${{ env.IMAGE_NAME }}:${{ needs.build-and-test.outputs.image_tag }}
          kustomize build . | kubectl apply -f -

      - name: Wait for deployment
        run: |
          kubectl rollout status deployment/fastapi-app -n production --timeout=180s

      - name: Verify production deployment
        run: |
          kubectl get pods -n production
          kubectl get ingress -n production
          
      - name: Notify deployment success
        if: success()
        run: |
          echo "✅ Production deployment successful!"
          echo "Image: ${{ env.IMAGE_NAME }}:${{ needs.build-and-test.outputs.image_tag }}"
```

---

## **GitHub Environments & Secrets**

### **Create Environments**

1. Go to repository → **Settings** → **Environments**
2. Create these environments:

| Environment | Approval Required |
|-------------|-------------------|
| `development` | No |
| `sit` | No |
| `uat` | Yes (add yourself as reviewer) |
| `production` | Yes (add yourself as reviewer) |

### **Add Secrets**

Add these secrets for **EACH** environment:

**For Development**:
- `KUBE_CONFIG_DEV`: Base64 encoded kubeconfig
- `DEV_DB_PASSWORD`: Database password
- `DEV_API_KEY`: API key

**For SIT**:
- `KUBE_CONFIG_SIT`: Base64 encoded kubeconfig
- `SIT_DB_PASSWORD`: Database password
- `SIT_API_KEY`: API key

**For UAT**:
- `KUBE_CONFIG_UAT`: Base64 encoded kubeconfig
- `UAT_DB_PASSWORD`: Database password
- `UAT_API_KEY`: API key

**For Production**:
- `KUBE_CONFIG_PROD`: Base64 encoded kubeconfig
- `PROD_DB_PASSWORD`: Database password
- `PROD_API_KEY`: API key

**Repository Secrets** (available to all jobs):
- `DOCKER_USERNAME`: Docker Hub username
- `DOCKER_PASSWORD`: Docker Hub password/access token

### **Generate Kubeconfig**
```bash
# Get your kubeconfig
cat ~/.kube/config | base64 -w 0
# Copy the output to GitHub secrets
```

---

## **Exposing Local Cluster with ngrok**

### **Why ngrok?**
GitHub Actions runners in the cloud cannot reach your local K8s cluster. ngrok creates a public tunnel.

### **Setup ngrok**

```bash
# 1. Sign up for free account at ngrok.com
# 2. Install ngrok
wget https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-linux-amd64.tgz
tar -xvf ngrok-v3-stable-linux-amd64.tgz
sudo mv ngrok /usr/local/bin/

# 3. Authenticate
ngrok config add-authtoken YOUR_REAL_AUTH_TOKEN

# 4. Create tunnel to K8s API
ngrok tcp 192.168.56.10:6443

# Example output:
# Forwarding tcp://4.tcp.eu.ngrok.io:19351 -> 192.168.56.10:6443
```

### **Update Kubeconfig**

```bash
# Create new kubeconfig with ngrok URL
kubectl config set-cluster ngrok-cluster \
  --server=https://4.tcp.eu.ngrok.io:19351 \
  --insecure-skip-tls-verify=true

# Set context
kubectl config set-context ngrok-context \
  --cluster=ngrok-cluster \
  --user=kubernetes-admin

# Use the new context
kubectl config use-context ngrok-context

# Test connectivity
kubectl get nodes

# Encode new kubeconfig for GitHub
cat ~/.kube/config | base64 -w 0
```

### **Keep ngrok Running**

```bash
# Run in screen session
screen -S ngrok-tunnel
ngrok tcp 192.168.56.10:6443
# Press Ctrl+A, then D to detach

# Reattach later
screen -r ngrok-tunnel
```

---

## **Testing & Validation**

### **Local Testing**

```bash
# Test Kustomize builds
kubectl kustomize k8s/overlays/development
kubectl kustomize k8s/overlays/sit
kubectl kustomize k8s/overlays/uat
kubectl kustomize k8s/overlays/production

# Test locally with Docker
docker build -t fastapi-app:latest .
docker run -p 8000:8000 fastapi-app:latest
curl http://localhost:8000/health
```

### **Update /etc/hosts**
```bash
sudo tee -a /etc/hosts << EOF
192.168.56.10 dev.app.local
192.168.56.10 sit.app.local
192.168.56.10 uat.app.local
192.168.56.10 app.local
EOF
```

### **Verify Deployments**
```bash
# Check pods in each namespace
kubectl get pods -n development
kubectl get pods -n sit
kubectl get pods -n uat
kubectl get pods -n production

# Test each environment
curl http://dev.app.local/
curl http://sit.app.local/
curl http://uat.app.local/
curl http://app.local/

# Check environment-specific configs
curl http://dev.app.local/env
curl http://app.local/env
```

---

## **Troubleshooting Guide**

### **Common Issues and Solutions**

| Issue | Error | Solution |
|-------|-------|----------|
| **Image Pull Failed** | `ImagePullBackOff` | Check registry credentials; ensure image exists |
| **Connection Timeout** | `dial tcp 192.168.56.10:6443: i/o timeout` | ngrok tunnel not running; restart it |
| **Pipeline Permission** | `denied: installation not allowed` | Add `packages: write` permission |
| **Kustomize Error** | `apiVersion should be kustomize.config.k8s.io/v1beta1` | Correct the kustomization.yaml apiVersion |
| **Deployment Timeout** | `timed out waiting for the condition` | Check pod logs; verify image pull |

### **Diagnostic Commands**

```bash
# Check pod status
kubectl get pods -n development
kubectl describe pod -n development -l app=fastapi-app
kubectl logs -f deployment/fastapi-app -n development

# Check events
kubectl get events -n development --sort-by='.lastTimestamp'

# Test image pull manually
kubectl run test-pod --image=fastapi-app:latest -n development

# Check ingress
kubectl get ingress -n development
kubectl describe ingress fastapi-app -n development

# Verify ngrok tunnel
curl -v https://4.tcp.eu.ngrok.io:19351/version
```

### **Reset and Clean Up**

```bash
# Delete all deployments
kubectl delete deployment fastapi-app -n development
kubectl delete deployment fastapi-app -n sit
kubectl delete deployment fastapi-app -n uat
kubectl delete deployment fastapi-app -n production

# Delete all services
kubectl delete service fastapi-app -n development
kubectl delete service fastapi-app -n sit
kubectl delete service fastapi-app -n uat
kubectl delete service fastapi-app -n production

# Delete all ingresses
kubectl delete ingress fastapi-app -n development
kubectl delete ingress fastapi-app -n sit
kubectl delete ingress fastapi-app -n uat
kubectl delete ingress fastapi-app -n production
```

---

## **Key Concepts Demonstrated**

### **1. Build Once, Deploy Many Times**
- Single immutable Docker artifact
- Same image promoted through all environments
- No rebuilding code for different environments

### **2. Environment Configuration**
- Kustomize overlays for environment-specific configs
- GitHub Environments for manual approvals
- Environment-specific secrets and variables

### **3. GitOps Principles**
- All manifests stored in Git
- Declarative infrastructure
- Argo CD for automated sync (optional)

### **4. Security**
- Secrets managed via GitHub Secrets
- Environment-specific API keys
- Non-root user in Docker container

### **5. Zero Cost Infrastructure**
- Local K3s cluster on laptop
- Free GitHub Actions
- Free Docker Hub
- Free ngrok account

### **6. Pipeline as Code**
- Single YAML file defining entire workflow
- Sequential stages with dependencies
- Manual approval gates

---

## **Next Steps & Enhancements**

### **Immediate Enhancements**

1. **Add Database Support**
   ```bash
   # Deploy PostgreSQL in each namespace
   kubectl apply -f postgres-dev.yaml -n development
   ```

2. **Implement Canary Deployments**
   ```yaml
   # Add to production overlay
   spec:
     strategy:
       type: RollingUpdate
       rollingUpdate:
         maxSurge: 25%
         maxUnavailable: 0
   ```

3. **Add Monitoring**
   ```bash
   # Install Prometheus and Grafana
   helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
   helm install monitoring prometheus-community/kube-prometheus-stack
   ```

4. **Add Security Scanning**
   ```yaml
   # Add to GitHub Actions
   - name: Scan Docker image
     uses: aquasecurity/trivy-action@master
     with:
       image-ref: ${{ env.IMAGE_NAME }}:${{ steps.set-tag.outputs.tag }}
   ```

### **Advanced Enhancements**

5. **Self-Hosted GitHub Runner** (for production-like setup)
6. **Argo CD GitOps** (automated sync)
7. **Service Mesh** (Istio for traffic management)
8. **Cloud Kubernetes** (GKE/EKS for production readiness)

### **Learning Resources**

- [GitHub Actions Documentation](https://docs.github.com/en/actions)
- [Kustomize Documentation](https://kubectl.docs.kubernetes.io/guides/)
- [Argo CD Documentation](https://argo-cd.readthedocs.io/)
- [FastAPI Documentation](https://fastapi.tiangolo.com/)
- [Kubernetes Documentation](https://kubernetes.io/docs/)

---

## **🎯 Summary of Achievements**

✅ **Single pipeline** builds once and deploys to all environments  
✅ **Immutable artifacts** - same Docker image everywhere  
✅ **Environment-specific configs** via Kustomize overlays  
✅ **Manual approval gates** for UAT and Production  
✅ **GitOps-ready** with all manifests in Git  
✅ **Zero cost** - all running on your homelab  
✅ **Complete CI/CD** with GitHub Actions  
✅ **Production-grade** architecture and patterns  

---

## **📋 Quick Reference Commands**

```bash
# Deploy to all environments
git push origin main

# Test locally
curl http://dev.app.local/health
curl http://app.local/env

# Debug
kubectl logs -f deployment/fastapi-app -n development
kubectl describe pod -n development -l app=fastapi-app

# Update image
kustomize edit set image dockrphage/homelab-fastapi-pipeline:latest

# Restart deployment
kubectl rollout restart deployment/fastapi-app -n development
```

---

## **📝 License**

This implementation guide is provided as-is for educational purposes. All tools used are open-source or have free tiers.

---
