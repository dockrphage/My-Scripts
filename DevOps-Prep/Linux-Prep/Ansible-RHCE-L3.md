

This is Lesson 3 - a continuation from Lesson 1&2 of Ansible learning series with RHCE scope.
I already had a multi-node (rocky,ubuntu,debian) ansible lab configured from a previous project.
You can quickly spin up a multi-node ansible setup using instructions available here in a different topic.
You can try setting up containers for ansible setup if you dont have sufficient memory/ compute resources to setup VMs.

💡Pls note, My implimentation guides are AI‑generated for my specific env constraints; treat it as helpful starting points, not strict recipes.
🧩 AI adapts to each person’s context, so following my instructions verbatim can lead to mismatched results and unnecessary frustration.
🔍 Use my material as a base, explore freely, and collaborate with your own AI assistant.
🌟 Even if you end up somewhere completely different, you’ve still learned something valuable.




You must have completed Lessons 1 & 2 - time to dive into **Roles and Reusability**. 
This is a fairly long lessons; try to do multiple iterations instead of trying to understand everything in one go 🎯

## 🎯 Lesson 3: Roles, Galaxy, and Reusable Automation

### Objective
Create modular, reusable roles that can be shared across projects. We'll build a complete HPC role structure that follows best practices.

### Part 1: Understanding Role Structure

First, let's create a role structure:

```bash
cd /home/vagrant/hpc-ansible

# Create role directory structure
mkdir -p roles/hpc_base/{tasks,handlers,templates,files,vars,defaults,meta,tests}
mkdir -p roles/hpc_security/{tasks,handlers,templates,files,vars,defaults,meta}
mkdir -p roles/hpc_monitoring/{tasks,handlers,templates,files,vars,defaults,meta}
mkdir -p roles/hpc_slurm/{tasks,handlers,templates,files,vars,defaults,meta}

# Create role documentation
for role in hpc_base hpc_security hpc_monitoring hpc_slurm; do
    touch roles/$role/README.md
    touch roles/$role/meta/main.yml
    touch roles/$role/tests/test.yml
done

# Verify structure
tree roles/ -L 3
```

### Part 2: Build Your First Role - HPC Base

Create `roles/hpc_base/tasks/main.yml`:

```yaml
---
# HPC Base Role - Main Tasks
- name: Include OS-specific variables
  include_vars: "{{ ansible_os_family }}.yml"
  tags: always

- name: Include tasks based on OS family
  include_tasks: "{{ ansible_os_family }}.yml"
  tags: always

- name: Setup HPC directories
  include_tasks: directories.yml
  tags: directories

- name: Configure users and groups
  include_tasks: users.yml
  tags: users

- name: Install base packages
  include_tasks: packages.yml
  tags: packages

- name: Configure system settings
  include_tasks: system.yml
  tags: system

- name: Configure SSH
  include_tasks: ssh.yml
  tags: ssh
```

Create `roles/hpc_base/tasks/RedHat.yml`:

```yaml
---
# RedHat/CentOS/Rocky specific tasks
- name: Enable EPEL repository
  dnf:
    name: epel-release
    state: present
  when: ansible_distribution != "RedHat"  # RHEL has it differently

- name: Set SELinux to enforcing
  selinux:
    policy: targeted
    state: "{{ hpc_selinux_state | default('enforcing') }}"

- name: Configure tuned profile
  command: tuned-adm profile virtual-guest
  when: hpc_tuned_enabled | default(true)
```

Create `roles/hpc_base/tasks/Debian.yml`:

```yaml
---
# Debian/Ubuntu specific tasks
- name: Update apt cache
  apt:
    update_cache: yes
    cache_valid_time: 3600

- name: Install common Debian packages
  apt:
    name: "{{ hpc_debian_packages | default([]) }}"
    state: present
```

Create `roles/hpc_base/tasks/directories.yml`:

```yaml
---
# Directory structure tasks
- name: Create HPC directory structure
  file:
    path: "{{ item }}"
    state: directory
    owner: root
    group: root
    mode: '0755'
  loop:
    - /opt/hpc
    - /opt/hpc/bin
    - /opt/hpc/lib
    - /opt/hpc/logs
    - /opt/hpc/config
    - /var/log/hpc
  tags: directories

- name: Create application data directories
  file:
    path: "{{ hpc_data_dir | default('/data/hpc') }}/{{ item }}"
    state: directory
    owner: "{{ hpc_admin_user | default('hpcadmin') }}"
    group: "{{ hpc_admin_group | default('hpcadmin') }}"
    mode: '0755'
  loop:
    - apps
    - scratch
    - archives
    - benchmarks
  when: hpc_create_data_dirs | default(true)
  tags: directories
```

Create `roles/hpc_base/tasks/users.yml`:

```yaml
---
# User management tasks
- name: Create HPC admin group
  group:
    name: "{{ hpc_admin_group | default('hpcadmin') }}"
    state: present
    gid: "{{ hpc_admin_gid | default(1000) }}"

- name: Create HPC admin user
  user:
    name: "{{ hpc_admin_user | default('hpcadmin') }}"
    comment: "HPC Administrator"
    group: "{{ hpc_admin_group | default('hpcadmin') }}"
    groups: "{{ 'wheel' if ansible_os_family == 'RedHat' else 'sudo' }}"
    shell: /bin/bash
    createhome: yes
    generate_ssh_key: yes
    ssh_key_bits: 4096
    ssh_key_type: ed25519
    state: present

- name: Create HPC user groups
  group:
    name: "{{ item }}"
    state: present
  loop:
    - hpcusers
    - hpctest
    - hpcdev

- name: Configure sudo for admin
  lineinfile:
    path: /etc/sudoers.d/hpc_admin
    line: "{{ hpc_admin_user | default('hpcadmin') }} ALL=(ALL) NOPASSWD: ALL"
    create: yes
    validate: 'visudo -cf %s'
    mode: '0440'
```

Create `roles/hpc_base/tasks/packages.yml`:

```yaml
---
# Package installation tasks
- name: Install base packages for HPC
  package:
    name: "{{ hpc_base_packages[ansible_os_family] | default([]) }}"
    state: present
  when: hpc_base_packages is defined

- name: Install development tools
  package:
    name: "{{ hpc_dev_packages[ansible_os_family] | default([]) }}"
    state: present
  when: hpc_install_dev_tools | default(false)

- name: Install HPC-specific packages
  package:
    name: "{{ hpc_hpc_packages[ansible_os_family] | default([]) }}"
    state: present
  when: hpc_hpc_packages is defined
```

Create `roles/hpc_base/tasks/system.yml`:

```yaml
---
# System configuration tasks
- name: Configure sysctl for HPC
  sysctl:
    name: "{{ item.name }}"
    value: "{{ item.value }}"
    state: present
    reload: yes
  loop:
    - { name: 'vm.swappiness', value: '10' }
    - { name: 'vm.vfs_cache_pressure', value: '50' }
    - { name: 'net.core.rmem_max', value: '134217728' }
    - { name: 'net.core.wmem_max', value: '134217728' }
    - { name: 'net.ipv4.tcp_rmem', value: '4096 87380 134217728' }
    - { name: 'net.ipv4.tcp_wmem', value: '4096 65536 134217728' }
    - { name: 'net.core.somaxconn', value: '65535' }
  tags: sysctl

- name: Configure limits for HPC users
  pam_limits:
    domain: "{{ item.domain }}"
    limit_type: "{{ item.type }}"
    limit_item: "{{ item.item }}"
    value: "{{ item.value }}"
  loop:
    - { domain: 'hpcusers', type: 'hard', item: 'nproc', value: 'unlimited' }
    - { domain: 'hpcusers', type: 'soft', item: 'nproc', value: 'unlimited' }
    - { domain: 'hpcusers', type: 'hard', item: 'nofile', value: '65536' }
    - { domain: 'hpcusers', type: 'soft', item: 'nofile', value: '65536' }
    - { domain: '*', type: 'hard', item: 'memlock', value: 'unlimited' }
    - { domain: '*', type: 'soft', item: 'memlock', value: 'unlimited' }
  tags: limits

- name: Set timezone
  timezone:
    name: "{{ hpc_timezone | default('UTC') }}"
  tags: timezone

- name: Configure /etc/hosts
  lineinfile:
    path: /etc/hosts
    regexp: "^.*{{ item }}$"
    line: "{{ hpc_hosts[item] | default('') }}"
    state: present
  loop: "{{ hpc_hosts.keys() | list }}"
  when: hpc_hosts is defined
```

