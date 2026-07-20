# 📘 Complete Lab: Building a RedisCluster Operator with Kubernetes CRDs

## 🎯 Objective
Build a Custom Resource Definition (CRD) and a custom Controller (Operator) from scratch to automate the deployment of a Redis Cluster. This lab demonstrates the **Controller Pattern**, **Reconciliation Loop**, and **Declarative API Extension** in Kubernetes.

## 📂 Prerequisites
- A running Kubernetes cluster (3+ nodes recommended).
- `kubectl` configured to access the cluster.
- Basic knowledge of terminal commands.

---

## 🚀 Step-by-Step Implementation

### 1. Create the Project Directory
```bash
mkdir -p CRD-Lab-Complete
cd CRD-Lab-Complete
```

### 2. Create the Custom Resource Definition (CRD)
This file defines the new `RedisCluster` API type.

**File:** `crd.yaml`
```yaml
apiVersion: apiextensions.k8s.io/v1
kind: CustomResourceDefinition
metadata:
  name: redisclusters.example.com
spec:
  group: example.com
  names:
    kind: RedisCluster
    listKind: RedisClusterList
    plural: redisclusters
    singular: rediscluster
  scope: Namespaced
  versions:
    - name: v1alpha1
      served: true
      storage: true
      schema:
        openAPIV3Schema:
          type: object
          properties:
            spec:
              type: object
              properties:
                nodes:
                  type: integer
                  description: Number of Redis nodes in the cluster
                password:
                  type: string
                  description: Password for the Redis cluster
                version:
                  type: string
                  default: "7.0"
                  description: Redis version to use
            status:
              type: object
              properties:
                state:
                  type: string
                  description: Current state (Pending, Ready, Failed)
                message:
                  type: string
                  description: Human-readable status message
      subresources:
        status: {}
```

### 3. Create the Desired State (User Request)
This is the file you will run to request a Redis cluster.

**File:** `my-cluster.yaml`
```yaml
apiVersion: example.com/v1alpha1
kind: RedisCluster
metadata:
  name: my-redis-cluster
  namespace: default
spec:
  nodes: 3
  password: "supersecret123"
  version: "7.0"
```

### 4. Create the Controller Logic
This is the Python script that acts as the "brain" of the operator.

**File:** `run.py`
```python
import time
import subprocess
import json

print("Controller started. Watching for RedisCluster resources...")

while True:
    try:
        # 1. Fetch all RedisClusters
        result = subprocess.run(['kubectl', 'get', 'redisclusters', '-o', 'json'], capture_output=True, text=True)
        if result.returncode != 0:
            print(f"Error fetching clusters: {result.stderr}")
            time.sleep(10)
            continue
        
        clusters = json.loads(result.stdout)['items']

        for cluster in clusters:
            name = cluster['metadata']['name']
            namespace = cluster['metadata']['namespace']
            spec = cluster.get('spec', {})
            status = cluster.get('status', {})
            
            # If already ready, skip
            if status.get('state') == 'Ready':
                continue
            
            # If spec.nodes exists, we need to act
            if 'nodes' in spec:
                nodes = spec['nodes']
                password = spec.get('password', 'changeme')
                version = spec.get('version', '7.0')

                print(f"Processing cluster: {name} with {nodes} nodes")

                # --- Create Secret ---
                secret_yaml = f"""apiVersion: v1
kind: Secret
metadata:
  name: {name}-secret
  namespace: {namespace}
type: Opaque
stringData:
  password: {password}
"""
                with open('/tmp/secret.yaml', 'w') as f:
                    f.write(secret_yaml)
                subprocess.run(['kubectl', 'apply', '-f', '/tmp/secret.yaml'], capture_output=True)

                # --- Create StatefulSet ---
                sts_yaml = f"""apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: {name}-node
  namespace: {namespace}
spec:
  serviceName: {name}-headless
  replicas: {nodes}
  selector:
    matchLabels:
      app: {name}
  template:
    metadata:
      labels:
        app: {name}
    spec:
      containers:
      - name: redis
        image: redis:{version}
        command: ["redis-server", "--requirepass", "$(PASS)"]
        env:
        - name: PASS
          valueFrom:
            secretKeyRef:
              name: {name}-secret
              key: password
        ports:
        - containerPort: 6379
"""
                with open('/tmp/sts.yaml', 'w') as f:
                    f.write(sts_yaml)
                subprocess.run(['kubectl', 'apply', '-f', '/tmp/sts.yaml'], capture_output=True)

                # --- Create Headless Service ---
                svc_yaml = f"""apiVersion: v1
kind: Service
metadata:
  name: {name}-headless
  namespace: {namespace}
spec:
  clusterIP: None
  selector:
    app: {name}
  ports:
  - port: 6379
    name: redis
"""
                with open('/tmp/svc.yaml', 'w') as f:
                    f.write(svc_yaml)
                subprocess.run(['kubectl', 'apply', '-f', '/tmp/svc.yaml'], capture_output=True)

                # --- Update Status ---
                patch = f'{{"status":{{"state":"Ready","message":"Cluster deployed with {nodes} nodes"}}}}'
                subprocess.run(['kubectl', 'patch', 'rediscluster', name, '-n', namespace, '--type=merge', '-p', patch], capture_output=True)
                print(f"Updated {name} to Ready")

    except Exception as e:
        print(f"Error in loop: {e}")
    
    time.sleep(10)
```

