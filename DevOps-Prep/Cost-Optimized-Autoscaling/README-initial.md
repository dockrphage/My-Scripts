# Progressive Implementation Plan: Cost-Optimized Autoscaling & CI/CD


### Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         Your Ubuntu Laptop (Host)                          │
│                                                                             │
│  ┌──────────────────────────────────────────────────────────────────────┐   │
│  │                    CI/CD Pipeline (Dockerized)                       │   │
│  │  • Build multi-arch images (buildx)                                  │   │
│  │  • Security scanning (Trivy)                                         │   │
│  │  • Cost estimation & validation                                       │   │
│  │  • Helm deployment                                                    │   │
│  └──────────────────────────────────────────────────────────────────────┘   │
│                                                                             │
│  ┌──────────────────────────────────────────────────────────────────────┐   │
│  │                    Load Testing (hey/wrk)                            │   │
│  └──────────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                    Kubernetes Cluster (3 Nodes)                            │
│                                                                             │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                        Ingress (192.168.1.55)                       │   │
│  │                  Routes: app.cost-optimized.local                   │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                             │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐                     │
│  │    cp1       │  │    node1     │  │    node2     │                     │
│  │ 192.168.56.10│  │ 192.168.56.11│  │ 192.168.56.12│                     │
│  │              │  │              │  │              │                     │
│  │ ┌──────────┐ │  │ ┌──────────┐ │  │ ┌──────────┐ │                     │
│  │ │ Kubecost │ │  │ │ RabbitMQ │ │  │ │  App     │ │                     │
│  │ │ Metrics  │ │  │ │ (Stateful│ │  │ │  Pods    │ │                     │
│  │ │ Server   │ │  │ │  Set)    │ │  │ │          │ │                     │
│  │ └──────────┘ │  │ └──────────┘ │  │ └──────────┘ │                     │
│  │              │  │              │  │              │                     │
│  │ ┌──────────┐ │  │ ┌──────────┐ │  │ ┌──────────┐ │                     │
│  │ │ KEDA     │ │  │ │ Registry │ │  │ │  App     │ │                     │
│  │ │ Operator │ │  │ │ (Local)  │ │  │ │  Pods    │ │                     │
│  │ └──────────┘ │  │ └──────────┘ │  │ └──────────┘ │                     │
│  └──────────────┘  └──────────────┘  └──────────────┘                     │
│                                                                             │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                        MetalLB (192.168.1.55-65)                    │   │
│  │                  LoadBalancer services                              │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Phase 1: Base Infrastructure Setup

### 1.1 Verify Cluster & MetalLB
```bash
#!/bin/bash
# verify-cluster.sh

echo "=== Verifying Cluster ==="

# Check nodes
kubectl get nodes -o wide

# Check MetalLB
kubectl get pods -n metallb-system
kubectl get ipaddresspools -n metallb-system
kubectl get l2advertisements -n metallb-system

# Check Ingress
kubectl get pods -n ingress-nginx

# Set context
kubectl config set-context --current --namespace=cost-optimized
kubectl create namespace cost-optimized --dry-run=client -o yaml | kubectl apply -f -

echo "✅ Cluster ready!"
```

