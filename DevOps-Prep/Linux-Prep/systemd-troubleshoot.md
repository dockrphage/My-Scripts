**a full hands‑on, learn‑by‑doing SYSTEMD TROUBLESHOOTING LAB**

This is not theory.  
This is **real break–fix engineering**, exactly what Linux Engineer interviews expect.

You’ll intentionally break services, debug them, fix them, and document the RCA.

This lab gives you:

- realistic failure scenarios  
- commands to run  
- what output you should expect  
- how to diagnose  
- how to fix  
- how to automate checks  
- how to escalate to deeper Linux internals  

And every step includes **Guided Links** so you can jump deeper whenever you want.

---

# ⭐ SYSTEMD TROUBLESHOOTING LAB (Hands‑On)

Run these on **rocky1**, **ubuntu1**, and **debian1** — systemd behaves slightly differently across distros, so this is perfect practice.

---

# 🧩 **Lab 1 — Create a custom service and break it**

## Step 1: Create a simple service

```bash
sudo nano /etc/systemd/system/demo.service
```

Paste:

```
[Unit]
Description=Demo Service

[Service]
ExecStart=/usr/local/bin/demo.sh
Restart=always

[Install]
WantedBy=multi-user.target
```

Create the script:

```bash
echo -e '#!/bin/bash\necho "Demo running"\nsleep 5' | sudo tee /usr/local/bin/demo.sh
sudo chmod +x /usr/local/bin/demo.sh
```

Enable + start:

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now demo.service
```

Check status:

```bash
systemctl status demo.service
```

---

# 🧨 **Step 2: Break the service intentionally**

Delete the script:

```bash
sudo rm /usr/local/bin/demo.sh
sudo systemctl restart demo.service
```

Now check:

```bash
systemctl status demo.service
journalctl -u demo.service -n 20
```

You should see:

- `ExecStart=/usr/local/bin/demo.sh: No such file or directory`
- `Failed to start demo.service`

---

# 🔍 **Step 3: Diagnose like a Linux Engineer**

Use:

```bash
systemctl status demo.service
journalctl -xe
journalctl -u demo.service
systemctl cat demo.service
```

This is the core of **systemd troubleshooting**.

---

# 🛠️ **Step 4: Fix it**

Restore the script:

```bash
echo -e '#!/bin/bash\necho "Demo running"\nsleep 5' | sudo tee /usr/local/bin/demo.sh
sudo chmod +x /usr/local/bin/demo.sh
sudo systemctl restart demo.service
```

Check:

```bash
systemctl status demo.service
```

---

# 🧩 **Lab 2 — Simulate a crash loop**

Modify the script to exit with failure:

```bash
echo -e '#!/bin/bash\nexit 1' | sudo tee /usr/local/bin/demo.sh
sudo chmod +x /usr/local/bin/demo.sh
sudo systemctl restart demo.service
```

Check status:

```bash
systemctl status demo.service
```

Expected:

- `demo.service: Failed with result 'exit-code'`
- `Restarting in X seconds`

Now check logs:

```bash
journalctl -u demo.service -n 20
```

---

# 🧠 **Diagnose deeper**

Use:

```bash
systemctl show demo.service | grep -i restart
systemctl show demo.service | grep -i result
```

This teaches you how systemd tracks failures.

---

# 🛠️ **Fix**

Change the script:

```bash
echo -e '#!/bin/bash\necho "Recovered"\nsleep 5' | sudo tee /usr/local/bin/demo.sh
sudo chmod +x /usr/local/bin/demo.sh
sudo systemctl restart demo.service
```

---

# 🧩 **Lab 3 — Permission failure**

Break permissions:

```bash
sudo chmod -x /usr/local/bin/demo.sh
sudo systemctl restart demo.service
```

Expected:

- `Permission denied`
- `Failed to start demo.service`

Diagnose:

```bash
journalctl -u demo.service | tail
```

Fix:

```bash
sudo chmod +x /usr/local/bin/demo.sh
sudo systemctl restart demo.service
```

---

# 🧩 **Lab 4 — Dependency failure**

Create a fake dependency:

```bash
sudo nano /etc/systemd/system/demo.service
```

Add:

```
Requires=network-online.target
After=network-online.target
```

Now break networking:

```bash
sudo systemctl stop NetworkManager
sudo systemctl restart demo.service
```

Expected:

- `Dependency failed`
- `network-online.target not active`

Diagnose:

```bash
systemctl status network-online.target
journalctl -u demo.service
```

Fix:

```bash
sudo systemctl start NetworkManager
sudo systemctl restart demo.service
```

---

# 🧩 **Lab 5 — systemd unit syntax errors**

Break the unit file:

```bash
sudo nano /etc/systemd/system/demo.service
```

Add a typo:

```
ExecStartt=/usr/local/bin/demo.sh
```

Reload:

```bash
sudo systemctl daemon-reload
sudo systemctl restart demo.service
```

Expected:

- `Unknown lvalue 'ExecStartt'`
- `Failed to load unit`

Diagnose:

```bash
systemctl status demo.service
journalctl -xe
```

Fix the typo.

---

# 🧩 **Lab 6 — systemd masking/unmasking**

Mask the service:

```bash
sudo systemctl mask demo.service
sudo systemctl start demo.service
```

Expected:

- `Unit demo.service is masked`

Unmask:

```bash
sudo systemctl unmask demo.service
sudo systemctl start demo.service
```

---

# 🧩 **Lab 7 — systemd + SELinux (Rocky only)**

Check SELinux:

```bash
getenforce
```

Break SELinux:

```bash
sudo restorecon -Rv /usr/local/bin
sudo semanage fcontext -a -t bin_t "/usr/local/bin/demo.sh"
sudo restorecon -v /usr/local/bin/demo.sh
```

If SELinux blocks execution:

```bash
sudo ausearch -m avc
```

Fix:

```bash
sudo setenforce 0
```

Or correct context.

---

# 🧩 **Lab 8 — Write an RCA (Linux Engineer requirement)**

Document:

- What broke  
- Why it broke  
- How you diagnosed  
- How you fixed  
- How to prevent recurrence  

This is essential for **incident response** and **RCA writing**.

---

# ⭐ You now have a complete SYSTEMD TROUBLESHOOTING LAB

This is exactly what Linux Engineer interviews test:

- break–fix  
- journalctl  
- dependency debugging  
- service lifecycle  
- restart logic  
- masking  
- SELinux  
- unit syntax  
- RCA writing  

---