Create `roles/hpc_base/tasks/ssh.yml`:

```yaml
---
# SSH configuration tasks
- name: Configure SSH server
  lineinfile:
    path: /etc/ssh/sshd_config
    regexp: "^#?{{ item.option }}"
    line: "{{ item.option }} {{ item.value }}"
    state: present
  loop:
    - { option: 'PermitRootLogin', value: 'no' }
    - { option: 'PasswordAuthentication', value: 'no' }
    - { option: 'ChallengeResponseAuthentication', value: 'no' }
    - { option: 'UsePAM', value: 'yes' }
    - { option: 'X11Forwarding', value: 'yes' }
    - { option: 'PrintMotd', value: 'no' }
    - { option: 'ClientAliveInterval', value: '300' }
    - { option: 'ClientAliveCountMax', value: '2' }
    - { option: 'MaxAuthTries', value: '3' }
    - { option: 'Protocol', value: '2' }
  notify: restart sshd
  tags: ssh_config

- name: Deploy SSH banner
  copy:
    content: |
      *******************************************
      * WARNING: UNAUTHORIZED ACCESS PROHIBITED *
      * This system is for authorized users only *
      *******************************************
    dest: /etc/issue.net
    owner: root
    group: root
    mode: '0644'
  tags: ssh_banner

- name: Configure Motd
  template:
    src: motd.j2
    dest: /etc/motd
    owner: root
    group: root
    mode: '0644'
  tags: motd
```

Create `roles/hpc_base/handlers/main.yml`:

```yaml
---
- name: restart sshd
  service:
    name: "{{ 'sshd' if ansible_os_family == 'RedHat' else 'ssh' }}"
    state: restarted

- name: restart rsyslog
  service:
    name: rsyslog
    state: restarted

- name: update grub
  command: update-grub
  when: ansible_os_family == "Debian"
```

Create `roles/hpc_base/defaults/main.yml`:

```yaml
---
# Default variables for hpc_base role
hpc_admin_user: hpcadmin
hpc_admin_group: hpcadmin
hpc_admin_gid: 1000
hpc_environment: production
hpc_timezone: UTC
hpc_selinux_state: enforcing
hpc_tuned_enabled: true
hpc_install_dev_tools: false
hpc_create_data_dirs: true
hpc_data_dir: /data/hpc

# Base packages by OS family
hpc_base_packages:
  RedHat:
    - vim
    - curl
    - wget
    - git
    - htop
    - screen
    - tmux
    - bash-completion
    - telnet
    - net-tools
    - bind-utils
    - lsof
    - strace
    - tree
    - jq
    - yum-utils
  Debian:
    - vim
    - curl
    - wget
    - git
    - htop
    - screen
    - tmux
    - bash-completion
    - telnet
    - net-tools
    - dnsutils
    - lsof
    - strace
    - tree
    - jq
    - apt-transport-https

# Development packages
hpc_dev_packages:
  RedHat:
    - gcc
    - gcc-c++
    - make
    - automake
    - autoconf
    - libtool
    - cmake
    - kernel-devel
    - kernel-headers
    - perl
    - python3-devel
    - openmpi-devel
  Debian:
    - build-essential
    - gcc
    - g++
    - make
    - automake
    - autoconf
    - libtool
    - cmake
    - linux-headers-generic
    - perl
    - python3-dev
    - libopenmpi-dev

# HPC packages
hpc_hpc_packages:
  RedHat:
    - openssl-devel
    - libffi-devel
    - zlib-devel
    - bzip2-devel
    - readline-devel
    - sqlite-devel
    - expat-devel
    - gdbm-devel
    - tk-devel
    - ncurses-devel
    - openssh-clients
    - openssh-server
  Debian:
    - libssl-dev
    - libffi-dev
    - zlib1g-dev
    - libbz2-dev
    - libreadline-dev
    - libsqlite3-dev
    - libexpat1-dev
    - libgdbm-dev
    - tk-dev
    - libncurses5-dev
    - openssh-client
    - openssh-server
```

