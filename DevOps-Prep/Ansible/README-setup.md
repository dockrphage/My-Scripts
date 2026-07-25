Base setup for a three node Ansible Lab

this is the industry-standard approach for Ansible master-client setup.

## 📋 Complete Ansible Control Node Setup - Industry Standard

### 🎯 Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                    Control Node (Master)                    │
│                   192.168.56.10 (cp1)                        │
│  ┌──────────────────────────────────────────────────────┐   │
│  │  Ansible Engine + SSH Keys + Inventory + Playbooks   │   │
│  └──────────────────────────────────────────────────────┘   │
│                            │                                │
│                      SSH (Port 22)                         │
│                            ▼                                │
├─────────────────────────────────────────────────────────────┤
│              Managed Nodes (Clients)                        │
├───────────────┬────────────────┬───────────────────────────┤
│  node1        │   node2        │   node3 (optional)        │
│  192.168.56.11 │   192.168.56.12 │   192.168.56.13           │
│  web/app      │   database     │   monitoring              │
└───────────────┴────────────────┴───────────────────────────┘
```

## 🚀 Step-by-Step Implementation

### Step 1: Control Node Setup (cp1 - 192.168.56.10)

```bash
# SSH into control node
ssh vagrant@192.168.56.10
# Password: vagrant

# Update system
sudo apt update && sudo apt upgrade -y

# Install Ansible (Official method - recommended)
sudo apt install software-properties-common -y
sudo add-apt-repository --yes --update ppa:ansible/ansible
sudo apt install ansible -y

# Install additional tools for DevOps
sudo apt install -y \
    python3-pip \
    python3-venv \
    git \
    tree \
    jq \
    vim \
    sshpass

# Install Python modules
pip3 install --user \
    ansible-lint \
    jmespath \
    pyyaml \
    openshift \
    kubernetes

# Verify installation
ansible --version
which ansible
ansible --version | grep "python version"
```

### Step 2: SSH Key Setup (Best Practice)

```bash
# Generate SSH key (ed25519 is more secure than RSA)
ssh-keygen -t ed25519 -C "$(whoami)@$(hostname)-$(date +%Y-%m-%d)" -f ~/.ssh/id_ed25519 -N ""

# Or use RSA for compatibility
ssh-keygen -t rsa -b 4096 -C "$(whoami)@$(hostname)" -f ~/.ssh/id_rsa -N ""

# Set proper permissions
chmod 700 ~/.ssh
chmod 600 ~/.ssh/id_ed25519
chmod 644 ~/.ssh/id_ed25519.pub

# View and copy public key
cat ~/.ssh/id_ed25519.pub
```

### Step 3: Copy SSH Keys to Managed Nodes

```bash
# Method 1: Using ssh-copy-id (Recommended)
# You'll need to enter the vagrant password once per node
ssh-copy-id -o StrictHostKeyChecking=no vagrant@192.168.56.11
ssh-copy-id -o StrictHostKeyChecking=no vagrant@192.168.56.12

# Method 2: Using sshpass (if you want to automate)
sudo apt install sshpass -y
sshpass -p "vagrant" ssh-copy-id -o StrictHostKeyChecking=no vagrant@192.168.56.11
sshpass -p "vagrant" ssh-copy-id -o StrictHostKeyChecking=no vagrant@192.168.56.12

# Method 3: Manual copy (if above fails)
ssh vagrant@192.168.56.11 "mkdir -p ~/.ssh && chmod 700 ~/.ssh"
cat ~/.ssh/id_ed25519.pub | ssh vagrant@192.168.56.11 "cat >> ~/.ssh/authorized_keys"
ssh vagrant@192.168.56.11 "chmod 600 ~/.ssh/authorized_keys"

# Repeat for node2
ssh vagrant@192.168.56.12 "mkdir -p ~/.ssh && chmod 700 ~/.ssh"
cat ~/.ssh/id_ed25519.pub | ssh vagrant@192.168.56.12 "cat >> ~/.ssh/authorized_keys"
ssh vagrant@192.168.56.12 "chmod 600 ~/.ssh/authorized_keys"
```

### Step 4: Test Passwordless SSH

```bash
# Test SSH to each node
ssh -o ConnectTimeout=5 vagrant@192.168.56.11 "hostname && echo 'Connected to node1'"
ssh -o ConnectTimeout=5 vagrant@192.168.56.12 "hostname && echo 'Connected to node2'"

