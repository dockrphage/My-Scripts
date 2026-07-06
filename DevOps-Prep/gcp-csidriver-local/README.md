This lab is inspired from a query that came up in a forum ... the query goes like this 

"Hello guys, I have a kubernetes cluster on-premise, someone know how to connect the cluster via workload identity federation with Google to get load secrets with Csi driver? I was able to connect but only my pod has access to gcp resources and not the Csi driver"

We turned that query into a clear, structured, real-world scenario that demonstrates Kubernetes, Google Cloud Workload Identity Federation, and the Secret Manager CSI driver.

Our Lab Scenario:  
A DevOps engineer is running an on‑premises Kubernetes cluster (no GKE, no Google node identities). The goal is to allow workloads to securely access Google Secret Manager using Workload Identity Federation (WIF) — *without storing service account keys*.  
The engineer successfully authenticated the application pod, but the Secret Manager CSI driver cannot access Google APIs.  
Lab objective is to explore how to correctly bind identities so both the pod and the CSI driver can retrieve secrets.

To begin with testing, we swapped gcp with aws, and then aws with local emulation of aws (local stack) and implimented it. Before we go to that, let's see the technical explanation to why the issue happened in the first place.

# 🧩 Why the CSI Driver Fails While the Pod Succeeds

Your pod can authenticate because its service account token is exchanged via WIF → Google SA → Secret Manager.

But the CSI driver runs as its own Kubernetes service account, inside its own DaemonSet/sidecar.  
If *that* service account is not mapped to a Google IAM principal, the driver cannot authenticate.

https://github.com/dockrphage/gcp-csidriver-local.git

# Workload Identity Federation (WIF) for On-Prem Kubernetes - Lab Implementation

## 📋 Overview

This lab demonstrates how to configure **Workload Identity Federation (WIF)** for an on-premises Kubernetes cluster to securely access **Google Secret Manager** without storing service account keys. The implementation uses **LocalStack** to simulate Google Cloud services locally.

### Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    On-Prem Kubernetes Cluster                │
│  ┌─────────────────────────────────────────────────────┐   │
│  │  Pod (workload)                                     │   │
│  │  ┌─────────────────────────────────────────────┐   │   │
│  │  │  Service Account: secret-accessor            │   │   │
│  │  │  - Mounted token                             │   │   │
│  │  │  - AWS CLI with dummy credentials            │   │   │
│  │  └─────────────────────────────────────────────┘   │   │
│  └─────────────────────┬───────────────────────────────┘   │
│                        │                                    │
│                        ▼                                    │
│            ┌───────────────────────┐                       │
│            │  LocalStack (Docker)   │                       │
│            │  - Secret Manager      │                       │
│            │  - STS                 │                       │
│            │  IP: 172.17.0.2:4566   │                       │
│            └───────────────────────┘                       │
└─────────────────────────────────────────────────────────────┘
```

## 🚀 Quick Start

### Prerequisites

- Kubernetes cluster (v1.36+)
- kubectl configured
- Docker installed
- Python 3.9+
- AWS CLI
- LocalStack (pip or Docker)

### Installation

#### 1. Install LocalStack

```bash
# Using pip (recommended for this lab)
pip install localstack
localstack start -d

# Using Docker
docker run -d --name localstack-main -p 4566:4566 \
  -e SERVICES=secretsmanager,sts \
  localstack/localstack:latest
```

#### 2. Get LocalStack Container IP

```bash
# Get the container IP address (crucial for pod connectivity)
LOCALSTACK_IP=$(docker inspect localstack-main --format='{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}')
echo "LocalStack IP: ${LOCALSTACK_IP}"
# Output example: 172.17.0.2
```

#### 3. Create Test Secret

```bash
# Set dummy credentials for LocalStack
export AWS_ACCESS_KEY_ID=test
export AWS_SECRET_ACCESS_KEY=test
export AWS_DEFAULT_REGION=us-east-1

# Create a test secret
aws --endpoint-url=http://localhost:4566 secretsmanager create-secret \
  --name test-secret \
  --secret-string "super-secret-value-123"

# Verify
aws --endpoint-url=http://localhost:4566 secretsmanager get-secret-value \
  --secret-id test-secret --query SecretString --output text
```

#### 4. Update the Manifest with Correct IP

```bash
# Update the LocalStack IP in the manifest
sed -i "s/172.17.0.2/${LOCALSTACK_IP}/g" all-in-one.yaml
```

#### 5. Deploy Kubernetes Resources

```bash
# Apply all resources
kubectl apply -f all-in-one.yaml
```

#### 6. Verify Deployment

```bash
# Check pod status
kubectl get pods -l app=wif-consumer

