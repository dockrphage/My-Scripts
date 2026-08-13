

This is Lesson 2 - a continuation from Lesson 1 of Ansible learning series with RHCE scope.
I already had a multi-node (rocky,ubuntu,debian) ansible lab configured from a previous project.
You can quickly spin up a multi-node ansible setup using instructions available here in a different topic.
You can try setting up containers for ansible setup if you dont have sufficient memory/ compute resources to setup VMs.

Please note, this is an AI generated guide.

You've mastered ad-hoc commands in Lesson 1 - now let's level up to **playbooks**. 

## 🎯 Lesson 2: Playbook Fundamentals

### Objective
Create your first production-ready playbooks with proper structure, variables, and error handling. We'll build an HPC node initialization playbook.

### Part 1: Project Structure Setup

First, let's create a proper Ansible project structure:

```bash
cd /home/vagrant/hpc-ansible

# Create directory structure
mkdir -p playbooks/{base,monitoring,security}
mkdir -p roles
mkdir -p group_vars/{rocky,ubuntu,debian_family,all}
mkdir -p host_vars/{rocky1,rocky2,rocky3,ubuntu1,ubuntu2,bookworm1}
mkdir -p files/ssh
mkdir -p templates

# Verify structure
tree -L 3
```

### Part 2: Your First Playbook - Base Configuration

Create `playbooks/base/01-initial-setup.yml`:

```yaml
---
- name: HPC Cluster - Initial Base Configuration
  hosts: hpc_cluster
  gather_facts: yes
  become: yes
  
  vars:
    hpc_admin_user: hpcadmin
    hpc_shared_dir: /opt/hpc
    motd_message: "Welcome to HPC Cluster - Managed by Ansible"
    
  tasks:
    # Task 1: Update package cache (OS-specific)
    - name: Update package cache on RHEL family
      dnf:
        update_cache: yes
      when: ansible_os_family == "RedHat"
      
    - name: Update package cache on Debian family
      apt:
        update_cache: yes
      when: ansible_os_family == "Debian"
    
    # Task 2: Install common packages
    - name: Install base packages on RHEL
      dnf:
        name:
          - vim
          - curl
          - wget
          - git
          - htop
          - screen
          - tmux
          - bash-completion
          - epel-release
        state: present
      when: ansible_os_family == "RedHat"
      
    - name: Install base packages on Debian
      apt:
        name:
          - vim
          - curl
          - wget
          - git
          - htop
          - screen
          - tmux
          - bash-completion
        state: present
      when: ansible_os_family == "Debian"
    
    # Task 3: Create admin user
    - name: Create HPC admin user
      user:
        name: "{{ hpc_admin_user }}"
        state: present
        shell: /bin/bash
        groups: "{{ 'wheel' if ansible_os_family == 'RedHat' else 'sudo' }}"
        append: yes
        create_home: yes
        generate_ssh_key: yes
        ssh_key_bits: 2048
        ssh_key_file: .ssh/id_rsa
        
    # Task 4: Setup shared directory
    - name: Create shared directory
      file:
        path: "{{ hpc_shared_dir }}"
        state: directory
        owner: "{{ hpc_admin_user }}"
        group: "{{ hpc_admin_user }}"
        mode: '0755'
        
    # Task 5: Deploy MOTD
    - name: Deploy custom MOTD
      copy:
        content: |
          ********************************************
          * {{ motd_message }}
          * Host: {{ ansible_hostname }}
          * OS: {{ ansible_distribution }} {{ ansible_distribution_version }}
          * CPU: {{ ansible_processor_cores }} cores
          * RAM: {{ ansible_memory_mb.real.total }} MB
          ********************************************
        dest: /etc/motd
        owner: root
        group: root
        mode: '0644'
        
    # Task 6: Configure SSH hardening
    - name: Disable root SSH login
      lineinfile:
        path: /etc/ssh/sshd_config
        regexp: '^PermitRootLogin'
        line: 'PermitRootLogin no'
      notify: restart sshd
      
    - name: Disable password authentication
      lineinfile:
        path: /etc/ssh/sshd_config
        regexp: '^PasswordAuthentication'
        line: 'PasswordAuthentication no'
      notify: restart sshd
      
    # Task 7: Set timezone
    - name: Set timezone to UTC
      timezone:
        name: UTC
        
    # Task 8: Create simple monitoring script
    - name: Deploy node health check script
      copy:
        dest: /usr/local/bin/node_health.sh
        content: |
          #!/bin/bash
          echo "=== NODE HEALTH CHECK ==="
          echo "Hostname: $(hostname)"
          echo "Uptime: $(uptime -p)"
          echo "Load: $(uptime | awk -F'load average:' '{print $2}')"
          echo "Disk Usage:"
          df -h | grep -E '^/dev'
          echo "Memory Usage:"
          free -h
          echo "=== END HEALTH CHECK ==="
        mode: '0755'
        owner: root
        group: root
        
  handlers:
    - name: restart sshd
      service:
        name: "{{ 'sshd' if ansible_os_family == 'RedHat' else 'ssh' }}"
        state: restarted
```

### Part 3: Run Your First Playbook