Create `roles/hpc_base/templates/motd.j2`:

```j2
********************************************
* HPC CLUSTER NODE
* Hostname: {{ ansible_hostname }}
* IP Address: {{ ansible_default_ipv4.address | default('N/A') }}
* OS: {{ ansible_distribution }} {{ ansible_distribution_version }}
* Kernel: {{ ansible_kernel }}
* Architecture: {{ ansible_architecture }}
* CPU Cores: {{ ansible_processor_cores }}
* Total Memory: {{ ansible_memory_mb.real.total }} MB
* Swap: {{ ansible_memory_mb.swap.total }} MB
* Environment: {{ hpc_environment }}
* Managed by: Ansible - Role: hpc_base
********************************************
```

Create `roles/hpc_base/vars/RedHat.yml`:

```yaml
---
# RedHat-specific variables
package_manager: dnf
ssh_service: sshd
firewall_service: firewalld
service_manager: systemd
```

Create `roles/hpc_base/vars/Debian.yml`:

```yaml
---
# Debian-specific variables
package_manager: apt
ssh_service: ssh
firewall_service: ufw
service_manager: systemd
```

### Part 3: Build HPC Security Role

Create `roles/hpc_security/tasks/main.yml`:

```yaml
---
# HPC Security Role
- name: Install security tools
  include_tasks: tools.yml
  tags: tools

- name: Configure firewall
  include_tasks: firewall.yml
  tags: firewall

- name: Configure audit
  include_tasks: audit.yml
  tags: audit

- name: Configure SELinux/AppArmor
  include_tasks: selinux.yml
  when: ansible_os_family == "RedHat"
  tags: selinux

- name: Configure fail2ban
  include_tasks: fail2ban.yml
  tags: fail2ban
```

Create `roles/hpc_security/tasks/firewall.yml`:

```yaml
---
# Firewall configuration
- name: Enable and configure firewalld (RedHat)
  firewalld:
    service: "{{ item }}"
    permanent: yes
    state: enabled
    immediate: yes
  loop:
    - ssh
    - http
    - https
  when: ansible_os_family == "RedHat"
  tags: firewalld

- name: Add custom firewall rules
  firewalld:
    port: "{{ item }}"
    permanent: yes
    state: enabled
    immediate: yes
  loop:
    - 8888/tcp  # Jupyter
    - 8787/tcp  # RStudio
    - 8786/tcp  # Dask
  when: ansible_os_family == "RedHat"
  tags: firewalld

- name: Enable and configure UFW (Ubuntu/Debian)
  ufw:
    rule: allow
    port: "{{ item.port }}"
    proto: "{{ item.proto }}"
  loop:
    - { port: '22', proto: 'tcp' }
    - { port: '80', proto: 'tcp' }
    - { port: '443', proto: 'tcp' }
    - { port: '8888', proto: 'tcp' }
    - { port: '8787', proto: 'tcp' }
  when: ansible_os_family == "Debian"
  tags: ufw

- name: Enable UFW
  ufw:
    state: enabled
  when: ansible_os_family == "Debian"
  tags: ufw

- name: Set default UFW policy
  ufw:
    direction: incoming
    policy: deny
  when: ansible_os_family == "Debian"
  tags: ufw
```

Create `roles/hpc_security/defaults/main.yml`:

```yaml
---
# Security role defaults
hpc_security_enable_firewall: true
hpc_security_enable_fail2ban: true
hpc_security_enable_audit: true
hpc_security_allowed_ssh_ips:
  - 192.168.56.0/24
  - 10.0.0.0/8

hpc_security_fail2ban_jails:
  - name: sshd
    enabled: true
    maxretry: 3
    bantime: 3600
    findtime: 600
```

