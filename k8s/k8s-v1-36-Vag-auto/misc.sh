# Install Rancher's local-path-provisioner
kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/master/deploy/local-path-storage.yaml

# Verify it installed
kubectl get storageclass
# Should show: local-path (default)

# Make it the default storage class
kubectl patch storageclass local-path -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'

# Verify default is set
kubectl get storageclass
# Should show (default) next to local-path

----

# Install metrics-server for HPA support
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

# Patch metrics-server to work with self-signed certificates (for lab)
kubectl patch deployment metrics-server -n kube-system \
  --type='json' \
  -p='[{"op": "add", "path": "/spec/template/spec/containers/0/args/-", "value": "--kubelet-insecure-tls"}]'

# Wait for metrics-server to be ready
kubectl get pods -n kube-system | grep metrics-server