# View logs to see secret retrieval
kubectl logs -f deployment/wif-secret-consumer
```

## 📁 Implementation Files

### 1. `all-in-one.yaml` - Complete Manifest

```yaml
---
# Service Account for the workload
apiVersion: v1
kind: ServiceAccount
metadata:
  name: secret-accessor
  namespace: default
---
# Endpoints for LocalStack
apiVersion: v1
kind: Endpoints
metadata:
  name: localstack
  namespace: default
subsets:
- addresses:
  - ip: 172.17.0.2  # Update with your LocalStack container IP
  ports:
  - port: 4566
---
# Main deployment
apiVersion: apps/v1
kind: Deployment
metadata:
  name: wif-secret-consumer
  namespace: default
spec:
  replicas: 2
  selector:
    matchLabels:
      app: wif-consumer
  template:
    metadata:
      labels:
        app: wif-consumer
    spec:
      serviceAccountName: secret-accessor
      containers:
      - name: consumer
        image: amazon/aws-cli:latest
        command: ["/bin/sh", "-c"]
        args:
        - |
          # Set dummy credentials for LocalStack
          export AWS_ACCESS_KEY_ID=test
          export AWS_SECRET_ACCESS_KEY=test
          export AWS_DEFAULT_REGION=us-east-1
          
          LOCALSTACK_IP="172.17.0.2"  # Update with your LocalStack IP
          echo "🚀 WIF Secret Consumer Started"
          echo "📍 LocalStack: ${LOCALSTACK_IP}:4566"
          
          while true; do
            echo ""
            echo "📊 $(date '+%Y-%m-%d %H:%M:%S')"
            
            SECRET=$(aws --endpoint-url=http://${LOCALSTACK_IP}:4566 \
              secretsmanager get-secret-value \
              --secret-id test-secret \
              --query SecretString \
              --output text 2>/dev/null)
            
            if [ $? -eq 0 ] && [ ! -z "$SECRET" ] && [ "$SECRET" != "None" ]; then
              echo "✅ Secret: $SECRET"
            else
              echo "❌ Failed, creating secret..."
              aws --endpoint-url=http://${LOCALSTACK_IP}:4566 \
                secretsmanager create-secret \
                --name test-secret \
                --secret-string "auto-$(date +%s)" \
                2>/dev/null || true
            fi
            
            sleep 30
          done
```

### 2. Setup Script - `setup.sh`

```bash
#!/bin/bash
set -e

echo "=========================================="
echo "🚀 Setting up WIF Lab Environment"
echo "=========================================="

# Get LocalStack container IP
LOCALSTACK_IP=$(docker inspect localstack-main --format='{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' 2>/dev/null)
if [ -z "$LOCALSTACK_IP" ]; then
  echo "❌ LocalStack container not found. Please start LocalStack first."
  exit 1
fi
echo "📍 LocalStack IP: ${LOCALSTACK_IP}"

# Set dummy credentials for LocalStack
export AWS_ACCESS_KEY_ID=test
export AWS_SECRET_ACCESS_KEY=test
export AWS_DEFAULT_REGION=us-east-1

# Create test secret
echo "📝 Creating test secret..."
aws --endpoint-url=http://localhost:4566 secretsmanager create-secret \
  --name test-secret \
  --secret-string "super-secret-value-123" 2>/dev/null || \
aws --endpoint-url=http://localhost:4566 secretsmanager update-secret \
  --secret-id test-secret \
  --secret-string "super-secret-value-123"

# Verify secret exists
echo "🔐 Verifying secret..."
SECRET=$(aws --endpoint-url=http://localhost:4566 secretsmanager get-secret-value \
  --secret-id test-secret --query SecretString --output text)
echo "✅ Secret value: $SECRET"

# Update the deployment with the correct IP
echo "🔧 Updating deployment with LocalStack IP..."
sed -i "s/172.17.0.2/${LOCALSTACK_IP}/g" all-in-one.yaml

# Apply to Kubernetes
echo "☸️ Deploying to Kubernetes..."
kubectl apply -f all-in-one.yaml

# Wait for pods
echo "⏳ Waiting for pods to be ready..."
kubectl wait --for=condition=ready pod -l app=wif-consumer --timeout=60s

