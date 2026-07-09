# KubeUser Lab: GitOps-Driven Kubernetes User Management

## Lab Overview
**Time:** 45-60 minutes  
**Difficulty:** Intermediate  
**Prerequisites:** For convenience, I've used Vagrant Kubernetes cluster (1 control-plane + 2 workers) with MetalLB configured. Any other k8s/ k3s/ kind should work.

In this hands-on lab, we'll transform manual certificate generation into declarative user management using KubeUser. We'll onboard a testcase - user "Alice" as a developer and "Bob" as a viewer, then experience automated certificate rotation.

## Step 1: Verify Environment

First, confirm cluster is ready:

```bash
# Check cluster nodes
kubectl get nodes -o wide

# Verify MetalLB is working (note the IP pool)
kubectl -n metallb-system get ipaddresspools.metallb.io

# Check that we have a working kubeconfig
kubectl cluster-info
```

**Expected Output:**
```
Kubernetes control plane is running at https://192.168.56.10:6443
```
> **📘 What's happening:** Our Vagrant cluster uses 192.168.56.10 for API communication. MetalLB provides LoadBalancer IPs from 192.168.1.55-192.168.1.65 - important for accessing services later.

## Step 2: Install Cert-Manager

KubeUser requires cert-manager for webhook certificates:

```bash
# Install cert-manager
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.19.2/cert-manager.yaml

# Wait for cert-manager pods
kubectl wait --for=condition=ready pod -l app=cert-manager -n cert-manager --timeout=120s

# Verify installation
kubectl get pods -n cert-manager
```

**For errors:** If the `kubectl wait` command times out, check pods manually with `kubectl get pods -n cert-manager`. Some pods might need a few extra seconds to start.

## Step 3: Install KubeUser Operator

### 3.1 Add Helm Repository and Configure

```bash
# Add the KubeUser Helm repository
helm repo add kubeuser https://openkube-hub.github.io/KubeUser
helm repo update

# Extract API server address - verify the output
export KUBERNETES_API_SERVER=$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}')
echo "API Server: $KUBERNETES_API_SERVER"
```

**Expected Output:**
```
API Server: https://192.168.56.10:6443
```

### 3.2 Install the Operator

```bash
# Install KubeUser in its own namespace
helm install kubeuser kubeuser/kubeuser --create-namespace -n kubeuser \
  --set env.KUBERNETES_API_SERVER="$KUBERNETES_API_SERVER"

# Verify installation
kubectl get pods -n kubeuser
kubectl get crd | grep users
```

**Troubleshooting:** If the `helm install` fails, ensure cluster has network access to GitHub. This can be checked with `curl -I https://github.com`.

> **📘 What's happening:** The operator needs API server address to generate valid kubeconfigs. It creates a CRD called `User` that extends Kubernetes' API.

## Step 4: Create Custom Roles (Pre-Requisite)

Create Required Namespaces

```bash
# Create the namespaces needed for the lab
kubectl create namespace staging
kubectl create namespace development
kubectl create namespace ci

# Verify they were created
kubectl get namespaces
```

Before creating users, define the custom roles referenced in our configuration:

```bash
# Create a developer Role in staging namespace
kubectl create role developer --verb=get,list,create,update,delete --resource=pods,services,configmaps -n staging

# Create a cluster-wide view-plus Role
kubectl create clusterrole view-plus --verb=get,list,watch --resource=pods,nodes,events,services

# Verify roles exist
kubectl get roles -n staging
kubectl get clusterroles | grep view-plus
```

> **📘 What's happening:** KubeUser binds users to existing roles but doesn't create them. By pre-creating these roles, we follow GitOps best practices where role definitions live separate from user assignments.

## Step 5: Onboard Developer "Alice"

### 5.1 Create the User Manifest

Create a file named `alice-user.yaml`:

