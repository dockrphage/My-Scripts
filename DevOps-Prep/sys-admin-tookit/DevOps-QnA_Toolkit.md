## **📌 Q&A Index**
A growing collection of concise, FAQs and Script snippets.
Click any question below to jump to its answer.

- **[Q1. Does `cat ~/.kube/config | base64` work for extracting a base64 kubeconfig, or do newline characters cause problems?](#q1-base64-kubeconfig-newline-issues)**  
- **[Q2. How do you enable passwordless SSH login for Ansible across multiple Linux nodes?](#q2-passwordless-ssh-for-ansible)**  
- **[Q3. How do you enable ssh login for (multiple)vagrant ubuntu vms?](#q3-enable-ssh-login-for-vagrant-ubuntu)**
- **[Q4. Add a new SSH key to GitHub](#q4-add-new-ssh-key-to-github)**
- **[Q5. How do I backup my Kubernetes cluster and restore it to the original state after finishing a lab?](#q5-velero-minio-configure-backup-restore)**
- **[Q6. Explain kubernetes CRD like you explain to a child](#q6-explain-k8s-crd-to-a-child)**



---

---

## **Q1: Base64 kubeconfig — newline issues**  
### <a name="q1-base64-kubeconfig-newline-issues"></a>  
**Q. For extracting a base64‑encoded kubeconfig, does `cat ~/.kube/config | base64` work, or will newline characters cause a problem?**

### ⚠️ Why standard `cat ... | base64` breaks

- **Line wrapping:**  
  The default Linux `base64` encoder inserts a newline every 76 characters. Kubernetes secrets require **one continuous base64 string**.

- **Trailing newline:**  
  Most files end with an invisible `\n`.  
  Standard `base64` includes this newline, altering the final encoded output.

### 🛠 Correct commands (Linux)

Lossless, safe, no wrapping:

```bash
printf "%s" "$(cat ~/.kube/config)" | base64 -w 0
```

Or using modern flags:

```bash
base64 -w 0 ~/.kube/config
```

This produces a **single uninterrupted base64 string** suitable for Kubernetes Secrets, CI pipelines, and automation.

---

---

## **Q2: Passwordless SSH for Ansible**  
### <a name="q2-passwordless-ssh-for-ansible"></a>  
**Q. How do you enable passwordless SSH login for Ansible across multiple Linux nodes?**

**A:**  
You generate an SSH key pair on the Ansible controller and distribute the public key to all managed nodes. This enables secure, non‑interactive authentication—critical for automation.

---

### 🧩 Step 1 — Generate an SSH key pair

```bash
ssh-keygen -t rsa -b 4096 -f ~/.ssh/ansible -N ""
```

This creates:

- `~/.ssh/ansible` — private key  
- `~/.ssh/ansible.pub` — public key  

---

### 🧩 Step 2 — Copy the public key to all nodes

```bash
for ip in {50..54}; do
    echo ">>> Copying key to 192.168.1.$ip"
    ssh-copy-id -i ~/.ssh/ansible.pub ansible@192.168.1.$ip
done
```

This installs your key into:

```
/home/ansible/.ssh/authorized_keys
```

---

### 🧩 Step 3 — Test passwordless login

```bash
ssh ansible@192.168.1.50
```

If no password prompt appears, passwordless SSH is correctly configured.

---

### 🧩 Why this matters for Ansible

- Fully automated playbook execution  
- No password prompts  
- Secure authentication  
- Faster connections  

---

#Q3.  **Enable SSH Password Login on Vagrant Ubuntu VMs (Quick Note)**
### <a name="q3-enable-ssh-login-for-vagrant-ubuntu"></a>  

Vagrant Ubuntu boxes normally authenticate using the **insecure default SSH key** that ships with Vagrant. Sometimes you need **password‑based SSH login**—for example, when testing Ansible inventory, SSH automation, or simulating real‑world server access.

This note shows how to quickly enable password login across multiple Vagrant VMs using a simple shell loop.

---


To enable password login, you must:

1. Modify the SSH config  
2. Set a password  
3. Restart the SSH daemon  

---

## **Quick method: Patch all VMs using a loop**

```bash
for i in {1..5}; do
    vagrant ssh node$i -c "
        sudo sed -i 's/^PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config &&
        echo 'vagrant:ss' | sudo chpasswd &&
        sudo systemctl restart sshd
    "
done
```

### What this does
- **Enables password authentication** in `/etc/ssh/sshd_config`
- **Sets the vagrant user password** to `ss`
- **Restarts the correct SSH service** (`sshd` on Vagrant boxes)

After this, you can log in normally:
---

#Q4.  **Enable SSH Password Login on Vagrant Ubuntu VMs (Quick Note)**
### <a name="q4-add-new-ssh-key-to-github"></a>  

Below is a **clean, reusable quick‑reference note** for **adding a new SSH key to GitHub**, based entirely on the commands you used.  
It’s formatted so you can paste it into any repo’s `/docs/` folder or keep it as a personal cheat‑sheet.

---

# **🔐 Quick Reference — Add a New SSH Key to GitHub**

## **1. Generate a new SSH key**
Use **ed25519** (modern, secure, fast):

```bash
ssh-keygen -t ed25519 -C "dockrphage" -f ~/.ssh/gha-practice-ed25519
```

- `-C` → label/comment  
- `-f` → output file path  
- Creates:
  - `~/.ssh/gha-practice-ed25519` (private key)
  - `~/.ssh/gha-practice-ed25519.pub` (public key)

---

## **2. Verify the key files**
```bash
ls -altr ~/.ssh
```

---

## **3. Start the SSH agent**
```bash
eval "$(ssh-agent -s)"
```

---

## **4. Add the private key to the agent**
```bash
ssh-add ~/.ssh/gha-practice-ed25519
```

Check loaded keys:

```bash
ssh-add -l
```

---

## **5. View your public key**
Either command works:

```bash
cat ~/.ssh/gha-practice-ed25519.pub
```

or

```bash
cat gha-practice-ed25519.pub
```

Copy the entire output (single line starting with `ssh-ed25519`).

---

## **6. Add the key to GitHub**
Navigate:

**GitHub → Settings → SSH and GPG keys → New SSH key**

Paste the public key → give it a name (e.g., `gha-practice`) → Save.

GitHub will confirm:

> *You have successfully added the key 'gha-practice'.*

---

## **7. Test GitHub SSH connectivity**
```bash
ssh -T git@github.com
```

Expected output:

> *Hi dockrphage! You've successfully authenticated…*

---

## **8. Reuse this pattern for any future key**
Just change:
- Key label (`-C`)
- Output filename (`-f`)
- GitHub key name

---



#Q5.  **How do I backup my Kubernetes cluster and restore it to the original state after finishing a lab?**
### <a name="q5-velero-minio-configure-backup-restore"></a>  

Objective is to snapshot entire Kubernetes cluster before running a lab and restore it back to the exact original state afterward.  
It uses **Velero** + **MinIO**; miniIO is running on a dedicated VM (node2) over a **private network** (10.0.0.x); this extra network was needed because VirtualBox host‑only and bridged networks block MinIO traffic even after promiscuous mode is enabled.  

```ruby
nodes = {
  "cp1"   => { ip: "192.168.56.10", bridged_ip: "192.168.1.50", pvt_ip: "10.10.10.10", cpu: 2, mem: 2048 },
  "node1" => { ip: "192.168.56.11", bridged_ip: "192.168.1.51", pvt_ip: "10.10.10.11", cpu: 2, mem: 6144 },
  "node2" => { ip: "192.168.56.12", bridged_ip: "192.168.1.52", pvt_ip: "10.10.10.12", cpu: 2, mem: 6144 }
}
```

The **private network (10.10.10.x)** is what allows Velero (inside Kubernetes) to reach MinIO (running in Docker on node2).

---

# **A. MinIO Setup (node2 VM)**

Run MinIO on node2 using the private IP:

```bash
docker run -d \
  --name minio-server \
  --restart unless-stopped \
  -p 10.10.10.12:9000:9000 \
  -p 10.10.10.12:9001:9001 \
  -v /data/minio:/data \
  -e "MINIO_ROOT_USER=minioadmin" \
  -e "MINIO_ROOT_PASSWORD=minioadmin123" \
  minio/minio server /data --console-address ":9001"
```

Verify MinIO:

```bash
docker ps
curl http://10.10.10.12:9000/minio/health/ready
```

Create the Velero bucket:

```bash
docker exec minio-server mc alias set local http://10.10.10.12:9000 minioadmin minioadmin123
docker exec minio-server mc mb local/velero-bucket
```

Create MinIO credentials file:

```bash
cat > /home/vagrant/minio-credentials <<EOF
[default]
aws_access_key_id = minioadmin
aws_secret_access_key = minioadmin123
EOF

chmod 600 /home/vagrant/minio-credentials
```

---

# **B. Velero Setup (inside Kubernetes cluster)**

Create Velero namespace:

```bash
kubectl create namespace velero
```

Create cloud credentials secret:

```bash
cat > credentials-velero <<EOF
[default]
aws_access_key_id = minioadmin
aws_secret_access_key = minioadmin123
EOF

kubectl create secret generic cloud-credentials \
  --namespace velero \
  --from-file=cloud=credentials-velero
```

Install Velero CLI inside cp1:

```bash
wget https://github.com/vmware-tanzu/velero/releases/download/v1.12.0/velero-v1.12.0-linux-amd64.tar.gz
tar -xvf velero-v1.12.0-linux-amd64.tar.gz
sudo mv velero-v1.12.0-linux-amd64/velero /usr/local/bin/
```

Install Velero server into the cluster:

```bash
velero install \
  --provider aws \
  --plugins velero/velero-plugin-for-aws:v1.8.0 \
  --bucket velero-bucket \
  --secret-file ./credentials-velero \
  --backup-location-config region=minio,s3ForcePathStyle="true",s3Url=http://10.10.10.12:9000 \
  --use-volume-snapshots=false \
  --wait
```

Verify:

```bash
kubectl get pods -n velero
velero backup-location get
```

---

# **C. Take a Pre‑Lab Snapshot (Backup)**

Before starting any lab:

```bash
velero backup create prelab-$(date +%F-%H%M) \
  --include-cluster-resources=true \
  --wait
```

Check backup:

```bash
velero backup get
velero backup describe <backup-name>
velero backup logs <backup-name>
```

---

# **D. Restore Cluster After Lab**

After finishing lab/ experiment:

```bash
velero restore create --from-backup <backup-name> --wait
```

Validate:

```bash
kubectl get all -A
kubectl get crd
kubectl get ns
```

Cluster is now **exactly** back to the pre‑lab state.

---

# **E. Using Velero from the Host Laptop**

Install Velero CLI on host laptop:

```bash
VELERO_VERSION=v1.15.2
wget https://github.com/vmware-tanzu/velero/releases/download/${VELERO_VERSION}/velero-${VELERO_VERSION}-linux-amd64.tar.gz
tar -xvf velero-${VELERO_VERSION}-linux-amd64.tar.gz
sudo mv velero-${VELERO_VERSION}-linux-amd64/velero /usr/local/bin/
velero version --client-only
```

Enable autocompletion:

```bash
source <(velero completion bash)
```

Run restore from host:

```bash
velero backup get
velero restore create --from-backup <backup-name> --wait
```

This works because host can reach the control plane at:

```
https://192.168.56.10:6443
```

and uses the same kubeconfig as the cp1 VM.

---

# **F. Summary**

- MinIO runs on **node2** using the **private network (10.10.10.x)**  
- Velero runs inside Kubernetes and backs up to MinIO  
- Take a **pre‑lab snapshot**  
- After finishing the lab, **restore**  
- Velero commands from **cp1** or **from host laptop**  
- No cleanup scripts needed — backup/restore is deterministic and safe  

---

#Q6.  **Q6. Explain kubernetes CRD like you explain to a child?**
### <a name="q6-explain-k8s-crd-to-a-child"></a>  
Imagine Kubernetes is a **super-busy restaurant** run by a very strict but helpful **Head Chef** (the Kubernetes API).

Here is how everything fits together:

### 1. The Kubernetes API (The Head Chef)
The Head Chef stands at the front of the kitchen. You don't talk to the cooks, the waiters, or the dishes. **You only talk to the Head Chef.**
*   If you want a pizza, you tell the Chef.
*   If you want to change the menu, you tell the Chef.
*   The Chef writes every order down on a giant chalkboard (this is called `etcd`, the memory).
*   **Rule:** The Chef never cooks. The Chef just takes orders and makes sure the kitchen follows them.

### 2. A "Resource" (The Menu Item)
In a normal restaurant, the menu only has **Pizza**, **Salad**, and **Soup**. These are standard things everyone knows.
*   In Kubernetes, **Pods**, **Services**, and **Deployments** are like Pizza and Salad. They are built-in menu items.
*   But what if you want to serve **"Dragon Burger"**? It’s not on the standard menu yet!
*   A **Resource** is just **an item on the menu**. It could be a standard item (Pizza) or a special item (Dragon Burger).

### 3. A "CRD" (The Custom Recipe Book)
This is the magic part.
*   The Head Chef says: *"I don't know what a Dragon Burger is. I can't cook it, and I don't know how to write it on the chalkboard."*
*   So, you give the Chef a **Custom Recipe Book** (the **CRD**).
*   You open the book to a page that says:
    > **"Dragon Burger"**
    > - Must have 2 buns.
    > - Must have spicy sauce.
    > - Must be served on a red plate.
*   Now, the Chef **knows** what a Dragon Burger is! He can write it on the blackboard. He can even check if your order is wrong (e.g., if you ask for a burger with 0 buns).
*   **CRD = The definition of a new type of thing the kitchen can understand.**

### 4. A "Custom Resource" (The Actual Order)
Now that the Chef has the Recipe Book, you can place an order!
*   You slide a note to the Chef: *"One Dragon Burger, 2 buns, spicy sauce."*
*   That note is a **Custom Resource**.
*   The Chef writes it on the chalkboard.
*   **Resource = The actual thing you asked for (the order).**

### 5. The "Controller" (The Robot Cook)
Here is the problem: The Chef writes the order on the board, but **nobody has cooked the burger yet!** The Chef doesn't know how to cook it because it's a new recipe.
*   You need a **Robot Cook** (the **Controller**).
*   The Robot Cook stands there constantly looking at the chalkboard.
*   Every 5 seconds, the Robot checks: *"Hey! Is there a Dragon Burger on the list that isn't cooked yet?"*
*   **If yes:** The Robot cooks the burger (starts a Pod).
*   **If the burger burns:** The Robot sees it's broken and makes a new one.
*   **If you change the order:** The Robot sees the new order and fixes the burger.
*   **Controller = The worker that watches the board and makes sure the actual food matches the order.**

### 6. The "Endpoint" (The Waiter's Route)
Once the Robot Cook makes the Dragon Burger, it sits on a table.
*   But how do you know **where** the burger is? Is it on Table 1? Table 5?
*   The **Endpoint** is like a small sign the Robot puts on the table: *"Dragon Burger is here!"*
*   When you (or another part of the restaurant) want to eat the burger, you ask the Chef: *"Where is the Dragon Burger?"*
*   The Chef looks at the sign (the Endpoint) and says: *"Go to Table 3."*
*   **Endpoint = The list of places where your "food" (service) is actually running.**

---

### 🍽️ Putting it all together (The Story)

1.  **You** want a **Dragon Burger**.
2.  You give the **Head Chef (API)** a **Custom Recipe Book (CRD)** so he knows what it is.
3.  The Chef puts a note on the chalkboard: **"Order: 1 Dragon Burger"**. This note is the **Custom Resource**.
4.  The **Robot Cook (Controller)** sees the note. He doesn't know how to cook it yet, so he starts working. He builds a little kitchen station.
5.  The Robot finishes the burger and puts a sign on the table: **"Burger Ready -> Table 3"**. This is the **Endpoint**.
6.  You ask the Chef, "Where is my burger?" The Chef points to the sign. You go to Table 3 and eat!

**If the Robot breaks:** The Chef still sees the order on the board, but no burger appears. The Robot (if it crashes) stops working, and the order stays "pending" until a new Robot starts.

**Why is this cool?**
Because now, instead of just making Pizza (standard resources), you can teach the restaurant to make **anything** you want: a "Database Burger," a "Secret Sauce," or a "Network Tunnel," as long as you write the Recipe Book (CRD) and hire a Robot to cook it (Controller)!