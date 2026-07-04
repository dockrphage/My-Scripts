# RBAC Lab: Learn by Implementing on Vagrant VM Kubernetes

## Lab Overview

This lab transforms the GKE-based RBAC tutorial [eplus.dev](https://eplus.dev/using-role-based-access-control-in-kubernetes-engine-gsp493) into a hands-on experience for local Vagrant VM Kubernetes cluster. Learn Role-Based Access Control by implementing scenarios that assign different permissions to user personas and API access to applications.

**Local Cluster Info:**
- Control Plane: cp1 (192.168.56.10)
- Worker Nodes: node1 (192.168.56.11), node2 (192.168.56.12)
- MetalLB Address Pool: 192.168.1.55-192.168.1.65
- Kubernetes Version: v1.36.2

---

## Prerequisites

```bash
# Verify cluster access
kubectl cluster-info
kubectl get nodes

# Verify MetalLB is working
kubectl get ipaddresspools.metallb.io -n metallb-system
```

---

## Lab Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Kubernetes Cluster                       │
├─────────────────────────────────────────────────────────────┤
│  ┌──────────┐  ┌──────────┐  ┌──────────┐                │
│  │  dev NS  │  │  test NS │  │  prod NS │                │
│  └──────────┘  └──────────┘  └──────────┘                │
│                                                             │
│  ┌─────────────────────────────────────────────────────┐   │
│  │  User Personas                                      │   │
│  │  ┌─────────┐  ┌─────────┐  ┌─────────┐           │   │
│  │  │ Admin   │  │ Owner   │  │ Auditor │           │   │
│  │  │ (full)  │  │ (rw)    │  │ (ro-dev)│           │   │
│  │  └─────────┘  └─────────┘  └─────────┘           │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                             │
│  ┌─────────────────────────────────────────────────────┐   │
│  │  Application: Pod Labeler                           │   │
│  │  ServiceAccount → Role → RoleBinding               │   │
│  └─────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

---

## Task 1: Setup Service Accounts and Namespaces

### Step 1.1: Create Service Accounts for User Personas

Since we're using a local cluster (not GCP IAM), we'll create Kubernetes ServiceAccounts to represent our users:

```bash
# Create service accounts for personas
kubectl create sa admin-user -n kube-system
kubectl create sa owner-user
kubectl create sa auditor-user

# Verify creation
kubectl get sa | grep -E "owner|auditor"
```

### Step 1.2: Create Namespaces

```bash
# Create three namespaces for our environments
kubectl create namespace dev
kubectl create namespace test
kubectl create namespace prod

# Verify
kubectl get namespaces
```

### Step 1.3: Set Up Admin Access

For admin access, we'll bind the cluster-admin role:

```bash
# Create ClusterRoleBinding for admin
cat <<EOF | kubectl apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: admin-binding
subjects:
- kind: ServiceAccount
  name: admin-user
  namespace: kube-system
roleRef:
  kind: ClusterRole
  name: cluster-admin
  apiGroup: rbac.authorization.k8s.io
EOF

# Test admin access
kubectl auth can-i get pods --as=system:serviceaccount:kube-system:admin-user
# Should return: yes
```

---

## Task 2: Scenario 1 - User Persona Permissions

### Step 2.1: Create Owner Role and Binding

The owner should have read-write access to all namespaces:

```bash
# Create ClusterRole for owner (read-write on core resources)
cat <<EOF | kubectl apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: owner-clusterrole
rules:
- apiGroups: [""]
  resources: ["pods", "services", "deployments", "configmaps", "secrets"]
  verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
- apiGroups: ["apps"]
  resources: ["deployments", "replicasets"]
  verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
EOF

# Create ClusterRoleBinding for owner
cat <<EOF | kubectl apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: owner-binding
subjects:
- kind: ServiceAccount
  name: owner-user
  namespace: default
roleRef:
  kind: ClusterRole
  name: owner-clusterrole
  apiGroup: rbac.authorization.k8s.io
EOF
```

### Step 2.2: Create Auditor Role and Binding

The auditor should have read-only access to ONLY the dev namespace:

```bash
# Create Role (namespace-scoped) for auditor in dev namespace
cat <<EOF | kubectl apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: auditor-role
  namespace: dev
rules:
- apiGroups: [""]
  resources: ["pods", "services", "deployments", "configmaps", "secrets"]
  verbs: ["get", "list", "watch"]
- apiGroups: ["apps"]
  resources: ["deployments", "replicasets"]
  verbs: ["get", "list", "watch"]
EOF

# Create RoleBinding for auditor in dev namespace
cat <<EOF | kubectl apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: auditor-binding
  namespace: dev
subjects:
- kind: ServiceAccount
  name: auditor-user
  namespace: default
roleRef:
  kind: Role
  name: auditor-role
  apiGroup: rbac.authorization.k8s.io
EOF
```

### Step 2.3: Test Owner Permissions

```bash
# Test as owner - should work in all namespaces
echo "=== Testing Owner Permissions ==="

# Check can get pods in dev
kubectl auth can-i get pods --as=system:serviceaccount:default:owner-user -n dev
# Should return: yes

# Check can create deployment in prod
kubectl auth can-i create deployments --as=system:serviceaccount:default:owner-user -n prod
# Should return: yes

# Check can delete in test
kubectl auth can-i delete pods --as=system:serviceaccount:default:owner-user -n test
# Should return: yes
```

### Step 2.4: Test Auditor Permissions

```bash
echo "=== Testing Auditor Permissions ==="

# Should work in dev
kubectl auth can-i get pods --as=system:serviceaccount:default:auditor-user -n dev
# Should return: yes

# Should FAIL in test
kubectl auth can-i get pods --as=system:serviceaccount:default:auditor-user -n test
# Should return: no

# Should FAIL in prod
kubectl auth can-i get pods --as=system:serviceaccount:default:auditor-user -n prod
# Should return: no

# Should FAIL for create operations even in dev
kubectl auth can-i create pods --as=system:serviceaccount:default:auditor-user -n dev
# Should return: no
```

### Step 2.5: Deploy Sample Application as Owner

Create a sample `hello-server.yaml`:

```bash
cat <<'EOF' > hello-server.yaml
apiVersion: v1
kind: Service
metadata:
  name: hello-server
  labels:
    app: hello-server
spec:
  selector:
    app: hello-server
  ports:
  - port: 80
    targetPort: 8080
  type: LoadBalancer
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: hello-server
  labels:
    app: hello-server
spec:
  replicas: 2
  selector:
    matchLabels:
      app: hello-server
  template:
    metadata:
      labels:
        app: hello-server
    spec:
      containers:
      - name: hello-server
        image: gcr.io/google-samples/hello-app:1.0
        ports:
        - containerPort: 8080
EOF
```

Deploy to all namespaces:

```bash
# Deploy as owner using impersonation
kubectl apply -f hello-server.yaml --as=system:serviceaccount:default:owner-user -n dev
kubectl apply -f hello-server.yaml --as=system:serviceaccount:default:owner-user -n test
kubectl apply -f hello-server.yaml --as=system:serviceaccount:default:owner-user -n prod

# Verify deployments
kubectl get pods --all-namespaces -l app=hello-server
```

### Step 2.6: Verify Auditor Access

```bash
# Auditor CAN view pods in dev
kubectl get pods -n dev --as=system:serviceaccount:default:auditor-user

# Auditor CANNOT view pods in test
kubectl get pods -n test --as=system:serviceaccount:default:auditor-user
# Should fail with: Error from server (Forbidden)

# Auditor CANNOT create deployments
kubectl apply -f hello-server.yaml --as=system:serviceaccount:default:auditor-user -n dev
# Should fail with: Error from server (Forbidden)
```

---

## Task 3: Scenario 2 - Application API Permissions

### Step 3.1: Create Pod Labeler Application

Create the pod-labeler application manifest:

```bash
cat <<'EOF' > pod-labeler.yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: pod-labeler
  namespace: default
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: pod-labeler
  namespace: default
rules:
- apiGroups: [""]
  resources: ["pods"]
  verbs: ["list"]   # Intentionally limited - will cause error
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: pod-labeler
  namespace: default
subjects:
- kind: ServiceAccount
  name: pod-labeler
  namespace: default
roleRef:
  kind: Role
  name: pod-labeler
  apiGroup: rbac.authorization.k8s.io
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: pod-labeler
  namespace: default
spec:
  replicas: 1
  selector:
    matchLabels:
      app: pod-labeler
  template:
    metadata:
      labels:
        app: pod-labeler
    spec:
      serviceAccountName: default   # Intentional misconfiguration
      containers:
      - name: pod-labeler
        image: gcr.io/pso-examples/pod-labeler:0.1.5
        imagePullPolicy: IfNotPresent
EOF
```

### Step 3.2: Deploy and Observe Errors

```bash
# Deploy the application
kubectl apply -f pod-labeler.yaml

# Check pod status - should show Error/CrashLoopBackOff
kubectl get pods -l app=pod-labeler

# View logs to see the error
kubectl logs -l app=pod-labeler

# Describe pod for more details
kubectl describe pod -l app=pod-labeler
```

### Step 3.3: Diagnose Issue 1 - Wrong ServiceAccount

Check the pod's service account:

```bash
# Inspect the pod's service account
kubectl get pod -l app=pod-labeler -oyaml | grep serviceAccount
# Should show: serviceAccount: default (not pod-labeler)
```

Fix by updating the deployment:

```bash
cat <<'EOF' > pod-labeler-fix-1.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: pod-labeler
  namespace: default
spec:
  replicas: 1
  selector:
    matchLabels:
      app: pod-labeler
  template:
    metadata:
      labels:
        app: pod-labeler
    spec:
      serviceAccountName: pod-labeler   # Fix: use correct SA
      containers:
      - name: pod-labeler
        image: gcr.io/pso-examples/pod-labeler:0.1.5
        imagePullPolicy: IfNotPresent
EOF

kubectl apply -f pod-labeler-fix-1.yaml
```

### Step 3.4: Diagnose Issue 2 - Insufficient Permissions

Wait for new pod and check logs again:

```bash
kubectl get pods -l app=pod-labeler
kubectl logs -l app=pod-labeler
# Should show permission denied for PATCH operations
```

Fix by updating the Role:

```bash
cat <<'EOF' > pod-labeler-fix-2.yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: pod-labeler
  namespace: default
rules:
- apiGroups: [""]
  resources: ["pods"]
  verbs: ["list", "patch"]   # Fix: add patch permission
EOF

kubectl apply -f pod-labeler-fix-2.yaml
```

### Step 3.5: Verify Successful Operation

```bash
# Delete old pod to force restart
kubectl delete pod -l app=pod-labeler

# Wait for new pod to start
kubectl get pods -l app=pod-labeler -w

# Verify logs are clean (no errors)
kubectl logs -l app=pod-labeler

# Check that pods have been labeled
kubectl get pods --show-labels | grep pod-labeler
# Should show "updated" label with timestamp
```

---

## Task 4: RBAC Troubleshooting Practice

### Step 4.1: Common RBAC Check Commands

```bash
# Check what a user can do
kubectl auth can-i --list --as=system:serviceaccount:default:auditor-user

# Check specific permission
kubectl auth can-i delete pods --as=system:serviceaccount:default:owner-user -n dev

# Check all permissions in a namespace
kubectl auth can-i --list -n dev --as=system:serviceaccount:default:auditor-user
```

### Step 4.2: View RBAC Resources

```bash
# List all Roles
kubectl get roles --all-namespaces

# List all ClusterRoles
kubectl get clusterroles

# List RoleBindings
kubectl get rolebindings --all-namespaces

# Inspect specific role
kubectl describe role auditor-role -n dev

# View RoleBinding subjects
kubectl get rolebinding auditor-binding -n dev -oyaml
```

### Step 4.3: Clean Up

```bash
# Delete application resources
kubectl delete -f pod-labeler.yaml
kubectl delete -f pod-labeler-fix-1.yaml 2>/dev/null || true

# Delete hello-server resources
kubectl delete deployment hello-server -n dev
kubectl delete deployment hello-server -n test
kubectl delete deployment hello-server -n prod
kubectl delete service hello-server -n dev
kubectl delete service hello-server -n test
kubectl delete service hello-server -n prod

# Delete RBAC resources
kubectl delete clusterrolebinding admin-binding owner-binding
kubectl delete clusterrole owner-clusterrole
kubectl delete rolebinding auditor-binding -n dev
kubectl delete role auditor-role -n dev

# Delete service accounts
kubectl delete sa admin-user -n kube-system
kubectl delete sa owner-user auditor-user

# Delete namespaces
kubectl delete namespace dev test prod
```

---

## Verification Checklist

- [ ] Service accounts created (admin-user, owner-user, auditor-user)
- [ ] Namespaces created (dev, test, prod)
- [ ] Owner can create/delete resources in all namespaces
- [ ] Auditor can view but not modify resources in dev namespace
- [ ] Auditor cannot view resources in test/prod namespaces
- [ ] Pod-labeler initially fails with wrong ServiceAccount
- [ ] Pod-labeler fails with permission error after SA fix
- [ ] Pod-labeler works correctly after Role update
- [ ] "updated" label appears on pods

---

## Key Takeaways

1. **Roles vs ClusterRoles**: Roles are namespace-scoped; ClusterRoles are cluster-wide
2. **RoleBindings vs ClusterRoleBindings**: Bind Roles to subjects within namespace; ClusterRoleBindings across cluster
3. **ServiceAccounts**: Pods use ServiceAccounts for API authentication
4. **Impersonation**: Use `--as=system:serviceaccount:namespace:name` for testing
5. **Troubleshooting**: Always check logs, events, and `kubectl auth can-i`

---

## Additional Resources

```bash
# Generate a token for a service account (for external access)
kubectl create token owner-user

# Create kubeconfig for a service account
kubectl config view --minify --raw > kubeconfig-base
# (Then add user credentials using the token)
```

**Lab Complete!** Successfully implemented and debugged RBAC on local Kubernetes cluster.
