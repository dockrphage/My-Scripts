# Comprehensive Kubernetes Health Check & Chaos Engineering Lab

## 📋 Table of Contents
1. [Overview](#overview)
2. [Architecture](#architecture)
3. [Prerequisites](#prerequisites)
4. [Quick Start](#quick-start)
5. [Detailed Implementation](#detailed-implementation)
6. [Chaos Engineering](#chaos-engineering)
7. [Monitoring & Observability](#monitoring--observability)
8. [Interview Preparation](#interview-preparation)
9. [Troubleshooting](#troubleshooting)
10. [Cleanup](#cleanup)

---

## Overview

This lab provides a complete Kubernetes-based health check and chaos engineering implementation designed for DevOps learning and interview preparation. It demonstrates:

- **Health Probes**: Liveness, readiness, and custom health endpoints
- **Auto-scaling**: HPA based on custom metrics and resource usage
- **Chaos Engineering**: Fault injection using Chaos Mesh
- **Observability**: Prometheus metrics and Grafana dashboards
- **Service Mesh**: Istio for traffic management and canary deployments
- **Custom Operators**: Building controllers for health-aware automation

### Learning Objectives
- Understand Kubernetes health checks beyond basic endpoints
- Implement chaos engineering practices
- Build observability into applications
- Design resilient microservices
- Create custom Kubernetes controllers

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                     Kubernetes Cluster (Vagrant)                │
│                                                                  │
│  ┌────────────────────────────────────────────────────────┐    │
│  │                    Istio Service Mesh                  │    │
│  │  ┌──────────────────────────────────────────────────┐ │    │
│  │  │          Health Check Application                │ │    │
│  │  │  ┌────────────┐  ┌────────────┐  ┌────────────┐ │ │    │
│  │  │  │   Pod v1   │  │   Pod v2   │  │   Pod v3   │ │ │    │
│  │  │  │  Flask API │  │  Flask API │  │  Flask API │ │ │    │
│  │  │  │ Port:8080  │  │ Port:8080  │  │ Port:8080  │ │ │    │
│  │  │  └─────┬──────┘  └─────┬──────┘  └─────┬──────┘ │ │    │
│  │  │        │                │                │        │ │    │
│  │  │        └────────────────┼────────────────┘        │ │    │
│  │  │                         │                        │ │    │
│  │  │              ┌──────────▼──────────┐            │ │    │
│  │  │              │   Service (ClusterIP) │            │ │    │
│  │  │              └──────────┬──────────┘            │ │    │
│  │  └─────────────────────────┼────────────────────────┘ │    │
│  └─────────────────────────────┼──────────────────────────┘    │
│                                │                               │
│  ┌─────────────────────────────┼──────────────────────────┐    │
│  │                             │                          │    │
│  ▼                             ▼                          ▼    │
│ ┌──────────────┐    ┌──────────────────┐    ┌─────────────────┐│
│ │  Prometheus  │    │     Grafana      │    │  Chaos Mesh     ││
│ │   Metrics    │    │   Dashboards     │    │  Fault Injector ││
│ └──────────────┘    └──────────────────┘    └─────────────────┘│
│                                                                  │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │              Custom Health Operator                      │  │
│  │  - Monitors HealthCheck CRD                             │  │
│  │  - Auto-healing logic                                   │  │
│  │  - Scaling decisions                                    │  │
│  └──────────────────────────────────────────────────────────┘  │
│                                                                  │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │                   HPA (Auto-scaling)                     │  │
│  │  - CPU/Memory based scaling                             │  │
│  │  - Custom health metrics                                │  │
│  └──────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

---

## Prerequisites

### Infrastructure Requirements
```bash
# Minimum Resources
- CPU: 4 cores
- Memory: 8GB RAM
- Storage: 20GB free space

# Software Versions
- Kubernetes: v1.28+
- Helm: v3.10+
- Kubectl: v1.28+
- Vagrant: 2.2+
- Istio: 1.20+
- Chaos Mesh: 2.6+
```

### Your Cluster Setup
[Clone and run the cluster-up script](https://github.com/dockrphage/My-Scripts/blob/main/k8s/k8s-v1-36-Vag-auto/cluster-up.sh)
```bash
cr@7:~/vag/current$ kubectl get nodes -o wide
NAME    STATUS   ROLES           VERSION   INTERNAL-IP     CONTAINER-RUNTIME
cp1     Ready    control-plane   v1.36.2   192.168.56.10   containerd://2.3.2
node1   Ready    <none>          v1.36.2   192.168.56.11   containerd://2.3.2
node2   Ready    <none>          v1.36.2   192.168.56.12   containerd://2.3.2

# MetalLB Configuration
cr@7:~/vag/current$ kubectl -n metallb-system get ipaddresspools.metallb.io
NAME           ADDRESSES
bridged-pool   ["192.168.1.55-192.168.1.65"]
```

---




### Manual Deployment Steps

```bash
# 1. Deploy the health check application
kubectl apply -f manifests/01-health-check-app.yaml

# 2. Install monitoring stack
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm install prometheus prometheus-community/kube-prometheus-stack -n monitoring --create-namespace

# 3. Install Chaos Mesh
helm repo add chaos-mesh https://charts.chaos-mesh.org
helm install chaos-mesh chaos-mesh/chaos-mesh -n chaos-mesh --create-namespace

# 4. Deploy custom operator
kubectl apply -f manifests/02-health-operator.yaml

# 5. Configure auto-scaling
kubectl apply -f manifests/03-hpa.yaml

# 6. Set up service mesh (optional)
istioctl install --set profile=demo -y
kubectl label namespace default istio-injection=enabled
kubectl apply -f manifests/04-istio-routing.yaml
```

---

## Detailed Implementation

### 1. Health Check Application

#### Application Code (Flask API)
```python
# app.py - Complete health check implementation
from flask import Flask, jsonify
import os, time, random, socket, json
import logging
from datetime import datetime

app = Flask(__name__)
start_time = time.time()

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Health status flags - can be modified by external endpoints
health_status = {
    'database': True,
    'cache': True,
    'external_api': True,
    'disk_space': True
}

@app.route('/health/live')
def liveness():
    """Kubernetes liveness probe - checks if container is alive"""
    return jsonify({
        "status": "alive", 
        "pod": socket.gethostname(),
        "timestamp": datetime.now().isoformat()
    })

@app.route('/health/ready')
def readiness():
    """Kubernetes readiness probe - checks if pod can serve traffic"""
    pod_name = socket.gethostname()
    
    # Simulate occasional unreadiness
    if random.random() < 0.05:
        logger.warning(f"Pod {pod_name} reporting NOT READY")
        return jsonify({"status": "not ready"}), 503
    
    return jsonify({
        "status": "ready", 
        "pod": pod_name,
        "timestamp": datetime.now().isoformat()
    })

@app.route('/health/detailed')
def detailed_health():
    """Custom detailed health endpoint for monitoring"""
    return jsonify({
        "status": "healthy" if all(health_status.values()) else "degraded",
        "pod": socket.gethostname(),
        "ip": os.environ.get('POD_IP', 'unknown'),
        "uptime": int(time.time() - start_time),
        "timestamp": datetime.now().isoformat(),
        "checks": {
            "database": {
                "status": "connected" if health_status['database'] else "disconnected",
                "latency_ms": random.randint(1, 50)
            },
            "cache": {
                "status": "connected" if health_status['cache'] else "disconnected",
                "hit_rate": random.randint(85, 99)
            },
            "external_api": {
                "status": "available" if health_status['external_api'] else "unavailable",
                "response_time_ms": random.randint(10, 200)
            },
            "disk_space": {
                "status": "available" if health_status['disk_space'] else "full",
                "free_gb": random.randint(1, 100)
            }
        },
        "metrics": {
            "request_count": random.randint(1000, 10000),
            "error_rate": random.randint(0, 5),
            "avg_response_time": random.randint(10, 100)
        }
    })

@app.route('/metrics')
def metrics():
    """Prometheus metrics endpoint"""
    pod = socket.gethostname()
    return f"""# HELP health_score Current health score (0-100)
# TYPE health_score gauge
health_score {{pod="{pod}"}} {random.randint(80, 100)}

# HELP request_count_total Total requests handled
# TYPE request_count_total counter
request_count_total {{pod="{pod}"}} {random.randint(1000, 10000)}

# HELP error_count_total Total errors
# TYPE error_count_total counter
error_count_total {{pod="{pod}"}} {random.randint(0, 50)}

# HELP response_time_seconds Response time in seconds
# TYPE response_time_seconds histogram
response_time_seconds_bucket {{pod="{pod}",le="0.1"}} {random.randint(100, 1000)}
response_time_seconds_bucket {{pod="{pod}",le="0.5"}} {random.randint(1000, 5000)}
response_time_seconds_bucket {{pod="{pod}",le="1.0"}} {random.randint(5000, 10000)}
response_time_seconds_bucket {{pod="{pod}",le="+Inf"}} {random.randint(10000, 20000)}
response_time_seconds_sum {{pod="{pod}"}} {random.randint(1000, 5000)}
response_time_seconds_count {{pod="{pod}"}} {random.randint(1000, 10000)}

# HELP pod_status Pod status indicator
# TYPE pod_status gauge
pod_status {{pod="{pod}"}} 1
"""

@app.route('/health/toggle/<component>')
def toggle_health(component):
    """Toggle health status for testing - API endpoint"""
    if component in health_status:
        health_status[component] = not health_status[component]
        return jsonify({
            "component": component, 
            "status": health_status[component],
            "message": f"Toggled {component} to {health_status[component]}"
        })
    return jsonify({"error": "Component not found"}), 404

@app.route('/health/reset')
def reset_health():
    """Reset all health checks to healthy"""
    for key in health_status:
        health_status[key] = True
    return jsonify({"message": "All health checks reset", "status": health_status})

@app.route('/')
def index():
    """Root endpoint with service info"""
    return jsonify({
        "service": "Health Check API",
        "version": "v1.0.0",
        "endpoints": [
            "/health/live",
            "/health/ready", 
            "/health/detailed",
            "/metrics",
            "/health/toggle/<component>",
            "/health/reset"
        ],
        "pod": socket.gethostname()
    })

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8080)
```

#### Kubernetes Deployment
```yaml
# manifests/01-health-check-app.yaml
---
apiVersion: v1
kind: Namespace
metadata:
  name: health-system
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: health-check-api
  namespace: health-system
  labels:
    app: health-check-api
    version: v1
spec:
  replicas: 3
  selector:
    matchLabels:
      app: health-check-api
  template:
    metadata:
      labels:
        app: health-check-api
        version: v1
    spec:
      containers:
      - name: health-checker
        image: python:3.9-slim
        command:
        - /bin/sh
        - -c
        - |
          pip install flask -q
          cat > /app/app.py << 'EOF'
          # Paste the Python code above here
          EOF
          python3 /app/app.py
        ports:
        - containerPort: 8080
          name: http
          protocol: TCP
        env:
        - name: POD_IP
          valueFrom:
            fieldRef:
              fieldPath: status.podIP
        - name: NODE_NAME
          valueFrom:
            fieldRef:
              fieldPath: spec.nodeName
        - name: POD_NAME
          valueFrom:
            fieldRef:
              fieldPath: metadata.name
        livenessProbe:
          httpGet:
            path: /health/live
            port: 8080
          initialDelaySeconds: 10
          periodSeconds: 5
          timeoutSeconds: 3
          failureThreshold: 3
        readinessProbe:
          httpGet:
            path: /health/ready
            port: 8080
          initialDelaySeconds: 5
          periodSeconds: 3
          timeoutSeconds: 2
          failureThreshold: 2
        startupProbe:
          httpGet:
            path: /health/live
            port: 8080
          initialDelaySeconds: 0
          periodSeconds: 2
          failureThreshold: 15
        resources:
          requests:
            memory: "64Mi"
            cpu: "50m"
          limits:
            memory: "128Mi"
            cpu: "100m"
        securityContext:
          allowPrivilegeEscalation: false
          readOnlyRootFilesystem: true
          runAsNonRoot: true
          runAsUser: 1000
---
apiVersion: v1
kind: Service
metadata:
  name: health-check-service
  namespace: health-system
  labels:
    app: health-check-api
spec:
  selector:
    app: health-check-api
  ports:
  - name: http
    port: 8080
    targetPort: 8080
  - name: metrics
    port: 8081
    targetPort: 8080
  type: ClusterIP
---
apiVersion: v1
kind: Service
metadata:
  name: health-check-external
  namespace: health-system
  annotations:
    metallb.universe.tf/address-pool: bridged-pool
spec:
  type: LoadBalancer
  selector:
    app: health-check-api
  ports:
  - name: http
    port: 80
    targetPort: 8080
  - name: metrics
    port: 9090
    targetPort: 8080
```

### 2. Health Operator (Custom Controller)

```yaml
# manifests/02-health-operator.yaml
---
apiVersion: apiextensions.k8s.io/v1
kind: CustomResourceDefinition
metadata:
  name: healthchecks.health.example.com
spec:
  group: health.example.com
  versions:
  - name: v1
    served: true
    storage: true
    schema:
      openAPIV3Schema:
        type: object
        properties:
          spec:
            type: object
            properties:
              targetService:
                type: string
              checkInterval:
                type: string
                default: "30s"
              autoHeal:
                type: boolean
                default: false
              scaling:
                type: object
                properties:
                  minReplicas:
                    type: integer
                    default: 2
                  maxReplicas:
                    type: integer
                    default: 10
                  targetHealthScore:
                    type: integer
                    default: 80
              thresholds:
                type: object
                properties:
                  errorRate:
                    type: integer
                    default: 20
                  latency:
                    type: integer
                    default: 500
                  availability:
                    type: integer
                    default: 95
          status:
            type: object
            properties:
              lastCheck:
                type: string
              status:
                type: string
              healthScore:
                type: integer
              details:
                type: object
              conditions:
                type: array
                items:
                  type: object
                  properties:
                    type:
                      type: string
                    status:
                      type: string
                    lastTransitionTime:
                      type: string
                    message:
                      type: string
  scope: Namespaced
  names:
    plural: healthchecks
    singular: healthcheck
    kind: HealthCheck
    shortNames:
    - hc
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: health-operator-sa
  namespace: health-system
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: health-operator-role
rules:
- apiGroups: ["health.example.com"]
  resources: ["healthchecks"]
  verbs: ["*"]
- apiGroups: ["health.example.com"]
  resources: ["healthchecks/status"]
  verbs: ["update", "patch"]
- apiGroups: [""]
  resources: ["services", "pods", "deployments", "endpoints"]
  verbs: ["get", "list", "watch"]
- apiGroups: ["apps"]
  resources: ["deployments", "replicasets"]
  verbs: ["get", "list", "watch", "update", "patch"]
- apiGroups: ["autoscaling"]
  resources: ["horizontalpodautoscalers"]
  verbs: ["get", "list", "watch", "update", "patch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: health-operator-binding
subjects:
- kind: ServiceAccount
  name: health-operator-sa
  namespace: health-system
roleRef:
  kind: ClusterRole
  name: health-operator-role
  apiGroup: rbac.authorization.k8s.io
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: health-operator
  namespace: health-system
  labels:
    app: health-operator
spec:
  replicas: 1
  selector:
    matchLabels:
      app: health-operator
  template:
    metadata:
      labels:
        app: health-operator
    spec:
      serviceAccountName: health-operator-sa
      containers:
      - name: operator
        image: python:3.9-slim
        command:
        - /bin/sh
        - -c
        - |
          pip install kubernetes kopf requests prometheus-client -q
          cat > /app/operator.py << 'EOF'
          import kopf
          import kubernetes
          import requests
          import time
          import json
          import logging
          from datetime import datetime
          from prometheus_client import start_http_server, Gauge, Counter
          
          logging.basicConfig(level=logging.INFO)
          logger = logging.getLogger(__name__)
          
          # Prometheus metrics
          health_score_gauge = Gauge('health_check_score', 'Health score of service', ['service'])
          health_errors_total = Counter('health_check_errors_total', 'Total health check errors', ['service'])
          health_check_duration = Gauge('health_check_duration_seconds', 'Health check duration in seconds', ['service'])
          
          @kopf.on.startup()
          def configure(settings: kopf.OperatorSettings, **_):
              settings.persistence.finalizer = 'healthchecks.health.example.com/finalizer'
              settings.persistence.progress_storage = kopf.AnnotationsProgressStorage()
              settings.persistence.resume_timeout = 300
              logger.info("Health Operator started")
          
          @kopf.on.create('health.example.com', 'v1', 'healthchecks')
          def create_handler(spec, name, namespace, logger, **kwargs):
              logger.info(f"HealthCheck {name} created in {namespace}")
              target = spec.get('targetService')
              interval = spec.get('checkInterval', '30s')
              auto_heal = spec.get('autoHeal', False)
              
              # Initial status
              return {
                  'lastCheck': datetime.now().isoformat(),
                  'status': 'pending',
                  'healthScore': 0,
                  'targetService': target,
                  'autoHeal': auto_heal
              }
          
          @kopf.on.update('health.example.com', 'v1', 'healthchecks')
          def update_handler(spec, status, name, namespace, logger, **kwargs):
              logger.info(f"HealthCheck {name} updated")
              # Update status with new spec changes
              return {
                  'autoHeal': spec.get('autoHeal', False),
                  'targetService': spec.get('targetService')
              }
          
          @kopf.timer('health.example.com', 'v1', 'healthchecks', interval=30.0)
          def check_health(spec, status, name, namespace, logger, **kwargs):
              start_time = time.time()
              target = spec.get('targetService')
              auto_heal = spec.get('autoHeal', False)
              thresholds = spec.get('thresholds', {})
              
              error_rate_threshold = thresholds.get('errorRate', 20)
              latency_threshold = thresholds.get('latency', 500)
              
              logger.info(f"Checking health for {target}")
              
              try:
                  # Check if service exists
                  api = kubernetes.client.CoreV1Api()
                  service = api.read_namespaced_service(target, namespace)
                  
                  # Check pods in the service
                  label_selector = ""
                  if service.spec.selector:
                      label_selector = ",".join([f"{k}={v}" for k, v in service.spec.selector.items()])
                  
                  pod_list = api.list_namespaced_pod(
                      namespace,
                      label_selector=label_selector
                  )
                  
                  # Analyze pods
                  healthy_pods = 0
                  total_pods = len(pod_list.items)
                  pod_health_data = []
                  
                  for pod in pod_list.items:
                      pod_health = {
                          'name': pod.metadata.name,
                          'status': pod.status.phase,
                          'ready': False,
                          'health_status': 'unknown'
                      }
                      
                      for condition in pod.status.conditions or []:
                          if condition.type == 'Ready':
                              pod_health['ready'] = condition.status == 'True'
                              break
                      
                      if pod_health['ready']:
                          healthy_pods += 1
                          pod_health['health_status'] = 'healthy'
                      else:
                          pod_health['health_status'] = 'unhealthy'
                      
                      pod_health_data.append(pod_health)
                  
                  # Calculate health score
                  health_score = int((healthy_pods / total_pods) * 100) if total_pods > 0 else 0
                  
                  # Update Prometheus metrics
                  health_score_gauge.labels(service=target).set(health_score)
                  health_check_duration.labels(service=target).set(time.time() - start_time)
                  
                  # Update status
                  status_result = {
                      'lastCheck': datetime.now().isoformat(),
                      'healthScore': health_score,
                      'status': 'healthy' if health_score >= 80 else 'degraded',
                      'details': {
                          'totalPods': total_pods,
                          'healthyPods': healthy_pods,
                          'podDetails': pod_health_data
                      },
                      'conditions': [
                          {
                              'type': 'Healthy',
                              'status': 'True' if health_score >= 80 else 'False',
                              'lastTransitionTime': datetime.now().isoformat(),
                              'message': f"{healthy_pods}/{total_pods} pods healthy"
                          }
                      ]
                  }
                  
                  # Auto-healing logic
                  if auto_heal and health_score < 80:
                      logger.warning(f"Health score {health_score} below threshold, initiating auto-heal")
                      try:
                          # Scale up deployment
                          apps_api = kubernetes.client.AppsV1Api()
                          deployment_name = service.metadata.name
                          if not deployment_name:
                              # Try to find deployment with same labels
                              deploy_list = apps_api.list_namespaced_deployment(
                                  namespace,
                                  label_selector=label_selector
                              )
                              if deploy_list.items:
                                  deployment_name = deploy_list.items[0].metadata.name
                          
                          if deployment_name:
                              deployment = apps_api.read_namespaced_deployment(
                                  deployment_name, namespace
                              )
                              current_replicas = deployment.spec.replicas or 0
                              new_replicas = min(
                                  current_replicas + 2,
                                  spec.get('scaling', {}).get('maxReplicas', 10)
                              )
                              deployment.spec.replicas = new_replicas
                              apps_api.patch_namespaced_deployment(
                                  deployment_name, namespace, deployment
                              )
                              logger.info(f"Scaled {deployment_name} to {new_replicas} replicas")
                              status_result['details']['scalingAction'] = {
                                  'oldReplicas': current_replicas,
                                  'newReplicas': new_replicas,
                                  'reason': 'Auto-heal triggered'
                              }
                      except Exception as e:
                          logger.error(f"Auto-heal failed: {e}")
                          health_errors_total.labels(service=target).inc()
                  
                  return status_result
                  
              except kubernetes.client.ApiException as e:
                  logger.error(f"API error checking health: {e}")
                  health_errors_total.labels(service=target).inc()
                  return {
                      'lastCheck': datetime.now().isoformat(),
                      'status': 'error',
                      'healthScore': 0,
                      'error': str(e),
                      'conditions': [
                          {
                              'type': 'Healthy',
                              'status': 'False',
                              'lastTransitionTime': datetime.now().isoformat(),
                              'message': f"Error: {e}"
                          }
                      ]
                  }
              except Exception as e:
                  logger.error(f"Unexpected error: {e}")
                  health_errors_total.labels(service=target).inc()
                  return {
                      'lastCheck': datetime.now().isoformat(),
                      'status': 'error',
                      'healthScore': 0,
                      'error': str(e)
                  }
          
          @kopf.on.delete('health.example.com', 'v1', 'healthchecks')
          def delete_handler(spec, name, namespace, logger, **kwargs):
              logger.info(f"HealthCheck {name} deleted from {namespace}")
              health_score_gauge.remove(spec.get('targetService', 'unknown'))
          
          if __name__ == '__main__':
              # Start Prometheus metrics server
              start_http_server(8000)
              kopf.run()
          EOF
          python3 /app/operator.py
        ports:
        - containerPort: 8000
          name: metrics
        resources:
          requests:
            memory: "128Mi"
            cpu: "100m"
          limits:
            memory: "256Mi"
            cpu: "200m"
---
apiVersion: v1
kind: Service
metadata:
  name: health-operator-metrics
  namespace: health-system
  labels:
    app: health-operator
spec:
  selector:
    app: health-operator
  ports:
  - name: metrics
    port: 8000
    targetPort: 8000
  type: ClusterIP
```

### 3. Auto-scaling Configuration

```yaml
# manifests/03-hpa.yaml
---
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: health-check-hpa
  namespace: health-system
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: health-check-api
  minReplicas: 2
  maxReplicas: 10
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70
  - type: Resource
    resource:
      name: memory
      target:
        type: Utilization
        averageUtilization: 80
  behavior:
    scaleDown:
      stabilizationWindowSeconds: 300
      policies:
      - type: Percent
        value: 50
        periodSeconds: 60
    scaleUp:
      stabilizationWindowSeconds: 60
      policies:
      - type: Percent
        value: 100
        periodSeconds: 30
      - type: Pods
        value: 2
        periodSeconds: 30
      selectPolicy: Max
---
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: health-check-custom-hpa
  namespace: health-system
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: health-check-api
  minReplicas: 2
  maxReplicas: 10
  metrics:
  - type: Pods
    pods:
      metric:
        name: health_score
      target:
        type: AverageValue
        averageValue: "80"
```

### 4. Istio Service Mesh Configuration

```yaml
# manifests/04-istio-routing.yaml
---
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: health-check-routing
  namespace: health-system
spec:
  hosts:
  - health-check-service
  http:
  - match:
    - headers:
        version:
          exact: v2
    route:
    - destination:
        host: health-check-service
        subset: v2
      weight: 10
    - destination:
        host: health-check-service
        subset: v1
      weight: 90
  - route:
    - destination:
        host: health-check-service
        subset: v1
      weight: 100
---
apiVersion: networking.istio.io/v1beta1
kind: DestinationRule
metadata:
  name: health-check-destination
  namespace: health-system
spec:
  host: health-check-service
  subsets:
  - name: v1
    labels:
      version: v1
  - name: v2
    labels:
      version: v2
  trafficPolicy:
    connectionPool:
      tcp:
        maxConnections: 100
    loadBalancer:
      simple: LEAST_CONN
---
apiVersion: networking.istio.io/v1beta1
kind: Gateway
metadata:
  name: health-check-gateway
  namespace: health-system
spec:
  selector:
    istio: ingressgateway
  servers:
  - port:
      number: 80
      name: http
      protocol: HTTP
    hosts:
    - "health-check.local"
    - "*"
---
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: health-check-ingress
  namespace: health-system
spec:
  hosts:
  - "*"
  gateways:
  - health-check-gateway
  http:
  - match:
    - uri:
        prefix: /health
    route:
    - destination:
        host: health-check-service
        port:
          number: 8080
```

---

## Chaos Engineering

### Chaos Mesh Installation

```bash
# Install Chaos Mesh
cat << 'EOF' | bash
helm repo add chaos-mesh https://charts.chaos-mesh.org
helm repo update
helm install chaos-mesh chaos-mesh/chaos-mesh \
  --namespace chaos-mesh \
  --create-namespace \
  --set chaosDashboard.enable=true \
  --set chaosDashboard.service.type=LoadBalancer
EOF
```

### Chaos Experiment Templates

#### 1. Pod Failure Chaos
```yaml
# chaos/pod-failure.yaml
apiVersion: chaos-mesh.org/v1alpha1
kind: Schedule
metadata:
  name: scheduled-pod-failure
  namespace: health-system
spec:
  schedule: "*/5 * * * *"  # Every 5 minutes
  type: "PodChaos"
  historyLimit: 3
  podChaos:
    action: pod-failure
    mode: one
    selector:
      labelSelectors:
        app: health-check-api
    duration: "20s"
```

#### 2. Network Chaos
```yaml
# chaos/network-chaos.yaml
apiVersion: chaos-mesh.org/v1alpha1
kind: Schedule
metadata:
  name: scheduled-network-delay
  namespace: health-system
spec:
  schedule: "*/10 * * * *"  # Every 10 minutes
  type: "NetworkChaos"
  historyLimit: 3
  networkChaos:
    action: delay
    mode: one
    selector:
      labelSelectors:
        app: health-check-api
    delay:
      latency: "100ms"
      correlation: "50"
      jitter: "20ms"
    duration: "15s"
```

#### 3. CPU Stress Chaos
```yaml
# chaos/cpu-stress.yaml
apiVersion: chaos-mesh.org/v1alpha1
kind: Schedule
metadata:
  name: scheduled-cpu-stress
  namespace: health-system
spec:
  schedule: "*/15 * * * *"  # Every 15 minutes
  type: "StressChaos"
  historyLimit: 3
  stressChaos:
    mode: one
    selector:
      labelSelectors:
        app: health-check-api
    stressors:
      cpu:
        workers: 2
        load: 70
    duration: "30s"
```

#### 4. Memory Stress Chaos
```yaml
# chaos/memory-stress.yaml
apiVersion: chaos-mesh.org/v1alpha1
kind: Schedule
metadata:
  name: scheduled-memory-stress
  namespace: health-system
spec:
  schedule: "*/20 * * * *"  # Every 20 minutes
  type: "StressChaos"
  historyLimit: 3
  stressChaos:
    mode: one
    selector:
      labelSelectors:
        app: health-check-api
    stressors:
      memory:
        workers: 1
        size: "100MB"
    duration: "20s"
```

#### 5. IO Chaos
```yaml
# chaos/io-chaos.yaml
apiVersion: chaos-mesh.org/v1alpha1
kind: Schedule
metadata:
  name: scheduled-io-delay
  namespace: health-system
spec:
  schedule: "0 */2 * * *"  # Every 2 hours
  type: "IOChaos"
  historyLimit: 3
  ioChaos:
    action: latency
    mode: one
    selector:
      labelSelectors:
        app: health-check-api
    delay: "10ms"
    volumePath: "/tmp"
    duration: "30s"
```

### Chaos Test Suite

```bash
#!/bin/bash
# chaos-test-suite.sh

echo "=== Running Chaos Test Suite ==="

# 1. Pod Failure Test
echo "1. Testing Pod Failure..."
kubectl apply -f chaos/pod-failure.yaml
sleep 30
kubectl get pods -n health-system -l app=health-check-api

# 2. Network Chaos Test
echo "2. Testing Network Chaos..."
kubectl apply -f chaos/network-chaos.yaml
sleep 30
kubectl exec -n health-system deploy/health-check-api -- wget -O- http://localhost:8080/health/detailed

# 3. CPU Stress Test
echo "3. Testing CPU Stress..."
kubectl apply -f chaos/cpu-stress.yaml
sleep 30
kubectl top pods -n health-system -l app=health-check-api

# 4. Check HPA response
echo "4. HPA Status after chaos:"
kubectl get hpa -n health-system

# 5. Check health operator response
echo "5. Health Check Status:"
kubectl get healthchecks -n health-system

echo "Chaos test suite complete!"
```

---

## Monitoring & Observability

### Prometheus Configuration

```yaml
# monitoring/prometheus-config.yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: health-check-monitor
  namespace: monitoring
spec:
  selector:
    matchLabels:
      app: health-check-api
  namespaceSelector:
    matchNames:
    - health-system
  endpoints:
  - port: metrics
    path: /metrics
    interval: 15s
    scrapeTimeout: 10s
---
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: health-operator-monitor
  namespace: monitoring
spec:
  selector:
    matchLabels:
      app: health-operator
  namespaceSelector:
    matchNames:
    - health-system
  endpoints:
  - port: metrics
    path: /metrics
    interval: 30s
```

### Grafana Dashboards

```json
{
  "dashboard": {
    "title": "Health Check Dashboard",
    "panels": [
      {
        "title": "Service Health Score",
        "type": "gauge",
        "targets": [
          {
            "expr": "health_check_score",
            "legendFormat": "{{service}}"
          }
        ]
      },
      {
        "title": "Pod Status",
        "type": "stat",
        "targets": [
          {
            "expr": "count(kube_pod_status_ready{namespace='health-system', condition='true'})"
          }
        ]
      },
      {
        "title": "Chaos Events",
        "type": "table",
        "targets": [
          {
            "expr": "chaos_events_total"
          }
        ]
      },
      {
        "title": "Auto-scaling Activity",
        "type": "graph",
        "targets": [
          {
            "expr": "kube_hpa_status_current_replicas"
          }
        ]
      }
    ]
  }
}
```

### Health Check API Testing

```bash
#!/bin/bash
# test-health-api.sh

echo "=== Testing Health Check API ==="

# Get service endpoint
SERVICE_IP=$(kubectl get svc -n health-system health-check-external -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

echo "Service IP: $SERVICE_IP"

# 1. Liveness Probe
echo -e "\n1. Testing Liveness Probe:"
curl -s http://$SERVICE_IP/health/live | jq .

# 2. Readiness Probe
echo -e "\n2. Testing Readiness Probe:"
curl -s http://$SERVICE_IP/health/ready | jq .

# 3. Detailed Health
echo -e "\n3. Testing Detailed Health:"
curl -s http://$SERVICE_IP/health/detailed | jq .

# 4. Metrics
echo -e "\n4. Testing Metrics:"
curl -s http://$SERVICE_IP/metrics | head -20

# 5. Toggle health status for testing
echo -e "\n5. Toggle Database Health:"
curl -s -X POST http://$SERVICE_IP/health/toggle/database | jq .

# 6. Check health after toggle
echo -e "\n6. Health after toggle:"
curl -s http://$SERVICE_IP/health/detailed | jq '.checks.database'

# 7. Reset health
echo -e "\n7. Reset Health:"
curl -s -X POST http://$SERVICE_IP/health/reset | jq .
```

---

## Interview Preparation

### Common Interview Questions & Answers

#### 1. **What are Kubernetes health probes and why are they important?**

**Answer:**
Kubernetes provides three types of health probes:
- **Liveness Probe**: Determines if a container is running. If it fails, the container is restarted.
- **Readiness Probe**: Determines if a container can serve traffic. If it fails, the container is removed from service endpoints.
- **Startup Probe**: Provides grace period for slow-starting containers.

**Importance:**
- Ensures application availability and resilience
- Enables automatic recovery from failures
- Prevents traffic to unhealthy instances
- Supports zero-downtime deployments

**Example:**
```yaml
livenessProbe:
  httpGet:
    path: /health/live
    port: 8080
  initialDelaySeconds: 30
  periodSeconds: 10
```

#### 2. **How do you implement custom health checks?**

**Answer:**
Custom health checks go beyond simple liveness/readiness endpoints:

1. **Application-Level Checks**: Database connectivity, external API health, disk space
2. **Business Logic Checks**: Feature availability, business process status
3. **Integration Checks**: Downstream service availability, message queue status

**Implementation:**
```python
@app.route('/health/detailed')
def detailed_health():
    return jsonify({
        "status": "healthy",
        "checks": {
            "database": "connected",
            "cache": "connected",
            "external_api": "available"
        }
    })
```

#### 3. **What is Chaos Engineering and how does it benefit DevOps?**

**Answer:**
Chaos Engineering is the practice of intentionally injecting failures into a system to test its resilience.

**Benefits:**
- **Confidence Building**: Validates system resilience
- **Issue Discovery**: Finds weaknesses before they cause production incidents
- **Continuous Improvement**: Encourages proactive problem-solving
- **Team Education**: Builds understanding of system behavior

**Principles:**
1. Start with hypothesis about system behavior
2. Define steady state metrics
3. Simulate real-world events
4. Analyze results and learn
5. Automate experiments

#### 4. **How do you implement auto-scaling based on custom metrics?**

**Answer:**
Using Custom Metrics in Kubernetes HPA:

1. **Expose Custom Metrics**: Implement `/metrics` endpoint with custom metrics
2. **Configure Prometheus Adapter**: Set up custom metrics adapter
3. **Create HPA with Custom Metrics**:
```yaml
metrics:
- type: Pods
  pods:
    metric:
      name: health_score
    target:
      type: AverageValue
      averageValue: "80"
```

#### 5. **Explain the Service Mesh benefits in your architecture**

**Answer:**
Service Mesh (Istio) provides:

- **Traffic Management**: Canary deployments, A/B testing
- **Security**: mTLS, authorization policies
- **Observability**: Distributed tracing, metrics
- **Resiliency**: Retry logic, circuit breakers
- **Fault Injection**: For chaos testing

**Example:**
```yaml
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
spec:
  http:
  - match:
    - headers:
        version: v2
    route:
    - destination:
        host: service
        subset: v2
      weight: 10
```

### Lab-Based Interview Demo Script

```bash
#!/bin/bash
# interview-demo.sh

echo "=== DevOps Interview Demo Script ==="

# 1. Show cluster health
echo -e "\n1. Cluster Status:"
kubectl get nodes

# 2. Show deployed applications
echo -e "\n2. Application Status:"
kubectl get pods -n health-system

# 3. Show health checks
echo -e "\n3. Health Check Demo:"
SERVICE_IP=$(kubectl get svc -n health-system health-check-external -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
curl -s http://$SERVICE_IP/health/detailed | jq .

# 4. Show HPA
echo -e "\n4. Auto-scaling Status:"
kubectl get hpa -n health-system

# 5. Show chaos experiments
echo -e "\n5. Chaos Engineering:"
kubectl get podchaos,networkchaos,stresschaos -n health-system

# 6. Show custom operator
echo -e "\n6. Health Operator:"
kubectl get healthchecks -n health-system
kubectl logs -l app=health-operator -n health-system --tail=10

# 7. Show monitoring
echo -e "\n7. Monitoring Stack:"
kubectl get svc -n monitoring

echo -e "\nDemo Complete! Ready for Q&A."
```

### Technical Interview Tips

1. **Know Your Architecture**
   - Be prepared to draw the architecture diagram
   - Explain why you chose each component
   - Discuss alternatives considered

2. **Demonstrate Understanding**
   - Show how components interact
   - Explain failure scenarios
   - Discuss scalability considerations

3. **Practice Troubleshooting**
   - Understand common failure modes
   - Know where to look for logs/metrics
   - Demonstrate debugging methodology

4. **Show Automation**
   - Explain CI/CD pipeline integration
   - Discuss GitOps approaches
   - Show Infrastructure-as-Code

5. **Discuss Trade-offs**
   - Complexity vs. features
   - Cost vs. performance
   - Time-to-market vs. perfection

---

## Troubleshooting

### Common Issues & Solutions

#### 1. Pods in CrashLoopBackOff
```bash
# Check logs
kubectl logs <pod-name> -n health-system

# Check events
kubectl describe pod <pod-name> -n health-system

# Check resource limits
kubectl top pod <pod-name> -n health-system
```

#### 2. Operator Not Working
```bash
# Check operator logs
kubectl logs -l app=health-operator -n health-system

# Verify RBAC
kubectl auth can-i get pods -n health-system --as=system:serviceaccount:health-system:health-operator-sa

# Check CRD
kubectl get crd healthchecks.health.example.com -o yaml
```

#### 3. Chaos Experiments Not Running
```bash
# Check Chaos Mesh status
kubectl get pods -n chaos-mesh

# Verify Chaos CRDs
kubectl api-resources | grep chaos

# Check schedule
kubectl get schedule -n health-system

# View chaos events
kubectl get events -n health-system --sort-by='.lastTimestamp' | grep -i chaos
```

#### 4. HPA Not Working
```bash
# Check HPA status
kubectl describe hpa -n health-system

# Verify metrics
kubectl top pods -n health-system

# Check custom metrics
kubectl get --raw /apis/custom.metrics.k8s.io/v1beta1 | jq .
```

#### 5. Service Mesh Issues
```bash
# Check injection
kubectl get pods -n health-system -o jsonpath='{.items[*].spec.containers[*].name}'

# Verify Istio configuration
kubectl get virtualservice,gateway,destinationrule -n health-system

# Check Istio proxy status
kubectl exec -n health-system <pod-name> -c istio-proxy -- pilot-agent status
```

### Diagnostic Commands

```bash
#!/bin/bash
# diagnostic.sh - Complete diagnostic script

echo "=== Complete Diagnostic Report ==="

# 1. Cluster Information
echo -e "\n1. Cluster Info:"
kubectl cluster-info
kubectl get nodes

# 2. Namespace Status
echo -e "\n2. Namespace Status:"
kubectl get ns

# 3. Application Status
echo -e "\n3. Application Status:"
kubectl get all -n health-system

# 4. Health Check Resources
echo -e "\n4. Health Check Status:"
kubectl get healthchecks -n health-system

# 5. Chaos Experiments
echo -e "\n5. Chaos Experiments:"
kubectl get podchaos,networkchaos,stresschaos -n health-system

# 6. HPA Status
echo -e "\n6. HPA Status:"
kubectl get hpa -n health-system

# 7. Monitoring
echo -e "\n7. Monitoring Status:"
kubectl get pods -n monitoring

# 8. Service Mesh
echo -e "\n8. Service Mesh Status:"
kubectl get pods -n istio-system 2>/dev/null || echo "Istio not installed"

# 9. Resource Usage
echo -e "\n9. Resource Usage:"
kubectl top nodes 2>/dev/null || echo "Metrics not available"

# 10. Events
echo -e "\n10. Recent Events:"
kubectl get events -A --sort-by='.lastTimestamp' | tail -20
```

---

## Cleanup

### Complete Cleanup Script

```bash
#!/bin/bash
# cleanup-all.sh

echo "=== Cleaning Up K8s Health Check Lab ==="

# 1. Delete chaos experiments
echo "1. Removing Chaos Experiments..."
kubectl delete podchaos --all -n health-system 2>/dev/null
kubectl delete networkchaos --all -n health-system 2>/dev/null
kubectl delete stresschaos --all -n health-system 2>/dev/null
kubectl delete schedule --all -n health-system 2>/dev/null

# 2. Delete health check application
echo "2. Removing Health Check App..."
kubectl delete namespace health-system 2>/dev/null

# 3. Delete monitoring stack
echo "3. Removing Monitoring Stack..."
helm uninstall prometheus -n monitoring 2>/dev/null
kubectl delete namespace monitoring 2>/dev/null

# 4. Delete Chaos Mesh
echo "4. Removing Chaos Mesh..."
helm uninstall chaos-mesh -n chaos-mesh 2>/dev/null
kubectl delete namespace chaos-mesh 2>/dev/null

# 5. Delete Istio
echo "5. Removing Istio..."
istioctl uninstall --purge -y 2>/dev/null
kubectl delete namespace istio-system 2>/dev/null

# 6. Delete CRDs
echo "6. Removing CRDs..."
kubectl delete crd healthchecks.health.example.com 2>/dev/null

# 7. Verify cleanup
echo -e "\n7. Verification:"
kubectl get ns | grep -E "health-system|monitoring|chaos-mesh|istio-system" || echo "All namespaces cleaned!"

echo -e "\nCleanup Complete!"
```

### Selective Cleanup

```bash
# Clean health check app only
kubectl delete namespace health-system

# Clean chaos experiments only
kubectl delete podchaos,networkchaos,stresschaos,schedule -n health-system --all

# Clean monitoring only
helm uninstall prometheus -n monitoring

# Clean Chaos Mesh only
helm uninstall chaos-mesh -n chaos-mesh

# Clean Istio only
istioctl uninstall --purge -y
```

---

## Additional Resources

### Useful Commands Quick Reference

```bash
# Health Check Operations
kubectl get healthchecks -n health-system                    # List health checks
kubectl describe healthcheck <name> -n health-system        # View health status
kubectl edit healthcheck <name> -n health-system            # Modify health check

# Chaos Operations
kubectl get podchaos,networkchaos,stresschaos -n health-system  # List chaos experiments
kubectl logs -n chaos-mesh -l app.kubernetes.io/component=chaos-controller-manager  # Chaos logs

# Monitoring
kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-prometheus 9090:9090
kubectl port-forward -n monitoring svc/prometheus-grafana 3000:80

# Service Mesh
kubectl get virtualservice,destinationrule -n health-system
kubectl exec -n health-system deploy/health-check-api -c istio-proxy -- pilot-agent stats

# Debugging
kubectl logs -l app=health-check-api -n health-system --tail=50
kubectl describe pod -l app=health-check-api -n health-system
kubectl get events -n health-system --sort-by='.lastTimestamp'
```

### Learning Path

1. **Week 1**: Basic health checks and Kubernetes probes
2. **Week 2**: Custom health endpoints and metrics
3. **Week 3**: Auto-scaling and HPA configuration
4. **Week 4**: Chaos engineering fundamentals
5. **Week 5**: Service mesh and advanced traffic management
6. **Week 6**: Custom operators and controllers
7. **Week 7**: Observability and monitoring
8. **Week 8**: Full integration and production readiness

### Recommended Reading

- [Kubernetes Health Probes Documentation](https://kubernetes.io/docs/tasks/configure-pod-container/configure-liveness-readiness-startup-probes/)
- [Chaos Engineering Principles](https://principlesofchaos.org/)
- [Istio Traffic Management](https://istio.io/latest/docs/concepts/traffic-management/)
- [Prometheus Metrics](https://prometheus.io/docs/concepts/metric_types/)
- [Kubernetes HPA Documentation](https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale/)

---

## License

MIT License

---

**Contributors**: DevOps Engineering Team  
**Version**: 1.0.0  
**Last Updated**: 2026-07-08
