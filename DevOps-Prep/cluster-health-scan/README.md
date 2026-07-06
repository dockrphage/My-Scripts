# 🏥 Kubernetes Cluster Health Scanner

> **Production-ready automation tool for comprehensive Kubernetes cluster health monitoring and diagnostics**

[![Python Version](https://img.shields.io/badge/python-3.7+-blue.svg)](https://www.python.org/downloads/)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)
[![Kubernetes](https://img.shields.io/badge/kubernetes-1.19+-blue.svg)](https://kubernetes.io/)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg)](CONTRIBUTING.md)

## 🎯 Overview

Cluster Health Scanner is a powerful, automated tool that detects and diagnoses issues in Kubernetes clusters. It intelligently scans all pods, identifies problematic containers, analyzes logs, and provides actionable root cause analysis - all without overwhelming you with raw JSON output.

### ✨ Key Features

- **🔍 Automated Scanning** - Instantly scan all pods across any namespace
- **🎯 Smart Filtering** - Detect CrashLoopBackOff, OOMKilled, ImagePullBackOff, and more
- **📊 Multiple Output Formats** - Console, JSON, HTML, Prometheus metrics
- **🤖 Root Cause Analysis** - Automated pattern detection with severity levels
- **📈 Prometheus Integration** - Export metrics for monitoring systems
- **🌐 HTML Reports** - Beautiful, shareable web reports
- **🔄 Daemon Mode** - Continuous monitoring with configurable intervals
- **🎛️ Configurable** - Custom thresholds, namespace filters, and patterns
- **📧 Notification Ready** - Slack and email integration (extensible)
- **🚀 Multi-Cluster** - Support for multiple kubeconfig contexts

## 📋 Use Cases

- **DevOps Labs** - Learn-by-doing Kubernetes troubleshooting
- **Production Monitoring** - Daily health checks and alerting
- **CI/CD Pipelines** - Post-deployment validation
- **Security Audits** - Detect misconfigurations and vulnerabilities
- **Performance Testing** - Identify resource bottlenecks
- **Disaster Recovery** - Rapid cluster health assessment

## 🚀 Quick Start

### Prerequisites

- Kubernetes cluster (v1.19+)
- kubectl configured
- Python 3.7+

### Installation

```bash
# Clone the repository
git clone https://github.com/yourusername/cluster-health-scan.git
cd cluster-health-scan

# Create virtual environment (optional but recommended)
python3 -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install pyyaml

# Make script executable
chmod +x cluster-health-scan.py
```

### Basic Usage

```bash
# Run a basic health scan
python3 cluster-health-scan.py

# Scan with specific kubeconfig
python3 cluster-health-scan.py --kubeconfig ~/.kube/config

# Generate HTML report
python3 cluster-health-scan.py --format html --output report.html

# Continuous monitoring (daemon mode)
python3 cluster-health-scan.py --daemon --interval 60

# Generate Prometheus metrics
python3 cluster-health-scan.py --format prometheus --output metrics.txt
```

## 📖 Usage Examples

### Example 1: Basic Health Check

```bash
$ python3 cluster-health-scan.py

🔍 Starting Cluster Health Scan...
============================================================
⏰ Time: 2026-07-06 11:20:33

📊 Found 42 pods in cluster

⚠️  Problematic pod: crashloop-backoff-1 (namespace: default)
   - Issues: Container app: CrashLoopBackOff, High restart count: 7

⚠️  Problematic pod: memory-hog (namespace: default)
   - Issues: Container memory-hog: CrashLoopBackOff, High restart count: 7

📋 CLUSTER HEALTH SCAN REPORT
============================================================
⏰ Scan Time: 2026-07-06T11:20:33.646161
📊 Total pods scanned: 42
🚨 Problematic pods found: 4
⚠️  Problem rate: 9.5%

🚨 PROBLEM PODS DETAILS:
----------------------------------------

🔴 #1 POD: crashloop-backoff-1
   📍 Namespace: default
   📊 Status: Running
   🔄 Restart Count: 7
   🖥️  Node: 192.168.56.11

   ⚠️  Issues Detected:
      • Container app: CrashLoopBackOff
      • High restart count: 7

   🎯 Root Cause Analysis:
      CRITICAL: Application error - check application logs for specific error messages
```

### Example 2: Generate HTML Report for Dashboard

```bash
$ python3 cluster-health-scan.py --format html --output /var/www/html/health.html
```

![HTML Report](https://via.placeholder.com/800x400?text=HTML+Report+Preview)

### Example 3: Continuous Monitoring

```bash
$ python3 cluster-health-scan.py --daemon --interval 300 --format json --output /var/log/cluster-health.json
```

### Example 4: Focus on Specific Namespaces

```bash
$ python3 cluster-health-scan.py --include-namespaces production,staging --threshold 3
```

## 🎛️ Configuration Options

### Command Line Arguments

| Argument | Description | Default |
|----------|-------------|---------|
| `--kubeconfig` | Path to kubeconfig file | `~/.kube/config` |
| `--context` | Kubernetes context to use | Current context |
| `--format` | Output format (console, json, html, prometheus) | console |
| `--output` | Output file path | None (stdout) |
| `--threshold` | Restart count threshold | 5 |
| `--include-namespaces` | Comma-separated namespaces to scan | All namespaces |
| `--exclude-namespaces` | Comma-separated namespaces to exclude | kube-system |
| `--daemon` | Run in daemon mode | False |
| `--interval` | Scan interval in seconds (daemon mode) | 300 |
| `--slack-webhook` | Slack webhook URL for notifications | None |
| `--email` | Email address for notifications | None |
| `--verbose` | Enable verbose logging | False |

### Environment Variables

| Variable | Description |
|----------|-------------|
| `KUBECONFIG` | Path to kubeconfig file |
| `CLUSTER_NAME` | Cluster name for reports |
| `SLACK_WEBHOOK` | Slack webhook URL for notifications |
| `EMAIL_RECIPIENT` | Email address for notifications |

## 📊 Output Formats

### Console (Default)
Human-readable output with colored indicators and structured sections.

### JSON
Machine-readable format for integration with other tools.

```json
{
  "total_pods": 42,
  "problem_pods": [...],
  "detailed_results": [...],
  "namespace_stats": {...},
  "scan_time": "2026-07-06T11:20:33.646161"
}
```

### HTML
Beautiful, shareable web report with statistics and visual indicators.

### Prometheus
Export metrics for Prometheus monitoring:

```
k8s_health_total_pods 42
k8s_health_problem_pods 4
k8s_health_problem_rate 9.52
k8s_health_pod_restarts{pod="crashloop-backoff-1",namespace="default"} 7
```

## 🧪 Demo / Lab Setup

For learning and demonstration purposes:

```bash
# Deploy failing pods for simulation
kubectl apply -f failing-pods.yaml

# Wait for pods to enter failing state
sleep 30

# Run the scanner
python3 cluster-health-scan.py

# Clean up
kubectl delete -f failing-pods.yaml
```

## 🔧 Extending the Scanner

### Adding Custom Error Patterns

```python
# In cluster-health-scan.py
self.error_patterns = {
    'custom_error': re.compile(r'custom error pattern', re.IGNORECASE),
    # ... existing patterns
}
```

### Adding Notification Handlers

```python
# Add your custom notification logic
def send_slack_notification(webhook_url, message):
    # Implement Slack notification
    pass

def send_email_notification(recipient, subject, body):
    # Implement email notification
    pass
```

## 📁 Project Structure

```
cluster-health-scan/
├── cluster-health-scan.py   # Main scanner script
├── cluster-health-scan.log  # Log file (auto-generated)
├── failing-pods.yaml        # Demo failing pods
├── README.md                # This file
├── LICENSE                  # MIT License
└── .gitignore              # Git ignore file
```

## 🛠️ Troubleshooting

### Common Issues

**Issue**: `error: unknown flag: --short` (kubectl version)
**Solution**: The script automatically handles this - newer kubectl versions don't support `--short`.

**Issue**: `Permission denied: /var/log/health.json`
**Solution**: Use a writable directory or run with appropriate permissions.

**Issue**: `Cannot connect to Kubernetes cluster`
**Solution**: Verify kubeconfig is correct and cluster is accessible: `kubectl cluster-info`

## 🔐 Security Considerations

- The script uses the same authentication as kubectl
- No credentials are stored or transmitted
- Logs may contain sensitive information - handle appropriately
- HTML reports could expose cluster information - restrict access

## 🤝 Contributing

Contributions are welcome! Please see [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

1. Fork the repository
2. Create a feature branch
3. Commit your changes
4. Push to the branch
5. Create a Pull Request

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🙏 Acknowledgments

- Kubernetes community for the amazing platform
- All contributors and users of this tool

## 📞 Support

- **Issues**: [GitHub Issues](https://github.com/yourusername/cluster-health-scan/issues)
- **Discussions**: [GitHub Discussions](https://github.com/yourusername/cluster-health-scan/discussions)
- **Email**: dockrphage@gmail.com
- **Master Repo**: [Github](https://github.com/dockrphage/cluster-health-scan.git)

## 🌟 Star History

[![Star History Chart](https://api.star-history.com/svg?repos=yourusername/cluster-health-scan&type=Date)](https://star-history.com/#yourusername/cluster-health-scan&Date)

---


[⬆ Back to top](#-kubernetes-cluster-health-scanner)
