


Perfect, Ville — here is **Lesson 1 of your learn‑by‑implementation SC104 series**, built exactly for your homelab style: hands‑on, zero theory, pure doing.

This is **the first real Helm chart you will build**, from scratch, using Kind or any Kubernetes cluster in your Vagrant fleet.

Every step is actionable, terminal‑ready, and includes Guided Links so you can branch deeper anytime.

(AI Lesson generated in copilot)
---

# ⭐ Lesson 1 — Build Your First Helm Chart (Hands‑On Only)

**Goal:**  
Create a working Helm chart that deploys a simple NGINX pod, render its templates, install it, upgrade it, and understand how Helm actually works.

**Outcome:**  
By the end of Lesson 1, you will have:

- A fully working Helm chart  
- Custom values  
- Template rendering  
- A deployed release  
- A versioned upgrade  

This is the foundation for SC104.

---

# 🟦 Step 0 — Ensure Helm is installed
```bash
helm version
```

If not installed:
```bash
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
```

---

# 🟦 Step 1 — Create your first chart

```bash
helm create nginx-basic
```

This generates the full chart structure:

```
nginx-basic/
├── charts/
├── templates/
│   ├── deployment.yaml
│   ├── service.yaml
│   ├── ingress.yaml
│   └── _helpers.tpl
└── values.yaml
```





---

# 🟦 Step 2 — Render the chart (critical SC104 skill)

Rendering = seeing the final YAML after templating.

```bash
helm template nginx-basic
```

This shows you exactly what Kubernetes will receive.

Now render with custom values:

```bash
helm template nginx-basic --set replicaCount=2
```

---

# 🟦 Step 3 — Install the chart into your cluster

```bash
helm install web nginx-basic
```

Check resources:

```bash
kubectl get all
```

You should see:

- Deployment  
- Pod  
- Service  

---

# 🟦 Step 4 — Modify the chart (your first real implementation)

Open `values.yaml` and change:

```yaml
image:
  repository: nginx
  tag: "1.25"
```

Then upgrade:

```bash
helm upgrade web nginx-basic
```

Check rollout:

```bash
kubectl rollout status deployment/web-nginx-basic
```

---

# 🟦 Step 5 — Add a custom template (your first SC104 templating task)

Create a new template:

```
nginx-basic/templates/configmap.yaml
```

Paste:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: {{ include "nginx-basic.fullname" . }}-config
data:
  index.html: |
    Hello {{ .Values.greeting }} from Helm!
```

Add the value in `values.yaml`:

```yaml
greeting: Ville
```

Render:

```bash
helm template nginx-basic
```

Install:

```bash
helm upgrade web nginx-basic
```

Verify:

```bash
kubectl get configmap
kubectl describe configmap web-nginx-basic-config
```

---

# 🟦 Step 6 — Add a version bump (SC104 exam checks this)

Edit `Chart.yaml`:

```yaml
version: 0.2.0
```

Upgrade again:

```bash
helm upgrade web nginx-basic
```

Check release history:

```bash
helm history web
```

---

# 🟦 Step 7 — Clean up

```bash
helm uninstall web
```

---

# ⭐ Lesson 1 Summary (What you just learned)

- Creating charts  
- Rendering templates  
- Installing releases  
- Upgrading releases  
- Adding custom templates  
- Using values  
- Versioning charts  

This is the exact foundation SC104 expects.

---

# ⭐ Next lessons (choose your path)

- Templating Mastery — loops, conditionals, pipelines  
- Chart Dependencies — `requirements.yaml`  
- Helm Hooks — pre/post install  
- Testing Charts — `helm test`  
- Publishing Charts — OCI registry  
