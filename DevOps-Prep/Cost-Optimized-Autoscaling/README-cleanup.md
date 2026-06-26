# 🧹 Lab Cleanup Commands

## Complete Cleanup Script

Here's a comprehensive cleanup script to remove all resources created during the Cost-Optimized Autoscaling Lab:

```bash
#!/bin/bash
# cleanup-lab.sh - Complete lab cleanup

echo "🧹 Starting Cost-Optimized Autoscaling Lab Cleanup"
echo "=================================================="
echo ""

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 1. Delete Application Resources
echo -e "${YELLOW}1. Deleting Application Resources...${NC}"
kubectl delete deployment sample-app -n cost-optimized 2>/dev/null && echo "✅ Deleted sample-app deployment"
kubectl delete service sample-app -n cost-optimized 2>/dev/null && echo "✅ Deleted sample-app service"
kubectl delete configmap python-app -n cost-optimized 2>/dev/null && echo "✅ Deleted python-app configmap"
kubectl delete configmap app-code -n cost-optimized 2>/dev/null && echo "✅ Deleted app-code configmap"
kubectl delete scaledobject sample-app-scaler -n cost-optimized 2>/dev/null && echo "✅ Deleted scaledobject"
kubectl delete hpa -n cost-optimized --all 2>/dev/null && echo "✅ Deleted all HPAs"

# 2. Delete RabbitMQ
echo -e "\n${YELLOW}2. Deleting RabbitMQ...${NC}"
kubectl delete deployment rabbitmq -n cost-optimized 2>/dev/null && echo "✅ Deleted rabbitmq deployment"
kubectl delete service rabbitmq -n cost-optimized 2>/dev/null && echo "✅ Deleted rabbitmq service"
kubectl delete configmap rabbitmq-config -n cost-optimized 2>/dev/null && echo "✅ Deleted rabbitmq configmap"

# 3. Delete KEDA
echo -e "\n${YELLOW}3. Uninstalling KEDA...${NC}"
helm uninstall keda -n keda-system 2>/dev/null && echo "✅ Uninstalled KEDA Helm chart"
kubectl delete namespace keda-system 2>/dev/null && echo "✅ Deleted keda-system namespace"

# Clean up KEDA CRDs (if they exist)
echo "Cleaning up KEDA CRDs..."
kubectl delete crd clustertriggerauthentications.keda.sh 2>/dev/null && echo "✅ Deleted CRD: clustertriggerauthentications"
kubectl delete crd scaledjobs.keda.sh 2>/dev/null && echo "✅ Deleted CRD: scaledjobs"
kubectl delete crd scaledobjects.keda.sh 2>/dev/null && echo "✅ Deleted CRD: scaledobjects"
kubectl delete crd triggerauthentications.keda.sh 2>/dev/null && echo "✅ Deleted CRD: triggerauthentications"

# 4. Delete Kubecost (if installed)
echo -e "\n${YELLOW}4. Uninstalling Kubecost...${NC}"
helm uninstall kubecost -n kubecost 2>/dev/null && echo "✅ Uninstalled Kubecost"
kubectl delete namespace kubecost 2>/dev/null && echo "✅ Deleted kubecost namespace"

# 5. Delete Registry
echo -e "\n${YELLOW}5. Deleting Local Registry...${NC}"
kubectl delete deployment local-registry -n kube-system 2>/dev/null && echo "✅ Deleted local-registry deployment"
kubectl delete service local-registry -n kube-system 2>/dev/null && echo "✅ Deleted local-registry service"

# Stop Docker registry container
docker stop local-registry 2>/dev/null && echo "✅ Stopped local-registry container"
docker rm local-registry 2>/dev/null && echo "✅ Removed local-registry container"

# 6. Delete Namespace
echo -e "\n${YELLOW}6. Deleting cost-optimized Namespace...${NC}"
kubectl delete namespace cost-optimized 2>/dev/null && echo "✅ Deleted cost-optimized namespace"

# 7. Remove Debug Pods
echo -e "\n${YELLOW}7. Cleaning up Debug Pods...${NC}"
kubectl delete pod node-debugger-node1-s45ts -n cost-optimized 2>/dev/null && echo "✅ Deleted debug pod 1"
kubectl delete pod node-debugger-node1-ztq6g -n cost-optimized 2>/dev/null && echo "✅ Deleted debug pod 2"
kubectl delete pod test-pull 2>/dev/null && echo "✅ Deleted test-pull pod"
kubectl delete pod keda-test-deployment 2>/dev/null && echo "✅ Deleted test deployment pod"

# 8. Kill Port Forwarding
echo -e "\n${YELLOW}8. Stopping Port Forwarding Processes...${NC}"
pkill -f "kubectl port-forward.*8080" 2>/dev/null && echo "✅ Stopped port-forward on 8080"
pkill -f "kubectl port-forward.*15672" 2>/dev/null && echo "✅ Stopped port-forward on 15672"
pkill -f "kubectl port-forward.*9090" 2>/dev/null && echo "✅ Stopped port-forward on 9090"
pkill -f "kubectl port-forward.*5000" 2>/dev/null && echo "✅ Stopped port-forward on 5000"

# 9. Clean Docker
echo -e "\n${YELLOW}9. Cleaning Docker Artifacts...${NC}"
docker system prune -f 2>/dev/null && echo "✅ Pruned Docker system"
docker volume prune -f 2>/dev/null && echo "✅ Pruned Docker volumes"

# 10. Remove Local Files
echo -e "\n${YELLOW}10. Removing Local Files...${NC}"
rm -f sample-app.tar 2>/dev/null && echo "✅ Removed sample-app.tar"
rm -f Dockerfile.python 2>/dev/null && echo "✅ Removed Dockerfile.python"
rm -f app.py 2>/dev/null && echo "✅ Removed app.py"
rm -f app-final.py 2>/dev/null && echo "✅ Removed app-final.py"

# 11. Final Verification
echo -e "\n${GREEN}==================================================${NC}"
echo -e "${GREEN}✅ Lab Cleanup Complete!${NC}"
echo -e "${GREEN}==================================================${NC}"

echo -e "\n${YELLOW}Remaining Resources Check:${NC}"
echo "=================================================="

# Check remaining resources
echo -e "\n📊 Namespaces:"
kubectl get namespaces | grep -E "(cost-optimized|keda-system|kubecost)" || echo "  ✅ All lab namespaces removed"

echo -e "\n📊 Pods in cost-optimized:"
kubectl get pods -n cost-optimized 2>/dev/null || echo "  ✅ No pods remaining"

echo -e "\n📊 Deployments in cost-optimized:"
kubectl get deploy -n cost-optimized 2>/dev/null || echo "  ✅ No deployments remaining"

echo -e "\n📊 Services in cost-optimized:"
kubectl get svc -n cost-optimized 2>/dev/null || echo "  ✅ No services remaining"

echo -e "\n📊 KEDA CRDs:"
kubectl get crd | grep keda.sh || echo "  ✅ No KEDA CRDs remaining"

echo -e "\n📊 KEDA Helm releases:"
helm list -n keda-system 2>/dev/null || echo "  ✅ No KEDA Helm releases"

echo -e "\n📊 Docker containers:"
docker ps -a | grep -E "(local-registry|sample-app)" || echo "  ✅ No lab containers running"

echo -e "\n${GREEN}==================================================${NC}"
echo -e "${GREEN}🎉 Lab Cleanup Complete!${NC}"
echo -e "${GREEN}==================================================${NC}"
```

