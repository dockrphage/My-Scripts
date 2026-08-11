

**Lesson 2: Exposing Your App & Powerful Template Functions**.

(AI Generated)
In Lesson 1, you had a Deployment, but your app is trapped inside the cluster. In this lesson, we are going to expose it to the outside world using a **Service**, and we will introduce **Helm Template Functions** to make your chart smarter (and more annoying to break).

---

### The Goal
1. Add a Kubernetes Service to your chart.
2. Use the `default` function to protect against missing values.
3. Use the `quote` function to handle data types properly.
4. Expose your Nginx app to your browser.

---

### Step 1: Adding the Service Template
In your `templates/` folder, create a new file called `service.yaml`.

```yaml
# templates/service.yaml
apiVersion: v1
kind: Service
metadata:
  name: my-first-app-svc
spec:
  selector:
    app: my-first-app  # This must match the labels in your Deployment!
  ports:
    - protocol: TCP
      port: {{ .Values.service.port }}
      targetPort: 80
  type: {{ .Values.service.type }}
```

---

### Step 2: Update `values.yaml` with Service Settings
Open your `values.yaml` and add the new `service` section at the bottom:

```yaml
# values.yaml
image:
  repository: nginx
  tag: alpine
  pullPolicy: IfNotPresent

replicaCount: 1

# NEW SERVICE SECTION
service:
  type: NodePort
  port: 80
```

---

### Step 3: The "Learn-by-Breaking" (Template Functions)
Now, let's introduce a bug. Delete the `service.type` line from your `values.yaml` so it looks like this:

```yaml
service:
  # type: NodePort  <-- COMMENTED OUT or DELETED
  port: 80
```

Now run a dry-run:
```bash
helm install my-first-release ./my-first-chart --dry-run
```

**Look at the `service.yaml` output.** You'll see:
```yaml
type: <no value>
```
This is bad! If you install this, Kubernetes will reject it because `type` is required.

**The Fix: The `default` Function**
We can tell Helm: *"If the user doesn't provide a `service.type`, default to `ClusterIP`."*

Update your `templates/service.yaml` to use the `default` function:

```yaml
# templates/service.yaml (UPDATED)
apiVersion: v1
kind: Service
metadata:
  name: my-first-app-svc
spec:
  selector:
    app: my-first-app
  ports:
    - protocol: TCP
      port: {{ .Values.service.port }}
      targetPort: 80
  type: {{ .Values.service.type | default "ClusterIP" }}
```

Now, run the dry-run again:
```bash
helm install my-first-release ./my-first-chart --dry-run
```
You'll see `type: ClusterIP`. The `default` function saved us!

---

### Step 4: The `quote` Function (Data Types Matter)
Helm templates are YAML, and YAML is picky about types. If your `port` was accidentally interpreted as a string instead of a number, it could fail.

Look at your `service.port: 80`. It's an integer (no quotes). That's correct for YAML. 

However, let's simulate a scenario where we *need* it as a string. Update your `values.yaml` to add a new field:

```yaml
# values.yaml (ADD this at the bottom)
environment: production
```

Now, update your `templates/deployment.yaml` to add an environment variable:

```yaml
# templates/deployment.yaml (ADD this under the containers: section)
        - name: nginx
          image: "{{ .Values.image.repository }}:{{ .Values.image.tag }}"
          imagePullPolicy: {{ .Values.image.pullPolicy }}
          ports:
            - containerPort: 80
          # NEW ENV SECTION
          env:
            - name: ENVIRONMENT
              value: {{ .Values.environment }}
```

Run a dry-run:
```bash
helm install my-first-release ./my-first-chart --dry-run
```

Look at the `env` section. It renders perfectly: `value: production`.

**But what if the value is a number?** 
Change `environment: production` to `environment: 123` in `values.yaml` and run the dry-run again.

Notice it renders as `value: 123` (without quotes). In Kubernetes, environment variables must be strings! If you apply this, it might fail or behave weirdly.

**The Fix: The `quote` Function**
Update your `deployment.yaml` to force it to be a string:

```yaml
          env:
            - name: ENVIRONMENT
              value: {{ .Values.environment | quote }}
```

Now run the dry-run again. You'll see `value: "123"`. Perfect!

---

### Step 5: Install and Expose Your App
Restore your `values.yaml` to its correct state (uncomment `type: NodePort`):

```yaml
service:
  type: NodePort
  port: 80
```

Now, upgrade your release with the new Service and the smart template functions:

```bash
helm upgrade my-first-release ./my-first-chart
```

Get the NodePort that Kubernetes assigned:
```bash
kubectl get svc my-first-app-svc
```

You'll see an output like:
```
NAME               TYPE       CLUSTER-IP     EXTERNAL-IP   PORT(S)        AGE
my-first-app-svc   NodePort   10.96.xxx.xx   <none>        80:3xxxx/TCP   5s
```

Look at the `PORT(S)` column. `80:3xxxx/TCP` means your app is available on port `3xxxx` of your node.

- If you're using **Minikube**: Run `minikube service my-first-app-svc` to auto-open it.
- If you're using **Docker Desktop/Kind**: Open `http://localhost:3xxxx` (replace with the actual port).

You should see the default Nginx welcome page!

---

### The "Why" Behind the Lesson
1.  **`default` function**: Always use this for optional values. It prevents Helm from rendering `<no value>` and breaking your cluster.
2.  **`quote` function**: Use this when you need a value to be a YAML string. 
3.  **Services**: Charts aren't just for Deployments; you can template *any* Kubernetes resource.
4.  **`helm upgrade`**: You can add entirely new Kubernetes objects (like a Service) to an existing release without deleting it.

---

### Your Homework (Implementation Practice)
Do **not** move to Lesson 3 until you do this:

1.  Change the `service.type` in `values.yaml` from `NodePort` to `LoadBalancer`.
2.  Run `helm upgrade my-first-release ./my-first-chart`.
3.  Run `kubectl get svc my-first-app-svc`. Notice the `EXTERNAL-IP` changes (if you're on a cloud provider) or stays `<pending>` (if you're local—this is expected!).
4.  **Hard Mode**: Add a new field to `values.yaml` called `containerPort: 8080`. In `deployment.yaml`, use the `default` function so that if the user *doesn't* provide it, it defaults to `80`. Update the `targetPort` in your `service.yaml` to use this new value. Dry-run it to ensure it works.

