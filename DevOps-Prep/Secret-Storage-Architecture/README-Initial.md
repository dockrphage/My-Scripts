**step-by-step implementation** from the perspective of a Senior DevOps Engineer, using our tested Vagrant/K8s cluster as the foundation.

---

## Phase 0: Pre-Implementation Assessment (Interview Context)

**Key Interview Questions to Ask First:**
- *"Are these 100+ microservices homogeneous (all Kubernetes) or mixed (VMs, serverless)?"*
- *"What's the current secret blast radius - database passwords, API keys, TLS certs?"*
- *"Do we need audit logging of who accessed which secret?"*

**For your cluster:** Assuming all services run on this 3-node K8s cluster (with optional 4th as dedicated secrets infrastructure node).

---

## Phase 1: Infrastructure Preparation (Days 1-2)

### Step 1.1 - Dedicated Secrets Node (Optional but Recommended)

```ruby
# Vagrantfile addition for the 4th node
"secrets" => { 
  ip: "192.168.56.13", 
  bridged_ip: "192.168.1.53", 
  cpu: 2, 
  mem: 4096,
  vault_install: true  # Dedicated Vault server
}
```

**Interview Talking Point:** *"Isolating Vault to a dedicated node prevents a compromised application node from accessing Vault's internal state. For 100+ services, this non-negotiable."*

### Step 1.2 - Deploy HashiCorp Vault (Unsealed + HA Ready)

```bash
# On the secrets node (192.168.56.13)
helm repo add hashicorp https://helm.releases.hashicorp.com
helm install vault hashicorp/vault \
  --namespace vault \
  --create-namespace \
  --set "server.ha.enabled=true" \
  --set "server.ha.raft.enabled=true" \
  --set "server.dataStorage.size=10Gi" \
  --set "ui.enabled=true" \
  --set "ui.serviceType=LoadBalancer"
```

**Critical Interview Insight:** *"For 100 services, we need HA mode with Raft storage - eliminates external database dependency while providing auto-unseal via KMS if cloud, or Shamir secrets split across 5 admins for on-prem."*

---

## Phase 2: Secret Storage Architecture (Days 3-4)

### Step 2.1 - Vault Path Structure for 100+ Services

```bash
# Mount KV engine with versioning
vault secrets enable -version=2 -path=secret kv-v2

# Structure for 100 services
secret/
├── shared/          # Cross-cutting (DB clusters, message brokers)
│   ├── postgres-prod/
│   ├── redis-cache/
│   └── kafka-brokers/
├── service/         # Per-service secrets
│   ├── payment-api/
│   │   ├── prod/
│   │   └── staging/
│   ├── inventory-svc/
│   └── user-auth/
└── platform/        # Infrastructure (monitoring, logging)
    ├── prometheus/
    └── grafana/
```

**Interview Rationale:** *"This hierarchical structure enables fine-grained policies - security team owns `shared/`, team leads own `service/*`, platform team owns `platform/`."*

### Step 2.2 - Service Account Authentication (Workload Identity)

```bash
# Enable Kubernetes auth method
vault auth enable kubernetes

# Configure Vault to talk to K8s API
vault write auth/kubernetes/config \
  kubernetes_host="https://192.168.56.10:6443" \
  kubernetes_ca_cert=@/var/run/secrets/kubernetes.io/serviceaccount/ca.crt

# Create role for payment-api service
vault write auth/kubernetes/role/payment-api \
  bound_service_account_names=payment-api-sa \
  bound_service_account_namespaces=prod \
  policies=payment-api-policy \
  ttl=24h
```

**Key Interview Point:** *"No static tokens. Each pod gets a Vault token tied to its Kubernetes ServiceAccount. When the pod dies, access dies. When namespace is deleted, all access revokes automatically."*

---

## Phase 3: Implementation Patterns for 100+ Services (Days 5-7)

Your interview mentioned **four approaches** - here's how to choose:

### Step 3.1 - Decision Matrix per Service Type

| Pattern | Best For | Pros | Cons |
|---------|----------|------|------|
| **External Secrets Operator (ESO)** | Stateless services, 80% of use cases | K8s native, reconciliation loop | Secrets in etcd (encrypted at rest) |
| **Secrets Store CSI Driver** | PCI/HIPAA workloads, DB credentials | No etcd storage, pod-level mount | More complex, slower rotation |
| **Sidecar Container** | Legacy apps that expect files | No app changes, language agnostic | Resource overhead per pod |
| **SOPS + Git** | GitOps (ArgoCD/Flux) setups | Auditable, no runtime dependency | Requires CI/CD pipeline changes |

