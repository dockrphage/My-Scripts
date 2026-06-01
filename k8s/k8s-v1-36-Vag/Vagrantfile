Vagrant.configure("2") do |config|
  nodes = {
    "cp1"  => "192.168.56.10",
    "node1"    => "192.168.56.11",
    "node2"    => "192.168.56.12",
    "minio"    => "192.168.56.13"
  }

  bridged_ips = {
    "cp1"  => "192.168.1.50",
    "node1"    => "192.168.1.51",
    "node2"    => "192.168.1.52",
    "minio"    => "192.168.1.53"
  }

  nodes.each do |name, host_only_ip|
    config.vm.define name do |node|
      node.vm.box = "ubuntu/jammy64"
      node.vm.hostname = name

      # Adapter 2: Host-only network (Kubernetes internal)
      node.vm.network "private_network",
        ip: host_only_ip,
        virtualbox__promiscuous_mode: "allow-all"

      # Adapter 3: Bridged network (LAN access)
      node.vm.network "public_network",
        ip: bridged_ips[name]

      # Adapter 4: MinIO ONLY — Dedicated private network (fixes pod → MinIO traffic)
      if name == "minio"
        node.vm.network "private_network",
          ip: "10.10.10.12",
          virtualbox__promiscuous_mode: "allow-all"

      end

      # VM resources
      node.vm.provider "virtualbox" do |vb|
        if name == "cp1"
          vb.memory = 2048
          vb.cpus = 2
        elsif name == "minio"
          vb.memory = 2048
          vb.cpus = 2
        else
          vb.memory = 1536
          vb.cpus = 1
        end
      end

      node.vm.synced_folder ".", "/vagrant", disabled: true
      # Copy Kubernetes setup scripts into VM
      node.vm.provision "file", source: "k8s-CP-setup.sh", destination: "/home/vagrant/k8s-CP-setup.sh"
      node.vm.provision "file", source: "k8s-worker-setup.sh", destination: "/home/vagrant/k8s-worker-setup.sh"

      # Make scripts executable
      node.vm.provision "shell", inline: <<-SHELL
        sudo chmod +x /home/vagrant/k8s-CP-setup.sh
        sudo chmod +x /home/vagrant/k8s-worker-setup.sh
      SHELL

      # Enable SSH password login and set password
      node.vm.provision "shell", inline: <<-SHELL
        sudo sed -i 's/PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config.d/60-cloudimg-settings.conf
        echo 'vagrant:Passwd123' | sudo chpasswd
        sudo systemctl restart ssh
      SHELL
    end
  end
end