```yaml
apiVersion: auth.openkube.io/v1alpha1
kind: User
metadata:
  name: alice
spec:
  auth:
    type: x509
    ttl: 8760h          # 1 Year
    autoRenew: true
    renewBefore: "720h" # Renew 30 days before expiry
  roles:
    - namespace: "development"
      existingClusterRole: "admin"
    - namespace: "staging"
      existingRole: "developer"
  clusterRoles:
    - existingClusterRole: "view"
    - existingClusterRole: "view-plus"
```

**Important:** Note the roles we created in Step 4 match `developer` and `view-plus`. The built-in `admin` and `view` clusterroles already exist.

### 5.2 Create the User

```bash
# Apply the user definition
kubectl apply -f alice-user.yaml

# Check user status
kubectl get users

# Examine the generated secret
kubectl get secrets -n kubeuser | grep alice
```

**Expected Output:**
```
NAME                AGE   STATUS   EXPIRY                 RENEWAL
alice               5s    Ready    2027-07-09T12:00:00Z   2027-06-09T12:00:00Z
```

> **📘 What's happening:** The operator generates a private key, creates a CSR, gets it signed, and stores everything in a secret named `alice-kubeconfig` - all without touching openssl!

### 5.3 Retrieve and Test Alice's Credentials

```bash
# Extract Alice's kubeconfig
kubectl get secret alice-kubeconfig -n kubeuser -o jsonpath='{.data.config}' | base64 -d > alice.kubeconfig

# Test access in development namespace
kubectl --kubeconfig alice.kubeconfig get pods -n development

# Test access in staging (should work with developer role)
kubectl --kubeconfig alice.kubeconfig get pods -n staging

# Test cluster-wide access (view-plus role)
kubectl --kubeconfig alice.kubeconfig get nodes
```

**Expected Results:**
- Development: Access to all pods (admin rights)
- Staging: Can list, create, update pods (developer rights)
- Cluster-wide: Can view nodes, events (view-plus rights)

### 5.4 Verify RBAC Bindings

```bash
# Check namespace bindings
kubectl get rolebindings -n development | grep alice
kubectl get rolebindings -n staging | grep alice

# Check cluster bindings
kubectl get clusterrolebindings | grep alice
```

## Step 6: Onboard Viewer "Bob"

Now create Bob with read-only access:

Create `bob-user.yaml`:

```yaml
apiVersion: auth.openkube.io/v1alpha1
kind: User
metadata:
  name: bob
spec:
  auth:
    type: x509
    ttl: 720h           # 30 days - shorter expiry for interns
    autoRenew: true
    renewBefore: "240h" # Renew 10 days before expiry
  clusterRoles:
    - existingClusterRole: "view"
```

```bash
kubectl apply -f bob-user.yaml
kubectl get users

# Retrieve Bob's kubeconfig
kubectl get secret bob-kubeconfig -n kubeuser -o jsonpath='{.data.config}' | base64 -d > bob.kubeconfig

# Test Bob's access - should be read-only everywhere
kubectl --kubeconfig bob.kubeconfig get pods -n development
kubectl --kubeconfig bob.kubeconfig get nodes
kubectl --kubeconfig bob.kubeconfig create deployment nginx --image=nginx -n development
```

**Expected Results:**
- Read operations work
- Create operations fail (permission denied)

## Step 7: Experience Auto-Renewal

### 7.1 Create a Short-Lived Certificate

Create `short-lived-user.yaml`:

```yaml
apiVersion: auth.openkube.io/v1alpha1
kind: User
metadata:
  name: temp-dev
spec:
  auth:
    type: x509
    ttl: 48h            # 2 days - for testing renewal
    autoRenew: true
    renewBefore: "16h"  # Renew at 33% of lifetime (16 hours in)
  roles:
    - namespace: "development"
      existingClusterRole: "view"
```

```bash
kubectl apply -f short-lived-user.yaml
kubectl get users
```

### 7.2 Monitor the Renewal Process

