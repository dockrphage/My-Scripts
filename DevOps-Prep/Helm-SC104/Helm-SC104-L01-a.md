

Welcome to **Lesson 1: Your First Chart – The "Mario" Test**.

By the end of this 15-minute lesson, you will have created a working Helm chart, installed it, and understood the absolute minimum moving parts.

(AI Generated)

### The Goal
To package a simple Nginx web server into a Helm chart and understand the **3 Core Files** that make a chart work.

---

### Prerequisites
- Kubernetes cluster running (Minikube, Docker Desktop, or Kind).
- `helm` CLI installed (v3+).

---

### Step 1: The "Scaffold" (Don't overthink it)
Helm has a generator command. Let's create a chart named `my-first-chart`.

```bash
helm create my-first-chart
```

**Now, DELETE almost everything.** Helm's default scaffold is great for production, but terrible for learning. It has too many files.

Navigate into the folder and delete the `templates` folder entirely.

```bash
cd my-first-chart
rm -rf templates/*
```

---

### Step 2: The 3 Sacred Files
A minimalist Helm chart requires exactly 3 files. Let's build them.

#### 1. `Chart.yaml` (The ID Card)
This tells Helm what this package is called and what version it is.
Create this file in the root of `my-first-chart`:

```yaml
# Chart.yaml
apiVersion: v2
name: my-first-chart
description: My very first implementation chart
type: application
version: 0.1.0
appVersion: "1.16.0"
```

#### 2. `values.yaml` (The Settings)
This is where we put configuration that the user can change.
Create this file:

```yaml
# values.yaml
image:
  repository: nginx
  tag: alpine
  pullPolicy: IfNotPresent

replicaCount: 1
```

#### 3. `templates/deployment.yaml` (The Blueprint)
Create the `templates` folder again, and inside it, create `deployment.yaml`. This is where the magic happens.

```yaml
# templates/deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-first-app
spec:
  replicas: {{ .Values.replicaCount }}
  selector:
    matchLabels:
      app: my-first-app
  template:
    metadata:
      labels:
        app: my-first-app
    spec:
      containers:
        - name: nginx
          image: "{{ .Values.image.repository }}:{{ .Values.image.tag }}"
          imagePullPolicy: {{ .Values.image.pullPolicy }}
          ports:
            - containerPort: 80
```

---

### Step 3: The "Mario" Test (Linting)
Before we install, Helm can check if our syntax is valid. This is called "linting".

Run this from the parent directory (outside the chart folder):
```bash
helm lint my-first-chart
```

**Expected Output:** `1 chart(s) linted, 0 chart(s) failed`

---

### Step 4: The "Dry-Run" (Look, don't touch)
This is the most important learning tool. It renders the YAML and shows you what Kubernetes will receive, *without* actually installing it.

```bash
helm install my-first-release ./my-first-chart --dry-run --debug
```

**Look at the output.** Notice how the `{{ .Values.replicaCount }}` has been replaced with the number `1` from your `values.yaml`. This proves Helm is just a template engine.

---

### Step 5: Install It (The Implementation)
Now, let's actually deploy it to your cluster.

```bash
helm install my-first-release ./my-first-chart
```

Check if it worked:
```bash
kubectl get pods
```

You should see a pod named `my-first-app-xxxxx` running.

---

### Step 6: Override Values (The "Learn" part)
Your chart currently runs 1 replica. What if you want 3?

You don't edit `values.yaml` for this (that would ruin the chart for everyone else). Instead, you pass the override during install or upgrade.

Upgrade your release to 3 replicas:
```bash
helm upgrade my-first-release ./my-first-chart --set replicaCount=3
```

Check again:
```bash
kubectl get pods
```
You should now see 3 pods.

---

### The "Why" Behind the Lesson
1.  **`Chart.yaml`** is mandatory for Helm to recognize the folder as a chart.
2.  **`values.yaml`** provides the default configuration.
3.  **Templates** are standard Kubernetes YAML with **Go-template syntax** (`{{ .Values... }}`).
4.  **`helm install --dry-run`** is your best friend for debugging.

---

### Your Homework (Implementation Practice)
Do **not** move to Lesson 2 until you do this:

1.  Change the `image.tag` in `values.yaml` from `alpine` to `latest`.
2.  Run `helm upgrade my-first-release ./my-first-chart` to apply the change.
3.  Run `kubectl describe pod <pod-name>` and look at the "Image" line to confirm it changed to `nginx:latest`.

---
