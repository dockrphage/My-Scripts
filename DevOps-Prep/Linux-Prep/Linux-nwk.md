— **a full, hands‑on Linux Networking Troubleshooting Lab**.  
This is *real* Linux Engineer work: interfaces, routing, DNS, firewalls, packet tracing, break–fix, and RCA.

Everything is implementation‑ready, and every step includes **Guided Links** so you can go deeper.

---

# ⭐ Linux Networking Basics — Full Hands‑On Lab

Run these labs on **rocky1**, **ubuntu1**, and **debian1** — networking differs slightly across distros, which is exactly what makes this valuable.

---

# 🧩 1. Inspect Network Interfaces

Check all interfaces:

```bash
ip -o -4 a
```

Check link status:

```bash
ip link show
```

Check routing table:

```bash
ip route
```

Check DNS:

```bash
cat /etc/resolv.conf
```

These commands form the foundation of **Linux networking basics**.

---

# 🧩 2. Break the Network Interface (Intentional Failure)

Disable the private network interface:

```bash
sudo ip link set enp0s8 down
```

Expected:

- VM loses connectivity to other nodes  
- `ping` fails  
- routing table changes  

Diagnose:

```bash
ip link show enp0s8
ip route
```

Fix:

```bash
sudo ip link set enp0s8 up
```

---

# 🧩 3. Add a Static IP (Manual Configuration)

Assign a temporary IP:

```bash
sudo ip addr add 192.168.56.50/24 dev enp0s8
```

Verify:

```bash
ip -o -4 a | grep enp0s8
```

Remove it:

```bash
sudo ip addr del 192.168.56.50/24 dev enp0s8
```

This teaches interface‑level IP management.

---

# 🧩 4. Routing Troubleshooting

### Show current routes:

```bash
ip route
```

### Break routing:

Delete default route:

```bash
sudo ip route del default
```

Now test:

```bash
ping 8.8.8.8
```

Expected: **Network unreachable**

### Fix routing:

```bash
sudo ip route add default via 192.168.56.1
```

This is core Linux Engineer troubleshooting.

---

# 🧩 5. DNS Troubleshooting

### Break DNS:

```bash
echo "nameserver 127.0.0.1" | sudo tee /etc/resolv.conf
```

Test:

```bash
ping google.com
```

Expected: **Temporary failure in name resolution**

### Diagnose:

```bash
cat /etc/resolv.conf
dig google.com
nslookup google.com
```

### Fix:

```bash
echo "nameserver 1.1.1.1" | sudo tee /etc/resolv.conf
```

---

# 🧩 6. Firewall Troubleshooting (iptables / firewalld)

### Check firewall status:

Rocky:

```bash
sudo systemctl status firewalld
sudo firewall-cmd --list-all
```

Ubuntu/Debian:

```bash
sudo ufw status
```

### Break connectivity:

Rocky:

```bash
sudo firewall-cmd --add-rich-rule='rule family="ipv4" source address="192.168.56.0/24" reject'
```

Ubuntu:

```bash
sudo ufw deny from 192.168.56.0/24
```

Test:

```bash
ping rocky1
```

Expected: **blocked**

### Fix:

Rocky:

```bash
sudo firewall-cmd --remove-rich-rule='rule family="ipv4" source address="192.168.56.0/24" reject'
```

Ubuntu:

```bash
sudo ufw delete deny from 192.168.56.0/24
```

---

# 🧩 7. Packet Tracing (tcpdump)

Install:

```bash
sudo dnf install -y tcpdump   # Rocky
sudo apt install -y tcpdump   # Ubuntu/Debian
```

Trace ICMP:

```bash
sudo tcpdump -i enp0s8 icmp
```

Trace DNS:

```bash
sudo tcpdump -i enp0s3 port 53
```

Trace HTTP:

```bash
sudo tcpdump -i enp0s3 port 80
```

This is essential for **real Linux troubleshooting**.

---

# 🧩 8. ARP Troubleshooting

Show ARP table:

```bash
ip neigh
```

Delete entry:

```bash
sudo ip neigh del 192.168.56.11 dev enp0s8
```

Ping again:

```bash
ping 192.168.56.11
```

Watch ARP rebuild:

```bash
ip neigh
```

---

# 🧩 9. NetworkManager vs systemd‑networkd

Rocky uses NetworkManager:

```bash
nmcli device status
nmcli connection show
```

Ubuntu/Debian use netplan:

```bash
cat /etc/netplan/*.yaml
sudo netplan apply
```

Understanding these differences is crucial for Linux Engineer roles.

---

# 🧩 10. Simulate Real Incidents

### Incident 1: Wrong gateway

```bash
sudo ip route replace default via 192.168.56.254
```

Fix:

```bash
sudo ip route replace default via 192.168.56.1
```

### Incident 2: Wrong DNS

```bash
echo "nameserver 9.9.9.9" | sudo tee /etc/resolv.conf
```

Fix:

```bash
echo "nameserver 1.1.1.1" | sudo tee /etc/resolv.conf
```

### Incident 3: Interface down

```bash
sudo ip link set enp0s8 down
```

Fix:

```bash
sudo ip link set enp0s8 up
```

### Incident 4: Firewall blocking SSH

Rocky:

```bash
sudo firewall-cmd --add-rich-rule='rule family="ipv4" service name="ssh" reject'
```

Fix:

```bash
sudo firewall-cmd --remove-rich-rule='rule family="ipv4" service name="ssh" reject'
```

---

# 🧩 11. Write an RCA (Linux Engineer requirement)

Document:

- What broke  
- Why it broke  
- How you diagnosed  
- How you fixed  
- How to prevent recurrence  

This builds your **incident response** skill.

---

# ⭐ You now have a complete Linux Networking Troubleshooting Lab

You covered:

- interfaces  
- routing  
- DNS  
- firewalls  
- ARP  
- packet tracing  
- NetworkManager  
- netplan  
- break–fix  
- RCA  