# Test without password (should not prompt)
ssh vagrant@192.168.56.11 "echo 'Success'"
```

### Step 5: Create SSH Config for Convenience

```bash
cat > ~/.ssh/config << 'EOF'
# SSH Config for Ansible managed nodes
Host k8s-node1
    HostName 192.168.56.11
    User vagrant
    IdentityFile ~/.ssh/id_ed25519
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null

Host k8s-node2
    HostName 192.168.56.12
    User vagrant
    IdentityFile ~/.ssh/id_ed25519
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null

Host k8s-master
    HostName 192.168.56.10
    User vagrant
    IdentityFile ~/.ssh/id_ed25519

Host 192.168.56.*
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null
    User vagrant
    IdentityFile ~/.ssh/id_ed25519
EOF

chmod 600 ~/.ssh/config
```

### Step 6: Create Ansible Directory Structure (Industry Standard)

```bash
# Create project structure in home directory
mkdir -p ~/ansible-lab/{inventories,playbooks,roles,group_vars,host_vars,templates,files,vars,scripts}

# Navigate to project
cd ~/ansible-lab
```

### Step 7: Create Ansible Configuration (ansible.cfg)

```bash
cat > ansible.cfg << 'EOF'
[defaults]
# Inventory
inventory = inventories/production.yml
host_key_checking = False
timeout = 30

# Output and Logging
stdout_callback = yaml
callback_whitelist = profile_tasks, timer
log_path = /var/log/ansible.log

# Performance
forks = 10
gathering = smart
fact_caching = jsonfile
fact_caching_connection = /tmp/ansible_cache
fact_caching_timeout = 3600

# Security and Permissions
remote_user = vagrant
private_key_file = ~/.ssh/id_ed25519
host_key_checking = False
ansible_managed = Ansible managed: {file} modified on %Y-%m-%d %H:%M:%S

# Roles and Collections
roles_path = roles
collections_path = collections

# Python
interpreter_python = /usr/bin/python3

[ssh_connection]
ssh_args = -o ControlMaster=auto -o ControlPersist=60s -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null
pipelining = True
control_path = /tmp/ansible-%%h-%%p-%%r

[privilege_escalation]
become = True
become_method = sudo
become_user = root
become_ask_pass = False

[colors]
highlight = white
verbose = blue
warn = bright purple
error = red
debug = dark gray
deprecate = purple
skip = cyan
unreachable = red
ok = green
changed = yellow
diff_add = green
diff_remove = red
EOF
```

### Step 8: Create Inventory (Industry Standard)

```bash
# Create production inventory in YAML format (preferred)
cat > inventories/production.yml << 'EOF'
---
# Production Inventory - Kubernetes Cluster
all:
  children:
    # Kubernetes Control Plane
    k8s_control_plane:
      hosts:
        cp1:
          ansible_host: 192.168.56.10
          ansible_user: vagrant
          ansible_python_interpreter: /usr/bin/python3
          k8s_role: control-plane
      
    # Kubernetes Worker Nodes
    k8s_workers:
      hosts:
        node1:
          ansible_host: 192.168.56.11
          ansible_user: vagrant
          ansible_python_interpreter: /usr/bin/python3
          node_type: worker
          
        node2:
          ansible_host: 192.168.56.12
          ansible_user: vagrant
          ansible_python_interpreter: /usr/bin/python3
          node_type: worker
    
    # Application Groups
    web_servers:
      hosts:
        node1:
      vars:
        app_environment: production
        nginx_port: 80
        app_role: webserver
    
    database_servers:
      hosts:
        node2:
      vars:
        db_type: postgresql
        db_port: 5432
        db_data_dir: /var/lib/postgresql/data
    
    # Monitoring Group
    monitoring:
      hosts:
        node1:
      vars:
        monitoring_enabled: true
        prometheus_port: 9090
        grafana_port: 3000
  
  vars:
    # Global variables
    ansible_ssh_common_args: '-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null'
    ansible_ssh_private_key_file: ~/.ssh/id_ed25519
    ansible_become: true
    ansible_become_method: sudo
    ansible_become_user: root
    
    # Environment
    environment: production
    cluster_name: k8s-prod
    deploy_user: vagrant
    
    # Monitoring
    enable_monitoring: true
    log_level: info
    
    # Security
    ssh_ports:
      - 22
    trusted_networks:
      - 192.168.56.0/24
    
    # Application settings
    app_version: latest
    app_repo: https://github.com/example/app.git
    deploy_path: /opt/app