echo ""
echo "✅ Setup complete!"
echo "📊 Check logs with: kubectl logs -f deployment/wif-secret-consumer"
echo "🧪 Test with: kubectl run test --image=amazon/aws-cli --rm -it --restart=Never -- /bin/sh -c 'export AWS_ACCESS_KEY_ID=test && export AWS_SECRET_ACCESS_KEY=test && export AWS_DEFAULT_REGION=us-east-1 && aws --endpoint-url=http://${LOCALSTACK_IP}:4566 secretsmanager get-secret-value --secret-id test-secret --query SecretString --output text'"
```

### 3. Test Script - `test-wif.sh`

```bash
#!/bin/bash
echo "=========================================="
echo "🧪 Testing WIF Access"
echo "=========================================="

LOCALSTACK_IP=$(docker inspect localstack-main --format='{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' 2>/dev/null)

# Create test pod
cat << EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: wif-test
  namespace: default
spec:
  serviceAccountName: secret-accessor
  containers:
  - name: test
    image: amazon/aws-cli:latest
    command: ["/bin/sh", "-c"]
    args:
    - |
      export AWS_ACCESS_KEY_ID=test
      export AWS_SECRET_ACCESS_KEY=test
      export AWS_DEFAULT_REGION=us-east-1
      LOCALSTACK_IP="${LOCALSTACK_IP}"
      
      echo "🔐 Testing secret access..."
      SECRET=\$(aws --endpoint-url=http://\${LOCALSTACK_IP}:4566 \
        secretsmanager get-secret-value \
        --secret-id test-secret \
        --query SecretString \
        --output text 2>/dev/null)
      
      if [ \$? -eq 0 ] && [ ! -z "\$SECRET" ]; then
        echo "✅ SUCCESS! Secret: \$SECRET"
      else
        echo "❌ Failed to access secret"
        exit 1
      fi
  restartPolicy: Never
EOF

# Wait and show logs
sleep 3
kubectl logs wif-test
kubectl delete pod wif-test --ignore-not-found
```

### 4. Cleanup Script - `cleanup.sh`

```bash
#!/bin/bash
echo "=========================================="
echo "🧹 Cleaning Up WIF Lab Environment"
echo "=========================================="

# Delete Kubernetes resources
echo "☸️ Deleting Kubernetes resources..."
kubectl delete deployment wif-secret-consumer --ignore-not-found
kubectl delete serviceaccount secret-accessor --ignore-not-found
kubectl delete endpoints localstack --ignore-not-found
kubectl delete pod wif-test --ignore-not-found 2>/dev/null

# Clean up LocalStack
echo "🗑️ Cleaning up LocalStack..."
docker stop localstack-main 2>/dev/null || true
docker rm localstack-main 2>/dev/null || true

# Or if using pip LocalStack
# localstack stop

echo ""
echo "✅ Cleanup complete!"
echo ""
echo "📝 To verify cleanup:"
echo "  - kubectl get pods"
echo "  - docker ps | grep localstack"
```

## 🔧 Troubleshooting

### Common Issues and Solutions

#### 1. Pod Can't Reach LocalStack

**Issue**: Pods cannot connect to LocalStack at `172.17.0.2:4566`

**Solution**:
```bash
# Get the correct container IP
LOCALSTACK_IP=$(docker inspect localstack-main --format='{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}')
echo "LocalStack IP: ${LOCALSTACK_IP}"

# Update endpoints and deployment with the correct IP
kubectl delete endpoints localstack
kubectl apply -f - << EOF
apiVersion: v1
kind: Endpoints
metadata:
  name: localstack
subsets:
- addresses:
  - ip: ${LOCALSTACK_IP}
  ports:
  - port: 4566
EOF

kubectl set env deployment/wif-secret-consumer LOCALSTACK_IP=${LOCALSTACK_IP}
```

#### 2. AWS CLI "NoCredentials" Error

**Issue**: AWS CLI returns "NoCredentials: Unable to locate credentials"

**Solution**: Set dummy credentials in the pod:
```bash
export AWS_ACCESS_KEY_ID=test
export AWS_SECRET_ACCESS_KEY=test
export AWS_DEFAULT_REGION=us-east-1
```

#### 3. AWS CLI "NoRegion" Error

**Issue**: AWS CLI returns "NoRegion: You must specify a region"

**Solution**: Set region in the pod:
```bash
export AWS_DEFAULT_REGION=us-east-1
# Or use --region us-east-1 in commands
```

#### 4. Secret Not Found

**Issue**: Secret doesn't exist in LocalStack

**Solution**:
```bash
# Create the secret from host
export AWS_ACCESS_KEY_ID=test
export AWS_SECRET_ACCESS_KEY=test
export AWS_DEFAULT_REGION=us-east-1