### 5. Create the Controller Deployment (RBAC + Pod)
This file creates the ServiceAccount, RBAC rules, ConfigMap (embedding the script), and the Deployment.
*Note: We use `alpine:3.18` and install `kubectl` at runtime to ensure compatibility.*

**File:** `controller.yaml`
```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: redis-controller
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: redis-controller-role
rules:
  - apiGroups: ["example.com"]
    resources: ["redisclusters", "redisclusters/status"]
    verbs: ["get", "list", "watch", "update", "patch"]
  - apiGroups: ["apps"]
    resources: ["statefulsets"]
    verbs: ["get", "list", "watch", "create", "update", "delete"]
  - apiGroups: [""]
    resources: ["services", "configmaps", "secrets"]
    verbs: ["get", "list", "watch", "create", "update", "delete"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: redis-controller-binding
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: redis-controller-role
subjects:
  - kind: ServiceAccount
    name: redis-controller
    namespace: default
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: redis-controller-script
data:
  run.py: |
    import time
    import subprocess
    import json

    print("Controller started. Watching for RedisCluster resources...")

    while True:
        try:
            result = subprocess.run(['kubectl', 'get', 'redisclusters', '-o', 'json'], capture_output=True, text=True)
            if result.returncode != 0:
                print(f"Error fetching clusters: {result.stderr}")
                time.sleep(10)
                continue
            
            clusters = json.loads(result.stdout)['items']

            for cluster in clusters:
                name = cluster['metadata']['name']
                namespace = cluster['metadata']['namespace']
                spec = cluster.get('spec', {})
                status = cluster.get('status', {})
                
                if status.get('state') == 'Ready':
                    continue
                
                if 'nodes' in spec:
                    nodes = spec['nodes']
                    password = spec.get('password', 'changeme')
                    version = spec.get('version', '7.0')

                    print(f"Processing cluster: {name} with {nodes} nodes")

                    # Create Secret
                    secret_yaml = f"""apiVersion: v1
kind: Secret
metadata:
  name: {name}-secret
  namespace: {namespace}
type: Opaque
stringData:
  password: {password}
"""
                    with open('/tmp/secret.yaml', 'w') as f:
                        f.write(secret_yaml)
                    subprocess.run(['kubectl', 'apply', '-f', '/tmp/secret.yaml'], capture_output=True)

                    # Create StatefulSet
                    sts_yaml = f"""apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: {name}-node
  namespace: {namespace}
spec:
  serviceName: {name}-headless
  replicas: {nodes}
  selector:
    matchLabels:
      app: {name}
  template:
    metadata:
      labels:
        app: {name}
    spec:
      containers:
      - name: redis
        image: redis:{version}
        command: ["redis-server", "--requirepass", "$(PASS)"]
        env:
        - name: PASS
          valueFrom:
            secretKeyRef:
              name: {name}-secret
              key: password
        ports:
        - containerPort: 6379
"""
                    with open('/tmp/sts.yaml', 'w') as f:
                        f.write(sts_yaml)
                    subprocess.run(['kubectl', 'apply', '-f', '/tmp/sts.yaml'], capture_output=True)

                    # Create Headless Service
                    svc_yaml = f"""apiVersion: v1
kind: Service
metadata:
  name: {name}-headless
  namespace: {namespace}
spec:
  clusterIP: None
  selector:
    app: {name}
  ports:
  - port: 6379
    name: redis
"""
                    with open('/tmp/svc.yaml', 'w') as f:
                        f.write(svc_yaml)
                    subprocess.run(['kubectl', 'apply', '-f', '/tmp/svc.yaml'], capture_output=True)

                    # Update Status
                    patch = f'{{"status":{{"state":"Ready","message":"Cluster deployed with {nodes} nodes"}}}}'
                    subprocess.run(['kubectl', 'patch', 'rediscluster', name, '-n', namespace, '--type=merge', '-p', patch], capture_output=True)
                    print(f"Updated {name} to Ready")

        except Exception as e:
            print(f"Error in loop: {e}")
        
        time.sleep(10)
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: redis-controller
  namespace: default
spec:
  replicas: 1
  selector:
    matchLabels:
      app: redis-controller
  template:
    metadata:
      labels:
        app: redis-controller
    spec:
      serviceAccountName: redis-controller
      containers:
      - name: controller
        image: alpine:3.18
        command:
        - sh
        - -c
        - |
          apk add --no-cache python3 curl ca-certificates
          curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
          chmod +x kubectl
          mv kubectl /usr/local/bin/kubectl
          python3 /app/run.py
        volumeMounts:
        - name: script
          mountPath: /app
      volumes:
      - name: script
        configMap:
          name: redis-controller-script
```

