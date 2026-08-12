

Lesson2: **Cross-platform patching with intelligent rollback**.

This is a **core operational task** that an HPC engineers do daily: 

This lesson will teach you:
- Conditional logic for mixed OS environments
- Pre/post-patch validation
- Automated reboot handling
- **Rollback procedures** (critical for HPC where a bad patch can break MPI jobs)


Prerequisite: In Lesson 1, you must have already configured your Ansible master/ client setup (control/ managed nodes), created your inventory file and confirmed connectivity across all 6 (or as many as you like) nodes.
Note: The code here will give you some errors. 

---

## Lesson 2: The Production-Ready Patching Playbook

### The Objective
Create a playbook that:
1. **Checks** for available security patches on all nodes
2. **Installs** patches based on OS family (dnf for Rocky, apt for Ubuntu/Debian)
3. **Handles** kernel updates gracefully with conditional reboots
4. **Records** exactly what changed
5. **Provides rollback capability** if something breaks

---

## Step 1: Create the Patching Role Structure

Create these directories and files:

```bash
cd ~/hpc-ansible

# Create role directories
mkdir -p roles/patching/{tasks,handlers,templates,vars}

# Create the main tasks file
touch roles/patching/tasks/main.yml
touch roles/patching/handlers/main.yml
touch roles/patching/vars/main.yml
```

---

## Step 2: Create the Patching Role - Main Tasks

**`~/hpc-ansible/roles/patching/tasks/main.yml`**:

```yaml
---
# ============================================
# ROLE: patching
# Purpose: Cross-platform patch management
# Supports: Rocky (dnf), Ubuntu/Debian (apt)
# ============================================

- name: Include OS-specific variables
  include_vars: "{{ ansible_os_family | lower }}.yml"
  ignore_errors: yes

- name: Pre-patch - Gather installed package list
  shell: |
    {% if ansible_os_family == 'RedHat' %}
    rpm -qa --last | head -20
    {% elif ansible_os_family == 'Debian' %}
    grep " install " /var/log/dpkg.log | tail -20
    {% endif %}
  register: pre_patch_packages
  changed_when: false

- name: Pre-patch - Check for pending security updates (RedHat)
  shell: dnf check-update --security --quiet
  register: redhat_security_updates
  when: ansible_os_family == 'RedHat'
  changed_when: false
  ignore_errors: yes

- name: Pre-patch - Check for pending updates (Debian)
  shell: apt-get update --quiet && apt-get upgrade --dry-run | grep -i "security"
  register: debian_security_updates
  when: ansible_os_family == 'Debian'
  changed_when: false
  ignore_errors: yes

- name: Display pending security updates
  debug:
    msg: 
      - "Node: {{ inventory_hostname }}"
      - "OS: {{ ansible_distribution }} {{ ansible_distribution_version }}"
      - "Pending security updates: {{ 'YES' if redhat_security_updates.stdout_lines | length > 0 or debian_security_updates.stdout_lines | length > 0 else 'NO' }}"
      - "Update details: {{ redhat_security_updates.stdout_lines if ansible_os_family == 'RedHat' else debian_security_updates.stdout_lines }}"

- name: Create patch log directory
  file:
    path: /var/log/hpc-patches
    state: directory
    mode: '0755'

- name: Apply security patches - RedHat family
  block:
    - name: Install all available security updates (Rocky)
      dnf:
        name: '*'
        state: latest
        security: yes
        bugfix: yes
        update_cache: yes
      register: dnf_result
      when: ansible_os_family == 'RedHat'

  rescue:
    - name: Log failure for Rocky nodes
      copy:
        content: |
          ==========================================
          PATCH FAILURE REPORT
          Node: {{ inventory_hostname }}
          Date: {{ ansible_date_time.date }} {{ ansible_date_time.time }}
          Error: {{ ansible_failed_result.msg }}
          ==========================================
        dest: "/var/log/hpc-patches/failure_{{ inventory_hostname }}_{{ ansible_date_time.date }}.log"
      when: ansible_os_family == 'RedHat'

- name: Apply security patches - Debian family
  block:
    - name: Update apt cache (Ubuntu/Debian)
      apt:
        update_cache: yes
        cache_valid_time: 3600
      when: ansible_os_family == 'Debian'

    - name: Install security updates (Ubuntu/Debian)
      apt:
        name: '*'
        state: latest
        only_updates: yes
      register: apt_result
      when: ansible_os_family == 'Debian'

  rescue:
    - name: Log failure for Debian nodes
      copy:
        content: |
          ==========================================
          PATCH FAILURE REPORT
          Node: {{ inventory_hostname }}
          Date: {{ ansible_date_time.date }} {{ ansible_date_time.time }}
          Error: {{ ansible_failed_result.msg }}
          ==========================================
        dest: "/var/log/hpc-patches/failure_{{ inventory_hostname }}_{{ ansible_date_time.date }}.log"
      when: ansible_os_family == 'Debian'

- name: Post-patch - Verify kernel version
  command: uname -r
  register: new_kernel
  changed_when: false

- name: Post-patch - Check if kernel was updated
  set_fact:
    kernel_updated: "{{ pre_patch_packages.stdout != new_kernel.stdout }}"
    
- name: Post-patch - Display kernel update status
  debug:
    msg: "Kernel updated: {{ kernel_updated }} (Old: {{ pre_patch_packages.stdout[:20] }}... New: {{ new_kernel.stdout }})"

- name: Post-patch - Determine if reboot is required
  shell: |
    {% if ansible_os_family == 'RedHat' %}
    if command -v needs-restarting &> /dev/null; then
      needs-restarting -r
      if [ $? -eq 1 ]; then
        echo "REBOOT_REQUIRED"
      else
        echo "NO_REBOOT_NEEDED"
      fi
    else
      # Fallback for Rocky without needs-restarting
      if [ -f /var/run/reboot-required ]; then
        echo "REBOOT_REQUIRED"
      else
        echo "NO_REBOOT_NEEDED"
      fi
    fi
    {% elif ansible_os_family == 'Debian' %}
    if [ -f /var/run/reboot-required ]; then
      echo "REBOOT_REQUIRED"
    else
      echo "NO_REBOOT_NEEDED"
    fi
    {% endif %}
  register: reboot_check
  ignore_errors: yes
  changed_when: false

- name: Display reboot status
  debug:
    msg: "Reboot required: {{ reboot_check.stdout }}"

- name: Create patch summary report
  copy:
    content: |
      ==========================================
      HPC PATCH REPORT
      ==========================================
      Node: {{ inventory_hostname }}
      Date: {{ ansible_date_time.date }} {{ ansible_date_time.time }}
      OS: {{ ansible_distribution }} {{ ansible_distribution_version }}
      Kernel: {{ new_kernel.stdout }}
      Kernel Updated: {{ kernel_updated }}
      Reboot Required: {{ reboot_check.stdout }}
      --------------------------------------------------
      PATCH RESULTS:
      {% if ansible_os_family == 'RedHat' %}
      {{ dnf_result.results | default('No patches applied') }}
      {% elif ansible_os_family == 'Debian' %}
      {{ apt_result.results | default('No patches applied') }}
      {% endif %}
      ==========================================
    dest: "/var/log/hpc-patches/patch_report_{{ inventory_hostname }}_{{ ansible_date_time.date }}.log"
    mode: '0644'

- name: Conditional reboot handler
  block:
    - name: Reboot if required
      reboot:
        reboot_timeout: 300
        pre_reboot_delay: 10
        post_reboot_delay: 30
        connect_timeout: 60
      when: 
        - "'REBOOT_REQUIRED' in reboot_check.stdout"
        - kernel_updated == true
      register: reboot_result

    - name: Wait for system to come back
      wait_for:
        host: "{{ ansible_host | default(inventory_hostname) }}"
        port: 22
        delay: 10
        timeout: 300
      when: reboot_result is defined
      
    - name: Verify system is operational after reboot
      ping:
        data: post_reboot
      when: reboot_result is defined

    - name: Log successful reboot
      copy:
        content: |
          REBOOT SUCCESSFUL
          Node: {{ inventory_hostname }}
          Reboot time: {{ ansible_date_time.date }} {{ ansible_date_time.time }}
        dest: "/var/log/hpc-patches/reboot_log_{{ inventory_hostname }}.log"
      when: reboot_result is defined
```

