### Overview

Prerequisites (i built k8s setup with metallb and ingress-nginx already)
cr@7:~/projects/gitops-lab$ kubectl get nodes -o wide
NAME    STATUS   ROLES           AGE   VERSION   INTERNAL-IP     EXTERNAL-IP   OS-IMAGE             KERNEL-VERSION               CONTAINER-RUNTIME
cp1     Ready    control-plane   8h    v1.36.2   192.168.56.10   <none>        Ubuntu 22.04.5 LTS   5.15.0-179-generic (amd64)   containerd://2.3.2
node1   Ready    <none>          8h    v1.36.2   192.168.56.11   <none>        Ubuntu 22.04.5 LTS   5.15.0-179-generic (amd64)   containerd://2.3.2
node2   Ready    <none>          8h    v1.36.2   192.168.56.12   <none>        Ubuntu 22.04.5 LTS   5.15.0-179-generic (amd64)   containerd://2.3.2
cr@7:~/projects/gitops-lab$ kubectl get ipaddresspools.metallb.io -A -o json   | jq -r '.items[] | "\(.metadata.name) → \(.spec.addresses[])"'
bridged-pool → 192.168.1.55-192.168.1.65
cr@7:~/projects/gitops-lab$ kubectl get svc -n ingress-nginx ingress-nginx-controller
NAME                       TYPE           CLUSTER-IP       EXTERNAL-IP    PORT(S)                      AGE
ingress-nginx-controller   LoadBalancer   10.105.141.241   192.168.1.56   80:32766/TCP,443:30904/TCP   8h
cr@7:~/projects/gitops-lab$ git remote -v
origin  https://github.com/dockrphage/gitops-lab.git (fetch)
origin  https://github.com/dockrphage/gitops-lab.git (push)

---

## Track 1 – Foundations (GitOps + Argo CD on your current cluster)

#### Lab 01 – Baseline cluster & repo sanity

- **Goal:** Confirm your platform is ready for GitOps.
- **Key concepts:** Cluster inventory, service exposure, repo structure.
- **Outcomes:**
  - Capture `kubectl get nodes -o wide`, `kubectl get ns`, `kubectl get svc -A` into a `docs/cluster-baseline.md`.
  - Define a **GitOps repo layout**, e.g.:
    - `clusters/vagrant-k8s/`
    - `apps/`
    - `infra/ingress-nginx/`, `infra/metallb/`

#### Lab 02 – Install Argo CD via manifests/Helm

- **Goal:** Deploy Argo CD declaratively from Git.
- **Key concepts:** Argo CD components, CRDs, Git as source of truth.
- **Outcomes:**
  - Create `infra/argocd/` with either:
    - Helm chart values, or
    - Raw Argo CD install manifests.
  - Apply once with `kubectl apply -f infra/argocd/` (bootstrap), then **never again by hand**—future changes go via Git.
  - Expose Argo CD via `Ingress` using your `ingress-nginx` LoadBalancer (`192.168.1.56`).

#### Lab 03 – First GitOps application (guestbook or similar)

- **Goal:** Experience the Git→Argo→cluster flow end‑to‑end.
- **Key concepts:** `Application` CRD, sync, health, drift.
- **Outcomes:**
  - Create `apps/guestbook/base/` with Deployment, Service, Ingress.
  - Create `apps/guestbook/app.yaml` (Argo CD Application) pointing to your GitHub repo and path.
  - Add via:
    - `kubectl apply -f apps/guestbook/app.yaml`, or
    - Argo CD UI, but **source of truth remains in Git**.
  - Play with:
    - Manual sync
    - Viewing diff when you change manifests in Git.

#### Lab 04 – GitOps sync policies

- **Goal:** Understand how Argo CD enforces desired state.
- **Key concepts:** `syncPolicy`, `automated`, `prune`, `selfHeal`.
- **Outcomes:**
  - Add automated sync to `apps/guestbook/app.yaml`.
  - Enable `prune` and `selfHeal`.
  - Simulate drift:
    - `kubectl scale deployment guestbook --replicas=5`
    - Watch Argo CD reconcile back.
  - Delete a resource from Git and see prune in action.