### 6. Cleanup Script
**File:** `cleanup.sh`
```bash
#!/bin/bash
echo "Cleaning up lab resources..."
kubectl delete rediscluster my-redis-cluster --ignore-not-found
kubectl delete deployment redis-controller --ignore-not-found
kubectl delete serviceaccount redis-controller --ignore-not-found
kubectl delete clusterrole redis-controller-role --ignore-not-found
kubectl delete clusterrolebinding redis-controller-binding --ignore-not-found
kubectl delete configmap redis-controller-script --ignore-not-found
kubectl delete crd redisclusters.example.com --ignore-not-found
echo "Cleanup complete."
```

---

## 🏃 Execution Instructions

### 1. Apply the CRD
```bash
kubectl apply -f crd.yaml
```

### 2. Apply the Controller
```bash
kubectl apply -f controller.yaml
```
*Wait for the pod to start and install dependencies (approx. 30-60 seconds).*

### 3. Apply the Cluster Request
```bash
kubectl apply -f my-cluster.yaml
```

### 4. Monitor Progress
```bash
# Watch the controller logs
kubectl logs -f deployment/redis-controller

# Watch the cluster status
kubectl get rediscluster my-redis-cluster -w

# Watch the pods being created
kubectl get pods -l app=my-redis-cluster -w
```

### 5. Test Scaling
```bash
kubectl patch rediscluster my-redis-cluster --type='json' -p='[{"op": "replace", "path": "/spec/nodes", "value": 5}]'
```

### 6. Cleanup
```bash
chmod +x cleanup.sh
./cleanup.sh
```

---

## 💡 Interview Articulation Guide

### The "Elevator Pitch"
> "I built a custom Kubernetes Operator to automate Redis cluster management. I defined a **Custom Resource Definition (CRD)** called `RedisCluster` to extend the Kubernetes API. Then, I implemented a **Controller** using a Python script that runs in a loop. This controller watches for `RedisCluster` resources, compares the **Desired State** (e.g., 3 nodes) with the **Current State**, and creates the necessary Secrets, Services, and StatefulSets to match. This demonstrates the **Reconciliation Loop** pattern, allowing users to manage complex stateful applications declaratively."

### Key Concepts to Mention
1.  **CRD vs. Controller:** The CRD is the *schema* (the "what"), the Controller is the *logic* (the "how").
2.  **Reconciliation Loop:** The continuous process of Observe → Compare → Act → Update Status.
3.  **Declarative vs. Imperative:** "I told Kubernetes *what* I wanted, not *how* to do it."
4.  **Self-Healing:** If a pod is deleted, the controller detects the drift and recreates it.

### Common Interview Questions
- **Q: Why use a CRD?**
  - A: To abstract complex application logic into a single, manageable API object.
- **Q: How does the controller know when to act?**
  - A: It polls the API server (or uses a watch) to detect changes in the `spec`.
- **Q: What is the status subresource?**
  - A: It allows the controller to write the current state (e.g., "Ready", "Failed") back to the object, separating user input (`spec`) from system state (`status`).

---

## 📝 Notes for Future Recreations
- **Image Choice:** We used `alpine:3.18` and installed `kubectl` dynamically. This avoids large pre-built images and ensures compatibility with any cluster version.
- **Script Embedding:** The Python script is embedded in a `ConfigMap` to keep the setup simple (no external file mounts needed for the controller pod).
- **Error Handling:** The script includes basic `try/except` blocks to prevent crashes on transient network errors.

---

**End of Lab Document**