```bash
# Syntax check (always do this first!)
ansible-playbook -i inventory/production/inventory.ini playbooks/base/01-initial-setup.yml --syntax-check

# Dry run (see what would change)
ansible-playbook -i inventory/production/inventory.ini playbooks/base/01-initial-setup.yml --check --diff

# Actually run it!
ansible-playbook -i inventory/production/inventory.ini playbooks/base/01-initial-setup.yml --ask-become-pass
```

### Part 4: Using Group Variables

Create `group_vars/all/00-common.yml`:

```yaml
---
# Global variables for all nodes
hpc_environment: production
hpc_owner: "HPC Team"
hpc_contact_email: "hpc-admin@example.com"

# Default package lists
base_packages_redhat:
  - vim
  - curl
  - wget
  - htop
  
base_packages_debian:
  - vim
  - curl
  - wget
  - htop
  
# NTP servers
ntp_servers:
  - pool.ntp.org
  - time.google.com
```

Create `group_vars/rocky/00-rocky-specific.yml`:

```yaml
---
# Rocky-specific variables
package_manager: dnf
ssh_service: sshd
firewall_service: firewalld
selinux_state: enforcing

# Rocky specific packages
rocky_packages:
  - tuned
  - systemd-resolved
```

Create `group_vars/ubuntu/00-ubuntu-specific.yml`:

```yaml
---
# Ubuntu-specific variables
package_manager: apt
ssh_service: ssh
firewall_service: ufw
ubuntu_packages:
  - net-tools
  - ifupdown
```

### Part 5: Advanced Playbook - Package Management

Create `playbooks/base/02-package-management.yml`:

```yaml
---
- name: HPC Cluster - Package Management
  hosts: hpc_cluster
  become: yes
  gather_facts: yes
  
  tasks:
    # Use group variables to handle OS differences
    - name: Install OS-specific packages
      package:
        name: "{{ item }}"
        state: present
      loop: "{{ 'rocky_packages' if ansible_os_family == 'RedHat' else 'ubuntu_packages' | default([]) }}"
      when: ansible_os_family in ['RedHat', 'Debian']
      ignore_errors: yes
      
    # Conditional package installation
    - name: Install development tools on Rocky nodes
      dnf:
        name:
          - gcc
          - make
          - automake
          - gcc-c++
          - kernel-devel
        state: present
      when: ansible_os_family == "RedHat"
      
    - name: Install development tools on Ubuntu nodes
      apt:
        name:
          - build-essential
          - make
          - gcc
          - g++
        state: present
      when: ansible_os_family == "Debian"
      
    # Upgrade all packages (use with caution!)
    - name: Upgrade all packages (dry-run mode)
      package:
        name: "*"
        state: latest
      check_mode: yes
      register: upgrade_result
      
    - name: Show upgrade results
      debug:
        msg: "Would upgrade {{ upgrade_result.changed }} packages"
      when: upgrade_result.changed is defined
      
    # Clean package cache
    - name: Clean DNF cache (Rocky)
      command: dnf clean all
      when: ansible_os_family == "RedHat"
      args:
        warn: no
      
    - name: Clean APT cache (Ubuntu/Debian)
      apt:
        autoclean: yes
      when: ansible_os_family == "Debian"
```

### Part 6: Playbook with Conditionals and Loops

Create `playbooks/base/03-user-management.yml`:

```yaml
---
- name: HPC Cluster - Advanced User Management
  hosts: hpc_cluster
  become: yes
  vars:
    hpc_users:
      - name: alice
        groups: "{{ 'wheel' if ansible_os_family == 'RedHat' else 'sudo' }}"
        comment: "HPC User Alice"
        shell: /bin/bash
      - name: bob
        groups: "{{ 'wheel' if ansible_os_family == 'RedHat' else 'sudo' }}"
        comment: "HPC User Bob"
        shell: /bin/bash
        
  tasks:
    - name: Create HPC users
      user:
        name: "{{ item.name }}"
        groups: "{{ item.groups }}"
        comment: "{{ item.comment }}"
        shell: "{{ item.shell }}"
        state: present
        create_home: yes
        generate_ssh_key: yes
      loop: "{{ hpc_users }}"
      when: ansible_os_family in ['RedHat', 'Debian']
      
    - name: Set up user SSH directories
      file:
        path: "/home/{{ item.name }}/.ssh"
        state: directory
        owner: "{{ item.name }}"
        group: "{{ item.name }}"
        mode: '0700'
      loop: "{{ hpc_users }}"
      
    - name: Add authorized keys for users
      authorized_key:
        user: "{{ item.name }}"
        key: "{{ lookup('file', 'files/ssh/{{ item.name }}.pub') }}"
        state: present
      loop: "{{ hpc_users }}"
      when: item.name in ['alice', 'bob']
      
    - name: Add sudoers entries for HPC users
      lineinfile:
        path: /etc/sudoers
        line: "{{ item.name }} ALL=(ALL) NOPASSWD: ALL"
        validate: 'visudo -cf %s'
      loop: "{{ hpc_users }}"
      when: ansible_os_family == "RedHat"
```