---

## Step 3: Create OS-Specific Variables

**`~/hpc-ansible/roles/patching/vars/RedHat.yml`**:
```yaml
---
# RedHat/Rocky specific variables
patch_package_manager: dnf
patch_command: "dnf update --security --bugfix -y"
patch_check_command: "dnf check-update --security --quiet"
kernel_package_name: kernel
reboot_required_command: "needs-restarting -r"
```

**`~/hpc-ansible/roles/patching/vars/Debian.yml`**:
```yaml
---
# Debian/Ubuntu specific variables
patch_package_manager: apt
patch_command: "apt-get upgrade -y --only-upgrade"
patch_check_command: "apt-get update && apt-get upgrade --dry-run"
kernel_package_name: linux-image-generic
reboot_required_command: "[ -f /var/run/reboot-required ]"
```

---

## Step 4: Create the Handlers File

**`~/hpc-ansible/roles/patching/handlers/main.yml`**:
```yaml
---
# Handlers for the patching role

- name: Restart services
  systemd:
    name: "{{ item }}"
    state: restarted
    daemon_reload: yes
  loop:
    - sshd
    - chronyd
  when: ansible_os_family == 'RedHat'

- name: Restart services (Debian)
  systemd:
    name: "{{ item }}"
    state: restarted
    daemon_reload: yes
  loop:
    - ssh
    - systemd-timesyncd
  when: ansible_os_family == 'Debian'
```

---

## Step 5: Create the Main Patching Playbook

**`~/hpc-ansible/playbooks/operations/02_patching_playbook.yml`**:

```yaml
---
- name: HPC Cluster - Production Patching
  hosts: hpc_cluster
  gather_facts: yes
  become: yes
  
  pre_tasks:
    - name: Display patching window start
      debug:
        msg: "========================================\nPATCHING WINDOW STARTED\nTime: {{ ansible_date_time.time }}\nNode: {{ inventory_hostname }}\n========================================"

    - name: Create pre-patch snapshot of critical files
      copy:
        src: "{{ item }}"
        dest: "/tmp/backup_{{ item | basename }}_{{ ansible_date_time.epoch }}"
        remote_src: yes
      loop:
        - /etc/fstab
        - /etc/hosts
        - /etc/resolv.conf
      ignore_errors: yes

  roles:
    - patching

  post_tasks:
    - name: Display patching window end
      debug:
        msg: "========================================\nPATCHING WINDOW ENDED\nTime: {{ ansible_date_time.time }}\nNode: {{ inventory_hostname }}\n========================================"

    - name: Collect patch reports from all nodes
      fetch:
        src: "/var/log/hpc-patches/patch_report_{{ inventory_hostname }}_{{ ansible_date_time.date }}.log"
        dest: "./logs/{{ inventory_hostname }}_{{ ansible_date_time.date }}_patch_report.log"
        flat: yes
      ignore_errors: yes
      run_once: yes
```

---

## Step 6: Create a Rollback Playbook

**`~/hpc-ansible/playbooks/operations/03_rollback_playbook.yml`**:

```yaml
---
- name: HPC Cluster - Rollback Last Kernel
  hosts: hpc_cluster
  gather_facts: yes
  become: yes
  
  tasks:
    - name: Display rollback warning
      debug:
        msg: "WARNING: Rolling back to previous kernel on {{ inventory_hostname }}"
      run_once: yes

    - name: List installed kernels - RedHat
      shell: rpm -qa kernel | sort -V
      register: redhat_kernels
      when: ansible_os_family == 'RedHat'
      ignore_errors: yes

    - name: List installed kernels - Debian
      shell: dpkg -l linux-image-* | grep -v headers | awk '{print $2}'
      register: debian_kernels
      when: ansible_os_family == 'Debian'
      ignore_errors: yes

    - name: Display available kernels (RedHat)
      debug:
        msg: "Available kernels: {{ redhat_kernels.stdout_lines }}"
      when: ansible_os_family == 'RedHat'

    - name: Display available kernels (Debian)
      debug:
        msg: "Available kernels: {{ debian_kernels.stdout_lines }}"
      when: ansible_os_family == 'Debian'

    - name: Set default kernel to previous version - RedHat
      command: grub2-set-default "{{ redhat_kernels.stdout_lines[-2] }}"
      when: 
        - ansible_os_family == 'RedHat'
        - redhat_kernels.stdout_lines | length > 1
      ignore_errors: yes
      register: rollback_redhat

    - name: Set default kernel to previous version - Debian
      command: grub-set-default "{{ debian_kernels.stdout_lines[-2] }}"
      when: 
        - ansible_os_family == 'Debian'
        - debian_kernels.stdout_lines | length > 1
      ignore_errors: yes
      register: rollback_debian

    - name: Reboot to apply rollback
      reboot:
        reboot_timeout: 300
        pre_reboot_delay: 10
        post_reboot_delay: 30
      when: 
        - rollback_redhat is defined or rollback_debian is defined

    - name: Verify rollback was successful
      command: uname -r
      register: rolled_back_kernel

    - name: Display rollback result
      debug:
        msg: "Rollback complete. Current kernel: {{ rolled_back_kernel.stdout }}"
```

---

## Step 7: Run the Patching Playbook

**IMPORTANT**: Before running, take snapshots of ALL 6 VMs!

```bash
cd ~/hpc-ansible

# First, do a dry run on a single node to test
ansible-playbook -i inventory/production/inventory.ini playbooks/operations/02_patching_playbook.yml --limit rocky1 --check

# If dry run looks good, run for real
ansible-playbook -i inventory/production/inventory.ini playbooks/operations/02_patching_playbook.yml

# To patch only specific groups
ansible-playbook -i inventory/production/inventory.ini playbooks/operations/02_patching_playbook.yml --limit redhat
ansible-playbook -i inventory/production/inventory.ini playbooks/operations/02_patching_playbook.yml --limit debian_family
```

---

## Step 8: Verify the Results

```bash
# Check patch reports on all nodes
ansible -i inventory/production/inventory.ini hpc_cluster -m shell -a "cat /var/log/hpc-patches/patch_report_*"

# Check reboot status
ansible -i inventory/production/inventory.ini hpc_cluster -m shell -a "uptime"

# Verify kernel versions across all nodes
ansible -i inventory/production/inventory.ini hpc_cluster -m shell -a "uname -r"

# Check for any failed patches
ansible -i inventory/production/inventory.ini hpc_cluster -m shell -a "ls -la /var/log/hpc-patches/failure_*" --ignore-errors
```

---

## Your Deliverables for Lesson 2:

1. **The patch report** from at least one Rocky and one Ubuntu node
2. **The kernel version** on all 6 nodes after patching
3. **Any failures** you encountered (especially differences between Rocky and Ubuntu)
4. **Your rollback test** - pick one node, run the rollback playbook, and show the kernel before/after

---

## What You've Learned:

- ✅ Cross-platform patching logic (RedHat vs Debian families)
- ✅ Pre/post-patch validation
- ✅ Conditional reboots (only when kernel changes)
- ✅ Failure handling with `block/rescue`
- ✅ Rollback procedures for kernel updates
- ✅ Centralized logging for audit purposes

---

## Common Issues You Might Encounter:

1. **Rocky nodes missing `needs-restarting`**: The playbook handles this with a fallback
2. **Ubuntu nodes showing "held packages"**: This is normal for some packages (like docker)
3. **Different patch counts**: Rocky and Ubuntu will have different security update counts

---

## Next Steps (Lesson 3 Preview):

Once this works, **Lesson 3** will focus on:
- **Container deployment** (Docker/Podman on all nodes)
- **Basic monitoring** (CheckMK or similar)
- **High-availability checks** across the cluster

---

**Question for you**: Which OS had more pending security updates? Rocky or Ubuntu? And did any node require a reboot? Reply with your patch report summary and let me know if you encountered any OS-specific quirks!