EOF

# Also create a simpler INI format inventory for quick tests
cat > inventories/production.ini << 'EOF'
# Production Inventory - INI Format (Simpler)

[web_servers]
node1 ansible_host=192.168.56.11

[database_servers]
node2 ansible_host=192.168.56.12

[kubernetes_control]
cp1 ansible_host=192.168.56.10

[kubernetes_nodes:children]
web_servers
database_servers

[all:vars]
ansible_user=vagrant
ansible_ssh_private_key_file=~/.ssh/id_ed25519
ansible_python_interpreter=/usr/bin/python3
ansible_ssh_common_args='-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null'
ansible_become=yes
ansible_become_method=sudo
environment=production
EOF

# Create staging inventory
cat > inventories/staging.yml << 'EOF'
---
# Staging Inventory - For testing
all:
  children:
    staging_servers:
      hosts:
        staging-web:
          ansible_host: 192.168.56.11
        staging-db:
          ansible_host: 192.168.56.12
      vars:
        environment: staging
        debug_enabled: true
        log_level: debug
EOF
```

### Step 9: Test Connectivity

```bash
# Test with ping module
ansible all -i inventories/production.yml -m ping

# Test with specific groups
ansible web_servers -i inventories/production.yml -m ping
ansible database_servers -i inventories/production.yml -m ping

# Test with verbose output
ansible all -i inventories/production.yml -m ping -v

# Gather facts
ansible all -i inventories/production.yml -m setup --tree facts/

# Check specific node
ansible node1 -i inventories/production.yml -m setup | grep -E "hostname|distribution|memory"
```

### Step 10: Create First Playbook

```bash
cat > playbooks/01_initial_setup.yml << 'EOF'
---
- name: Initial Setup and Verification
  hosts: all
  gather_facts: yes
  become: yes
  
  tasks:
    - name: Display system information
      debug:
        msg: 
          - "Hostname: {{ ansible_hostname }}"
          - "OS: {{ ansible_distribution }} {{ ansible_distribution_version }}"
          - "Kernel: {{ ansible_kernel }}"
          - "CPU Cores: {{ ansible_processor_cores }}"
          - "Memory: {{ ansible_memtotal_mb }} MB"
          - "IP Address: {{ ansible_default_ipv4.address }}"
      run_once: true
      delegate_to: localhost
    
    - name: Verify Python is installed
      command: python3 --version
      register: python_version
    
    - name: Display Python version
      debug:
        msg: "Python version: {{ python_version.stdout }}"
    
    - name: Check connectivity from control node
      command: ping -c 2 {{ ansible_host }}
      delegate_to: localhost
      register: ping_result
      run_once: true
      ignore_errors: yes
    
    - name: Display ping results
      debug:
        msg: "{{ ping_result.stdout_lines }}"
      when: ping_result.stdout is defined

    - name: Ensure SSH is running
      service:
        name: ssh
        state: started
        enabled: yes
    
    - name: Check disk usage
      command: df -h /
      register: disk_usage
    
    - name: Display disk usage
      debug:
        var: disk_usage.stdout_lines

- name: Node-Specific Configuration
  hosts: web_servers
  become: yes
  
  tasks:
    - name: Create web server group variable
      debug:
        msg: "Configuring web server on {{ ansible_hostname }}"
    
    - name: Ensure nginx is installed
      apt:
        name: nginx
        state: present
      when: ansible_os_family == "Debian"
      register: nginx_install
    
    - name: Debug nginx installation
      debug:
        msg: "Nginx installation status: {{ nginx_install }}"
      when: nginx_install is defined

- name: Database Server Configuration
  hosts: database_servers
  become: yes
  
  tasks:
    - name: Configure database server
      debug:
        msg: "Configuring database on {{ ansible_hostname }} with type {{ db_type | default('postgresql') }}"
    
    - name: Ensure PostgreSQL is installed
      apt:
        name: postgresql
        state: present
      when: ansible_os_family == "Debian" and db_type is defined and db_type == "postgresql"
EOF

# Run the playbook
ansible-playbook playbooks/01_initial_setup.yml
```

### Step 11: Create Verification Script

```bash
cat > scripts/verify_setup.sh << 'EOF'
#!/bin/bash

