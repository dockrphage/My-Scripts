This is intended as a a comprehensive learning series with Vagrant VMs for Ansible mastery. Completely setup in local laptop env, this lab gives the luxury of repeating the setup to gain muscle memory without incurring cloud costs. Below doc is my initial draft with several blockers and errors. For learning purposes, this is a good thing . With each error, we pause, troubleshoot and learn.

The finished implimentation plan with fewer issues is published as a different doc in this repo/ folder.


## Architecture Overview

### Network Design
- **Host-only Network**: 192.168.56.0/24 (stable, isolated management network)
- **Bridged Network**: 192.168.1.0/24 (same subnet as host for external access)
- **Host Machine**: Ubuntu laptop acting as Ansible control node

## Complete Vagrantfile

```ruby
# -*- mode: ruby -*-
# vi: set ft=ruby :

Vagrant.configure("2") do |config|
  # Base box configuration
  config.vm.box = "ubuntu/focal64"
  
  # Define nodes
  nodes = {
    "node1" => { 
      ip: "192.168.56.10", 
      bridged_ip: "192.168.1.50", 
      cpu: 2, 
      mem: 2048,
      os: "ubuntu"
    },
    "node2" => { 
      ip: "192.168.56.11", 
      bridged_ip: "192.168.1.51", 
      cpu: 1, 
      mem: 2048,
      os: "centos"
    },
    "node3" => { 
      ip: "192.168.56.12", 
      bridged_ip: "192.168.1.52", 
      cpu: 1, 
      mem: 2048,
      os: "ubuntu"
    },
    "node4" => { 
      ip: "192.168.56.13", 
      bridged_ip: "192.168.1.53", 
      cpu: 1, 
      mem: 2048,
      os: "centos"
    },
    "node5" => { 
      ip: "192.168.56.14", 
      bridged_ip: "192.168.1.54", 
      cpu: 1, 
      mem: 2048,
      os: "ubuntu"
    }
  }

  # Configure each node
  nodes.each do |node_name, node_config|
    config.vm.define node_name do |node|
      # Set box based on OS
      if node_config[:os] == "ubuntu"
        node.vm.box = "ubuntu/focal64"
        node.vm.provision "shell", inline: <<-SHELL
          apt-get update
          apt-get install -y python3 python3-pip python3-apt
          # Disable password authentication for ansible
          sed -i 's/^PasswordAuthentication .*/PasswordAuthentication no/' /etc/ssh/sshd_config
          systemctl restart sshd
        SHELL
      else
        node.vm.box = "centos/8"
        node.vm.provision "shell", inline: <<-SHELL
          dnf install -y python3 python3-pip
          # Disable password authentication for ansible
          sed -i 's/^PasswordAuthentication .*/PasswordAuthentication no/' /etc/ssh/sshd_config
          systemctl restart sshd
        SHELL
      end

      # Host-only network (management)
      node.vm.network "private_network", 
        ip: node_config[:ip],
        netmask: "255.255.255.0"
      
      # Bridged network (external access)
      node.vm.network "public_network", 
        ip: node_config[:bridged_ip],
        bridge: "en0: Wi-Fi (AirPort)", # Change this to your interface
        netmask: "255.255.255.0"
      
      # VirtualBox settings
      node.vm.provider "virtualbox" do |vb|
        vb.memory = node_config[:mem]
        vb.cpus = node_config[:cpu]
        vb.name = node_name
        vb.customize ["modifyvm", :id, "--natdnshostresolver1", "on"]
      end

      # SSH settings
      node.vm.provision "shell", inline: <<-SHELL
        mkdir -p /root/.ssh
        chmod 700 /root/.ssh
        # Generate SSH key for ansible
        ssh-keygen -t rsa -b 4096 -f /root/.ssh/id_rsa -N ""
        cp /root/.ssh/id_rsa.pub /root/.ssh/authorized_keys
        chmod 600 /root/.ssh/authorized_keys
      SHELL

      # Additional provisioning based on node type
      if node_name == "node1"
        node.vm.provision "shell", inline: <<-SHELL
          # Install additional tools on node1
          apt-get install -y docker.io docker-compose
          systemctl enable docker
          systemctl start docker
          usermod -aG docker vagrant
        SHELL
      end
    end
  end

  # Master provisioner (Ansible on host)
  config.vm.provision "shell", inline: <<-SHELL
    echo "Vagrant VMs are ready!"
    echo "=========================================="
    echo "Node IPs:"
    echo "node1: 192.168.56.10 (host-only), 192.168.1.50 (bridged)"
    echo "node2: 192.168.56.11 (host-only), 192.168.1.51 (bridged)"
    echo "node3: 192.168.56.12 (host-only), 192.168.1.52 (bridged)"
    echo "node4: 192.168.56.13 (host-only), 192.168.1.53 (bridged)"
    echo "node5: 192.168.56.14 (host-only), 192.168.1.54 (bridged)"
    echo "=========================================="
  SHELL
end
```