### 1.2 Install Core Components
```bash
#!/bin/bash
# install-core.sh

set -e
NAMESPACE="cost-optimized"
REGISTRY_IP="192.168.1.60"  # Using MetalLB range

echo "=== Installing Core Components ==="

# 1. Install KEDA
echo "Installing KEDA..."
kubectl apply -f https://github.com/kedacore/keda/releases/download/v2.10.0/keda-2.10.0.yaml
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=keda-operator -n keda-system --timeout=120s

# 2. Install Kubecost
echo "Installing Kubecost..."
helm repo add kubecost https://kubecost.github.io/cost-analyzer/
helm repo update
helm upgrade --install kubecost kubecost/cost-analyzer \
    --namespace kubecost --create-namespace \
    --set global.prometheus.enabled=true \
    --set prometheus.server.persistentVolume.enabled=true \
    --set prometheus.server.persistentVolume.size=10Gi \
    --set kubecostProductConfigs.productConfigs.defaultStorageClass="local-path"

# 3. Install Local Registry with LoadBalancer
echo "Installing Local Registry..."
kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: local-registry
  namespace: kube-system
spec:
  replicas: 1
  selector:
    matchLabels:
      app: local-registry
  template:
    metadata:
      labels:
        app: local-registry
    spec:
      containers:
      - name: registry
        image: registry:2
        ports:
        - containerPort: 5000
        env:
        - name: REGISTRY_HTTP_ADDR
          value: ":5000"
        resources:
          requests:
            memory: "128Mi"
            cpu: "50m"
---
apiVersion: v1
kind: Service
metadata:
  name: local-registry
  namespace: kube-system
spec:
  type: LoadBalancer
  loadBalancerIP: ${REGISTRY_IP}
  ports:
  - port: 5000
    targetPort: 5000
  selector:
    app: local-registry
EOF

# Wait for registry
kubectl wait --for=condition=ready pod -l app=local-registry -n kube-system --timeout=60s

# 4. Configure Docker on host for registry
echo "Configuring host Docker..."
sudo mkdir -p /etc/docker
sudo tee /etc/docker/daemon.json > /dev/null <<EOF
{
  "insecure-registries": ["${REGISTRY_IP}:5000", "localhost:5000"],
  "experimental": true,
  "features": {
    "buildkit": true
  }
}
EOF
sudo systemctl restart docker

echo "✅ Core components installed!"
echo "Registry: ${REGISTRY_IP}:5000"
echo "Kubecost: kubectl port-forward -n kubecost service/kubecost-cost-analyzer 9090:9090"
```

---

## Phase 2: Application & Messaging

### 2.1 Deploy RabbitMQ (StatefulSet with persistence)
```yaml
# rabbitmq-statefulset.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: rabbitmq-config
  namespace: cost-optimized
data:
  rabbitmq.conf: |
    default_user = guest
    default_pass = guest
    default_vhost = /
    management.tcp.port = 15672
  enabled_plugins: |
    [rabbitmq_management, rabbitmq_prometheus].
---
apiVersion: v1
kind: Secret
metadata:
  name: rabbitmq-secret
  namespace: cost-optimized
type: Opaque
stringData:
  rabbitmq-password: guest
  rabbitmq-erlang-cookie: "secret-cookie-12345"
---
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: rabbitmq
  namespace: cost-optimized
spec:
  serviceName: rabbitmq-headless
  replicas: 1
  selector:
    matchLabels:
      app: rabbitmq
  template:
    metadata:
      labels:
        app: rabbitmq
    spec:
      containers:
      - name: rabbitmq
        image: rabbitmq:3.12-management-alpine
        ports:
        - containerPort: 5672
          name: amqp
        - containerPort: 15672
          name: management
        - containerPort: 15692
          name: prometheus
        env:
        - name: RABBITMQ_DEFAULT_USER
          value: guest
        - name: RABBITMQ_DEFAULT_PASS
          valueFrom:
            secretKeyRef:
              name: rabbitmq-secret
              key: rabbitmq-password
        - name: RABBITMQ_ERLANG_COOKIE
          valueFrom:
            secretKeyRef:
              name: rabbitmq-secret
              key: rabbitmq-erlang-cookie
        resources:
          requests:
            memory: "512Mi"
            cpu: "500m"
          limits:
            memory: "1Gi"
            cpu: "1000m"
        volumeMounts:
        - name: rabbitmq-data
          mountPath: /var/lib/rabbitmq
        - name: rabbitmq-config
          mountPath: /etc/rabbitmq/conf.d/
        livenessProbe:
          exec:
            command: ["rabbitmq-diagnostics", "check_port_connectivity"]
          initialDelaySeconds: 30
          periodSeconds: 10
        readinessProbe:
          exec:
            command: ["rabbitmq-diagnostics", "check_port_connectivity"]
          initialDelaySeconds: 20
          periodSeconds: 10
      volumes:
      - name: rabbitmq-config
        configMap:
          name: rabbitmq-config
  volumeClaimTemplates:
  - metadata:
      name: rabbitmq-data
    spec:
      accessModes: [ "ReadWriteOnce" ]
      resources:
        requests:
          storage: 10Gi
---
apiVersion: v1
kind: Service
metadata:
  name: rabbitmq
  namespace: cost-optimized
  annotations:
    metallb.universe.tf/loadBalancerIPs: "192.168.1.61"
spec:
  type: LoadBalancer
  selector:
    app: rabbitmq
  ports:
  - name: amqp
    port: 5672
    targetPort: 5672
  - name: management
    port: 15672
    targetPort: 15672
---
apiVersion: v1
kind: Service
metadata:
  name: rabbitmq-headless
  namespace: cost-optimized
spec:
  clusterIP: None
  selector:
    app: rabbitmq
  ports:
  - name: amqp
    port: 5672
```

