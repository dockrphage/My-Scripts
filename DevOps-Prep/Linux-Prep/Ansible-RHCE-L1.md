

This is **Lesson 1: Ad-hoc Commands and Module Mastery** of an AI-Generated progressive learn-by-impliment Ansible learning series with RHCE scope.
I already had a multi-node (rocky,ubuntu,debian) ansible lab configured from a previous project, so the base infra is configured.
 .

## 🎯 Lesson 1: Ad-hoc Commands & Essential Modules

### Objective
Master the `ansible` command-line tool and essential modules that appear frequently in RHCE exams and real-world automation.

### Prerequisites Check
First, verify your setup:

```bash
# Test connectivity to all hosts
ansible all -i inventory/production/inventory.ini -m ping

# Check Python interpreter on each OS family
ansible redhat -i inventory/production/inventory.ini -m command -a "python3 --version"
ansible debian_family -i inventory/production/inventory.ini -m command -a "python3 --version"
```

### Part 1: The `command` vs `shell` Module

```bash
# command module (safer, no shell environment)
ansible rocky -i inventory/production/inventory.ini -m command -a "uptime"

# shell module (full shell, can use pipes/redirects)
ansible ubuntu -i inventory/production/inventory.ini -m shell -a "ps aux | grep python | wc -l"
```

**📝 RHCE Tip:** Always prefer `command` over `shell` unless you need shell features like `|`, `>`, `&`, or environment variables.

### Part 2: Package Management (Critical for RHCE)

```bash
# DNF/YUM (RHEL/Rocky)
ansible rocky -i inventory/production/inventory.ini -m dnf -a "name=httpd state=present" --become

# APT (Ubuntu/Debian)
ansible debian_family -i inventory/production/inventory.ini -m apt -a "name=nginx state=present update_cache=yes" --become

# Check installed packages
ansible rocky -i inventory/production/inventory.ini -m dnf -a "name=httpd state=absent" --check  # Dry run
```

### Part 3: Service Management

```bash
# Start services
ansible rocky -i inventory/production/inventory.ini -m service -a "name=httpd state=started enabled=yes" --become

# Check service status
ansible all -i inventory/production/inventory.ini -m service -a "name=sshd state=started"
```

### Part 4: File Operations

```bash
# Copy files
echo "Hello HPC Cluster" > /tmp/test.txt
ansible all -i inventory/production/inventory.ini -m copy -a "src=/tmp/test.txt dest=/tmp/hpc_test.txt owner=vagrant mode=0644"

# File module (create directories, set permissions)
ansible rocky -i inventory/production/inventory.ini -m file -a "path=/opt/hpc state=directory owner=vagrant group=vagrant mode=0755" --become

# Fetch files from remote (collect logs)
ansible rocky1 -i inventory/production/inventory.ini -m fetch -a "src=/etc/hostname dest=/tmp/ hostname_safe=yes"
```

### Part 5: User Management

```bash
# Create user
ansible all -i inventory/production/inventory.ini -m user -a "name=hpcuser state=present groups=vagrant shell=/bin/bash" --become

# Set password (with hash)
ansible all -i inventory/production/inventory.ini -m user -a "name=hpcuser password={{ 'SecurePass123!' | password_hash('sha512') }}" --become
```

### Part 6: System Information Gathering (setup module)

```bash
# Gather facts from all hosts
ansible all -i inventory/production/inventory.ini -m setup

# Filter specific facts
ansible rocky -i inventory/production/inventory.ini -m setup -a "filter=ansible_os_family"
ansible ubuntu -i inventory/production/inventory.ini -m setup -a "filter=ansible_distribution_version"

# Save facts for later use
ansible all -i inventory/production/inventory.ini -m setup -a "filter=ansible_memory_mb" --tree /tmp/facts/
```

## 🛠️ Practice Exercises

### Exercise 1: Multi-OS Package Audit
Create a one-liner that reports which web servers (httpd/nginx) are installed on each node:

```bash
# Hint: Use shell module and register output
ansible all -i inventory/production/inventory.ini -m shell -a "rpm -q httpd nginx 2>/dev/null || dpkg -l apache2 nginx 2>/dev/null | grep ^ii"
```

### Exercise 2: Disk Usage Alert
Check disk usage across all nodes and identify any partition > 80%:

```bash
# Use the command module with df
ansible all -i inventory/production/inventory.ini -m command -a "df -h | awk '$5+0 > 80 {print $1, $5, $6}'"
```

### Exercise 3: Time Synchronization
Verify chrony/ntp service is running on all nodes:

```bash
# Check service status
ansible all -i inventory/production/inventory.ini -m service -a "name=chronyd state=started" 
# Ubuntu uses ntp or systemd-timesyncd
```

### Exercise 4: Create an Ansible Ad-hoc "Playbook" Pipeline
Chain multiple modules using a semicolon:

```bash
ansible rocky -i inventory/production/inventory.ini -m shell -a "mkdir -p /opt/hpc/logs && echo 'HPC Node $(hostname)' > /opt/hpc/node_info.txt && chown -R vagrant:vagrant /opt/hpc" --become
```

## 📚 Key Learning Points for RHCE

1. **Module Paths:** Always know where modules are located:
   ```bash
   ansible-doc -l | grep -E "dnf|apt|copy|file|service"
   ```

2. **Idempotency:** Most modules are idempotent - they only make changes if needed. Test with `--check`:
   ```bash
   ansible rocky -i inventory/production/inventory.ini -m dnf -a "name=httpd state=present" --check --diff
   ```

3. **Become (sudo):** Master privilege escalation:
   ```bash
   # Different become methods
   ansible rocky -i inventory/production/inventory.ini -m command -a "whoami" --become --become-user=root
   ansible rocky -i inventory/production/inventory.ini -m command -a "whoami" --become --become-user=vagrant
   ```

4. **Debug Mode:** When commands fail:
   ```bash
   ansible rocky -i inventory/production/inventory.ini -m dnf -a "name=httpd state=present" --become -vvv
   ```

## 🎓 Challenge Exercise

Create a single ad-hoc command that:
1. Creates a directory `/opt/hpc_shared`
2. Sets ownership to `vagrant:vagrant`
3. Copies a test file from your controller to that directory
4. Displays the contents of the copied file
5. Shows the disk usage of the directory

```bash
# One-liner approach (using shell module)
ansible rocky1 -i inventory/production/inventory.ini -m shell -a "mkdir -p /opt/hpc_shared && chown vagrant:vagrant /opt/hpc_shared && echo 'HPC Test File' > /opt/hpc_shared/test.txt && cat /opt/hpc_shared/test.txt && du -sh /opt/hpc_shared" --become
```

## ✅ Success Criteria

You've mastered this lesson when you can:
- ✅ Use `ping`, `command`, `shell`, `dnf`, `apt`, `service`, `copy`, `file`, `user`, and `setup` modules confidently
- ✅ Handle both RHEL and Debian families with appropriate modules
- ✅ Use `--check`, `--diff`, `--become`, and `-vvv` effectively
- ✅ Create multi-step ad-hoc commands using logical operators
- ✅ Understand when to use command vs shell

## 📖 Next Steps

Once comfortable with ad-hoc commands, **Lesson 2** will cover:
- Playbook structure and YAML syntax
- Variables and facts in playbooks
- Conditionals and loops
- Handlers for service restarts

**Pro Tip:** Create an alias for your inventory to save typing:
```bash
echo "alias ans='ansible -i /home/vagrant/hpc-ansible/inventory/production/inventory.ini'" >> ~/.bashrc
source ~/.bashrc
# Now use: ans all -m ping
```