## Project Structure

```
ansible-learning-series/
├── Vagrantfile
├── ansible/
│   ├── ansible.cfg
│   ├── inventory/
│   │   ├── production/
│   │   │   ├── hosts
│   │   │   └── group_vars/
│   │   │       ├── all.yml
│   │   │       ├── webservers.yml
│   │   │       └── databases.yml
│   │   └── staging/
│   │       ├── hosts
│   │       └── group_vars/
│   ├── playbooks/
│   │   ├── 01_basic/
│   │   ├── 02_variables/
│   │   ├── 03_conditionals/
│   │   ├── 04_loops/
│   │   ├── 05_handlers/
│   │   ├── 06_roles/
│   │   ├── 07_templates/
│   │   ├── 08_facts/
│   │   ├── 09_jinja2/
│   │   ├── 10_dynamic_inventory/
│   │   ├── 11_error_handling/
│   │   ├── 12_awx_tower/
│   │   └── 13_production/
│   ├── roles/
│   │   ├── common/
│   │   ├── webserver/
│   │   ├── database/
│   │   ├── monitoring/
│   │   └── security/
│   ├── templates/
│   └── files/
└── scripts/
    ├── setup-ansible-host.sh
    └── generate-ssh-keys.sh
```

## Ansible Configuration

**ansible/ansible.cfg:**
```ini
[defaults]
inventory = ./inventory/production/hosts
host_key_checking = False
forks = 10
timeout = 30
gathering = smart
fact_caching = jsonfile
fact_caching_connection = /tmp/ansible_facts
fact_caching_timeout = 3600
retry_files_enabled = False
stdout_callback = yaml
callback_whitelist = profile_tasks

[ssh_connection]
pipelining = True
control_path = /tmp/ansible-%%h-%%p-%%r
```

**ansible/inventory/production/hosts:**
```ini
[all]
node1 ansible_host=192.168.56.10 ansible_user=root
node2 ansible_host=192.168.56.11 ansible_user=root
node3 ansible_host=192.168.56.12 ansible_user=root
node4 ansible_host=192.168.56.13 ansible_user=root
node5 ansible_host=192.168.56.14 ansible_user=root

[webservers]
node1
node2
node3

[databases]
node4
node5

[loadbalancers]
node1

[monitoring]
node5

[ubuntu:children]
webservers

[centos:children]
databases
```

## Learning Series Curriculum

### Phase 1: Foundation (Weeks 1-2)

**01_basic/hello_world.yml:**
```yaml
---
- name: Basic Hello World Playbook
  hosts: all
  tasks:
    - name: Print system information
      debug:
        msg: "Hello from {{ ansible_hostname }} running {{ ansible_distribution }}"

    - name: Check connectivity
      ping:
```

**01_basic/package_management.yml:**
```yaml
---
- name: Package Management Basics
  hosts: all
  tasks:
    - name: Update package cache (Ubuntu)
      apt:
        update_cache: yes
      when: ansible_distribution == "Ubuntu"

    - name: Update package cache (CentOS)
      dnf:
        update_cache: yes
      when: ansible_distribution == "CentOS"

    - name: Install common packages
      package:
        name:
          - git
          - vim
          - curl
          - wget
          - net-tools
        state: present
```

**02_variables/variable_usage.yml:**
```yaml
---
- name: Variables and Facts
  hosts: all
  vars:
    app_name: myapp
    app_port: 8080
    app_env: production

  tasks:
    - name: Display variables
      debug:
        msg: 
          - "Application: {{ app_name }}"
          - "Port: {{ app_port }}"
          - "Environment: {{ app_env }}"
          - "OS Family: {{ ansible_os_family }}"
          - "IP Address: {{ ansible_default_ipv4.address }}"

    - name: Set fact dynamically
      set_fact:
        deployment_path: "/opt/{{ app_name }}"

    - name: Show dynamic fact
      debug:
        var: deployment_path
```

