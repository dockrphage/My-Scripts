# 🚀 Complete Ansible Lab Implementation Guide
## *Reusable Infrastructure as Code with Vagrant + Ansible*
Project repo: https://github.com/dockrphage/ansible-learning-series.git
---

## 📋 Table of Contents
1. [Prerequisites](#prerequisites)
2. [Project Architecture](#project-architecture)
3. [Infrastructure Setup](#infrastructure-setup)
4. [Ansible Configuration](#ansible-configuration)
5. [Playbook Development](#playbook-development)
6. [Testing & Validation](#testing--validation)
7. [Troubleshooting Guide](#troubleshooting-guide)
8. [Production Readiness](#production-readiness)
9. [Quick Reference](#quick-reference)

---

## 🎯 Prerequisites

### Hardware Requirements
| Component | Minimum | Recommended |
|-----------|---------|-------------|
| CPU | 4 cores | 8+ cores |
| RAM | 8 GB | 16+ GB |
| Storage | 20 GB | 50+ GB |
| Network | Internet | High-speed |

### Software Requirements
```bash
# Version Requirements
- VirtualBox 6.1+
- Vagrant 2.3+
- Ansible 2.14+
- Python 3.9+
- Git 2.25+
```

### Install Prerequisites (Ubuntu/Debian)

```bash
#!/bin/bash
# install_prerequisites.sh

echo "🔧 Installing prerequisites for Ansible Lab..."

# Update system
sudo apt update && sudo apt upgrade -y

# Install VirtualBox
sudo apt install -y virtualbox virtualbox-ext-pack
sudo apt install -y linux-headers-$(uname -r) build-essential

# Install Vagrant
wget -O- https://apt.releases.hashicorp.com/gpg | gpg --dearmor | sudo tee /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt update && sudo apt install -y vagrant

# Install Python and Ansible
sudo apt install -y python3 python3-pip python3-venv python3-dev
python3 -m pip install --upgrade pip
python3 -m pip install ansible

# Install Git
sudo apt install -y git

# Verify installations
echo "✅ Installations complete:"
echo "VirtualBox: $(VBoxManage --version 2>/dev/null || echo 'Not installed')"
echo "Vagrant: $(vagrant --version 2>/dev/null || echo 'Not installed')"
echo "Ansible: $(ansible --version 2>/dev/null | head -1 || echo 'Not installed')"
echo "Python: $(python3 --version)"
```

---

## 🏗️ Project Architecture

### Directory Structure
```
ansible-lab/
├── .gitignore
├── README.md
├── Vagrantfile                    # Infrastructure as Code
├── ansible.cfg                    # Ansible configuration
├── ansible/
│   └── inventory/
│       ├── production/
│       │   ├── hosts              # Production inventory
│       │   └── group_vars/
│       │       ├── all.yml
│       │       ├── webservers.yml
│       │       └── databases.yml
│       └── staging/
│           ├── hosts
│           └── group_vars/
├── playbooks/
│   ├── 01_basic/
│   │   ├── hello_world.yml
│   │   └── package_management.yml
│   ├── 02_variables/
│   ├── 03_variables/
│   ├── 04_loops/
│   ├── 05_handlers/
│   ├── 06_roles/
│   ├── 07_templates/
│   ├── 08_facts/
│   ├── 09_jinja2/
│   ├── 10_dynamic_inventory/
│   ├── 11_error_handling/
│   ├── 12_awx_tower/
│   └── 13_production/
├── roles/
│   ├── common/
│   ├── webserver/
│   ├── database/
│   └── monitoring/
├── templates/
├── files/
├── scripts/
│   ├── setup.sh
│   ├── cleanup.sh
│   └── deploy.sh
└── tests/
    └── test_playbooks.yml
```

### Create Project Structure
```bash
#!/bin/bash
# create_project_structure.sh

PROJECT_ROOT=~/projects/ansible-lab

echo "📁 Creating project structure..."

mkdir -p ${PROJECT_ROOT}/{ansible/inventory/{production,staging},playbooks,roles,templates,files,scripts,tests}

cd ${PROJECT_ROOT}

# Create production inventory directories
mkdir -p ansible/inventory/production/group_vars
mkdir -p ansible/inventory/staging/group_vars

# Create role directories
for role in common webserver database monitoring security; do
    mkdir -p roles/${role}/{tasks,handlers,templates,files,vars,meta}
done

echo "✅ Project structure created at: ${PROJECT_ROOT}"
```

---

## 🔧 Infrastructure Setup

### Complete Vagrantfile

```ruby
# Vagrantfile - Infrastructure as Code
# -*- mode: ruby -*-
# vi: set ft=ruby :

Vagrant.configure("2") do |config|
  # Global settings
  config.vm.boot_timeout = 600
  config.ssh.insert_key = true
  config.ssh.forward_agent = true
  
  # Node definitions - Mixed OS (Ubuntu 22.04 + AlmaLinux 9)
  nodes = {
    "node1" => { 
      ip: "192.168.56.10", 
      bridged_ip: "192.168.1.50", 
      cpu: 2, 
      mem: 2048,
      os: "ubuntu",
      role: "control"
    },
    "node2" => { 
      ip: "192.168.56.11", 
      bridged_ip: "192.168.1.51", 
      cpu: 1, 
      mem: 2048,
      os: "almalinux",
      role: "webserver"
    },
    "node3" => { 
      ip: "192.168.56.12", 
      bridged_ip: "192.168.1.52", 
      cpu: 1, 
      mem: 2048,
      os: "ubuntu",
      role: "webserver"
    },
    "node4" => { 
      ip: "192.168.56.13", 
      bridged_ip: "192.168.1.53", 
      cpu: 1, 
      mem: 2048,
      os: "almalinux",
      role: "database"
    },
    "node5" => { 
      ip: "192.168.56.14", 
      bridged_ip: "192.168.1.54", 
      cpu: 1, 
      mem: 2048,
      os: "ubuntu",
      role: "database"
    }
  }

  nodes.each do |name, cfg|
    config.vm.define name do |node|
      
      # OS Selection
      if cfg[:os] == "ubuntu"
        node.vm.box = "ubuntu/jammy64"
        node.vm.provision "shell", inline: ubuntu_provision(name, cfg[:role])
      else
        node.vm.box = "almalinux/9"
        node.vm.provision "shell", inline: almalinux_provision(name, cfg[:role])
      end

      # Networks
      node.vm.network "private_network",
        ip: cfg[:ip],
        virtualbox__promiscuous_mode: "allow-all"

      node.vm.network "public_network",
        ip: cfg[:bridged_ip],
        bridge: "wlp0s20f3"  # Change based on your interface

      # VirtualBox Settings
      node.vm.provider "virtualbox" do |vb|
        vb.memory = cfg[:mem]
        vb.cpus = cfg[:cpu]
        vb.name = name
        vb.customize ["modifyvm", :id, "--natdnshostresolver1", "on"]
        vb.customize ["modifyvm", :id, "--natdnsproxy1", "on"]
        vb.customize ["modifyvm", :id, "--graphicscontroller", "vmsvga"]
        vb.customize ["modifyvm", :id, "--audio", "none"]
      end

      # Synced folder
      node.vm.synced_folder ".", "/vagrant", disabled: false
    end
  end

  # Final message
  config.vm.provision "shell", inline: <<-SHELL
    echo "============================================================"
    echo "🚀 ANSIBLE LAB READY!"
    echo "============================================================"
    echo "Ubuntu 22.04 (Python 3.10): node1, node3, node5"
    echo "AlmaLinux 9 (Python 3.9): node2, node4"
    echo "============================================================"
    echo "SSH: vagrant ssh node1 | ansible@192.168.1.50 (password: ansible)"
    echo "============================================================"
  SHELL
end

# Provisioning functions
def ubuntu_provision(name, role)
  return <<-SHELL
    sudo apt-get update
    sudo apt-get install -y python3 python3-pip python3-apt net-tools curl wget vim git tree htop telnet dnsutils jq
    
    sudo sed -i 's/PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config.d/60-cloudimg-settings.conf
    echo 'vagrant:vagrant' | sudo chpasswd
    sudo systemctl restart ssh
    
    sudo useradd -m -s /bin/bash ansible 2>/dev/null || true
    echo 'ansible:ansible' | sudo chpasswd
    sudo usermod -aG sudo ansible
    echo 'ansible ALL=(ALL) NOPASSWD:ALL' | sudo tee /etc/sudoers.d/ansible
    
    sudo mkdir -p /home/ansible/.ssh
    sudo chmod 700 /home/ansible/.ssh
    sudo ssh-keygen -t rsa -b 4096 -f /home/ansible/.ssh/id_rsa -N "" -q
    sudo cat /home/ansible/.ssh/id_rsa.pub | sudo tee /home/ansible/.ssh/authorized_keys
    sudo chmod 600 /home/ansible/.ssh/authorized_keys
    sudo chown -R ansible:ansible /home/ansible/.ssh
    
    sudo hostnamectl set-hostname #{name}
    echo "127.0.1.1 #{name}" | sudo tee -a /etc/hosts
    
    if [ "#{role}" = "control" ]; then
      sudo apt-get install -y nginx docker.io docker-compose
      sudo systemctl enable docker
      sudo systemctl start docker
      sudo usermod -aG docker vagrant
      sudo usermod -aG docker ansible
    elif [ "#{role}" = "database" ]; then
      sudo apt-get install -y postgresql
      sudo systemctl enable postgresql
      sudo systemctl start postgresql
    elif [ "#{role}" = "webserver" ]; then
      sudo apt-get install -y nginx
      sudo systemctl enable nginx
      sudo systemctl start nginx
    fi
  SHELL
end

def almalinux_provision(name, role)
  return <<-SHELL
    sudo dnf update -y
    sudo dnf install -y epel-release
    sudo dnf install -y python3 python3-pip net-tools curl wget vim git tree htop telnet dnsutils jq
    
    sudo dnf config-manager --set-enabled crb 2>/dev/null || true
    
    sudo sed -i 's/^PasswordAuthentication .*/PasswordAuthentication yes/' /etc/ssh/sshd_config
    sudo sed -i 's/^#PasswordAuthentication .*/PasswordAuthentication yes/' /etc/ssh/sshd_config
    echo 'vagrant:vagrant' | sudo chpasswd
    sudo systemctl restart sshd
    
    sudo useradd -m -s /bin/bash ansible 2>/dev/null || true
    echo 'ansible:ansible' | sudo chpasswd
    sudo usermod -aG wheel ansible
    echo 'ansible ALL=(ALL) NOPASSWD:ALL' | sudo tee /etc/sudoers.d/ansible
    
    sudo mkdir -p /home/ansible/.ssh
    sudo chmod 700 /home/ansible/.ssh
    sudo ssh-keygen -t rsa -b 4096 -f /home/ansible/.ssh/id_rsa -N "" -q
    sudo cat /home/ansible/.ssh/id_rsa.pub | sudo tee /home/ansible/.ssh/authorized_keys
    sudo chmod 600 /home/ansible/.ssh/authorized_keys
    sudo chown -R ansible:ansible /home/ansible/.ssh
    
    sudo hostnamectl set-hostname #{name}
    echo "127.0.1.1 #{name}" | sudo tee -a /etc/hosts
    
    sudo systemctl stop firewalld
    sudo systemctl disable firewalld
    
    if [ "#{role}" = "control" ]; then
      sudo dnf config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
      sudo dnf install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
      sudo systemctl enable docker
      sudo systemctl start docker
      sudo usermod -aG docker vagrant
      sudo usermod -aG docker ansible
    elif [ "#{role}" = "database" ]; then
      sudo dnf install -y postgresql-server postgresql-contrib
      sudo postgresql-setup --initdb || true
      sudo systemctl enable postgresql
      sudo systemctl start postgresql
    elif [ "#{role}" = "webserver" ]; then
      sudo dnf install -y nginx
      sudo systemctl enable nginx
      sudo systemctl start nginx
    fi
  SHELL
end
```

---

## ⚙️ Ansible Configuration

### ansible.cfg

```ini
# ansible.cfg - Optimized Ansible Configuration
[defaults]
# Inventory
inventory = ./ansible/inventory/production/hosts
host_key_checking = False

# Performance
forks = 20
timeout = 30
gathering = smart
fact_caching = jsonfile
fact_caching_connection = /tmp/ansible_facts
fact_caching_timeout = 3600

# Output
stdout_callback = default
display_ok_hosts = yes
display_failed_stderr = yes
deprecation_warnings = False

# Retry
retry_files_enabled = False

# Logging
log_path = /var/log/ansible.log

[ssh_connection]
pipelining = True
control_path = /tmp/ansible-%%h-%%p-%%r
scp_if_ssh = True

[privilege_escalation]
become = True
become_method = sudo
become_user = root
```

### Inventory File

```ini
# ansible/inventory/production/hosts
[all]
node1 ansible_host=192.168.1.50 ansible_user=ansible ansible_password=ansible ansible_become_password=ansible
node2 ansible_host=192.168.1.51 ansible_user=ansible ansible_password=ansible ansible_become_password=ansible
node3 ansible_host=192.168.1.52 ansible_user=ansible ansible_password=ansible ansible_become_password=ansible
node4 ansible_host=192.168.1.53 ansible_user=ansible ansible_password=ansible ansible_become_password=ansible
node5 ansible_host=192.168.1.54 ansible_user=ansible ansible_password=ansible ansible_become_password=ansible

# Groups
[webservers]
node2
node3

[databases]
node4
node5

[control]
node1

# OS Groups
[ubuntu]
node1
node3
node5

[almalinux]
node2
node4

# Children groups
[all:vars]
ansible_ssh_common_args='-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null'
ansible_python_interpreter=/usr/bin/python3

[webservers:vars]
http_port=80
max_clients=200

[databases:vars]
db_port=5432
db_user=ansible
```

### Group Variables

```yaml
# ansible/inventory/production/group_vars/all.yml
---
# Global variables for all hosts
ntp_servers:
  - 0.pool.ntp.org
  - 1.pool.ntp.org

timezone: UTC

packages:
  - git
  - vim
  - curl
  - wget
  - net-tools
  - htop
  - tree
```

```yaml
# ansible/inventory/production/group_vars/webservers.yml
---
web_package: "{{ 'nginx' if ansible_os_family == 'Debian' else 'httpd' }}"
web_service: "{{ 'nginx' if ansible_os_family == 'Debian' else 'httpd' }}"
web_root: "/var/www/html"
web_user: "{{ 'www-data' if ansible_os_family == 'Debian' else 'apache' }}"
```

```yaml
# ansible/inventory/production/group_vars/databases.yml
---
db_package: "{{ 'postgresql' if ansible_os_family == 'Debian' else 'postgresql-server' }}"
db_service: postgresql
db_port: 5432
db_data_dir: "/var/lib/postgresql/data"
```

---

## 📝 Core Playbooks

### 1. Hello World Playbook

```yaml
# playbooks/01_basic/hello_world.yml
---
- name: Hello World Playbook
  hosts: all
  gather_facts: yes
  
  tasks:
    - name: Print hello message
      debug:
        msg: "Hello from {{ ansible_facts['hostname'] }}!"

    - name: Show OS information
      debug:
        msg: "This is {{ ansible_facts['distribution'] }} {{ ansible_facts['distribution_version'] }}"

    - name: Show Python version
      debug:
        msg: "Python version: {{ ansible_facts['python_version'] }}"

    - name: Show OS Family
      debug:
        msg: "OS Family: {{ ansible_facts['os_family'] }}"

    - name: Ping test
      ping:
```

### 2. Package Management Playbook

```yaml
# playbooks/01_basic/package_management.yml
---
- name: Package Management Basics
  hosts: all
  become: yes
  gather_facts: yes
  
  tasks:
    - name: Update package cache (Ubuntu)
      apt:
        update_cache: yes
        cache_valid_time: 3600
      when: ansible_facts['os_family'] == "Debian"

    - name: Update package cache (RHEL)
      dnf:
        update_cache: yes
      when: ansible_facts['os_family'] == "RedHat"

    - name: Install common packages
      package:
        name:
          - git
          - vim
          - curl
          - wget
          - net-tools
          - htop
          - tree
        state: present

    - name: Install OS-specific packages (Ubuntu)
      package:
        name:
          - python3-pip
          - python3-apt
          - snapd
        state: present
      when: ansible_facts['os_family'] == "Debian"

    - name: Install OS-specific packages (RHEL)
      package:
        name:
          - python3-pip
          - epel-release
          - yum-utils
        state: present
      when: ansible_facts['os_family'] == "RedHat"
```

### 3. Handler Example Playbook

```yaml
# playbooks/05_handlers/simple_handlers.yml
---
- name: Simple Handler Examples
  hosts: all
  become: yes
  
  tasks:
    - name: Create a test configuration file
      copy:
        content: |
          # Test configuration file
          # Created by Ansible on {{ ansible_facts['date_time']['iso8601'] }}
          HOSTNAME={{ ansible_facts['hostname'] }}
          OS={{ ansible_facts['distribution'] }}
          VERSION={{ ansible_facts['distribution_version'] }}
        dest: /tmp/test_config.txt
        mode: '0644'
      notify:
        - restart test service
        - verify file exists

    - name: Create a test log file
      file:
        path: /tmp/test.log
        state: touch
        mode: '0644'
      notify: log file created

    - name: Display completion message
      debug:
        msg: "Configuration files created. Handlers will be triggered."

  handlers:
    - name: restart test service
      debug:
        msg: "Handler: Restarting test service (simulated) on {{ ansible_facts['hostname'] }}"

    - name: verify file exists
      stat:
        path: /tmp/test_config.txt
      register: file_check

    - name: verify file exists handler
      debug:
        msg: "Handler: File /tmp/test_config.txt exists: {{ file_check.stat.exists }}"

    - name: log file created
      debug:
        msg: "Handler: Log file /tmp/test.log was created"
```

### 4. Production Deployment Playbook

```yaml
# playbooks/13_production/production_deployment.yml
---
- name: Production Deployment Pipeline
  hosts: all
  become: yes
  gather_facts: yes
  serial: 1  # Rolling update - one node at a time
  any_errors_fatal: false
  max_fail_percentage: 20

  pre_tasks:
    - name: Backup application configuration
      archive:
        path: /etc/app
        dest: "/tmp/backup_{{ ansible_facts['date_time']['iso8601'] }}.tar.gz"
      when: not ansible_check_mode
      ignore_errors: yes

    - name: Display deployment info
      debug:
        msg: "Deploying to {{ inventory_hostname }} ({{ ansible_facts['distribution'] }})"

  tasks:
    - name: Deploy new version
      block:
        - name: Install web server
          package:
            name: "{{ 'nginx' if ansible_facts['os_family'] == 'Debian' else 'httpd' }}"
            state: present

        - name: Deploy application code
          git:
            repo: "{{ app_repo | default('https://github.com/example/app.git') }}"
            dest: "/var/www/{{ app_name | default('myapp') }}"
            version: "{{ app_version | default('main') }}"
          when: app_repo is defined

        - name: Set permissions
          file:
            path: "/var/www/{{ app_name | default('myapp') }}"
            recurse: yes
            owner: "{{ 'www-data' if ansible_facts['os_family'] == 'Debian' else 'apache' }}"
            group: "{{ 'www-data' if ansible_facts['os_family'] == 'Debian' else 'apache' }}"
            mode: '0755'

      rescue:
        - name: Rollback on failure
          debug:
            msg: "Deployment failed on {{ inventory_hostname }}. Rolling back..."

        - name: Restore from backup
          unarchive:
            src: "{{ backup_file }}"
            dest: /etc/app
            remote_src: yes
          when: backup_file is defined

      always:
        - name: Display deployment status
          debug:
            msg: "Deployment completed on {{ inventory_hostname }} with status: {{ ansible_failed_result | default('Success') }}"

  post_tasks:
    - name: Health check
      uri:
        url: "http://{{ ansible_facts['default_ipv4']['address'] }}:{{ http_port | default(80) }}/health"
        status_code: 200
        timeout: 10
      register: health_check
      until: health_check.status == 200
      retries: 10
      delay: 5
      ignore_errors: yes

    - name: Update monitoring
      debug:
        msg: "Updating monitoring for {{ inventory_hostname }}"
      when: not ansible_check_mode

    - name: Deployment notification
      debug:
        msg: "✅ Deployment complete on {{ inventory_hostname }}"
```

---

## 🚀 Deployment Scripts

### Setup Script

```bash
#!/bin/bash
# scripts/setup.sh - Complete setup automation

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

PROJECT_ROOT=~/projects/ansible-lab

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}🚀 Ansible Lab Setup Script${NC}"
echo -e "${BLUE}========================================${NC}"

# Check prerequisites
echo -e "\n${YELLOW}📋 Checking prerequisites...${NC}"

check_command() {
    if command -v $1 &> /dev/null; then
        echo -e "${GREEN}✅ $1 installed${NC}"
    else
        echo -e "${RED}❌ $1 not found${NC}"
        exit 1
    fi
}

check_command vagrant
check_command virtualbox
check_command ansible
check_command python3

# Create project structure
echo -e "\n${YELLOW}📁 Creating project structure...${NC}"
mkdir -p ${PROJECT_ROOT}
cd ${PROJECT_ROOT}

# Setup virtual environment
echo -e "\n${YELLOW}🐍 Setting up Python virtual environment...${NC}"
python3 -m venv .venv
source .venv/bin/activate
pip install --upgrade pip
pip install ansible

# Create directory structure
mkdir -p ansible/inventory/{production,staging}
mkdir -p ansible/inventory/production/group_vars
mkdir -p playbooks/{01_basic,03_variables,04_loops,05_handlers,06_roles,07_templates,08_facts,09_jinja2,10_dynamic_inventory,11_error_handling,12_awx_tower,13_production}
mkdir -p roles/{common,webserver,database,monitoring,security}/{tasks,handlers,templates,files,vars,meta}
mkdir -p templates files scripts tests

# Setup Vagrant
echo -e "\n${YELLOW}🖥️  Starting Vagrant VMs...${NC}"
vagrant up

# Wait for VMs to be ready
echo -e "\n${YELLOW}⏳ Waiting for VMs to be ready...${NC}"
sleep 30

# Test connectivity
echo -e "\n${YELLOW}🔌 Testing connectivity...${NC}"
for node in node1 node2 node3 node4 node5; do
    if ping -c 1 192.168.1.${node##node}0 &> /dev/null; then
        echo -e "${GREEN}✅ $node is reachable${NC}"
    else
        echo -e "${RED}❌ $node is not reachable${NC}"
    fi
done

# Test Ansible
echo -e "\n${YELLOW}🔍 Testing Ansible...${NC}"
ansible all -m ping

echo -e "\n${GREEN}✅ Setup complete!${NC}"
echo -e "\n${BLUE}📝 Next steps:${NC}"
echo "  1. cd ${PROJECT_ROOT}"
echo "  2. source .venv/bin/activate"
echo "  3. ansible-playbook playbooks/01_basic/hello_world.yml"
echo "  4. Run your first playbook!"
```

### Deployment Script

```bash
#!/bin/bash
# scripts/deploy.sh - Deployment automation

set -e

ENVIRONMENT=${1:-production}
PLAYBOOK=${2:-playbooks/13_production/production_deployment.yml}

echo "🚀 Deploying to $ENVIRONMENT environment..."
echo "📝 Playbook: $PLAYBOOK"

# Activate virtual environment
source .venv/bin/activate

# Validate inventory
echo "📋 Validating inventory..."
ansible-inventory --list

# Syntax check
echo "🔍 Running syntax check..."
ansible-playbook $PLAYBOOK --syntax-check

# Dry run
echo "🧪 Running dry run..."
ansible-playbook $PLAYBOOK --check --diff

# Deploy
echo "📦 Deploying..."
ansible-playbook $PLAYBOOK -e "environment=$ENVIRONMENT"

echo "✅ Deployment complete!"
```

### Cleanup Script

```bash
#!/bin/bash
# scripts/cleanup.sh - Clean up resources

set -e

echo "🧹 Cleaning up Ansible Lab..."

# Destroy VMs
vagrant destroy -f

# Remove virtual environment
rm -rf .venv

# Clean Ansible cache
rm -rf /tmp/ansible_facts

# Remove logs
rm -rf /var/log/ansible.log

echo "✅ Cleanup complete!"
```

---

## 🧪 Testing & Validation

### Test All Playbooks

```bash
#!/bin/bash
# tests/test_playbooks.yml - Playbook test script

echo "🧪 Testing Ansible Playbooks"

# Test basic playbooks
echo "📝 Testing hello_world..."
ansible-playbook playbooks/01_basic/hello_world.yml

# Test package management
echo "📦 Testing package_management..."
ansible-playbook playbooks/01_basic/package_management.yml

# Test variables
echo "🔢 Testing variable_usage..."
ansible-playbook playbooks/03_variables/variable_usage.yml -e "app_env=staging"

# Test handlers
echo "⚡ Testing handlers..."
ansible-playbook playbooks/05_handlers/simple_handlers.yml

# Test facts
echo "🔍 Testing facts..."
ansible-playbook playbooks/08_facts/facts_examples.yml

# Test production
echo "🏭 Testing production deployment..."
ansible-playbook playbooks/13_production/production_deployment.yml --check

echo "✅ All tests completed!"
```

### Validation Checks

```bash
# Check node status
for node in node1 node2 node3 node4 node5; do
    echo "=== $node ==="
    ssh -o StrictHostKeyChecking=no ansible@192.168.1.${node##node}0 "hostname && uptime"
done

# Check Python versions
ansible all -m shell -a "python3 --version"

# Check web servers
ansible webservers -m shell -a "curl -s http://localhost | grep Welcome"

# Check databases
ansible databases -m shell -a "systemctl status postgresql --no-pager | grep Active"

# Check disk space
ansible all -m shell -a "df -h /"

# Check memory
ansible all -m shell -a "free -h"
```

---

## 🐛 Troubleshooting Guide

### Common Issues and Solutions

#### 1. SSH Timeout
```bash
# Issue: Cannot SSH to node
# Solution:
vagrant up --provision
vagrant ssh node1

# Or manually reset SSH
ssh-keygen -R 192.168.1.50
```

#### 2. Python Version Issues
```bash
# Issue: Python 3.8 found, Ansible requires 3.9+
# Solution:
# Ubuntu 20.04:
sudo apt-get install python3.9 python3.9-pip
sudo update-alternatives --set python3 /usr/bin/python3.9

# AlmaLinux 9 has Python 3.9 by default
# Ubuntu 22.04 has Python 3.10 by default
```

#### 3. Permission Denied
```bash
# Issue: Permission denied during playbook execution
# Solution:
# Ensure become: yes in playbook
# Check sudoers file
vagrant ssh node1 -c "sudo cat /etc/sudoers.d/ansible"
```

#### 4. Service Won't Start
```bash
# Issue: httpd/nginx won't start
# Solution for AlmaLinux:
ssh ansible@192.168.1.51
sudo setenforce 0
sudo systemctl stop firewalld
sudo systemctl disable firewalld
sudo systemctl start httpd
sudo systemctl status httpd
```

#### 5. Inventory Not Found
```bash
# Issue: No inventory parsed
# Solution:
ansible -i ./ansible/inventory/production/hosts all -m ping
# Or export inventory path
export ANSIBLE_INVENTORY=./ansible/inventory/production/hosts
```

---

## 📈 Performance Tuning

### Optimize ansible.cfg
```ini
[defaults]
forks = 50                    # Max parallelism
timeout = 60                  # Increase timeout
pipelining = True             # Reduce SSH overhead
gathering = smart             # Smart fact gathering
fact_caching = redis          # Use Redis for caching
fact_caching_connection = localhost:6379:0

[ssh_connection]
control_path = /tmp/ansible-%%h-%%p-%%r
pipelining = True
scp_if_ssh = True
```

### Benchmark Commands
```bash
# Profile playbook execution
ANSIBLE_PROFILE=1 ansible-playbook playbooks/13_production/production_deployment.yml

# Time execution
time ansible-playbook playbooks/01_basic/hello_world.yml

# Check for bottlenecks
ansible all -m setup --timeout 10
```

---

## 📚 Quick Reference

### Common Ansible Commands

```bash
# Test connectivity
ansible all -m ping

# Run ad-hoc commands
ansible webservers -m shell -a "uptime"
ansible databases -m command -a "df -h"

# Gather facts
ansible all -m setup -a "filter=ansible_distribution*"

# Run playbooks
ansible-playbook playbooks/01_basic/hello_world.yml
ansible-playbook playbooks/03_variables/variable_usage.yml -e "app_env=staging"

# Dry run
ansible-playbook playbooks/13_production/production_deployment.yml --check

# Step mode
ansible-playbook playbooks/13_production/production_deployment.yml --step

# Verbose mode
ansible-playbook playbooks/01_basic/hello_world.yml -vvv

# Limit to specific nodes
ansible-playbook playbooks/01_basic/hello_world.yml --limit node1,node2

# Inventory management
ansible-inventory --list
ansible-inventory --host node1
```

### Vagrant Commands

```bash
# Start all VMs
vagrant up

# Start specific VM
vagrant up node1

# SSH into VM
vagrant ssh node1

# Stop VMs
vagrant halt

# Suspend VMs
vagrant suspend

# Resume VMs
vagrant resume

# Reload VMs
vagrant reload --provision

# Destroy VMs
vagrant destroy -f

# Check status
vagrant status

# Provision VMs
vagrant provision
```

---

## 🔐 Security Checklist

### Pre-Deployment
- [ ] SSH keys generated and distributed
- [ ] sudoers configured for ansible user
- [ ] Firewall rules verified
- [ ] SELinux/AppArmor status checked
- [ ] Python version confirmed (3.9+)

### During Deployment
- [ ] Use `--check` for dry run
- [ ] Use `--diff` to see changes
- [ ] Use `--step` for manual confirmation
- [ ] Enable logging with `-v` for visibility
- [ ] Use `any_errors_fatal` for critical operations

### Post-Deployment
- [ ] Verify service status
- [ ] Run health checks
- [ ] Check logs for errors
- [ ] Validate configuration
- [ ] Test rollback procedure

---

## 📊 Monitoring & Metrics

### Node Health Checks

```yaml
# health_check.yml
---
- name: Health Check Playbook
  hosts: all
  tasks:
    - name: Check CPU usage
      shell: "top -bn1 | grep 'Cpu(s)'"
      register: cpu

    - name: Check memory usage
      shell: "free -h | grep Mem"
      register: memory

    - name: Check disk usage
      shell: "df -h /"
      register: disk

    - name: Check service status
      service:
        name: "{{ 'nginx' if ansible_facts['os_family'] == 'Debian' else 'httpd' }}"
        state: started
      ignore_errors: yes
      register: service_status

    - name: Check connectivity
      ping:
```

---

## 🎯 Success Metrics

| Metric | Target | How to Measure |
|--------|--------|----------------|
| Deployment Time | < 5 min | `time ansible-playbook` |
| Idempotency | 100% | `ansible-playbook --check` |
| Success Rate | > 99% | Log review |
| Node Coverage | 100% | `ansible all -m ping` |
| Playbook Quality | Zero warnings | `ansible-playbook --syntax-check` |

---

## 📝 Final Notes

### Best Practices
1. **Always use version control** - Git for all configurations
2. **Write idempotent playbooks** - Can be run multiple times safely
3. **Use roles for reusability** - Don't repeat yourself
4. **Keep secrets in Vault** - Never in plain text
5. **Test in staging** - Before production
6. **Document everything** - Comments and README

### Common Patterns
```yaml
# Idempotent task
- name: Ensure package installed
  package:
    name: nginx
    state: present

# Template with validation
- name: Deploy config
  template:
    src: app.conf.j2
    dest: /etc/app.conf
  validate: "app -t %s"

# Handler pattern
- name: Update config
  copy: src=config.conf dest=/etc/app.conf
  notify: restart app

# Error handling
- name: Attempt operation
  block:
    - name: Critical task
      command: /usr/bin/critical-command
  rescue:
    - name: Rollback
      command: /usr/bin/rollback
  always:
    - name: Cleanup
      command: /usr/bin/cleanup
```

---

## 🎉 Congratulations!

You have successfully implemented a complete Ansible Lab with:
- ✅ **Mixed OS Infrastructure** (Ubuntu + AlmaLinux)
- ✅ **Infrastructure as Code** (Vagrant)
- ✅ **Configuration Management** (Ansible)
- ✅ **Progressive Learning Path** (Beginner to Advanced)
- ✅ **Production Patterns** (Rolling updates, health checks)
- ✅ **Comprehensive Documentation** (This guide!)

### Next Steps
1. ✅ **Run your first playbook** - `ansible-playbook playbooks/01_basic/hello_world.yml`
2. ✅ **Explore all modules** - `ansible-doc -l`
3. ✅ **Create your own roles** - Reusable components
4. ✅ **Add more nodes** - Scale your infrastructure
5. ✅ **Integrate CI/CD** - GitHub Actions, Jenkins
6. ✅ **Automate everything** - Make it production-ready!

---

## 📖 Additional Resources

### Documentation
- [Ansible Official Documentation](https://docs.ansible.com/)
- [Vagrant Documentation](https://www.vagrantup.com/docs)
- [VirtualBox Documentation](https://www.virtualbox.org/wiki/Documentation)

### Practice Platforms
- [KodeKloud](https://kodekloud.com/)
- [Linux Academy](https://linuxacademy.com/)
- [A Cloud Guru](https://acloudguru.com/)

### Community
- [Ansible Community](https://github.com/ansible/community)
- [Reddit r/ansible](https://www.reddit.com/r/ansible/)
- [Stack Overflow](https://stackoverflow.com/questions/tagged/ansible)

---

**"Automation is the key to scalability and reliability"**

Happy Automating! 🚀