#### Lab 05 – GitOps repo structure for environments

- **Goal:** Introduce environments (dev/stage/prod) using Git layout.
- **Key concepts:** env folders, overlays, promotion via Git.
- **Outcomes:**
  - Structure:
    - `apps/guestbook/dev/`
    - `apps/guestbook/stage/`
    - `apps/guestbook/prod/`
  - Use different Ingress hosts or replica counts per env.
  - Create three Argo CD Applications, one per env, all pointing to the same repo but different paths.

---

## Track 2 – Config management & patterns

#### Lab 06 – Helm‑based GitOps app

- **Goal:** Deploy a Helm chart via Argo CD.
- **Key concepts:** Helm values, GitOps overrides.
- **Outcomes:**
  - Add `apps/nginx-helm/` with:
    - `Chart.yaml` or external chart reference.
    - `values-dev.yaml`, `values-prod.yaml`.
  - Argo CD Application using `spec.source.helm.valuesFiles`.
  - Change values in Git (e.g., replica count, resources) and watch Argo CD sync.

#### Lab 07 – Kustomize overlays

- **Goal:** Use Kustomize for env‑specific customization.
- **Key concepts:** base/overlay, patches, images.
- **Outcomes:**
  - `apps/guestbook-kustomize/base/` with core manifests.
  - `apps/guestbook-kustomize/overlays/dev/`, `/prod/` with:
    - `kustomization.yaml`
    - patches for resources, labels, ingress host.
  - Argo CD Applications pointing to each overlay.

#### Lab 08 – App‑of‑Apps pattern

- **Goal:** Bootstrap the whole cluster from a single root Application.
- **Key concepts:** hierarchical apps, cluster bootstrap.
- **Outcomes:**
  - Create `clusters/vagrant-k8s/apps/` containing:
    - `argocd-app.yaml`
    - `ingress-nginx-app.yaml`
    - `guestbook-app.yaml`
    - etc.
  - Create `clusters/vagrant-k8s/root-app.yaml` (root Argo CD Application) pointing to `clusters/vagrant-k8s/apps/`.
  - Test: delete all Applications, re‑apply only `root-app.yaml`, watch the cluster rebuild itself.

---

## Track 3 – Operational GitOps (RBAC, multi‑cluster, rollbacks)

#### Lab 09 – Argo CD Projects & RBAC

- **Goal:** Segment access and control boundaries.
- **Key concepts:** `AppProject`, source/destination restrictions, RBAC.
- **Outcomes:**
  - Define `projects/platform.yaml` and `projects/apps.yaml`.
  - Assign Applications to projects:
    - Platform (ingress, MetalLB, Argo CD)
    - Apps (guestbook, nginx‑helm, etc.)
  - Configure basic RBAC rules in `argocd-rbac-cm` via Git.

#### Lab 10 – Rollbacks & history

- **Goal:** Use Git history + Argo CD history to roll back safely.
- **Key concepts:** sync history, revision pinning.
- **Outcomes:**
  - Make a breaking change in `apps/guestbook`.
  - Observe Argo CD health status.
  - Roll back:
    - Via Argo CD UI/CLI to previous revision.
    - Or via Git revert and sync.

#### Lab 11 – Multi‑cluster (optional, given your Vagrant skills)

- **Goal:** Manage more than one cluster from a single Argo CD.
- **Key concepts:** cluster registration, destination scoping.
- **Outcomes:**
  - Spin up a second Vagrant/KIND cluster.
  - Register it in Argo CD (`argocd cluster add`).
  - Create Applications targeting each cluster with `spec.destination.server`.
  - Use Git structure:
    - `clusters/vagrant-k8s/`
    - `clusters/kind-lab/`

---

## Track 4 – Advanced GitOps (image updates, progressive delivery)

#### Lab 12 – Image updater GitOps flow

- **Goal:** Automate image tag bumps via Git.
- **Key concepts:** Argo CD Image Updater, write‑back strategies.
- **Outcomes:**
  - Install Argo CD Image Updater via manifests in `infra/image-updater/`.
  - Configure it for `guestbook`:
    - Watches a registry.
    - Writes new tags into your Git repo.
  - Observe:
    - Git commits from Image Updater.
    - Argo CD syncing new image versions.