### Phase 2: Intermediate (Weeks 3-4)

**04_loops/loop_examples.yml:**
```yaml
---
- name: Loop Examples
  hosts: all
  tasks:
    - name: Create multiple users
      user:
        name: "{{ item }}"
        state: present
        shell: /bin/bash
      loop:
        - deployer
        - monitor
        - backup

    - name: Install multiple packages with dict
      package:
        name: "{{ item.name }}"
        state: "{{ item.state }}"
      loop:
        - { name: nginx, state: present }
        - { name: postgresql, state: absent }
        - { name: redis, state: latest }

    - name: Loop with index
      debug:
        msg: "User {{ index }} is {{ item }}"
      loop:
        - alice
        - bob
        - charlie
      loop_control:
        index_var: index
```

**06_roles/web_server_role.yml:**
```yaml
---
- name: Deploy Web Server Role
  hosts: webservers
  roles:
    - common
    - webserver
    - security

- name: Configure Load Balancer
  hosts: loadbalancers
  roles:
    - common
    - loadbalancer
    - security

- name: Setup Monitoring
  hosts: monitoring
  roles:
    - common
    - monitoring
    - security
```

### Phase 3: Advanced (Weeks 5-6)

**10_dynamic_inventory/aws_inventory.yml:**
```yaml
---
plugin: aws_ec2
regions:
  - us-east-1
  - us-west-2
keyed_groups:
  - key: tags.Role
    prefix: role
  - key: tags.Environment
    prefix: env
  - key: placement.region
    prefix: aws_region
filters:
  instance-state-name: running
  tag:Environment: production
```

**11_error_handling/error_handling.yml:**
```yaml
---
- name: Error Handling Examples
  hosts: all
  any_errors_fatal: false
  max_fail_percentage: 20

  tasks:
    - name: Attempt dangerous operation
      command: /usr/bin/dangerous-command
      register: result
      ignore_errors: true
      failed_when: 
        - result.rc != 0
        - "'ERROR' in result.stderr"

    - name: Handle failure with block
      block:
        - name: Try to start service
          service:
            name: nginx
            state: started
          register: service_start

      rescue:
        - name: Handle service failure
          debug:
            msg: "Failed to start nginx: {{ service_start.msg }}"
          
        - name: Send alert
          command: /usr/bin/send-alert "Nginx failed on {{ inventory_hostname }}"

      always:
        - name: Always run this
          debug:
            msg: "This runs regardless of success or failure"
```

**13_production/production_deployment.yml:**
```yaml
---
- name: Production Deployment Pipeline
  hosts: all
  become: yes
  serial: 1  # Rolling update
  pre_tasks:
    - name: Backup configuration
      archive:
        path: /etc/app
        dest: /tmp/backup_{{ ansible_date_time.date }}.tar.gz

  tasks:
    - name: Deploy new version
      include_role:
        name: app_deploy

    - name: Health check
      uri:
        url: "http://{{ ansible_default_ipv4.address }}:8080/health"
        status_code: 200
      register: health_check
      until: health_check.status == 200
      retries: 10
      delay: 5

  post_tasks:
    - name: Update monitoring
      include_role:
        name: monitoring_update

    - name: Deployment notification
      debug:
        msg: "Deployment complete on {{ inventory_hostname }}"
```

## Setup Scripts

**scripts/setup-ansible-host.sh:**
```bash
#!/bin/bash
# Setup Ansible on host Ubuntu laptop

# Install Ansible
sudo apt update
sudo apt install -y ansible python3-pip python3-venv

# Install Ansible collections
ansible-galaxy collection install community.general
ansible-galaxy collection install community.docker
ansible-galaxy collection install amazon.aws

# Setup SSH keys
ssh-keygen -t rsa -b 4096 -f ~/.ssh/ansible -N ""

# Copy SSH keys to nodes
for node in node1 node2 node3 node4 node5; do
    sshpass -p 'vagrant' ssh-copy-id -i ~/.ssh/ansible.pub vagrant@$node
done

# Create ansible directory structure
mkdir -p ~/ansible-learning/{playbooks,roles,inventory,templates,files}

# Copy ansible.cfg
cat > ~/ansible-learning/ansible.cfg <<EOF
[defaults]
inventory = ./inventory/hosts
host_key_checking = False
timeout = 30
gathering = smart
fact_caching = jsonfile
fact_caching_connection = /tmp/ansible_facts
stdout_callback = yaml
EOF

echo "Ansible setup complete!"
```

