#!/bin/bash
# deploy-kubernetes-ec2.sh
# Master script to deploy Kubernetes on EC2

set -e

echo "=========================================="
echo "Kubernetes on EC2 Deployment Script"
echo "=========================================="

# Set variables
CONTROL_PLANE_IP=""
WORKER1_IP=""
WORKER2_IP=""
SSH_USER="ubuntu"  # Change to 'ec2-user' for Amazon Linux
SSH_KEY_PATH="~/.ssh/your-key.pem"  # Update with your key path

# Function to get instance IPs
get_instance_ips() {
    echo "Enter the private IPs of your EC2 instances:"
    read -p "Control Plane IP: " CONTROL_PLANE_IP
    read -p "Worker 1 IP: " WORKER1_IP
    read -p "Worker 2 IP: " WORKER2_IP
}

# Function to copy scripts to instances
copy_scripts() {
    echo "Copying scripts to instances..."
    
    # Copy to control plane
    scp -i ${SSH_KEY_PATH} setup-control-plane-ec2.sh ${SSH_USER}@${CONTROL_PLANE_IP}:~/
    
    # Copy to workers
    scp -i ${SSH_KEY_PATH} setup-worker-node-ec2.sh ${SSH_USER}@${WORKER1_IP}:~/
    scp -i ${SSH_KEY_PATH} setup-worker-node-ec2.sh ${SSH_USER}@${WORKER2_IP}:~/
}

# Function to deploy control plane
deploy_control_plane() {
    echo "Deploying control plane..."
    ssh -i ${SSH_KEY_PATH} ${SSH_USER}@${CONTROL_PLANE_IP} \
        "sudo chmod +x setup-control-plane-ec2.sh && ./setup-control-plane-ec2.sh"
    
    # Copy join command from control plane
    scp -i ${SSH_KEY_PATH} ${SSH_USER}@${CONTROL_PLANE_IP}:~/join-command.txt ./
}

# Function to deploy workers
deploy_workers() {
    echo "Deploying worker 1..."
    scp -i ${SSH_KEY_PATH} join-command.txt ${SSH_USER}@${WORKER1_IP}:~/
    ssh -i ${SSH_KEY_PATH} ${SSH_USER}@${WORKER1_IP} \
        "sudo chmod +x setup-worker-node-ec2.sh && ./setup-worker-node-ec2.sh"
    
    echo "Deploying worker 2..."
    scp -i ${SSH_KEY_PATH} join-command.txt ${SSH_USER}@${WORKER2_IP}:~/
    ssh -i ${SSH_KEY_PATH} ${SSH_USER}@${WORKER2_IP} \
        "sudo chmod +x setup-worker-node-ec2.sh && ./setup-worker-node-ec2.sh"
}

# Function to verify cluster
verify_cluster() {
    echo "Verifying cluster..."
    ssh -i ${SSH_KEY_PATH} ${SSH_USER}@${CONTROL_PLANE_IP} \
        "kubectl get nodes -o wide"
    echo ""
    echo "Kubernetes cluster is ready!"
}

# Main execution
get_instance_ips
copy_scripts
deploy_control_plane
deploy_workers
verify_cluster