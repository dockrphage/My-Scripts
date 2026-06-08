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