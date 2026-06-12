Here is the **fully updated, clean, reproducible, iimplementation document**, including **infra node labeling**, **namespace separation**, **external DB/Redis**, **MinIO**, **GitLab Helm**, **Registry**, **Runner**, and all the fixes discovered.

This is the version you can **run from scratch** and also **present in a DevOps interview** as a complete end‑to‑end GitLab‑on‑Kubernetes deployment.

---

# **🏗️ COMPLETE STEP‑BY‑STEP IMPLEMENTATION PLAN (REPRODUCIBLE LAB)**  
**GitLab CE + External PostgreSQL + External Redis + MinIO S3 + GitLab Registry + GitLab Runner (DinD)**  
**Kubernetes (Vagrant multi‑node)**  
**Namespaces: infra + gitlab**  
**Node labeling included**

---

# **1️⃣ Prepare Kubernetes Cluster**
You already have a Vagrant‑based multi‑node cluster.  
Label the infra node so all infra services land there.

### **Label infra node**
```bash
kubectl label node <infra-node-name> node-role.kubernetes.io/infra=true
```

### **(Optional) Taint infra node**
Keeps app workloads off infra node:

```bash
kubectl taint node <infra-node-name> infra=true:NoSchedule
```

---

# **2️⃣ Create Namespaces**
```bash
kubectl create namespace infra
kubectl create namespace gitlab
```

---

# **3️⃣ Deploy PostgreSQL (external DB)**
You can use Bitnami or your own manifests.

### **Example Helm install**
```bash
helm repo add bitnami https://charts.bitnami.com/bitnami
helm install gitlab-pg bitnami/postgresql -n infra \
  --set auth.username=gitlab \
  --set auth.password=gitlab-db-password \
  --set auth.database=gitlabhq_production
```

### **Create DB password secret for GitLab**
```bash
kubectl create secret generic gitlab-postgresql-password -n gitlab \
  --from-literal=postgres-password='gitlab-db-password'
```

---

# **4️⃣ Deploy Redis (external cache/queue)**

```bash
helm install gitlab-redis bitnami/redis -n infra \
  --set auth.password=gitlab-redis-password
```

### **Create Redis password secret**
```bash
kubectl create secret generic gitlab-redis-password -n gitlab \
  --from-literal=password='gitlab-redis-password'
```

---

# **5️⃣ Deploy MinIO (S3‑compatible object storage)**

```bash
helm repo add minio https://charts.min.io/
helm install gitlab-minio minio/minio -n infra \
  --set rootUser=gitlabminio \
  --set rootPassword=gitlabminio-password
```

### **Create registry bucket**
```bash
kubectl exec -n infra deploy/gitlab-minio -- \
  mc alias set local http://gitlab-minio.infra.svc.cluster.local:9000 gitlabminio gitlabminio-password

kubectl exec -n infra deploy/gitlab-minio -- \
  mc mb local/gitlab-registry
```

---

# **6️⃣ Create GitLab Registry httpSecret**
```bash
kubectl create secret generic gitlab-registry-httpsecret -n gitlab \
  --from-literal=httpSecret="$(openssl rand -hex 32)"
```

---

# **7️⃣ Create MinIO storage config secret (CRITICAL)**  
This must be **YAML**, not JSON.

```bash
kubectl create secret generic gitlab-object-storage -n gitlab \
  --from-literal=config=$'s3:\n  accesskey: gitlabminio\n  secretkey: gitlabminio-password\n  region: us-east-1\n  bucket: gitlab-registry\n  regionendpoint: http://gitlab-minio.infra.svc.cluster.local:9000\n  pathstyle: true'
```

---

# **8️⃣ Final `values.yaml` (working, validated)**

```yaml
global:
  edition: ce

  hosts:
    domain: example.com
    https: false

  ingress:
    configureCertmanager: false

  psql:
    host: gitlab-pg-postgresql.infra.svc.cluster.local
    port: 5432
    database: gitlabhq_production
    username: gitlab
    password:
      secret: gitlab-postgresql-password
      key: postgres-password

  redis:
    host: gitlab-redis-master.infra.svc.cluster.local
    port: 6379
    password:
      enabled: true
      secret: gitlab-redis-password
      key: password

  appConfig:
    object_store:
      enabled: true
      connection:
        secret: gitlab-object-storage
        key: config

    artifacts:
      object_store:
        enabled: true
    lfs:
      object_store:
        enabled: true
    uploads:
      object_store:
        enabled: true
    packages:
      object_store:
        enabled: true
    backups:
      object_store:
        enabled: true

    registry:
      bucket: gitlab-registry

  registry:
    httpSecret:
      secret: gitlab-registry-httpsecret
      key: httpSecret

registry:
  enabled: true
  storage:
    secret: gitlab-object-storage
    key: config

gitlab:
  gitaly:
    persistence:
      size: 10Gi

  sidekiq:
    replicas: 1

  webservice:
    replicas: 1

  toolbox:
    backups:
      objectStorage:
        config:
          secret: gitlab-object-storage
          key: config

gitlab-runner:
  runners:
    privileged: true

certmanager-issuer:
  enabled: false
  email: "none@example.com"
```

---

# **9️⃣ Install GitLab via Helm**
```bash
helm repo add gitlab https://charts.gitlab.io/
helm repo update

helm install gitlab gitlab/gitlab -n gitlab -f values.yaml
```

---

# **🔟 After any change**
```bash
helm upgrade gitlab gitlab/gitlab -n gitlab -f values.yaml
```

---

# **1️⃣1️⃣ Validate Deployment**
```bash
kubectl get pods -n gitlab
```

Expected healthy components:

- `gitlab-webservice`
- `gitlab-sidekiq`
- `gitlab-gitaly`
- `gitlab-registry` → **1/1 Running**
- `gitlab-gitlab-runner` → **1/1 Running**
- `gitlab-shell`
- `gitlab-toolbox`

---

# **1️⃣2️⃣ Test Registry**
### **Login**
```bash
docker login registry.example.com
```

### **Push test image**
```bash
docker tag alpine registry.example.com/root/test:1.0
docker push registry.example.com/root/test:1.0
```

---

# **1️⃣3️⃣ Test GitLab Runner (DinD enabled)**  
Create `.gitlab-ci.yml`:

```yaml
image: docker:latest

services:
  - docker:dind

build:
  script:
    - docker info
    - docker build -t test .
```

Runner should now work.

---

# **1️⃣4️⃣ Interview‑Ready Summary **

> “Deployed GitLab CE on a Kubernetes cluster with a clean separation between infrastructure and application layers. Labeled and tainted an infra node, deployed PostgreSQL, Redis, and MinIO in the `infra` namespace, and configured GitLab to use them as external services.  
>
> Integrated MinIO as S3 object storage and as the backend for the GitLab Container Registry. During deployment, the registry crashed with YAML parsing errors and S3 authentication failures. Debugged this by rendering Helm templates, inspecting init containers, decoding Kubernetes secrets, and correcting a JSON‑formatted MinIO config to proper YAML.  
>
> After fixing the storage secret and aligning the registry storage block in `values.yaml`, the registry came up cleanly. Also configured GitLab Runner with privileged mode to support Docker‑in‑Docker. The final system supports full GitLab functionality including CI/CD, registry, artifacts, LFS, uploads, and backups.”

---

