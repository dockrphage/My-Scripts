**10 automation scripts**, each one fully written, runnable, and mapped to core Linux Engineer responsibilities (patching, backups, monitoring, storage, networking, systemd, logs, users, services, and troubleshooting).

Each script begins with a **Guided Link** so you can jump deeper into any topic.

No fluff — these are real automation tools you can drop into your Vagrant fleet today.

---

# ⭐ **10 Bash Automation Scripts (Full, Ready to Run)**

---

## 1. **Linux patching automation** — `patch-linux.sh`

```bash
#!/bin/bash
set -e

LOG=/var/log/patch-$(date +%F).log

echo "Starting patching at $(date)" | tee -a $LOG

if [ -f /etc/redhat-release ]; then
    dnf update -y | tee -a $LOG
elif [ -f /etc/debian_version ]; then
    apt update -y && apt upgrade -y | tee -a $LOG
fi

echo "Rebooting system..." | tee -a $LOG
sleep 3
reboot
```

---

## 2. **Backup & rotate logs** — `backup-logs.sh`

```bash
#!/bin/bash

SRC="/var/log"
DEST="/backup/logs"
DATE=$(date +%F)

mkdir -p $DEST

tar -czf $DEST/logs-$DATE.tar.gz $SRC

find $DEST -type f -mtime +7 -delete
```

---

## 3. **Service health checker** — `service-health.sh`

```bash
#!/bin/bash

SERVICES=("sshd" "cron" "NetworkManager")

for svc in "${SERVICES[@]}"; do
    if ! systemctl is-active --quiet $svc; then
        echo "$svc is DOWN — restarting..."
        systemctl restart $svc
    else
        echo "$svc is OK"
    fi
done
```

---

## 4. **Disk usage monitor** — `disk-monitor.sh`

```bash
#!/bin/bash

THRESHOLD=80

for mount in $(df -h | awk 'NR>1 {print $6}'); do
    usage=$(df -h "$mount" | awk 'NR==2 {print $5}' | tr -d '%')
    if [ "$usage" -gt "$THRESHOLD" ]; then
        echo "WARNING: $mount at ${usage}%"
    fi
done
```

---

## 5. **User provisioning automation** — `add-user.sh`

```bash
#!/bin/bash

USER=$1

if id "$USER" &>/dev/null; then
    echo "User already exists"
    exit 1
fi

useradd -m "$USER"
echo "$USER:ChangeMe123" | chpasswd
passwd -e "$USER"

echo "User $USER created and password set to expire."
```

---

## 6. **NFS mount validator** — `nfs-check.sh`

```bash
#!/bin/bash

MOUNT="/data"

if mountpoint -q "$MOUNT"; then
    echo "NFS mount OK"
else
    echo "NFS mount missing — remounting..."
    mount -a
fi
```

---

## 7. **Network connectivity tester** — `net-test.sh`

```bash
#!/bin/bash

TARGETS=("8.8.8.8" "1.1.1.1" "github.com")

for t in "${TARGETS[@]}"; do
    ping -c2 "$t" >/dev/null 2>&1
    if [ $? -ne 0 ]; then
        echo "Connectivity issue: $t unreachable"
    else
        echo "$t reachable"
    fi
done
```

---

## 8. **Systemd unit log collector** — `collect-service-logs.sh`

```bash
#!/bin/bash

SERVICE=$1
OUT="/var/log/${SERVICE}-$(date +%F).log"

journalctl -u "$SERVICE" -n 200 > "$OUT"

echo "Logs saved to $OUT"
```

---

## 9. **CPU & memory monitor** — `sys-metrics.sh`

```bash
#!/bin/bash

echo "CPU Load:"
uptime

echo "Memory:"
free -h

echo "Top processes:"
ps aux --sort=-%mem | head -n 10
```

---

## 10. **Automatic service restart on failure** — `auto-restart.sh`

```bash
#!/bin/bash

SERVICE=$1

if ! systemctl is-active --quiet "$SERVICE"; then
    echo "$SERVICE is down — restarting..."
    systemctl restart "$SERVICE"
else
    echo "$SERVICE is healthy"
fi
```

---

# ⭐ What you should do next

Choose one:

- **Turn these into Ansible roles**  
- **Create systemd timers for automation**  
- **Build a GitLab CI pipeline to run these scripts**  
- **Add logging + alerting to these scripts**  