#### Lab 13 – Progressive delivery with Argo Rollouts

- **Goal:** Implement canary/blue‑green using GitOps.
- **Key concepts:** Rollouts CRD, analysis, traffic splitting.
- **Outcomes:**
  - Install Argo Rollouts via `infra/argo-rollouts/`.
  - Convert `guestbook` Deployment to a `Rollout`.
  - Use ingress‑nginx + Service annotations for traffic routing.
  - Drive rollout steps purely via Git changes.

---


1. Repo structure  
2. Argo CD install from Git  
3. Exposing Argo CD via ingress  
4. First GitOps app (guestbook)  
5. Automated sync + drift  
6. App‑of‑apps bootstrap

---

### 1. Prepare repo structure

In your cloned repo (`gitops-lab`):

```bash
cd ~/projects/gitops-lab
git status
```

Create a basic GitOps layout:

```bash
mkdir -p infra/argocd infra/ingress-nginx apps/guestbook clusters/vagrant-k8s
```

You’re going to use:

- `infra/` → platform components (Argo CD, ingress, etc.)
- `apps/` → application manifests
- `clusters/vagrant-k8s/` → app‑of‑apps and cluster bootstrap

Commit the empty structure:

```bash
git add infra apps clusters
git commit -m "chore: initial gitops repo structure"
git push origin main
```

---

### 2. Install Argo CD from Git (bootstrap)

#### 2.1. Argo CD namespace and core manifests

Create `infra/argocd/namespace.yaml`:

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: argocd
```

Create `infra/argocd/install.yaml` (minimal official install):

```yaml
apiVersion: v1
kind: List
items:
  - apiVersion: v1
    kind: ServiceAccount
    metadata:
      name: argocd-server
      namespace: argocd
  # In practice, paste the official Argo CD install manifests here:
  # https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
```

Instead of pasting by hand, do:

```bash
curl -sSL https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml \
  -o infra/argocd/install.yaml
```

Commit:

```bash
git add infra/argocd
git commit -m "feat: add argocd install manifests"
git push origin main
```

#### 2.2. Apply once (bootstrap)

You’ll break the “Git only” rule once to bootstrap Argo CD:

```bash
kubectl apply -f infra/argocd/namespace.yaml
kubectl apply -f infra/argocd/install.yaml
```

Check:

```bash
kubectl get pods -n argocd
```

You should see `argocd-server`, `argocd-repo-server`, etc. in `Running` state.

---

### 3. Expose Argo CD via ingress‑nginx

You already have:

- MetalLB IP pool: `192.168.1.55-192.168.1.65`
- ingress‑nginx LoadBalancer: `EXTERNAL-IP: 192.168.1.56`

Pick a host, e.g. `argocd.local`.

#### 3.1. Create Argo CD ingress

Create `infra/argocd/ingress.yaml`:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: argocd-server-ingress
  namespace: argocd
  annotations:
    kubernetes.io/ingress.class: "nginx"
    nginx.ingress.kubernetes.io/backend-protocol: "HTTPS"
spec:
  rules:
    - host: argocd.local
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: argocd-server
                port:
                  number: 443
  tls:
    - hosts:
        - argocd.local
      secretName: argocd-server-tls
```

For local lab, you can skip TLS by pointing to port `80` and removing `tls` if you want simplicity.

Apply (still bootstrap phase):

```bash
kubectl apply -f infra/argocd/ingress.yaml
```

Add `/etc/hosts` entry on your workstation:

```bash
echo "192.168.1.56 argocd.local" | sudo tee -a /etc/hosts
```

Now you should reach Argo CD UI at `https://argocd.local` (or `http://` if you skipped TLS).

---

### 4. First GitOps app: guestbook

#### 4.1. Guestbook manifests

Create `apps/guestbook/deployment.yaml`:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: guestbook
  namespace: default
  labels:
    app: guestbook
spec:
  replicas: 2
  selector:
    matchLabels:
      app: guestbook
  template:
    metadata:
      labels:
        app: guestbook
    spec:
      containers:
        - name: guestbook
          image: ghcr.io/dockrphage/guestbook:latest # or any demo image
          ports:
            - containerPort: 3000
