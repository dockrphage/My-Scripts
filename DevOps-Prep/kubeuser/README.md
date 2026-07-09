Transform your cluster into a **GitOps-ready user management system** by replacing manual certificate generation with the **KubeUser** operator. This lab walks you through installing the operator, defining users declaratively, and retrieving auto-generated kubeconfigs—all on your existing `cp1`/`node1`/`node2` setup.

## Prerequisites

Your cluster is already running with:
- **Control Plane**: `cp1` (192.168.56.10)
- **Workers**: `node1`, `node2`
- **Networking**: MetallB configured with pool `192.168.1.55-192.168.1.65`
- **Runtime**: containerd v2.3.2

All steps below assume you have **cluster-admin** access via your current `kubectl` context.

---

## Step 1: Install cert-manager (Required Dependency)

KubeUser relies on `cert-manager` to secure its admission webhooks.

```bash
# Apply cert-manager
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.19.2/cert-manager.yaml

# Wait for it to be ready
kubectl wait --for=condition=ready pod -l app=cert-manager -n cert-manager --timeout=60s
```

Verify:
```bash
kubectl get pods -n cert-manager
# Expected: 3/3 Running (cert-manager, cert-manager-cainjector, cert-manager-webhook)
```

---

## Step 2: Install KubeUser Operator

We’ll use Helm to install KubeUser, injecting your cluster’s API server address so generated kubeconfigs point correctly to `cp1`.

```bash
# Add Helm repo
helm repo add kubeuser https://openkube-hub.github.io/KubeUser
helm repo update

# Capture your API server URL
export KUBERNETES_API_SERVER=$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}')

# Install KubeUser
helm install kubeuser kubeuser/kubeuser \
  --namespace kubeuser --create-namespace \
  --set env.KUBERNETES_API_SERVER="$KUBERNETES_API_SERVER"
```

Verify installation:
```bash
kubectl get pods -n kubeuser
# Expected: kubeuser-controller-manager-* Running
kubectl get crd users.auth.openkube.io
# Expected: users.auth.openkube.io established
```

---

## Step 3: Define Your First User (Declarative Access)

Instead of manually running `openssl`, `kubectl certificate`, and `kubeconfig` commands, define a `User` resource.

### Scenario: Onboard "alice" with Namespace + Cluster Access

Create `alice-user.yaml`:
```yaml
apiVersion: auth.openkube.io/v1alpha1
kind: User
metadata:
  name: alice
spec:
  auth:
    type: x509
    ttl: "72h"          # Short-lived cert (3 days) for lab safety
    autoRenew: false    # Disable auto-renewal for this lab
  roles:
    - namespace: "default"
      existingRole: "view"
  clusterRoles:
    - existingClusterRole: "view"
```

Apply it:
```bash
kubectl apply -f alice-user.yaml
```

Monitor reconciliation:
```bash
kubectl get user alice -w
# Watch for: Phase=Ready, Expiry set, AutoRenew=false
```

---

## Step 4: Retrieve and Test Alice’s Kubeconfig

KubeUser stores the generated kubeconfig in a Secret.

```bash
# Extract and decode
kubectl get secret alice-kubeconfig -n kubeuser \
  -o jsonpath='{.data.config}' | base64 -d > alice.kubeconfig

# Test access
kubectl --kubeconfig alice.kubeconfig get pods -A
kubectl --kubeconfig alice.kubeconfig get nodes
```

Verify RBAC:
- ✅ Alice can `get` pods across namespaces (via `view` ClusterRole).
- ❌ Alice cannot `delete` or `create` (no edit/admin permissions).

---

## Step 5: Advanced Patterns (Optional Extensions)

### A. Time-Bound Contractor Access
Create a 24-hour contractor account:
```yaml
apiVersion: auth.openkube.io/v1alpha1
kind: User
metadata:
  name: contractor-jane
spec:
  auth:
    type: x509
    ttl: "24h"
    autoRenew: false
  roles:
    - namespace: "production"
      existingRole: "developer"
```

### B. Cluster-Admin for Senior Engineers
```yaml
apiVersion: auth.openkube.io/v1alpha1
kind: User
metadata:
  name: bob-admin
spec:
  auth:
    type: x509
    ttl: "2160h"      # 90 days
    autoRenew: true
  clusterRoles:
    - existingClusterRole: "cluster-admin"
```

### C. Mixed Permissions (Namespace + Cluster)
```yaml
apiVersion: auth.openkube.io/v1alpha1
kind: User
metadata:
  name: dev-team-lead
spec:
  auth:
    type: x509
    ttl: "720h"
    autoRenew: true
  roles:
    - namespace: "staging"
      existingRole: "admin"
    - namespace: "monitoring"
      existingClusterRole: "view"  # ClusterRole bound to namespace
```

---

## Step 6: Rotation & Cleanup

### Automatic Rotation (if enabled)
If `autoRenew: true`, KubeUser handles renewal automatically. Monitor:
```bash
kubectl get user bob-admin -o wide
# Check: NextRenewal timestamp, Status=Ready
```

### Deleting a User
```bash
kubectl delete user alice
```
**Important**: Deleting a user removes RBAC bindings and the Secret, but **issued certificates remain valid until expiry**. Plan TTLs accordingly https://github.com/openkube-hub/KubeUser.