### 2.2 Deploy Application
```yaml
# app-deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: sample-app
  namespace: cost-optimized
  labels:
    app: sample-app
    version: v1
spec:
  replicas: 0  # Start at zero, KEDA will scale
  selector:
    matchLabels:
      app: sample-app
  template:
    metadata:
      labels:
        app: sample-app
        version: v1
    spec:
      containers:
      - name: app
        image: 192.168.1.60:5000/sample-app:latest
        imagePullPolicy: Always
        ports:
        - containerPort: 8080
          name: http
        env:
        - name: RABBITMQ_HOST
          value: rabbitmq.cost-optimized.svc.cluster.local
        - name: RABBITMQ_PORT
          value: "5672"
        - name: QUEUE_NAME
          value: work-queue
        - name: POD_NAME
          valueFrom:
            fieldRef:
              fieldPath: metadata.name
        - name: POD_NAMESPACE
          valueFrom:
            fieldRef:
              fieldPath: metadata.namespace
        resources:
          requests:
            memory: "64Mi"
            cpu: "50m"
          limits:
            memory: "128Mi"
            cpu: "100m"
        livenessProbe:
          httpGet:
            path: /health
            port: 8080
          initialDelaySeconds: 15
          periodSeconds: 20
        readinessProbe:
          httpGet:
            path: /health
            port: 8080
          initialDelaySeconds: 10
          periodSeconds: 10
---
apiVersion: v1
kind: Service
metadata:
  name: sample-app
  namespace: cost-optimized
spec:
  selector:
    app: sample-app
  ports:
  - port: 8080
    targetPort: 8080
    name: http
  type: ClusterIP
---
apiVersion: v1
kind: Service
metadata:
  name: sample-app-external
  namespace: cost-optimized
  annotations:
    metallb.universe.tf/loadBalancerIPs: "192.168.1.62"
spec:
  type: LoadBalancer
  selector:
    app: sample-app
  ports:
  - port: 80
    targetPort: 8080
    name: http
```

### 2.3 Ingress Configuration
```yaml
# ingress.yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: sample-app-ingress
  namespace: cost-optimized
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /
    nginx.ingress.kubernetes.io/ssl-redirect: "false"
    nginx.ingress.kubernetes.io/proxy-body-size: "10m"
spec:
  ingressClassName: nginx
  rules:
  - host: app.cost-optimized.local
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: sample-app
            port:
              number: 8080
  - host: rabbitmq.cost-optimized.local
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: rabbitmq
            port:
              number: 15672
```