---

## Quick One-Liner Cleanup Commands

### If you want to clean up specific components:

```bash
# 1. Delete only the application
kubectl delete deployment sample-app -n cost-optimized
kubectl delete service sample-app -n cost-optimized
kubectl delete scaledobject sample-app-scaler -n cost-optimized

# 2. Delete only RabbitMQ
kubectl delete deployment rabbitmq -n cost-optimized
kubectl delete service rabbitmq -n cost-optimized

# 3. Uninstall KEDA only
helm uninstall keda -n keda-system
kubectl delete namespace keda-system

# 4. Delete the namespace (deletes everything inside it)
kubectl delete namespace cost-optimized

# 5. Stop port forwarding
pkill -f "kubectl port-forward"

# 6. Clean Docker
docker system prune -f
docker volume prune -f
```

---

## Complete Cleanup (All Resources)

```bash
#!/bin/bash
# cleanup-all.sh - Nuclear option - removes everything

echo "⚠️  WARNING: This will remove ALL lab resources!"
read -p "Are you sure? (yes/no): " confirm

if [ "$confirm" != "yes" ]; then
    echo "Cleanup cancelled."
    exit 0
fi

echo "🧹 Starting nuclear cleanup..."

# Remove everything
helm uninstall keda -n keda-system 2>/dev/null
helm uninstall kubecost -n kubecost 2>/dev/null
kubectl delete namespace cost-optimized keda-system kubecost 2>/dev/null
kubectl delete crd clustertriggerauthentications.keda.sh scaledjobs.keda.sh scaledobjects.keda.sh triggerauthentications.keda.sh 2>/dev/null
kubectl delete apiservice v1beta1.external.metrics.k8s.io 2>/dev/null
kubectl delete validatingwebhookconfiguration keda-admission 2>/dev/null
kubectl delete clusterrole keda-operator keda-external-metrics-reader 2>/dev/null
kubectl delete clusterrolebinding keda-operator keda-hpa-controller-external-metrics keda-system-auth-delegator 2>/dev/null

# Stop port forwarding
pkill -f "kubectl port-forward" 2>/dev/null

# Clean Docker
docker stop local-registry 2>/dev/null
docker rm local-registry 2>/dev/null
docker system prune -af 2>/dev/null
docker volume prune -f 2>/dev/null

# Remove local files
rm -f sample-app.tar Dockerfile.python app.py app-final.py 2>/dev/null

echo "✅ Complete cleanup done!"
```

