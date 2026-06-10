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