### 2.4 Application Code (Enhanced)
```python
# app.py - Enhanced with metrics
import os
import pika
import json
import time
import logging
import socket
from flask import Flask, request, jsonify
from threading import Thread
from prometheus_client import Counter, Gauge, generate_latest, REGISTRY
import sys

app = Flask(__name__)
logging.basicConfig(level=logging.INFO)

# Metrics
messages_processed = Counter('app_messages_processed_total', 'Total messages processed')
messages_failed = Counter('app_messages_failed_total', 'Total failed messages')
queue_depth = Gauge('app_queue_depth', 'Current queue depth')
active_pods = Gauge('app_active_pods', 'Number of active pods')

RABBITMQ_HOST = os.getenv('RABBITMQ_HOST', 'rabbitmq.cost-optimized.svc.cluster.local')
RABBITMQ_PORT = int(os.getenv('RABBITMQ_PORT', 5672))
QUEUE_NAME = os.getenv('QUEUE_NAME', 'work-queue')
POD_NAME = os.getenv('POD_NAME', socket.gethostname())

# Set active pods metric
active_pods.set(1)

def process_message(ch, method, properties, body):
    """Process message from queue"""
    try:
        logging.info(f"Pod {POD_NAME} processing: {body[:50]}...")
        # Simulate work with variable delay
        delay = 0.05 + (hash(body) % 10) / 100.0
        time.sleep(delay)
        ch.basic_ack(delivery_tag=method.delivery_tag)
        messages_processed.inc()
        logging.info(f"✓ Message processed in {delay:.3f}s")
    except Exception as e:
        logging.error(f"✗ Failed to process: {e}")
        messages_failed.inc()
        ch.basic_nack(delivery_tag=method.delivery_tag, requeue=True)

def start_consumer():
    """Start consuming messages with retry logic"""
    retry_count = 0
    while True:
        try:
            logging.info(f"Connecting to RabbitMQ at {RABBITMQ_HOST}:{RABBITMQ_PORT}")
            connection = pika.BlockingConnection(
                pika.ConnectionParameters(
                    host=RABBITMQ_HOST,
                    port=RABBITMQ_PORT,
                    heartbeat=600,
                    blocked_connection_timeout=300
                )
            )
            channel = connection.channel()
            channel.queue_declare(queue=QUEUE_NAME, durable=True)
            channel.basic_qos(prefetch_count=5)
            channel.basic_consume(
                queue=QUEUE_NAME,
                on_message_callback=process_message
            )
            retry_count = 0
            logging.info(f"✓ Consumer started on {POD_NAME}")
            channel.start_consuming()
        except Exception as e:
            retry_count += 1
            logging.error(f"✗ Consumer error (attempt {retry_count}): {e}")
            time.sleep(min(30, retry_count * 2))

@app.route('/')
def root():
    return jsonify({
        "service": "sample-app",
        "version": "v1",
        "pod": POD_NAME,
        "status": "healthy"
    }), 200

@app.route('/health')
def health():
    return jsonify({"status": "healthy", "pod": POD_NAME}), 200

@app.route('/metrics')
def metrics():
    return generate_latest(REGISTRY), 200

@app.route('/enqueue', methods=['POST'])
def enqueue():
    """Add message to queue"""
    try:
        data = request.json or {}
        
        # Validate
        if not data:
            return jsonify({"error": "No data provided"}), 400
            
        connection = pika.BlockingConnection(
            pika.ConnectionParameters(host=RABBITMQ_HOST, port=RABBITMQ_PORT)
        )
        channel = connection.channel()
        channel.queue_declare(queue=QUEUE_NAME, durable=True)
        
        # Add metadata
        message = {
            "data": data,
            "timestamp": time.time(),
            "pod": POD_NAME
        }
        
        channel.basic_publish(
            exchange='',
            routing_key=QUEUE_NAME,
            body=json.dumps(message),
            properties=pika.BasicProperties(
                delivery_mode=2,  # Make message persistent
                content_type='application/json'
            )
        )
        connection.close()
        return jsonify({"status": "queued", "pod": POD_NAME}), 202
    except Exception as e:
        logging.error(f"Enqueue error: {e}")
        return jsonify({"error": str(e)}), 500

@app.route('/queue/status')
def queue_status():
    """Get queue status"""
    try:
        connection = pika.BlockingConnection(
            pika.ConnectionParameters(host=RABBITMQ_HOST, port=RABBITMQ_PORT)
        )
        channel = connection.channel()
        queue = channel.queue_declare(queue=QUEUE_NAME, durable=True, passive=True)
        messages = queue.method.message_count
        queue_depth.set(messages)
        connection.close()
        return jsonify({
            "name": QUEUE_NAME,
            "messages": messages,
            "pod": POD_NAME
        }), 200
    except Exception as e:
        return jsonify({"error": str(e)}), 500

@app.route('/queue/flush', methods=['POST'])
def flush_queue():
    """Flush all messages (for testing)"""
    try:
        connection = pika.BlockingConnection(
            pika.ConnectionParameters(host=RABBITMQ_HOST, port=RABBITMQ_PORT)
        )
        channel = connection.channel()
        count = 0
        while True:
            method_frame, header, body = channel.basic_get(queue=QUEUE_NAME, auto_ack=True)
            if not method_frame:
                break
            count += 1
        connection.close()
        return jsonify({"flushed": count}), 200
    except Exception as e:
        return jsonify({"error": str(e)}), 500

if __name__ == '__main__':
    # Start consumer in background
    consumer_thread = Thread(target=start_consumer, daemon=True)
    consumer_thread.start()
    
    # Start web server
    logging.info(f"Starting web server on {POD_NAME}")
    app.run(host='0.0.0.0', port=8080, threaded=True)
```