## Vagrant Commands

```bash
# Start all VMs
vagrant up

# Start specific VM
vagrant up node1

# SSH into VM
vagrant ssh node1

# Suspend all VMs
vagrant suspend

# Resume all VMs
vagrant resume

# Destroy all VMs
vagrant destroy -f

# Reload with provisioning
vagrant reload --provision

# Check status
vagrant status
```

## Ansible Commands for Each Phase

### Basic Commands
```bash
# Test connectivity
ansible all -m ping

# Run ad-hoc commands
ansible webservers -m shell -a "uptime"

# Gather facts
ansible all -m setup -a "filter=ansible_distribution*"

# Execute playbook
ansible-playbook playbooks/01_basic/hello_world.yml
```

### Intermediate Commands
```bash
# Run with extra variables
ansible-playbook playbooks/03_variables/variable_usage.yml -e "app_env=staging"

# Dry run
ansible-playbook playbooks/05_handlers/ -C

# Limit to specific hosts
ansible-playbook playbooks/06_roles/web_server_role.yml --limit node1,node2
```

### Advanced Commands
```bash
# Run with logging
ansible-playbook playbooks/10_dynamic_inventory/deploy.yml -v

# Check syntax
ansible-playbook playbooks/13_production/production_deployment.yml --syntax-check

# Step mode (confirm each task)
ansible-playbook playbooks/13_production/production_deployment.yml --step
```

## Sample Role Structure

**roles/common/tasks/main.yml:**
```yaml
---
- name: Update system
  package:
    name: "*"
    state: latest
  when: ansible_os_family != "Windows"

- name: Install essential packages
  package:
    name:
      - htop
      - iotop
      - nload
      - tmux
    state: present

- name: Setup timezone
  timezone:
    name: UTC

- name: Configure logging
  copy:
    dest: /etc/rsyslog.d/99-ansible.conf
    content: |
      # Custom logging for ansible managed hosts
      *.info;mail.none;authpriv.none;cron.none /var/log/messages
    owner: root
    group: root
    mode: '0644'
  notify: restart rsyslog

- name: Setup monitoring agent
  include_role:
    name: monitoring_agent
  when: ansible_facts.hostname in groups['monitoring']
```

**handlers/main.yml:**
```yaml
---
- name: restart rsyslog
  service:
    name: rsyslog
    state: restarted

- name: restart nginx
  service:
    name: nginx
    state: restarted
  when: ansible_os_family != "Windows"
```

## Testing Script

```python
#!/usr/bin/env python3
# test_ansible_learning.py

import subprocess
import time

def run_test(playbook):
    """Test a playbook and return results"""
    cmd = ["ansible-playbook", playbook, "-C"]
    result = subprocess.run(cmd, capture_output=True, text=True)
    return result.returncode == 0, result.stdout, result.stderr

def main():
    playbooks = [
        "playbooks/01_basic/hello_world.yml",
        "playbooks/02_variables/variable_usage.yml",
        "playbooks/06_roles/web_server_role.yml"
    ]
    
    for playbook in playbooks:
        print(f"\nTesting {playbook}...")
        success, stdout, stderr = run_test(playbook)
        if success:
            print("✅ PASSED")
        else:
            print("❌ FAILED")
            print(stderr)

if __name__ == "__main__":
    main()
```

## Best Practices Included

1. **Version Control**: Use Git for all configurations
2. **Idempotency**: All playbooks are idempotent
3. **Modularity**: Use roles for reusable components
4. **Security**: SSH key-based authentication, no passwords
5. **Monitoring**: Health checks and logging
6. **Rolling Updates**: Serial deployment with health checks
7. **Error Handling**: Graceful failure recovery
8. **Testing**: Dry-run and syntax checking
9. **Documentation**: Comments in playbooks
10. **CI/CD Ready**: Can be integrated with Jenkins/GitHub Actions

This architecture provides a complete learning environment that scales from basic to advanced Ansible usage, with practical, real-world scenarios and best practices built in.