### Part 4: Create a Playbook Using Roles

Create `playbooks/hpc-cluster.yml`:

```yaml
---
- name: HPC Cluster Full Deployment
  hosts: hpc_cluster
  gather_facts: yes
  become: yes
  
  vars:
    hpc_environment: production
    hpc_timezone: UTC
    hpc_admin_user: hpcadmin
    hpc_install_dev_tools: true
    hpc_create_data_dirs: true
    
  roles:
    - role: hpc_base
      tags: base
    - role: hpc_security
      tags: security
      
  post_tasks:
    - name: Deploy HPC environment check script
      copy:
        dest: /usr/local/bin/hpc-check.sh
        content: |
          #!/bin/bash
          echo "=== HPC NODE STATUS ==="
          echo "Hostname: $(hostname -f)"
          echo "OS: $(cat /etc/os-release | grep PRETTY_NAME | cut -d= -f2 | tr -d '\"')"
          echo "Uptime: $(uptime -p)"
          echo "Load: $(uptime | awk -F'load average:' '{print $2}')"
          echo "Memory: $(free -h | grep Mem | awk '{print $3 "/" $2}')"
          echo "Disk: $(df -h / | tail -1 | awk '{print $3 "/" $2 " (" $5 ")"}')"
          echo "==="
          echo "HPC Directories:"
          ls -la /opt/hpc /data/hpc 2>/dev/null | grep ^d
          echo "==="
          echo "HPC Users:"
          getent passwd | grep -E "hpcadmin|hpcusers"
          echo "=========================="
        mode: '0755'
        owner: root
        group: root
      tags: check_script

    - name: Display completion message
      debug:
        msg: |
          HPC Cluster deployment complete!
          Admin user: {{ hpc_admin_user }}
          Data directory: {{ hpc_data_dir }}
          Check script: /usr/local/bin/hpc-check.sh
      tags: always
```

### Part 5: Using Ansible Galaxy

```bash
# Install roles from Ansible Galaxy
ansible-galaxy install geerlingguy.docker
ansible-galaxy install geerlingguy.pip
ansible-galaxy install geerlingguy.nginx

# Create requirements file
cat > roles/requirements.yml << EOF
---
- src: geerlingguy.docker
  version: 6.0.0
- src: geerlingguy.pip
  version: 2.1.0
- src: geerlingguy.nginx
  version: 3.0.0
EOF

# Install from requirements
ansible-galaxy install -r roles/requirements.yml

# Create wrapper playbook for community roles
cat > playbooks/community-services.yml << EOF
---
- name: Install Community Services
  hosts: rocky1, rocky2
  become: yes
  
  roles:
    - role: geerlingguy.pip
      vars:
        pip_install_packages:
          - name: docker
          - name: docker-compose
    - role: geerlingguy.docker
      vars:
        docker_users:
          - hpcadmin
    - role: geerlingguy.nginx
      vars:
        nginx_vhosts:
          - listen: "80"
            server_name: "hpc-monitor.local"
            root: "/var/www/html"
EOF
```

### Part 6: Role Dependencies

Create `roles/hpc_slurm/meta/main.yml`:

```yaml
---
dependencies:
  - role: hpc_base
  - role: hpc_security
    vars:
      hpc_security_enable_firewall: true
      hpc_security_enable_fail2ban: false
      
galaxy_info:
  author: Your Name
  description: HPC SLURM Workload Manager
  company: HPC Team
  license: MIT
  min_ansible_version: 2.9
  platforms:
    - name: EL
      versions:
        - 8
        - 9
    - name: Ubuntu
      versions:
        - focal
        - jammy
  galaxy_tags:
    - hpc
    - slurm
    - cluster
    - scheduler
```

Create `roles/hpc_slurm/tasks/main.yml`:

```yaml
---
# SLURM role (placeholder - would be more complex in production)
- name: Install SLURM packages
  package:
    name: "{{ slurm_packages[ansible_os_family] | default([]) }}"
    state: present
  when: ansible_os_family in ['RedHat', 'Debian']

- name: Configure SLURM controller
  template:
    src: slurm.conf.j2
    dest: /etc/slurm/slurm.conf
    owner: root
    group: root
    mode: '0644'
  when: inventory_hostname in groups['slurm_controller']

- name: Configure SLURM nodes
  template:
    src: slurm.conf.j2
    dest: /etc/slurm/slurm.conf
    owner: root
    group: root
    mode: '0644'
  when: inventory_hostname in groups['slurm_compute']

- name: Start SLURM daemons
  service:
    name: "{{ item }}"
    state: started
    enabled: yes
  loop:
    - slurmctld
    - slurmd
```

## 🛠️ Practice Exercises

### Exercise 1: Create a Monitoring Role

Create `roles/hpc_monitoring` that:
1. Installs and configures `node_exporter` for Prometheus
2. Sets up `filebeat` to collect logs
3. Creates a health check script
4. Configures email alerts for critical conditions

### Exercise 2: Role Testing

```bash
# Test a role individually
ansible-playbook -i inventory/production/inventory.ini roles/hpc_base/tests/test.yml

# Test with specific tags
ansible-playbook -i inventory/production/inventory.ini playbooks/hpc-cluster.yml --tags "base,security" --check

# Test with limit
ansible-playbook -i inventory/production/inventory.ini playbooks/hpc-cluster.yml --limit rocky1 --check
```

### Exercise 3: Create a Requirements File

Create a `requirements.yml` that includes:
- hpc_base (local)
- hpc_security (local)  
- geerlingguy.docker (Galaxy)
- geerlingguy.pip (Galaxy)

### Exercise 4: Role Configuration

Create a playbook that:
1. Uses hpc_base role with custom variables
2. Overrides default package lists
3. Adds additional directories
4. Configure for a "development" environment

## 📚 Key RHCE Concepts for Roles

1. **Role Structure**: 
   ```
   role_name/
   ├── tasks/main.yml
   ├── handlers/main.yml
   ├── templates/
   ├── files/
   ├── vars/main.yml
   ├── defaults/main.yml
   ├── meta/main.yml
   └── tests/test.yml
   ```

2. **Variable Precedence** (in order):
   - Role defaults
   - Inventory group_vars
   - Playbook vars
   - Role vars
   - Extra vars (`-e`)

3. **Role Execution Flow**:
   - `pre_tasks`
   - Role tasks
   - `post_tasks`
   - Handlers

4. **Community Roles**:
   ```bash
   ansible-galaxy search "hpc" --platforms el
   ansible-galaxy info geerlingguy.docker
   ```

## 🚀 Advanced Role Patterns

### Role with Custom Facts
```yaml
# roles/hpc_base/tasks/facts.yml
- name: Create custom fact directory
  file:
    path: /etc/ansible/facts.d
    state: directory
    recurse: yes

- name: Install custom HPC fact
  template:
    src: hpc.fact.j2
    dest: /etc/ansible/facts.d/hpc.fact
    mode: '0755'

# In another task, access: ansible_local.hpc.role
```

### Role with Default Variables
```yaml
# roles/hpc_base/defaults/main.yml
hpc_config:
  master:
    memory_gb: 64
    cpu_cores: 16
  compute:
    memory_gb: 128
    cpu_cores: 32
```

## ✅ Success Criteria

Ready for Lesson 4 when you can:
- ✅ Create a complete role structure
- ✅ Separate tasks into OS-specific files
- ✅ Use role dependencies
- ✅ Install and use community roles from Galaxy
- ✅ Override role defaults with group/playbook vars
- ✅ Test roles individually
- ✅ Understand variable precedence with roles
- ✅ Create reusable, portable roles

## 🎯 Challenge: Production-Ready HPC Role

Create a single role `hpc_production` that:
1. Combines base, security, and monitoring
2. Uses conditional includes based on host groups
3. Has proper variable defaults
4. Includes README documentation
5. Passes ansible-lint
6. Has a test playbook

```bash
# Install ansible-lint
pip install ansible-lint

# Lint your role
ansible-lint roles/hpc_production/

# Test with molecule (advanced)
pip install molecule
molecule init role hpc_production
molecule test
```