---

## Phase 3: KEDA Autoscaling Configuration

### 3.1 ScaledObject with Advanced Metrics
```yaml
# scaledobject.yaml
apiVersion: keda.sh/v1alpha1
kind: ScaledObject
metadata:
  name: sample-app-scaler
  namespace: cost-optimized
  annotations:
    kubecost.keda/optimized: "true"
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: sample-app
  
  minReplicaCount: 0
  maxReplicaCount: 10
  
  # Advanced scaling policies
  pollingInterval: 5
  cooldownPeriod: 20
  
  triggers:
  # Primary: RabbitMQ queue depth
  - type: rabbitmq
    metadata:
      queueName: work-queue
      host: rabbitmq.cost-optimized.svc.cluster.local
      port: "5672"
      queueLength: "5"
      protocol: amqp
      enableTLS: "false"
  
  # Secondary: CPU utilization
  - type: cpu
    metadata:
      type: Utilization
      value: "70"
  
  # Fallback: Prometheus metrics
  - type: prometheus
    metadata:
      serverAddress: http://prometheus-server.kubecost.svc.cluster.local:80
      metricName: rabbitmq_queue_messages_ready
      threshold: "5"
      query: |
        rabbitmq_queue_messages_ready{
          queue="work-queue",
          namespace="cost-optimized"
        }

  scalingStrategy:
    strategy: default
    customScalingStrategy:
      - type: group
        metadata:
          target: "1.5"  # Scale factor

  # Advanced scaling behavior
  advanced:
    horizontalPodAutoscalerConfig:
      behavior:
        scaleDown:
          stabilizationWindowSeconds: 60
          policies:
          - type: Percent
            value: 50
            periodSeconds: 30
          - type: Pods
            value: 1
            periodSeconds: 60
          selectPolicy: Min
        scaleUp:
          stabilizationWindowSeconds: 10
          policies:
          - type: Percent
            value: 100
            periodSeconds: 15
          - type: Pods
            value: 2
            periodSeconds: 15
          selectPolicy: Max
```

---

## Phase 4: CI/CD Pipeline with Cost Optimization