### Part 7: Error Handling in Playbooks

Create `playbooks/base/04-error-handling.yml`:

```yaml
---
- name: HPC Cluster - Error Handling Examples
  hosts: hpc_cluster
  become: yes
  
  tasks:
    # Block with rescue for error handling
    - block:
        - name: Try to install a potentially problematic package
          package:
            name: "{{ item }}"
            state: present
          loop:
            - some-package-that-may-fail
            - another-package
            
      rescue:
        - name: Handle package installation failure
          debug:
            msg: "Package installation failed on {{ ansible_hostname }}"
            
        - name: Log failure to file
          copy:
            content: |
              Package installation failed on {{ ansible_hostname }}
              Time: {{ ansible_date_time.iso8601 }}
              OS: {{ ansible_distribution }}
            dest: "/tmp/package_failure_{{ ansible_hostname }}.log"
            
      always:
        - name: This always runs
          debug:
            msg: "Package installation attempt completed on {{ ansible_hostname }}"
            
    # Ignore failures
    - name: Attempt to stop service (ignoring errors)
      service:
        name: "{{ 'httpd' if ansible_os_family == 'RedHat' else 'apache2' }}"
        state: stopped
      ignore_errors: yes
      register: service_result
      
    - name: Check service result
      debug:
        msg: "Service stop {{ 'succeeded' if service_result is success else 'failed' }}"
        
    # Fail when condition met
    - name: Fail if not enough memory
      fail:
        msg: "{{ ansible_hostname }} has insufficient memory ({{ ansible_memory_mb.real.total }} MB)"
      when: ansible_memory_mb.real.total < 1000
```

## 🛠️ Practice Exercises

### Exercise 1: Create a Playbook for NTP Setup

Create `playbooks/base/05-ntp-setup.yml` that:
1. Installs `chrony` on Rocky nodes, `ntp` on Ubuntu
2. Configures `/etc/chrony.conf` or `/etc/ntp.conf` with your NTP servers
3. Starts and enables the service
4. Verifies time synchronization

```yaml
# Start with this skeleton
---
- name: HPC Cluster - NTP Configuration
  hosts: hpc_cluster
  become: yes
  vars:
    ntp_servers:
      - 0.pool.ntp.org
      - 1.pool.ntp.org
      
  tasks:
    # Your tasks here...
```

### Exercise 2: Create a Playbook for Firewall Configuration

Create `playbooks/security/01-firewall.yml`:
- Use `firewalld` on Rocky, `ufw` on Ubuntu
- Open ports: 22, 80, 443
- Allow specific IP ranges for SSH (use your subnet: 192.168.56.0/24)

### Exercise 3: Playbook for System Health Monitoring

Create `playbooks/monitoring/01-health-check.yml`:
- Check disk space (> 80% warning)
- Check memory usage (> 90% warning)
- Check service status (sshd, rsyslog)
- Generate a summary report

### Exercise 4: Use Tags in Playbooks

Add tags to your existing playbooks and run specific sections:
```bash
ansible-playbook -i inventory/production/inventory.ini playbooks/base/01-initial-setup.yml --tags "users,packages"
```

## 📚 Key RHCE Concepts Learned

1. **Playbook Structure**: `---`, `name`, `hosts`, `become`, `tasks`, `handlers`
2. **Variables**: Inline `vars:`, group_vars, host_vars
3. **Conditionals**: `when`, `block/rescue/always`
4. **Loops**: `loop`, `loop_control`, nested loops
5. **Error Handling**: `ignore_errors`, `fail`, `register` + `is success`
6. **Handlers**: Notify and restart services
7. **Tags**: Run specific sections of playbooks
8. **Check Mode**: `--check`, `--diff`

## 🚀 Pro Tips for RHCE

```bash
# Always validate YAML syntax first
ansible-playbook playbook.yml --syntax-check

# Use verbose mode for debugging
ansible-playbook playbook.yml -vvv

# Limit to specific hosts
ansible-playbook playbook.yml --limit rocky1

# Step through playbook (interactive)
ansible-playbook playbook.yml --step

# Use --list-tasks to see what will run
ansible-playbook playbook.yml --list-tasks

# Use --start-at-task to resume from a specific task
ansible-playbook playbook.yml --start-at-task "Install packages"
```

## ✅ Success Criteria

You're ready for Lesson 3 when you can:
- ✅ Write playbooks with proper YAML syntax and structure
- ✅ Use variables from multiple sources (vars, group_vars, host_vars)
- ✅ Implement OS-conditional tasks
- ✅ Use loops and conditionals effectively
- ✅ Handle errors with block/rescue/always
- ✅ Use tags to control execution
- ✅ Run playbooks with check mode and different verbosity levels

## 🎯 Challenge: Complete HPC Node Setup

Create a single playbook `playbooks/hpc-provision.yml` that:
1. Does everything from Lessons 1-2
2. Handles both OS families seamlessly
3. Includes proper error handling
4. Uses variables for customization
5. Has tags for: `users`, `packages`, `security`, `monitoring`, `all`

**Bonus:** Add a `pre_tasks` and `post_tasks` section.
