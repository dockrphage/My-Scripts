# Make script executable
chmod +x setup-cp-v1.36.sh
chmod +x setup-worker-v1.36.sh

# Run worker script and get join command
./setup-cp-v1.36.sh

# Run worker script with join command (copy the entire command as a single argument)
./setup-worker-v1.36.sh "kubeadm join 172.31.12.73:6443 --token 1u1fxm.6xgbirwrrw9ymvbj --discovery-token-ca-cert-hash sha256:4ec0ff33de370fa3a4eebe2a628760a0193afd841bb2637724dcfa9d61cf9076"