---

## Verify Cleanup

```bash
#!/bin/bash
# verify-cleanup.sh

echo "🔍 Verifying Lab Cleanup"
echo "========================"

# Check namespaces
echo -e "\n📊 Namespaces:"
kubectl get namespaces | grep -E "(cost-optimized|keda-system|kubecost)" || echo "✅ All lab namespaces removed"

# Check CRDs
echo -e "\n📊 CRDs:"
kubectl get crd | grep keda.sh || echo "✅ No KEDA CRDs remaining"

# Check Helm releases
echo -e "\n📊 Helm Releases:"
helm list -A | grep -E "(keda|kubecost)" || echo "✅ No lab Helm releases"

# Check Docker containers
echo -e "\n📊 Docker Containers:"
docker ps -a | grep -E "(local-registry|sample-app|keda)" || echo "✅ No lab containers running"

# Check running processes
echo -e "\n📊 Port Forwarding Processes:"
ps aux | grep "kubectl port-forward" | grep -v grep || echo "✅ No port-forwarding processes"

echo -e "\n✅ Verification complete! Lab is clean."
```

---

## Quick Reference: What Each Command Removes

| Command | Removes |
|---------|---------|
| `kubectl delete namespace cost-optimized` | Application, RabbitMQ, ScaledObject, HPA, Services, ConfigMaps |
| `helm uninstall keda -n keda-system` | KEDA operator, metrics server, admission webhooks |
| `kubectl delete namespace keda-system` | KEDA namespace and all resources (if Helm failed) |
| `kubectl delete crd *.keda.sh` | KEDA Custom Resource Definitions |
| `pkill -f "kubectl port-forward"` | All port-forwarding processes |
| `docker stop local-registry` | Local registry container |
| `docker system prune -f` | Unused Docker images, containers, networks |
| `rm -f *.tar *.py` | Local build artifacts |

---

## Expected Cleanup Output

```
🧹 Starting Cost-Optimized Autoscaling Lab Cleanup
==================================================

1. Deleting Application Resources...
✅ Deleted sample-app deployment
✅ Deleted sample-app service
✅ Deleted python-app configmap
✅ Deleted scaledobject
✅ Deleted all HPAs

2. Deleting RabbitMQ...
✅ Deleted rabbitmq deployment
✅ Deleted rabbitmq service

3. Uninstalling KEDA...
✅ Uninstalled KEDA Helm chart
✅ Deleted keda-system namespace
✅ Deleted CRD: scaledobjects

4. Deleting cost-optimized Namespace...
✅ Deleted cost-optimized namespace

5. Stopping Port Forwarding Processes...
✅ Stopped port-forward on 8080
✅ Stopped port-forward on 15672

6. Cleaning Docker Artifacts...
✅ Pruned Docker system

==================================================
✅ Lab Cleanup Complete!
==================================================
```

---

## Important Notes

1. **Port Forwarding**: The cleanup script kills all `kubectl port-forward` processes. If you have other port forwards running for different applications, they will also be stopped.

2. **Docker Registry**: If you're using the Docker registry for other projects, the cleanup script will stop and remove the `local-registry` container. Skip this step if needed.

3. **CRDs**: KEDA CRDs are cluster-scoped. The cleanup removes them. If you have other KEDA installations, this will affect them.

4. **Persistent Data**: RabbitMQ uses an EmptyDir volume by default. All data is lost on pod deletion. For production, use PersistentVolumeClaims.

5. **Helm Releases**: The cleanup uninstalls KEDA and Kubecost Helm releases. This removes all resources managed by these charts.

---

## Run Cleanup

```bash
# Save the cleanup script
chmod +x cleanup-lab.sh

# Run cleanup
./cleanup-lab.sh

# Verify cleanup
./verify-cleanup.sh
```

The lab is now completely cleaned up and ready for a fresh start! 🧹✨