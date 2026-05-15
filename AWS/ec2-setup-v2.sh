#!/bin/bash
set -e

# ==========================================
# CONFIGURATION
# ==========================================
# Options for NODE_NAME: 
#   "jenkins-master"  -> Installs Jenkins Controller
#   "git-server"      -> Installs Gitea (Git Host)
#   "app-repo"        -> Installs Dev tools (Node, Python, etc.)
#   "worker-1"        -> Installs Docker for Jenkins Agent
#   "worker-2"        -> Installs Docker for Jenkins Agent
# IMPORTANT: Change the value below for each instance you launch!
# CHANGE THIS VALUE FOR EACH INSTANCE BEFORE RUNNING
# Options: "jenkins-master", "git-server", "app-repo", "worker-1", "worker-2"
NODE_NAME="${1:-worker-2}" 
PASSWORD="Admin123"

echo ">>> Starting setup for role: ${NODE_NAME}..."

# ==========================================
# 1. SECURITY & SSH CONFIGURATION
# ==========================================
echo ">>> Configuring SSH..."
sudo apt-get update -qq
echo "ubuntu:${PASSWORD}" | sudo chpasswd

# Fix SSH config for AWS
SSH_OVERRIDE="/etc/ssh/sshd_config.d/60-cloudimg-settings.conf"
sudo touch $SSH_OVERRIDE
echo "PasswordAuthentication yes" | sudo tee -a $SSH_OVERRIDE 2>/dev/null || true
echo "PermitRootLogin yes" | sudo tee -a $SSH_OVERRIDE 2>/dev/null || true
sudo systemctl restart ssh

# ==========================================
# 2. SYSTEM UPDATES & JAVA DEPENDENCIES
# ==========================================
echo ">>> Installing Java 21, Docker and dependencies..."
sudo apt-get install -y fontconfig openjdk-21-jre curl wget gnupg2 software-properties-common docker.io

# Enable Docker
sudo systemctl start docker
sudo systemctl enable docker

# ==========================================
# 3. ROLE-SPECIFIC SETUP
# ==========================================
case ${NODE_NAME} in
  "jenkins-master")
    echo ">>> Configuring as Jenkins Master..."
    
    # 1. Add Jenkins Key (Official 2026 Key)
    sudo mkdir -p /etc/apt/keyrings
    sudo wget -O /etc/apt/keyrings/jenkins-keyring.asc \
      https://pkg.jenkins.io/debian-stable/jenkins.io-2026.key

    # 2. Add Repository
    echo "deb [signed-by=/etc/apt/keyrings/jenkins-keyring.asc] https://pkg.jenkins.io/debian-stable binary/" | \
      sudo tee /etc/apt/sources.list.d/jenkins.list > /dev/null

    # 3. Install
    sudo apt-get update -qq
    sudo apt-get install -y jenkins

    # 4. Start
    sudo systemctl start jenkins
    sudo systemctl enable jenkins
    
    # 5. Disable Security (Lab Only)
    echo "JENKINS_ENABLE_AUTH=false" | sudo tee /etc/default/jenkins
    
    echo ">>> Jenkins Master Ready. Port 8080 open."
    ;;

  "git-server")
    echo ">>> Configuring as Git Server (Gitea via Docker)..."
    
    # Create volume mapping for persistence
    sudo mkdir -p /home/ubuntu/gitea-data
    sudo chown -R ubuntu:ubuntu /home/ubuntu/gitea-data

    # Run Gitea
    # Note: Port 22 inside container is mapped to 2222 on host to avoid conflict with SSH
    sudo docker run -d --name gitea \
      -p 3000:3000 \
      -p 2222:22 \
      --restart=always \
      -v /home/ubuntu/gitea-data:/data \
      -e USER_UID=1000 \
      -e USER_GID=1000 \
      gitea/gitea:latest
      
    echo ">>> Gitea Ready. Port 3000 open. SSH on 2222."
    ;;

  "app-repo")
    echo ">>> Configuring as App Source & Dev Client..."
    sudo apt-get install -y build-essential nodejs npm python3-pip git
    sudo mkdir -p /home/ubuntu/app-source
    sudo chown -R ubuntu:ubuntu /home/ubuntu/app-source
    echo ">>> App Repo Ready. Node.js installed."
    ;;

  "worker-1"|"worker-2")
    echo ">>> Configuring as Jenkins Agent (${NODE_NAME})..."
    # Ensure docker is running
    sudo systemctl start docker
    sudo systemctl enable docker
    # Add ubuntu user to docker group
    sudo usermod -aG docker ubuntu
    # Create a marker file to identify the node
    echo "Role: ${NODE_NAME}" | sudo tee /etc/node-role
    echo ">>> Worker Node Ready. Docker installed."
    ;;

  *)
    echo "!!! Error: Unknown role '${NODE_NAME}'."
    echo "Usage: sudo ./setup.sh <role>"
    echo "Roles: jenkins-master, git-server, app-repo, worker-1, worker-2"
    exit 1
    ;;
esac

# ==========================================
# 4. FINALIZE
# ==========================================
echo ">>> Setup complete for ${NODE_NAME}."
echo "Public IP: $(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)"
echo "Private IP: $(curl -s http://169.254.169.254/latest/meta-data/local-ipv4)"
echo "Login: ssh -i your-key.pem ubuntu@<PUBLIC_IP>"
echo "Password for SSH: ${PASSWORD}"