Here's your **updated Vagrantfile** transformed into a complete **HAProxy + Nginx load balancer lab** for DevOps interview preparation. I've replaced the Kubernetes setup with a lightweight, interview-friendly load balancing architecture.

## 📁 Complete Project Structure

First, create this folder structure:
```
load-balancer-lab/
├── Vagrantfile
├── provisioning/
│   ├── haproxy.sh
│   └── webserver.sh
└── README.md (optional)
```

## 🚀 The Updated Vagrantfile

```ruby
Vagrant.configure("2") do |config|

  # ============================================================
  # LOAD BALANCER LAB CONFIGURATION
  # For DevOps Interview Preparation
  # ============================================================
  
  nodes = {
    "haproxy" => { ip: "192.168.56.10", cpu: 1, mem: 512, role: "lb" },
    "web1"    => { ip: "192.168.56.11", cpu: 1, mem: 512, role: "web" },
    "web2"    => { ip: "192.168.56.12", cpu: 1, mem: 512, role: "web" }
  }

  nodes.each do |name, cfg|
    config.vm.define name do |node|
      node.vm.box = "ubuntu/jammy64"
      node.vm.hostname = name

      # Private network for internal communication
      node.vm.network "private_network",
        ip: cfg[:ip],
        virtualbox__promiscuous_mode: "allow-all"

      # ============================================================
      # PROVISIONING SCRIPTS PER ROLE
      # ============================================================
      
      # Load Balancer Node (HAProxy)
      if cfg[:role] == "lb"
        node.vm.provision "shell",
          path: "provisioning/haproxy.sh",
          args: [nodes["web1"][:ip], nodes["web2"][:ip]],
          privileged: false
      end
      
      # Web Server Nodes (Nginx)
      if cfg[:role] == "web"
        node.vm.provision "shell",
          path: "provisioning/webserver.sh",
          args: [name],
          privileged: false
      end

      # ============================================================
      # COMMON PROVISIONING FOR ALL NODES
      # ============================================================
      node.vm.provision "shell", inline: <<-SHELL
        sudo apt-get update
        sudo apt-get install -y \
          apt-transport-https \
          ca-certificates \
          curl \
          wget \
          software-properties-common \
          net-tools \
          telnet \
          dnsutils \
          htop \
          vim \
          jq \
          tree \
          ncdu

        # Enable password auth for convenience
        sudo sed -i 's/PasswordAuthentication.*/PasswordAuthentication yes/' \
          /etc/ssh/sshd_config.d/60-cloudimg-settings.conf
        echo 'vagrant:vagrant' | sudo chpasswd
        sudo systemctl restart ssh

        # Install apache2-utils for load testing (ab command)
        sudo apt-get install -y apache2-utils
      SHELL

      # ============================================================
      # VIRTUALBOX PROVIDER SETTINGS
      # ============================================================
      node.vm.provider "virtualbox" do |vb|
        vb.memory = cfg[:mem]
        vb.cpus   = cfg[:cpu]
        vb.name   = "lb-lab-#{name}"
        
        # Optimize for laptop performance
        vb.customize ["modifyvm", :id, "--natdnshostresolver1", "on"]
        vb.customize ["modifyvm", :id, "--ioapic", "on"]
      end

      # Disable default synced folder for speed (optional)
      node.vm.synced_folder ".", "/vagrant", disabled: false
    end
  end

  # ============================================================
  # OPTIONAL: STATUS OUTPUT AFTER VAGRANT UP
  # ============================================================
  config.vm.provision "shell",
    inline: <<-SHELL,
    echo "=========================================="
    echo "LOAD BALANCER LAB IS READY!"
    echo "=========================================="
    echo "Access the load balancer at: http://192.168.56.10"
    echo "HAProxy stats page: http://192.168.56.10:8080/stats"
    echo ""
    echo "Run load test: ab -n 1000 -c 10 http://192.168.56.10/"
    echo ""
    echo "Check logs: ssh into haproxy and run: tail -f /var/log/haproxy.log"
    echo "=========================================="
    SHELL
    run: "always"
end
```

## 📜 Provisioning Scripts

### 1. `provisioning/haproxy.sh` (Load Balancer Setup)

Create this file at `provisioning/haproxy.sh`:

```bash
#!/bin/bash

# Variables
WEB1_IP=$1
WEB2_IP=$2

echo "=========================================="
echo "Setting up HAProxy Load Balancer"
echo "Backend Servers: $WEB1_IP, $WEB2_IP"
echo "=========================================="

# Install HAProxy
sudo apt-get update
sudo apt-get install -y haproxy

# Enable HAProxy to be started by systemd
sudo systemctl enable haproxy

# Create HAProxy configuration
sudo tee /etc/haproxy/haproxy.cfg > /dev/null <<EOF
global
    log /dev/log local0
    log /dev/log local1 notice
    chroot /var/lib/haproxy
    stats socket /run/haproxy/admin.sock mode 660 level admin expose-fd listeners
    stats timeout 30s
    user haproxy
    group haproxy
    daemon

    # Default SSL material locations
    ca-base /etc/ssl/certs
    crt-base /etc/ssl/private

    # Default ciphers to use on SSL-enabled listening sockets.
    ssl-default-bind-ciphers ECDH+AESGCM:DH+AESGCM:ECDH+AES256:DH+AES256:ECDH+AES128:DH+AES128:!aNULL:!MD5:!DSS
    ssl-default-bind-options no-sslv3

defaults
    log     global
    mode    http
    option  httplog
    option  dontlognull
    timeout connect 5000
    timeout client  50000
    timeout server  50000
    errorfile 400 /etc/haproxy/errors/400.http
    errorfile 403 /etc/haproxy/errors/403.http
    errorfile 408 /etc/haproxy/errors/408.http
    errorfile 500 /etc/haproxy/errors/500.http
    errorfile 502 /etc/haproxy/errors/502.http
    errorfile 503 /etc/haproxy/errors/503.http
    errorfile 504 /etc/haproxy/errors/504.http

# Frontend: HTTP listener
frontend http_front
    bind *:80
    stats uri /stats
    stats auth admin:admin
    stats refresh 5s
    default_backend http_back

# Backend: Web servers
backend http_back
    balance roundrobin
    option httpchk GET /
    server web1 $WEB1_IP:80 check inter 2s rise 2 fall 3
    server web2 $WEB2_IP:80 check inter 2s rise 2 fall 3

# Stats page (alternative on port 8080)
listen stats
    bind *:8080
    stats enable
    stats uri /stats
    stats auth admin:admin
    stats refresh 5s
    stats admin if TRUE
EOF

# Enable HAProxy logging
sudo sed -i 's/#$ModLoad imudp/$ModLoad imudp/' /etc/rsyslog.conf
sudo sed -i 's/#$UDPServerRun 514/$UDPServerRun 514/' /etc/rsyslog.conf
sudo systemctl restart rsyslog

# Configure HAProxy to log to separate file
sudo tee /etc/rsyslog.d/49-haproxy.conf > /dev/null <<EOF
local0.*    /var/log/haproxy.log
local1.*    /var/log/haproxy.log
&~
EOF

sudo systemctl restart rsyslog

# Start HAProxy
sudo systemctl restart haproxy

# Verify HAProxy is running
if sudo systemctl is-active --quiet haproxy; then
    echo "✅ HAProxy is running successfully!"
    echo "📊 Stats page: http://$(hostname -I | awk '{print $2}'):8080/stats"
    echo "   Username: admin, Password: admin"
else
    echo "❌ HAProxy failed to start. Check logs with: sudo journalctl -u haproxy"
    exit 1
fi

# Display configuration
echo ""
echo "=========================================="
echo "HAProxy Configuration Summary:"
echo "=========================================="
echo "Load Balancer IP: $(hostname -I | awk '{print $2}')"
echo "Backend Servers: $WEB1_IP, $WEB2_IP"
echo "Load Balancing Algorithm: roundrobin"
echo "Health Check Interval: 2 seconds"
echo "=========================================="
```

### 2. `provisioning/webserver.sh` (Web Server Setup)

Create this file at `provisioning/webserver.sh`:

```bash
#!/bin/bash

# Variables
SERVER_NAME=$1
SERVER_IP=$(hostname -I | awk '{print $2}')

echo "=========================================="
echo "Setting up Web Server: $SERVER_NAME"
echo "IP Address: $SERVER_IP"
echo "=========================================="

# Install Nginx
sudo apt-get update
sudo apt-get install -y nginx

# Create custom index page that identifies which server responded
sudo tee /var/www/html/index.html > /dev/null <<EOF
<!DOCTYPE html>
<html>
<head>
    <title>Load Balancer Test - $SERVER_NAME</title>
    <style>
        body {
            font-family: Arial, sans-serif;
            text-align: center;
            padding: 50px;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
        }
        .container {
            background: rgba(255,255,255,0.95);
            border-radius: 10px;
            padding: 30px;
            display: inline-block;
            color: #333;
            box-shadow: 0 10px 30px rgba(0,0,0,0.3);
        }
        .server-info {
            background: #f0f0f0;
            padding: 20px;
            border-radius: 5px;
            margin: 20px 0;
        }
        .badge {
            display: inline-block;
            padding: 5px 10px;
            background: #4CAF50;
            color: white;
            border-radius: 3px;
            font-size: 12px;
        }
        h1 { color: #667eea; }
        .timestamp { font-size: 12px; color: #999; margin-top: 20px; }
    </style>
</head>
<body>
    <div class="container">
        <h1>🚀 Load Balancer Demo</h1>
        <div class="server-info">
            <p><strong>Served by:</strong></p>
            <h2 style="color: #4CAF50;">$SERVER_NAME</h2>
            <p><strong>IP Address:</strong> $SERVER_IP</p>
            <p><span class="badge">Backend Server</span></p>
        </div>
        <p>This page was served by <strong>$SERVER_NAME</strong></p>
        <p>If you refresh, the load balancer will route you to the other server!</p>
        <div class="timestamp">
            <p>Request served at: <span id="timestamp"></span></p>
        </div>
    </div>
    <script>
        document.getElementById('timestamp').innerHTML = new Date().toLocaleString();
    </script>
</body>
</html>
EOF

# Create a health check endpoint for HAProxy
sudo tee /var/www/html/health.html > /dev/null <<EOF
OK
EOF

# Configure Nginx to log real IP from HAProxy
sudo tee /etc/nginx/conf.d/real_ip.conf > /dev/null <<EOF
set_real_ip_from 192.168.56.0/24;
real_ip_header X-Forwarded-For;
real_ip_recursive on;
EOF

# Backup default config and create optimized one
sudo tee /etc/nginx/sites-available/default > /dev/null <<EOF
server {
    listen 80 default_server;
    listen [::]:80 default_server;

    root /var/www/html;
    index index.html index.htm;

    server_name _;

    # Logging with real client IP
    set_real_ip_from 192.168.56.0/24;
    real_ip_header X-Forwarded-For;
    
    access_log /var/log/nginx/access.log;
    error_log /var/log/nginx/error.log;

    location / {
        try_files \$uri \$uri/ =404;
    }
    
    location /health {
        access_log off;
        return 200 "healthy\n";
        add_header Content-Type text/plain;
    }
}
EOF

# Test Nginx configuration
sudo nginx -t

# Restart Nginx
sudo systemctl restart nginx
sudo systemctl enable nginx

# Verify Nginx is running
if sudo systemctl is-active --quiet nginx; then
    echo "✅ Nginx is running successfully on $SERVER_NAME"
else
    echo "❌ Nginx failed to start. Check logs with: sudo journalctl -u nginx"
    exit 1
fi

# Display server info
echo ""
echo "=========================================="
echo "Web Server $SERVER_NAME Configuration:"
echo "=========================================="
echo "Server Name: $SERVER_NAME"
echo "IP Address: $SERVER_IP"
echo "Web Root: /var/www/html"
echo "Test locally: curl http://localhost"
echo "=========================================="

# Add a small delay to ensure Nginx is fully up
sleep 2
```

## 🚦 How to Use This Lab

### Step 1: Create Directory and Files
```bash
mkdir load-balancer-lab
cd load-balancer-lab
mkdir provisioning

# Copy the Vagrantfile and scripts into their respective locations
```

### Step 2: Make Scripts Executable
```bash
chmod +x provisioning/*.sh
```

### Step 3: Launch the Environment
```bash
vagrant up
```

This will:
- Create 3 VMs (haproxy, web1, web2)
- Install HAProxy on the load balancer
- Install Nginx on both web servers
- Configure HAProxy to distribute traffic to web1 and web2
- Set up health checks and statistics page

### Step 4: Test Your Load Balancer

```bash
# Test round-robin load balancing
curl http://192.168.56.10/
curl http://192.168.56.10/
curl http://192.168.56.10/

# You should see responses alternating between web1 and web2

# Check HAProxy statistics
# Open browser: http://192.168.56.10:8080/stats
# Login: admin / admin

# Run a proper load test
vagrant ssh haproxy
ab -n 1000 -c 10 http://192.168.56.10/
```

## 🎯 Interview Preparation Exercises

### Exercise 1: Test Failure Handling
```bash
# Simulate web1 failure
vagrant halt web1

# Now test load balancer behavior
# HAProxy should automatically stop sending traffic to web1
curl http://192.168.56.10/  # Should only get responses from web2

# Check health check logs on haproxy
vagrant ssh haproxy
sudo tail -f /var/log/haproxy.log
```

### Exercise 2: Change Load Balancing Algorithm
Edit `provisioning/haproxy.sh` and change line `balance roundrobin` to:
- `balance leastconn` (send to server with fewest connections)
- `balance source` (stickiness based on client IP)
- `balance uri` (stickiness based on request URI)

Then reprovision: `vagrant provision haproxy`

### Exercise 3: Add Rate Limiting
Add to HAProxy frontend section:
```
frontend http_front
    stick-table type ip size 1m expire 10s store http_req_rate(10s)
    http-request track-sc0 src
    http-request deny deny_status 429 if { sc_http_req_rate(0) gt 20 }
```

### Exercise 4: Simulate Real Traffic Pattern
```bash
# Generate varying load patterns
for i in {1..100}; do
    curl -s http://192.168.56.10/ | grep "Served by"
    sleep 0.$((RANDOM % 5))
done
```

## 📊 What This Proves to Interviewers

This lab demonstrates you understand:
1. **Layer 4 vs Layer 7 load balancing** (HAProxy in HTTP mode = Layer 7)
2. **Health checks** (Active probes every 2 seconds)
3. **Load balancing algorithms** (Round-robin, least connections, etc.)
4. **High availability patterns** (Active health monitoring and failover)
5. **Infrastructure as Code** (Full environment defined in Vagrantfile)
6. **Observability** (Stats page and logs)


You can easily add more web servers (web3, web4) by just editing the `nodes` hash!
