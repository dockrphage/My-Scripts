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
#
# IMPORTANT: Change the value below for each instance you launch!
NODE_NAME="${NODE_NAME:-jenkins-master}" 
PASSWORD="Admin123"

echo ">>> Starting setup for role: ${NODE_NAME}"

# ==========================================
# 1. SECURITY & SSH CONFIGURATION
# ==========================================
echo ">>> Configuring SSH for password login..."
sudo apt-get update -qq
echo "ubuntu:${PASSWORD}" | sudo chpasswd

SSH_OVERRIDE="/etc/ssh/sshd_config.d/60-cloudimg-settings.conf"
sudo touch $SSH_OVERRIDE
if sudo grep -q "^PasswordAuthentication" $SSH_OVERRIDE; then
    sudo sed -i 's/^PasswordAuthentication.*/PasswordAuthentication yes/' $SSH_OVERRIDE
else
    echo "PasswordAuthentication yes" | sudo tee -a $SSH_OVERRIDE
fi
sudo systemctl restart ssh
echo ">>> SSH configured."

# ==========================================
# 2. SYSTEM UPDATES & JAVA DEPENDENCIES
# ==========================================
echo ">>> Installing Java 21 and dependencies..."
# Install fontconfig and openjdk-21-jre as per official docs
sudo apt-get install -y fontconfig openjdk-21-jre curl wget gnupg docker.io

# Enable Docker service early
sudo systemctl start docker
sudo systemctl enable docker

# ==========================================
# 3. ROLE-SPECIFIC SETUP
# ==========================================
case ${NODE_NAME} in
  "jenkins-master")
    echo ">>> Configuring as Jenkins Master..."
    
    # 1. Download the CORRECT 2026 key
    sudo wget -O /etc/apt/keyrings/jenkins-keyring.asc \
      https://pkg.jenkins.io/debian-stable/jenkins.io-2026.key

    # 2. Add the repository
    echo "deb [signed-by=/etc/apt/keyrings/jenkins-keyring.asc] https://pkg.jenkins.io/debian-stable binary/" | \
      sudo tee /etc/apt/sources.list.d/jenkins.list > /dev/null

    # 3. Update and Install
    sudo apt-get update -qq
    sudo apt-get install -y jenkins

    # 4. Start and Enable
    sudo systemctl start jenkins
    sudo systemctl enable jenkins
    
    echo ">>> Jenkins installed successfully."
    ;;

  "git-server")
    echo ">>> Configuring as Git Server (Gitea)..."
    # Ensure docker is running
    sudo systemctl start docker
    sudo docker run -d --name gitea -p 3000:3000 -p 222:22 --restart=always -v gitea:/data gitea/gitea:latest
    ;;

  "app-repo")
    echo ">>> Configuring as App Source & Dev Client..."
    sudo apt-get install -y build-essential nodejs npm python3-pip
    sudo mkdir -p /home/ubuntu/app-source
    sudo chown -R ubuntu:ubuntu /home/ubuntu/app-source
    ;;

  "worker-1"|"worker-2")
    echo ">>> Configuring as Jenkins Agent (${NODE_NAME})..."
    # Ensure docker is running
    sudo systemctl start docker
    sudo systemctl enable docker
    sudo usermod -aG docker ubuntu
    echo "Role: ${NODE_NAME}" | sudo tee /etc/node-role > /dev/null
    ;;

  *)
    echo "!!! Unknown role: ${NODE_NAME}. Skipping role-specific setup."
    echo "Valid options are: jenkins-master, git-server, app-repo, worker-1, worker-2"
    exit 1
    ;;
esac

# ==========================================
# 4. FINALIZE
# ==========================================
echo ">>> Setup complete for ${NODE_NAME}."
echo "Public IP: $(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)"
echo "Private IP: $(curl -s http://169.254.169.254/latest/meta-data/local-ipv4)"
echo "Login with user: ubuntu and password: ${PASSWORD}"
