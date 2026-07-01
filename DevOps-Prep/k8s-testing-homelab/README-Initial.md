Below is a **full implementation‑based learning series** you can run **directly in our homelab**, built from the Medium article *“Kubernetes Testing in Practice: Chaos Engineering, Load Testing, Security Auditing, and Resource Optimization”*   [Medium](https://medium.com/@levin_52368/kubernetes-testing-in-practice-chaos-engineering-load-testing-security-auditing-and-resource-145ed285722f).

Our homelab already has:
- Multi‑node Kubernetes (Vagrant/VMs)
- MetalLB + ingress‑nginx
- GitOps repo (`gitops-lab`)
- Argo CD

So designing this series to be **hands‑on**, **tool‑driven**, and **cluster‑realistic**, using the same tools from the article:

- Chaos Mesh (resilience)   [oneuptime.com](https://oneuptime.com/blog/post/2026-02-09-chaos-mesh-pod-failure-network/view)  
- k6 (load testing)   [Medium](https://medium.com/@levin_52368/kubernetes-testing-in-practice-chaos-engineering-load-testing-security-auditing-and-resource-145ed285722f)  
- Trivy (image scanning)   [Medium](https://medium.com/@levin_52368/kubernetes-testing-in-practice-chaos-engineering-load-testing-security-auditing-and-resource-145ed285722f)  
- kube‑bench (CIS benchmark)   [Medium](https://medium.com/@levin_52368/kubernetes-testing-in-practice-chaos-engineering-load-testing-security-auditing-and-resource-145ed285722f)  
- Goldilocks (resource efficiency)   [Medium](https://medium.com/@levin_52368/kubernetes-testing-in-practice-chaos-engineering-load-testing-security-auditing-and-resource-145ed285722f)  

---

# 🎯 End‑to‑End Implementation Learning Series  
## Kubernetes Testing in Homelab (Chaos • Load • Security • Resource)

This series is structured as **phases** (like a real SRE training program) and each phase contains **weekly micro‑labs** we can run on our cluster.

To make this visually structured, here is your **multi‑week programme**:





Sources:   [Medium](https://medium.com/@levin_52368/kubernetes-testing-in-practice-chaos-engineering-load-testing-security-auditing-and-resource-145ed285722f)  [oneuptime.com](https://oneuptime.com/blog/post/2026-02-09-chaos-mesh-pod-failure-network/view)

---

# 🔥 Phase 1 — Chaos Engineering (Weeks 1–2)

Chaos Mesh is the recommended tool for Kubernetes-native chaos experiments. It supports PodChaos, NetworkChaos, StressChaos, IOChaos, etc.   [oneuptime.com](https://oneuptime.com/blog/post/2026-02-09-chaos-mesh-pod-failure-network/view)

### **Install Chaos Mesh**
```bash
helm repo add chaos-mesh https://charts.chaos-mesh.org
helm repo update
kubectl create namespace chaos-mesh

helm install chaos-mesh chaos-mesh/chaos-mesh \
  --namespace chaos-mesh \
  --set dashboard.create=true \
  --set dashboard.securityMode=false
```

### **Access dashboard**
```bash
kubectl port-forward -n chaos-mesh svc/chaos-dashboard 2333:2333
```
Open: **http://localhost:2333**

---

## Week 1 — Pod & Network Chaos

### **PodChaos (kill backend pods)**
```yaml
apiVersion: chaos-mesh.org/v1alpha1
kind: PodChaos
metadata:
  name: kill-backend
  namespace: default
spec:
  action: pod-kill
  mode: all
  selector:
    labelSelectors:
      app: backend
  duration: "30s"
```

### **NetworkChaos (inject latency)**
```yaml
apiVersion: chaos-mesh.org/v1alpha1
kind: NetworkChaos
metadata:
  name: backend-latency
  namespace: default
spec:
  selector:
    labelSelectors:
      app: backend
  delay:
    latency: "200ms"
  duration: "60s"
```

---

## Week 2 — StressChaos + GitOps Integration

### **StressChaos (CPU/memory pressure)**
```yaml
apiVersion: chaos-mesh.org/v1alpha1
kind: StressChaos
metadata:
  name: cpu-stress
  namespace: default
spec:
  mode: all
  selector:
    labelSelectors:
      app: backend
  stressors:
    cpu:
      workers: 2
      load: 80
  duration: "45s"
```

### Add chaos experiments to GitOps repo
Place them under:
```
infra/chaos/
```
Then create an Argo CD Application pointing to that folder.

---

# ⚡ Phase 2 — Load Testing (Weeks 3–4)

The Medium article uses **k6** for load testing.   [Medium](https://medium.com/@levin_52368/kubernetes-testing-in-practice-chaos-engineering-load-testing-security-auditing-and-resource-145ed285722f)

## Week 3 — Basic Load Test

### Install k6 runner (Kubernetes job)
```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: k6-loadtest
spec:
  template:
    spec:
      containers:
      - name: k6
        image: grafana/k6
        command: ["k6", "run", "/scripts/test.js"]
        volumeMounts:
        - name: scripts
          mountPath: /scripts
      volumes:
      - name: scripts
        configMap:
          name: k6-scripts
      restartPolicy: Never
```

### Example k6 script
```javascript
import http from 'k6/http';
import { sleep } from 'k6';

export default function () {
  http.get('http://frontend.default.svc.cluster.local');
  sleep(1);
}
```

---

## Week 4 — Soak Tests + CI Integration

Run long-duration tests:
```bash
k6 run --duration 30m soak.js
```

Add k6 tests to CI (GitHub Actions):
```yaml
- name: Run k6 tests
  run: k6 run test.js
```

---

# 🔐 Phase 3 — Security Auditing (Weeks 5–6)

The article uses **Trivy** and **kube-bench**.   [Medium](https://medium.com/@levin_52368/kubernetes-testing-in-practice-chaos-engineering-load-testing-security-auditing-and-resource-145ed285722f)

## Week 5 — Image Scanning with Trivy

### Install Trivy
```bash
sudo apt install trivy
```

### Scan your images
```bash
trivy image dockrphage/gitops-lab-backend:latest
```

Fix CVEs in:
- base images
- dependencies
- container user permissions

---

## Week 6 — CIS Benchmark with kube-bench

### Run kube-bench
```bash
kubectl apply -f https://raw.githubusercontent.com/aquasecurity/kube-bench/main/job.yaml
kubectl logs job/kube-bench -n kube-bench
```

Fix:
- API server flags
- etcd encryption
- RBAC misconfigurations
- PodSecurity admission

---

# 📊 Phase 4 — Resource Optimization (Weeks 7–8)

Goldilocks uses VPA to recommend CPU/memory requests/limits.   [Medium](https://medium.com/@levin_52368/kubernetes-testing-in-practice-chaos-engineering-load-testing-security-auditing-and-resource-145ed285722f)

## Week 7 — Install Goldilocks

```bash
kubectl create namespace goldilocks
helm repo add fairwinds-stable https://charts.fairwinds.com/stable
helm install goldilocks fairwinds-stable/goldilocks -n goldilocks
```

Access dashboard:
```bash
kubectl port-forward svc/goldilocks-dashboard -n goldilocks 8080:80
```

---

## Week 8 — Apply Optimized Requests/Limits

Goldilocks will show:
- recommended CPU request
- recommended memory request
- recommended limits

Apply them to deployments and re-run:
- k6 load tests
- Chaos Mesh stress tests

Validate:
- no OOMKills
- no throttling
- stable p95/p99 latency

---