---

## Lab Validation Checklist

| Task | Command | Expected Result |
|------|---------|-----------------|
| Operator Running | `kubectl get pods -n kubeuser` | `kubeuser-controller-manager-*` Running |
| CRD Available | `kubectl get crd users.auth.openkube.io` | `users.auth.openkube.io` established |
| User Ready | `kubectl get user alice -o jsonpath='{.status.phase}'` | `Ready` |
| Kubeconfig Valid | `kubectl --kubeconfig alice.kubeconfig get nodes` | Lists `cp1`, `node1`, `node2` |
| RBAC Enforced | `kubectl --kubeconfig alice.kubeconfig delete pod nginx -n default` | `Error: pods "nginx" is forbidden` |

---

## Why This Beats Manual Kubeconfig Generation

| Manual Process | With KubeUser |
|----------------|---------------|
| `openssl genrsa`, `csr`, `sign` | Declarative `User` CR |
| Track expiry in spreadsheets | `kubectl get user` shows `Expiry`, `NextRenewal` |
| RBAC drift risk | RBAC bindings auto-synced by controller |
| No audit trail | Kubernetes Events + Status Conditions |
| Error-prone rotations | Atomic secret updates with rollback |

---

## Next Steps

- **GitOps Integration**: Store `User` manifests in your Git repo; ArgoCD/Flux reconciles them.
- **Custom Roles**: Create namespaced `Role` resources for fine-grained access, then reference them in `User.spec.roles`.
- **Metrics**: Expose Prometheus metrics (default endpoint: `:8080/metrics`) to track certificate issuance and rotation https://github.com/openkube-hub/KubeUser.

::search[kubeuser gitops integration examples]{type=web}
::search[kubernetes user management best practices 2025]{type=web}

Need help extending

You: cr@7:~/projects/kubeuser$ cat alice-user.yaml 
apiVersion: auth.openkube.io/v1alpha1
kind: User
metadata:
  name: alice
spec:
  auth:
    type: x509
    ttl: "72h"          # Short-lived cert (3 days) for lab safety
    autoRenew: false    # Disable auto-renewal for this lab
  roles:
    - namespace: "default"
      existingRole: "view"
  clusterRoles:
    - existingClusterRole: "view"
cr@7:~/projects/kubeuser$ kubectl apply -f alice-user.yaml
Error from server (Forbidden): error when creating "alice-user.yaml": admission webhook "vuser.auth.openkube.io" denied the request: role 'view' not found in namespace 'default'
cr@7:~/projects/kubeuser$ 

Leo AI: The error occurs because the Kubernetes built-in Role named `view` **does not exist** in the `default` namespace by default.

While `view` is a **ClusterRole** (available cluster-wide), your YAML tries to bind it as a **namespace-scoped Role** inside `default`. KubeUser’s validating webhook checks if the specific Role exists in that namespace before allowing the creation, and it fails because it only finds the ClusterRole, not a local Role.

### The Fix

You have two options depending on your intent:

#### Option 1: Use a ClusterRole for Namespace Access (Recommended for Labs)
If you want Alice to have `view` access specifically in the `default` namespace, you must bind the **ClusterRole** to that namespace. KubeUser supports this via `existingClusterRole` inside the `roles` list.

Update your `alice-user.yaml`:

```yaml
apiVersion: auth.openkube.io/v1alpha1
kind: User
metadata:
  name: alice
spec:
  auth:
    type: x509
    ttl: "72h"
    autoRenew: false
  roles:
    # Bind the ClusterRole 'view' restricted to the 'default' namespace
    - namespace: "default"
      existingClusterRole: "view" 
  # Remove the duplicate clusterRoles section if you only want access in 'default'
  # clusterRoles:
  #   - existingClusterRole: "view"
```

**Why this works:** The `roles` field with `existingClusterRole` tells KubeUser: "Create a `RoleBinding` in the `default` namespace that grants the cluster-wide `view` permissions."

#### Option 2: Create a Local Role (Strict Isolation)
If you strictly need a local `Role` object named `view` in the `default` namespace (rare for simple labs), you must create it manually first:

```bash
kubectl create role view --verb=get,list,watch --resource=pods,deployments,services -n default
```
*Then re-run `kubectl apply -f alice-user.yaml`.*

### Recommended Lab Steps

Since you are in a lab environment, **Option 1** is the cleanest approach. It leverages the standard `view` ClusterRole without needing to create custom Role objects.

1.  **Update the file** `alice-user.yaml` to use `existingClusterRole: "view"` inside the `roles` list (as shown in Option 1).
2.  **Apply the change**:
    ```bash
    kubectl apply -f alice-user.yaml
    ```
3.  **Verify the User**:
    ```bash
    kubectl get user alice -n kubeuser
    ```
4.  **Retrieve the kubeconfig**:
    ```bash
    kubectl get secret alice-kubeconfig -n kubeuser -o jsonpath='{.data.config}' | base64 -d > alice.kubeconfig
    ```
5.  **Test Access**:
    ```bash
    kubectl --kubeconfig alice.kubeconfig get pods -n default
    ```

This will successfully onboard "Alice" with read-only access to the `default` namespace.