### 4.1 Full Pipeline Script
```bash
#!/bin/bash
# pipeline.sh - Full CI/CD with cost optimization

set -e

# Configuration
APP_NAME="sample-app"
NAMESPACE="cost-optimized"
REGISTRY_IP="192.168.1.60"
REGISTRY="${REGISTRY_IP}:5000"
IMAGE_TAG="${REGISTRY}/${APP_NAME}:${BUILD_NUMBER:-latest}"
COST_THRESHOLD=0.50  # $0.50 per month

echo "=== 🚀 CI/CD Pipeline ==="
echo "Build: ${BUILD_NUMBER:-latest}"
echo "Registry: ${REGISTRY}"

# Step 1: Lint & Test
echo "Step 1: Linting and Testing..."
shellcheck app.py 2>/dev/null || echo "ShellCheck not installed, skipping"

# Step 2: Security Scan (Dockerfile)
echo "Step 2: Scanning Dockerfile..."
cat > Dockerfile <<'EOF'
FROM python:3.9-slim

WORKDIR /app

RUN pip install --no-cache-dir flask pika prometheus_client

COPY app.py .

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:8080/health || exit 1

USER 1000:1000

CMD ["python", "app.py"]
EOF

trivy config Dockerfile --severity HIGH,CRITICAL

# Step 3: Build Multi-arch Image
echo "Step 3: Building Multi-arch Image..."
docker buildx create --name multiarch --use 2>/dev/null || docker buildx use multiarch
docker buildx inspect --bootstrap

docker buildx build \
    --platform linux/amd64,linux/arm64 \
    --tag ${IMAGE_TAG} \
    --push \
    --cache-from type=registry,ref=${REGISTRY}/${APP_NAME}:cache \
    --cache-to type=registry,ref=${REGISTRY}/${APP_NAME}:cache,mode=max \
    .

# Step 4: Security Scan (Image)
echo "Step 4: Scanning Image..."
trivy image ${IMAGE_TAG} \
    --severity HIGH,CRITICAL \
    --exit-code 1 \
    --ignore-unfixed \
    --vuln-type os,library

# Step 5: Helm Template Validation
echo "Step 5: Validating Helm Charts..."
helm template ${APP_NAME} ./helm-chart \
    --set image.repository=${REGISTRY}/${APP_NAME} \
    --set image.tag=${BUILD_NUMBER:-latest} \
    --namespace ${NAMESPACE} \
    --debug --dry-run

# Step 6: Deploy
echo "Step 6: Deploying..."
helm upgrade --install ${APP_NAME} ./helm-chart \
    --set image.repository=${REGISTRY}/${APP_NAME} \
    --set image.tag=${BUILD_NUMBER:-latest} \
    --set image.pullPolicy=Always \
    --namespace ${NAMESPACE} \
    --wait \
    --timeout 5m

# Step 7: Cost Estimation
echo "Step 7: Estimating Costs..."

# Get resource requests
CPU_REQUEST=$(kubectl get deployment ${APP_NAME} -n ${NAMESPACE} -o jsonpath='{.spec.template.spec.containers[0].resources.requests.cpu}')
MEM_REQUEST=$(kubectl get deployment ${APP_NAME} -n ${NAMESPACE} -o jsonpath='{.spec.template.spec.containers[0].resources.requests.memory}')
REPLICAS=$(kubectl get deployment ${APP_NAME} -n ${NAMESPACE} -o jsonpath='{.status.replicas}')

# Convert to standard units
CPU_CORES=$(echo ${CPU_REQUEST} | sed 's/m//' | awk '{print $1/1000}')
MEM_GB=$(echo ${MEM_REQUEST} | sed 's/Mi//' | awk '{print $1/1024}')

# Cloud pricing (example - adjust for your cloud)
CPU_PRICE_PER_CORE_HOUR=0.04
MEM_PRICE_PER_GB_HOUR=0.004
HOURS_PER_MONTH=730

CPU_COST=$(echo "scale=4; ${CPU_CORES} * ${CPU_PRICE_PER_CORE_HOUR} * ${HOURS_PER_MONTH}" | bc)
MEM_COST=$(echo "scale=4; ${MEM_GB} * ${MEM_PRICE_PER_GB_HOUR} * ${HOURS_PER_MONTH}" | bc)
POD_COST=$(echo "scale=4; ${CPU_COST} + ${MEM_COST}" | bc)
MONTHLY_COST=$(echo "scale=4; ${POD_COST} * ${REPLICAS:-0}" | bc)

echo "Resource Costs:"
echo "  CPU: $${CPU_COST}/month"
echo "  Memory: $${MEM_COST}/month"
echo "  Per Pod: $${POD_COST}/month"
echo "  Total: $${MONTHLY_COST}/month"

# Step 8: Cost Validation
if (( $(echo "${MONTHLY_COST} > ${COST_THRESHOLD}" | bc -l) )); then
    echo "❌ FAILED: Estimated cost $${MONTHLY_COST} > threshold $${COST_THRESHOLD}"
    echo "Rolling back..."
    helm rollback ${APP_NAME} -n ${NAMESPACE}
    exit 1
else
    echo "✅ Cost check passed: $${MONTHLY_COST} <= $${COST_THRESHOLD}"
fi

# Step 9: Verify Scaling
echo "Step 8: Verifying Autoscaling..."
kubectl get scaledobject ${APP_NAME}-scaler -n ${NAMESPACE} 2>/dev/null || {
    echo "Applying KEDA ScaledObject..."
    kubectl apply -f scaledobject.yaml
}

# Step 10: Wait for ready
echo "Step 9: Waiting for deployment to be ready..."
kubectl wait --for=condition=ready pod -l app=${APP_NAME} -n ${NAMESPACE} --timeout=60s || echo "No pods running (scaled to zero)"

echo "✅ Pipeline completed successfully!"
echo ""
echo "Application URL: http://192.168.1.62"
echo "RabbitMQ UI: http://192.168.1.61:15672 (guest/guest)"
echo "Kubecost: kubectl port-forward -n kubecost service/kubecost-cost-analyzer 9090:9090"
```