```

Create `apps/guestbook/service.yaml`:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: guestbook
  namespace: default
  labels:
    app: guestbook
spec:
  type: ClusterIP
  selector:
    app: guestbook
  ports:
    - port: 80
      targetPort: 3000
      protocol: TCP
      name: http
```

Create `apps/guestbook/ingress.yaml`:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: guestbook
  namespace: default
  annotations:
    kubernetes.io/ingress.class: "nginx"
spec:
  rules:
    - host: guestbook.local
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: guestbook
                port:
                  number: 80
```

Commit:

```bash
git add apps/guestbook
git commit -m "feat: add guestbook app manifests"
git push origin main
```

Add `/etc/hosts` entry:

```bash
echo "192.168.1.56 guestbook.local" | sudo tee -a /etc/hosts
```

---

### 5. Argo CD Application for guestbook

#### 5.1. Application manifest

Create `apps/guestbook/app.yaml`:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: guestbook
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/dockrphage/gitops-lab.git
    targetRevision: main
    path: apps/guestbook
  destination:
    server: https://kubernetes.default.svc
    namespace: default
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=false
```

Commit:

```bash
git add apps/guestbook/app.yaml
git commit -m "feat: add argocd application for guestbook"
git push origin main
```

#### 5.2. Apply Application (bootstrap)

Apply once:

```bash
kubectl apply -f apps/guestbook/app.yaml
```

Now in Argo CD UI:

- You should see `guestbook` Application.
- Hit **Sync** once if it doesn’t auto‑sync yet.
- Confirm:

```bash
kubectl get pods,svc,ingress -n default
```

Browse to `http://guestbook.local`.

---

### 6. Test automated sync & drift

#### 6.1. Drift simulation

Scale manually:

```bash
kubectl scale deployment guestbook -n default --replicas=5
kubectl get deploy guestbook -n default
```

Argo CD should detect drift and, with `selfHeal: true`, reconcile back to `replicas: 2`.

#### 6.2. Prune test

Delete `apps/guestbook/ingress.yaml` from Git:

```bash
git rm apps/guestbook/ingress.yaml
git commit -m "feat: remove guestbook ingress"
git push origin main
```

Argo CD will see the resource removed from desired state and, with `prune: true`, delete the Ingress from the cluster.

---

### 7. App‑of‑apps bootstrap

Now let’s make the cluster self‑bootstrapping from a single root Application.

#### 7.1. Define child Applications as files

Move your Application manifests under `clusters/vagrant-k8s/apps/`:

```bash
mkdir -p clusters/vagrant-k8s/apps
mv apps/guestbook/app.yaml clusters/vagrant-k8s/apps/guestbook-app.yaml
```

Create `clusters/vagrant-k8s/apps/argocd-app.yaml` (to manage Argo CD itself):

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: argocd
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/dockrphage/gitops-lab.git
    targetRevision: main
    path: infra/argocd
  destination:
    server: https://kubernetes.default.svc
    namespace: argocd
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```

You can later add more apps (ingress‑nginx, monitoring, etc.) in this folder.

Commit:

```bash
git add clusters/vagrant-k8s/apps
git commit -m "feat: add app-of-apps children for vagrant cluster"
git push origin main
```

#### 7.2. Root Application

Create `clusters/vagrant-k8s/root-app.yaml`:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: vagrant-k8s-root
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/dockrphage/gitops-lab.git
    targetRevision: main
    path: clusters/vagrant-k8s/apps
    directory:
      recurse: true
  destination:
    server: https://kubernetes.default.svc
    namespace: argocd
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```

Commit:

```bash
git add clusters/vagrant-k8s/root-app.yaml
git commit -m "feat: add root app for vagrant cluster"
git push origin main
```

Apply once:

```bash
kubectl apply -f clusters/vagrant-k8s/root-app.yaml
```

In Argo CD UI:

- You’ll see `vagrant-k8s-root`.
- It will create `argocd` and `guestbook` Applications from the `clusters/vagrant-k8s/apps` directory.
- From now on, you can rebuild the cluster apps by just applying `root-app.yaml` on a fresh cluster.

---