echo "═══════════════════════════════════════════════════════════"
echo "           ANSIBLE SETUP VERIFICATION SCRIPT              "
echo "═══════════════════════════════════════════════════════════"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "\n${YELLOW}1. Checking Ansible Version${NC}"
ansible --version || { echo -e "${RED}❌ Ansible not found${NC}"; exit 1; }

echo -e "\n${YELLOW}2. Checking SSH Keys${NC}"
if [ -f ~/.ssh/id_ed25519 ] || [ -f ~/.ssh/id_rsa ]; then
    echo -e "${GREEN}✅ SSH key exists${NC}"
else
    echo -e "${RED}❌ SSH key not found${NC}"
fi

echo -e "\n${YELLOW}3. Testing Inventory${NC}"
ansible-inventory -i inventories/production.yml --list --export | python3 -m json.tool | head -20

echo -e "\n${YELLOW}4. Testing Connectivity to All Nodes${NC}"
ansible all -i inventories/production.yml -m ping --one-line

echo -e "\n${YELLOW}5. Gathering Facts${NC}"
ansible all -i inventories/production.yml -m setup --tree facts/ --limit node1
echo -e "${GREEN}✅ Facts saved to facts/ directory${NC}"

echo -e "\n${YELLOW}6. Testing Playbook Syntax${NC}"
ansible-playbook playbooks/01_initial_setup.yml --syntax-check
if [ $? -eq 0 ]; then
    echo -e "${GREEN}✅ Playbook syntax valid${NC}"
else
    echo -e "${RED}❌ Playbook syntax error${NC}"
fi

echo -e "\n${YELLOW}7. Testing with Check Mode${NC}"
ansible-playbook playbooks/01_initial_setup.yml --check --diff

echo -e "\n${GREEN}═══════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}✅ Setup Verification Complete!${NC}"
echo -e "${GREEN}═══════════════════════════════════════════════════════════${NC}"

# Summary
echo -e "\n${YELLOW}📊 Summary:${NC}"
echo "Control Node: $(hostname) - $(hostname -I | awk '{print $1}')"
echo "Ansible Version: $(ansible --version | head -1)"
echo "Python Version: $(python3 --version)"
echo "Inventory Path: $(pwd)/inventories/production.yml"
echo "Playbooks: $(ls -1 playbooks/ 2>/dev/null | wc -l) playbooks"
echo "Roles: $(ls -1 roles/ 2>/dev/null | wc -l) roles"
echo "Managed Nodes: $(ansible all -i inventories/production.yml --list-hosts | grep -c 'node')"
EOF

chmod +x scripts/verify_setup.sh
./scripts/verify_setup.sh
```

## 📊 Summary: Industry Standard vs Your Setup

| Component | Industry Standard | Your Implementation |
|-----------|------------------|-------------------|
| Control Node | Dedicated server with Ansible | cp1 (192.168.56.10) ✅ |
| SSH Auth | Passwordless key-based | ed25519/RSA keys ✅ |
| Inventory | YAML/INI in /etc/ansible or project | ~/ansible-lab/inventories/ ✅ |
| Config | ansible.cfg in project root | ~/ansible-lab/ansible.cfg ✅ |
| Playbooks | Structured by function | ~/ansible-lab/playbooks/ ✅ |
| Roles | Reusable components | ~/ansible-lab/roles/ ✅ |
| Variables | group_vars/host_vars | ~/ansible-lab/group_vars/ ✅ |
| Version Control | Git | ✅ (add git init) |

## 🎯 Next Steps for DevOps Learning

```bash
# 1. Initialize Git repository
git init
git add .
git commit -m "Initial Ansible setup with production inventory"

# 2. Install ansible-lint for code quality
pip3 install --user ansible-lint

# 3. Create a role
ansible-galaxy init roles/webserver
ansible-galaxy init roles/database

# 4. Test ansible-lint
ansible-lint playbooks/01_initial_setup.yml

# 5. Create a full deployment playbook
cat > playbooks/deploy_app.yml << 'EOF'
---
- name: Full Application Deployment
  hosts: web_servers
  roles:
    - webserver
    - monitoring
  post_tasks:
    - name: Verify deployment
      uri:
        url: "http://{{ ansible_default_ipv4.address }}"
        status_code: 200
      register: health
      until: health.status == 200
      retries: 5
      delay: 5
EOF
```

This setup follows industry best practices and is ready for DevOps learning, CI/CD integration, and production use. The modular structure makes it easy to extend and maintain.