```bash
# Check initial secret creation time
kubectl get secret temp-dev-kubeconfig -n kubeuser -o yaml | grep creationTimestamp

# Simulate time passing (in a real environment, wait)
# Check the renewal status:
kubectl get users temp-dev -o yaml | grep -A 5 status
```

> **📘 What's happening:** KubeUser uses the "Shadow Secret" pattern - it creates new certificates in a temporary secret first, validates them, then atomically swaps. This ensures zero downtime during renewal.

## Step 8: Auditing and Cleanup

### 8.1 Audit Current Users

```bash
# List all users
kubectl get users

# Check specific user details
kubectl describe user alice

# List all role bindings
kubectl get clusterrolebindings,rolebindings --all-namespaces | grep -E "alice|bob|temp-dev"
```

### 8.2 Clean Up Resources

```bash
# Delete users (removes secrets and RBAC bindings)
kubectl delete user alice bob temp-dev

# Uninstall KubeUser (optional)
helm uninstall kubeuser -n kubeuser

# Delete cert-manager (optional)
kubectl delete -f https://github.com/cert-manager/cert-manager/releases/download/v1.19.2/cert-manager.yaml
```

## 🎯 Challenge Exercise

**Objective:** Create a user "jenkins-build" that can only create/update deployments in the `ci` namespace, with a 90-day certificate that auto-renews.

**Hint:** :
1. Create a custom role in the `ci` namespace
2. Create the User manifest with appropriate spec
3. Verify the permissions work

<details>
<summary>Solution (click to reveal)</summary>

```yaml
# First create the role
kubectl create namespace ci
kubectl create role deployment-manager --verb=get,list,create,update,delete --resource=deployments -n ci

# Create the user
cat <<EOF | kubectl apply -f -
apiVersion: auth.openkube.io/v1alpha1
kind: User
metadata:
  name: jenkins-build
spec:
  auth:
    type: x509
    ttl: 2160h          # 90 days
    autoRenew: true
    renewBefore: "720h" # 30 days before expiry
  roles:
    - namespace: "ci"
      existingRole: "deployment-manager"
EOF

# Retrieve and test
kubectl get secret jenkins-build-kubeconfig -n kubeuser -o jsonpath='{.data.config}' | base64 -d > jenkins.kubeconfig
kubectl --kubeconfig jenkins.kubeconfig create deployment test-nginx --image=nginx -n ci
```
</details>

## Common Issues and Solutions

| Issue | Solution |
|-------|----------|
| `error: unable to recognize "alice-user.yaml": no matches for kind "User"` | KubeUser not installed correctly. Check `kubectl get crd \| grep users` |
| User stuck in `Pending` state | Check operator logs: `kubectl logs -n kubeuser deployment/kubeuser-controller` |
| Role binding references missing role | Ensure roles exist before creating user: `kubectl get roles -n staging` |
| Certificate verification fails | Check API server address: `kubectl config view --minify` |

## Knowledge Check

1. **What's the advantage of the "Shadow Secret" pattern?**
   - It prevents downtime during certificate rotation by validating new certs before replacing old ones.

2. **Why must roles be pre-created before users?**
   - KubeUser binds to existing roles but doesn't manage role definitions, promoting separation of concerns in GitOps.

3. **What happens if autoRenew is disabled?**
   - The user's certificate expires at TTL and they lose access until manually renewed.

4. **How does the 33% rule protect our cluster?**
   - It triggers renewal early (at 33% of lifetime remaining) providing a safety buffer, preventing last-minute expiration issues.

## What we've Learned

✅ Install KubeUser operator with cert-manager  
✅ Create custom roles and clusterroles  
✅ Onboard users with different permission levels  
✅ Retrieve and test user kubeconfigs  
✅ Understand automatic certificate rotation  
✅ Audit user bindings and status  

We've transformed manual certificate management into declarative GitOps - now user access is as manageable as our application deployments!