---

## Phase 5: Load Testing

### 5.1 Load Test Script
```bash
#!/bin/bash
# load-test.sh

set -e

APP_URL="http://192.168.1.62"
NAMESPACE="cost-optimized"
DURATION=${1:-60}
RATE=${2:-20}

echo "=== 🚀 Load Test ==="
echo "Duration: ${DURATION}s"
echo "Rate: ${RATE} req/sec"
echo "Target: ${APP_URL}"

# Function to monitor scaling
monitor_scaling() {
    echo "📊 Monitoring scaling..."
    while true; do
        replicas=$(kubectl get deployment sample-app -n ${NAMESPACE} -o jsonpath='{.status.replicas}' 2>/dev/null || echo "0")
        ready=$(kubectl get deployment sample-app -n ${NAMESPACE} -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
        
        # Get queue depth
        queue_depth=$(kubectl exec -n ${NAMESPACE} deployment/rabbitmq -- \
            rabbitmqctl list_queues name messages_ready 2>/dev/null | \
            grep work-queue | awk '{print $2}' || echo "0")
        
        echo "$(date '+%H:%M:%S') | Pods: ${replicas:-0} (Ready: ${ready:-0}) | Queue: ${queue_depth:-0}"
        sleep 2
    done
}

# Phase 1: Generate load
echo "📤 Generating load..."
(
    for i in $(seq 1 $((DURATION * RATE / 10))); do
        for j in $(seq 1 10); do
            curl -s -X POST ${APP_URL}/enqueue \
                -H "Content-Type: application/json" \
                -d "{\"task\": \"load-test-${i}\", \"batch\": ${j}}" \
                > /dev/null 2>&1
        done
        echo -n "."
        sleep 0.1
    done
    echo " Done!"
) &

# Phase 2: Monitor scaling
monitor_scaling &
MONITOR_PID=$!

# Wait for load to finish
wait

# Phase 3: Check results
echo -e "\n📈 Test Results:"

# Get max pods reached
MAX_PODS=$(kubectl get deployment sample-app -n ${NAMESPACE} -o jsonpath='{.status.replicas}' 2>/dev/null || echo "0")
echo "Maximum pods reached: ${MAX_PODS}"

# Check queue status
QUEUE_STATUS=$(curl -s ${APP_URL}/queue/status 2>/dev/null || echo '{"messages":0}')
MESSAGES=$(echo $QUEUE_STATUS | jq -r '.messages // 0')
echo "Remaining queue messages: ${MESSAGES}"

# Phase 4: Wait for scale-down
echo -e "\n⏳ Waiting for scale-down (cooldown period)..."
sleep 45

FINAL_PODS=$(kubectl get deployment sample-app -n ${NAMESPACE} -o jsonpath='{.status.replicas}' 2>/dev/null || echo "0")
echo "Final pods after cooldown: ${FINAL_PODS}"

if [ "${FINAL_PODS}" -eq 0 ]; then
    echo "✅ Scale-to-zero successful!"
else
    echo "⚠️  Scale-to-zero not complete (${FINAL_PODS} pods remaining)"
fi

# Stop monitoring
kill $MONITOR_PID 2>/dev/null

echo -e "\n✅ Load test complete!"
```