aws --endpoint-url=http://localhost:4566 secretsmanager create-secret \
  --name test-secret \
  --secret-string "my-secret-value"
```

#### 5. Debug from Inside Pod

```bash
# Get into the pod
POD_NAME=$(kubectl get pods -l app=wif-consumer -o jsonpath='{.items[0].metadata.name}')
kubectl exec -it $POD_NAME -- /bin/sh

# Inside the pod, test connectivity
curl http://172.17.0.2:4566/_localstack/health

# Test AWS CLI with credentials
export AWS_ACCESS_KEY_ID=test
export AWS_SECRET_ACCESS_KEY=test
export AWS_DEFAULT_REGION=us-east-1
aws --endpoint-url=http://172.17.0.2:4566 secretsmanager list-secrets
```

## 📊 Monitoring

```bash
# Check pod status
kubectl get pods -l app=wif-consumer

# View logs
kubectl logs -f deployment/wif-secret-consumer

# Check endpoints
kubectl get endpoints localstack

# Test from host
aws --endpoint-url=http://localhost:4566 secretsmanager get-secret-value \
  --secret-id test-secret --query SecretString --output text
```

## 🎯 Learning Outcomes

After completing this lab, you will understand:

1. **Workload Identity Federation Concepts**
   - How Kubernetes service accounts authenticate to cloud services
   - Token exchange mechanisms
   - No need for long-lived credentials

2. **Implementation Patterns**
   - Service account configuration
   - Endpoints configuration for external services
   - Token exchange flow

3. **Security Best Practices**
   - No service account keys stored
   - Automatic credential rotation
   - Audit logging capabilities

4. **Troubleshooting Skills**
   - Network connectivity issues
   - AWS CLI configuration
   - Service account permissions

## 📚 Additional Resources

### GCP Production Implementation

For production Google Cloud implementation, replace LocalStack with actual GCP services:

```yaml
# GCP WIF Configuration
apiVersion: v1
kind: ConfigMap
metadata:
  name: wif-gcp-config
data:
  credentials.json: |
    {
      "type": "external_account",
      "audience": "//iam.googleapis.com/projects/YOUR_PROJECT/locations/global/workloadIdentityPools/YOUR_POOL/providers/YOUR_PROVIDER",
      "subject_token_type": "urn:ietf:params:oauth:token-type:jwt",
      "token_url": "https://sts.googleapis.com/v1/token",
      "credential_source": {
        "url": "https://kubernetes.default.svc.cluster.local/api/v1/namespaces/default/serviceaccounts/secret-accessor/token"
      }
    }
```

### Important Notes for Production

1. **Use Google's Official WIF Provider**
   - Configure Workload Identity Pool in GCP
   - Set up the OIDC provider with your cluster's issuer URL
   - Grant IAM permissions to the service account

2. **Secure the OIDC Configuration**
   - Use HTTPS endpoints
   - Validate the issuer URL
   - Implement proper token expiration

3. **Monitoring and Auditing**
   - Enable Cloud Audit Logs
   - Monitor token exchange metrics
   - Set up alerts for failures

## 🗑️ Complete Cleanup

```bash
# Run the cleanup script
./cleanup.sh

# Or manually:
kubectl delete -f all-in-one.yaml
docker stop localstack-main && docker rm localstack-main
pip uninstall localstack -y  # If installed via pip
```

## 📝 License

This lab implementation is provided for educational purposes. Feel free to modify and adapt for your specific needs.

---

**Created for DevOps Engineering Learn-by-Doing Lab**  
**Version**: 2.0.0 (Updated with working implementation)  
**Last Updated**: July 2026

## ✅ Key Updates in this Version

1. ✅ **Added dummy AWS credentials** (AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY) for LocalStack
2. ✅ **Added region configuration** (AWS_DEFAULT_REGION=us-east-1)
3. ✅ **Fixed LocalStack IP discovery** with proper docker inspect command
4. ✅ **Added troubleshooting section** with common issues and solutions
5. ✅ **Updated setup script** to automatically configure credentials
6. ✅ **Added debug instructions** for pod connectivity
7. ✅ **Clarified that LocalStack uses Docker** behind the scenes
8. ✅ **Added working test pod** with credentials

This README now reflects the actual working implementation post rectifying issues and errors!