### Step 3.2 - Primary Implementation: External Secrets Operator (For 80% of services)

```yaml
# Install ESO
helm repo add external-secrets https://charts.external-secrets.io
helm install external-secrets external-secrets/external-secrets \
  --namespace external-secrets \
  --set installCRDs=true

# SecretStore pointing to Vault
apiVersion: external-secrets.io/v1beta1
kind: SecretStore
metadata:
  name: vault-backend
  namespace: prod
spec:
  provider:
    vault:
      server: "http://vault.vault.svc.cluster.local:8200"
      path: "secret"
      version: "v2"
      auth:
        kubernetes:
          mountPath: "auth/kubernetes"
          role: "payment-api"
---
# ExternalSecret - syncs every hour
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: payment-api-secrets
  namespace: prod
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: vault-backend
    kind: SecretStore
  target:
    name: payment-api-creds  # Creates native K8s secret
    creationPolicy: Owner
  data:
    - secretKey: db_password
      remoteRef:
        key: service/payment-api/prod
        property: db_password
```

**Interview Insight:** *"ESO gives us reconciliation - if someone manually deletes the K8s secret, it's back within 1 hour. If Vault secret rotates, K8s secret updates within 1 hour. For 100 services, this automation is critical."*

### Step 3.3 - High-Security Pattern: Secrets Store CSI Driver (For 20% most critical services)

```yaml
# Install CSI driver
helm install secrets-store-csi-driver secrets-store-csi-driver/secrets-store-csi-driver \
  --namespace kube-system \
  --set syncSecret.enabled=true

# Pod mounts secret as volume, NOT in etcd
apiVersion: v1
kind: Pod
metadata:
  name: payment-api-sensitive
  annotations:
    vault.hashicorp.com/agent-inject: "true"
    vault.hashicorp.com/role: "payment-api"
spec:
  serviceAccountName: payment-api-sa
  containers:
  - name: app
    image: payment-api:v2
    volumeMounts:
    - name: secrets
      mountPath: /mnt/secrets
      readOnly: true
  volumes:
  - name: secrets
    csi:
      driver: secrets-store.csi.k8s.io
      readOnly: true
      volumeAttributes:
        secretProviderClass: vault-db
```

**Interview Point:** *"For PCI-DSS scope services, CSI driver ensures secrets never touch etcd. Even if someone dumps etcd, they get nothing. Perfect for database passwords."*

---

## Phase 4: Secret Rotation Strategy (Day 8)

### Step 4.1 - Automated Rotation with Vault Lease Management

```bash
# Vault database secret engine with automatic rotation
vault write database/config/postgres-db \
  plugin_name=postgresql-database-plugin \
  allowed_roles="app-role" \
  connection_url="postgresql://{{username}}:{{password}}@postgres:5432/app"

vault write database/roles/app-role \
  db_name=postgres-db \
  creation_statements="CREATE USER \"{{name}}\" WITH PASSWORD '{{password}}' VALID UNTIL '{{expiration}}';" \
  revocation_statements="DROP USER \"{{name}}\";" \
  default_ttl="24h" \
  max_ttl="720h"
```

### Step 4.2 - Rotate Without Downtime (Blue-Green Secret Strategy)

```yaml
# In Vault, maintain two versions
secret/service/payment-api/prod:
  current_password: "v1_hash"
  next_password: "v2_hash_ready"
  rotation_timestamp: "2026-06-10T10:00:00Z"

# Application logic (sidecar handles)
if time > rotation_timestamp:
  if current_connection_fails:
    try next_password
    if success:
      promote_next_to_current()
      rotate_next_in_vault()
```

**Interview Talking Point:** *"For 100+ services, you cannot have all rotating simultaneously at 2 AM. We use jittered rotation (service_hash % 24) and blue-green secrets to eliminate 'thundering herd' problems."*

---

## Phase 5: GitOps Integration (Day 9)

### Step 5.1 - SOPS for Git Commit

```bash
# Install age for key generation
age-keygen -o age-key.txt

# Create .sops.yaml in repo root
creation_rules:
  - path_regex: .*/secrets/prod/.*
    encrypted_regex: "^(password|token|key|secret)$"
    age: "age1xxxx..."

# Commit placeholders only
# vault/secrets/payment-api.enc.yaml
apiVersion: v1
kind: Secret
metadata:
  name: payment-api-placeholder
stringData:
  # sops:encrypted:password: "ENC[...]"
  password: "REPLACED_BY_ESO"
```