---

## Phase 6: Monitoring Dashboard

### 6.1 Setup Monitoring
```bash
#!/bin/bash
# setup-monitoring.sh

echo "=== 📊 Setting up Monitoring ==="

# 1. Port forward Kubecost
kubectl port-forward -n kubecost service/kubecost-cost-analyzer 9090:9090 &
echo "Kubecost: http://localhost:9090"

# 2. Port forward RabbitMQ
kubectl port-forward -n cost-optimized service/rabbitmq 15672:15672 &
echo "RabbitMQ UI: http://localhost:15672 (guest/guest)"

# 3. Port forward Prometheus (if available)
kubectl port-forward -n kubecost service/kubecost-prometheus-server 9091:80 &
echo "Prometheus: http://localhost:9091"

# 4. Port forward Grafana (if available)
kubectl port-forward -n kubecost service/kubecost-grafana 3000:80 &
echo "Grafana: http://localhost:3000"

echo ""
echo "📊 Monitoring URLs:"
echo "  Kubecost: http://localhost:9090"
echo "  RabbitMQ: http://localhost:15672"
echo "  Prometheus: http://localhost:9091"
echo "  Grafana: http://localhost:3000 (admin/admin)"

# 5. Show cost metrics
echo ""
echo "💰 Cost Metrics (last 5 minutes):"
curl -s "http://localhost:9090/api/costData?window=5m&aggregation=namespace" | \
    jq -r '.data[0].namespace | to_entries[] | "\(.key): $\(.value.totalCost)"' 2>/dev/null || \
    echo "Waiting for Kubecost data..."
```

---

## Phase 7: Production-Ready Manifest

### 7.1 Complete Helm Chart
```yaml
# helm-chart/values.yaml
image:
  repository: 192.168.1.60:5000/sample-app
  tag: latest
  pullPolicy: Always

replicaCount: 0

resources:
  requests:
    cpu: 50m
    memory: 64Mi
  limits:
    cpu: 100m
    memory: 128Mi

autoscaling:
  enabled: true
  minReplicas: 0
  maxReplicas: 10
  queueLength: 5
  cooldownPeriod: 20
  pollingInterval: 5

rabbitmq:
  host: rabbitmq.cost-optimized.svc.cluster.local
  port: 5672
  queue: work-queue
  username: guest
  password: guest

ingress:
  enabled: true