**Interview Note:** *"With ArgoCD, we point it to the Git repo with SOPS-encrypted files. ArgoCD decrypts using age key stored in Vault (bootstrapped once). This means even Git repo admins can't see secrets."*

---

## Phase 6: Monitoring & Auditing (Day 10)

### Step 6.1 - Audit All Secret Access

```bash
# Enable audit logging in Vault
vault audit enable file file_path=/vault/logs/audit.log

# Ship to ELK or Loki
cat > /etc/vector/vault-audit.toml <<EOF
[sources.vault_audit]
type = "file"
include = ["/vault/logs/audit.log"]

[sinks.loki]
type = "loki"
inputs = ["vault_audit"]
endpoint = "http://loki.monitoring.svc:3100"
EOF
```

### Step 6.2 - Prometheus Alerts

```yaml
# Alert if secret sync fails
- alert: ExternalSecretSyncFailure
  expr: rate(external_secret_sync_error[5m]) > 0
  annotations:
    summary: "ExternalSecret {{$labels.name}} failing to sync"

# Alert if Vault token near expiry (for services with >24h TTL)
- alert: VaultTokenExpiringSoon
  expr: vault_token_expiry_seconds < 3600
  annotations:
    summary: "Service token expires in <1 hour"
```

---

## Phase 7: Disaster Recovery (Cross-Interview Question)

### Step 7.1 - Vault Unseal Recovery

```bash
# Store Shamir keys in 5 different locations
# 1. Password manager (CISO)
# 2. Break-glass safe on-prem
# 3. AWS/GCP KMS (if hybrid cloud)
# 4. CI system as env var (encrypted)
# 5. DevOps lead's YubiKey

# Auto-unseal using K8s (for prod)
vault operator init -recovery-shares=1 -recovery-threshold=1 \
  -recovery-pgp-keys="keybase://devops-team"
```

**Interview Answer:** *"For 100 services, Vault HA with Raft + KMS auto-unseal means recovery time under 5 minutes. The KMS key is managed by cloud provider - even if Vault pods all crash, new pods auto-unseal without manual intervention."*

---

## Final Architecture Diagram (Draw on Whiteboard)

```
┌─────────────────────────────────────────────────────────────┐
│                     Git Repository                           │
│  secrets-prod/ (SOPS encrypted) + placeholders              │
└────────────┬────────────────────────────────────────────────┘
             │ ArgoCD decrypts with age key (from Vault)
             ▼
┌─────────────────────────────────────────────────────────────┐
│              3-Node Kubernetes Cluster                        │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐         │
│  │  Service A  │  │  Service B  │  │  Service C  │         │
│  │  (ESO)      │  │  (CSI)      │  │  (Sidecar)  │         │
│  └──────┬──────┘  └──────┬──────┘  └──────┬──────┘         │
│         │                │                │                 │
│         ▼                ▼                ▼                 │
│  ┌──────────────────────────────────────────────────┐      │
│  │  External Secrets Operator (syncs every 1h)     │      │
│  │  Secrets Store CSI (mounts directly)            │      │
│  └──────────────────────┬───────────────────────────┘      │
└─────────────────────────┼───────────────────────────────────┘
                          │ mTLS + K8s Auth
                          ▼
              ┌───────────────────────┐
              │   HashiCorp Vault      │
              │   (4th node optional)  │
              │   - KV v2 engine       │
              │   - Audit logging      │
              │   - Auto-rotate        │
              └───────────┬───────────┘
                          │
                          ▼
              PostgreSQL, Redis, Kafka (actual secrets)
```

---

## Interview Answer Summary

**"For 100+ microservices on your Vagrant K8s cluster, I'd implement a layered approach:**

1. **Deploy Vault** on the optional 4th node with Raft HA storage
2. **80% of services** use External Secrets Operator - creates K8s secrets, reconciliation loop, simple
3. **20% of critical services** (PCI scope) use Secrets Store CSI - secrets never hit etcd
4. **Service accounts authenticate** via Kubernetes workload identity - no static tokens
5. **Rotate secrets automatically** with Vault database engine + blue-green pattern to avoid downtime
6. **GitOps with SOPS** - encrypted secrets in Git, decrypted by ArgoCD at deploy time
7. **Monitor with Prometheus** - alert on sync failures or near-expiry tokens
8. **Auto-unseal Vault** using cloud KMS (or split Shamir keys for on-prem)

**Expected outcomes:** Zero secrets in Git, zero hardcoded credentials, rotation without downtime, and full auditability of who accessed which secret from which pod."

**Time to implement on your cluster:** ~2 weeks for 100 services (parallelizable by service teams after week 1).