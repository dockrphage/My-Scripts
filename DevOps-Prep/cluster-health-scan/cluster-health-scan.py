#!/usr/bin/env python3
"""
Cluster Health Scanner - Production Ready with All Fixes
"""

import subprocess
import json
import re
import os
import sys
import argparse
from collections import defaultdict
from datetime import datetime
from typing import Dict, List, Optional, Tuple, Any
import logging
import time
import glob

# Setup logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler('cluster-health-scan.log'),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)

class ClusterHealthScanner:
    def __init__(self, config: Dict = None, kubeconfig: str = None, context: str = None):
        """Initialize scanner with configuration"""
        self.config = self.load_default_config()
        if config:
            # Merge provided config with defaults
            for key, value in config.items():
                if key == 'filters' and isinstance(value, dict):
                    self.config['filters'].update(value)
                else:
                    self.config[key] = value
        
        self.kubeconfig = self.resolve_kubeconfig(kubeconfig)
        self.context = context
        self.error_patterns = self.load_error_patterns()
        self.problem_pods = []
        
    def resolve_kubeconfig(self, provided_kubeconfig: Optional[str]) -> str:
        """Resolve kubeconfig path with proper handling"""
        if provided_kubeconfig:
            return os.path.expanduser(provided_kubeconfig)
        
        # Check environment variable
        if os.environ.get('KUBECONFIG'):
            return os.environ.get('KUBECONFIG')
        
        # Check default locations
        home = os.path.expanduser('~')
        default_paths = [
            os.path.join(home, '.kube', 'config'),
            '/etc/kubernetes/admin.conf',
            '/var/lib/kubelet/kubeconfig'
        ]
        
        for path in default_paths:
            if os.path.exists(path):
                return path
        
        # Check for kubeconfig in current directory
        kubeconfig_files = glob.glob('*kubeconfig*')
        if kubeconfig_files:
            return kubeconfig_files[0]
        
        return '~/.kube/config'
    
    def load_default_config(self) -> Dict:
        """Load default configuration"""
        return {
            'restart_threshold': 5,
            'log_lines': 50,
            'max_events': 5,
            'scan_interval': 30,
            'report_format': 'json',
            'notifications': {
                'slack_webhook': os.environ.get('SLACK_WEBHOOK'),
                'email': os.environ.get('EMAIL_RECIPIENT')
            },
            'filters': {
                'namespaces': [],
                'exclude_namespaces': ['kube-system'],
                'min_restart_count': 3
            }
        }
    
    def load_error_patterns(self) -> Dict:
        """Load error patterns from configuration or use defaults"""
        return {
            'crashloop': re.compile(r'CrashLoopBackOff', re.IGNORECASE),
            'oomkilled': re.compile(r'OOMKilled|Out of memory', re.IGNORECASE),
            'config_error': re.compile(r'config|ConfigMap.*not found|Missing.*config', re.IGNORECASE),
            'port_conflict': re.compile(r'port.*already in use|address already in use', re.IGNORECASE),
            'dependency_error': re.compile(r'connection refused|no route to host|unreachable', re.IGNORECASE),
            'permission_error': re.compile(r'permission denied|access denied', re.IGNORECASE),
            'timeout_error': re.compile(r'timeout|deadline exceeded', re.IGNORECASE),
            'resource_limit': re.compile(r'exceeded.*memory|exceeded.*cpu|resource quota', re.IGNORECASE),
            'image_error': re.compile(r'image pull|pull.*failed|not found|nonexistent', re.IGNORECASE),
            'health_check': re.compile(r'liveness probe|readiness probe|health check', re.IGNORECASE),
            'certificate_error': re.compile(r'certificate|ssl|tls', re.IGNORECASE),
            'database_error': re.compile(r'database|connection pool|sql|postgres|mysql', re.IGNORECASE),
            'memory_pressure': re.compile(r'memory pressure|evicted|node pressure', re.IGNORECASE),
            'disk_pressure': re.compile(r'disk pressure|disk space|ephemeral storage', re.IGNORECASE)
        }
    
    def run_kubectl_command(self, command: List[str]) -> Tuple[str, str]:
        """Execute kubectl command with proper error handling"""
        cmd = ['kubectl']
        
        # Use provided kubeconfig
        if self.kubeconfig and os.path.exists(os.path.expanduser(self.kubeconfig)):
            cmd.extend(['--kubeconfig', os.path.expanduser(self.kubeconfig)])
        
        if self.context:
            cmd.extend(['--context', self.context])
        
        cmd.extend(command)
        
        try:
            result = subprocess.run(
                cmd,
                capture_output=True,
                text=True,
                check=False,
                timeout=60
            )
            return result.stdout, result.stderr
        except subprocess.TimeoutExpired:
            logger.error(f"Command timed out: {' '.join(cmd)}")
            return "", "Timeout"
        except FileNotFoundError:
            logger.error("kubectl not found. Please install kubectl.")
            return "", "kubectl not installed"
        except Exception as e:
            logger.error(f"Error executing command: {e}")
            return "", str(e)
    
    def check_kubectl_available(self) -> bool:
        """Check if kubectl is available and cluster is accessible"""
        stdout, stderr = self.run_kubectl_command(['version', '--short'])
        
        if stderr and ('not found' in stderr.lower() or 'error' in stderr.lower()):
            logger.error(f"kubectl not properly configured: {stderr}")
            # Try without --short flag for newer kubectl versions
            stdout, stderr = self.run_kubectl_command(['version'])
            if stderr and ('error' in stderr.lower() or 'unable' in stderr.lower()):
                return False
        
        # Check if we can connect to cluster
        stdout, stderr = self.run_kubectl_command(['cluster-info'])
        if stderr and ('error' in stderr.lower() or 'unable' in stderr.lower()):
            logger.error(f"Cannot connect to Kubernetes cluster: {stderr}")
            logger.error(f"Please check: KUBECONFIG={self.kubeconfig}")
            return False
        
        return True
    
    def get_cluster_info(self) -> Dict:
        """Get cluster information"""
        nodes_stdout, _ = self.run_kubectl_command(['get', 'nodes', '-o', 'json'])
        
        info = {
            'cluster_name': os.environ.get('CLUSTER_NAME', 'unknown'),
            'scan_time': datetime.now().isoformat(),
            'nodes': 0,
            'node_details': []
        }
        
        try:
            if nodes_stdout:
                nodes_data = json.loads(nodes_stdout)
                info['nodes'] = len(nodes_data.get('items', []))
                for node in nodes_data.get('items', []):
                    node_info = {
                        'name': node['metadata']['name'],
                        'status': node['status']['conditions'][-1]['type'] if node['status'].get('conditions') else 'Unknown',
                        'os': node['status']['nodeInfo']['osImage'] if node['status'].get('nodeInfo') else 'Unknown',
                        'kernel': node['status']['nodeInfo']['kernelVersion'] if node['status'].get('nodeInfo') else 'Unknown'
                    }
                    info['node_details'].append(node_info)
        except Exception as e:
            logger.warning(f"Could not get node details: {e}")
            
        return info
    
    def get_all_pods(self) -> List[Dict]:
        """Get all pods across all namespaces"""
        stdout, stderr = self.run_kubectl_command([
            'get', 'pods', '--all-namespaces', '-o', 'json'
        ])
        
        if not stdout:
            if stderr:
                logger.error(f"Error getting pods: {stderr}")
            return []
        
        try:
            data = json.loads(stdout)
            return data.get('items', [])
        except json.JSONDecodeError:
            logger.error("Failed to parse JSON output")
            return []
    
    def analyze_pod_status(self, pod: Dict) -> Optional[Dict]:
        """Analyze pod status and extract issues"""
        status = pod.get('status', {})
        metadata = pod.get('metadata', {})
        
        phase = status.get('phase', '')
        if phase in ['Succeeded', 'Completed']:
            return None
        
        namespace = metadata.get('namespace', 'default')
        exclude_namespaces = self.config['filters'].get('exclude_namespaces', ['kube-system'])
        if namespace in exclude_namespaces:
            return None
        
        include_namespaces = self.config['filters'].get('namespaces', [])
        if include_namespaces and namespace not in include_namespaces:
            return None
        
        problem_found = False
        issues = []
        restart_count = 0
        container_statuses = status.get('containerStatuses', [])
        
        for container in container_statuses:
            restart_count += container.get('restartCount', 0)
            
            state = container.get('state', {})
            if 'waiting' in state:
                reason = state['waiting'].get('reason', '')
                if reason in ['CrashLoopBackOff', 'ImagePullBackOff', 'ErrImagePull']:
                    problem_found = True
                    issues.append(f"Container {container.get('name')}: {reason}")
            
            if 'terminated' in state:
                reason = state['terminated'].get('reason', '')
                if reason in ['Error', 'OOMKilled']:
                    problem_found = True
                    issues.append(f"Container {container.get('name')}: Terminated with {reason}")
        
        if restart_count > self.config['restart_threshold']:
            problem_found = True
            issues.append(f"High restart count: {restart_count}")
        
        if problem_found or phase == 'Failed':
            return {
                'name': metadata.get('name'),
                'namespace': namespace,
                'phase': phase,
                'restart_count': restart_count,
                'issues': issues,
                'container_names': [c.get('name') for c in container_statuses],
                'node_name': status.get('hostIP', 'unknown'),
                'pod_ip': status.get('podIP', 'unknown'),
                'creation_time': metadata.get('creationTimestamp', 'unknown'),
                'labels': metadata.get('labels', {}),
                'annotations': metadata.get('annotations', {})
            }
        
        return None
    
    def get_pod_logs(self, namespace: str, pod_name: str, container: str = None) -> str:
        """Get logs from a pod"""
        cmd = ['logs', pod_name, '-n', namespace]
        if container:
            cmd.extend(['-c', container])
        cmd.extend(['--tail', str(self.config['log_lines'])])
        
        stdout, stderr = self.run_kubectl_command(cmd)
        return stdout if stdout else stderr
    
    def extract_error_patterns(self, logs: str) -> List[Dict]:
        """Extract error patterns from logs with severity"""
        found_errors = []
        if not logs:
            return found_errors
        
        for pattern_name, pattern in self.error_patterns.items():
            if pattern.search(logs):
                # Get some context around the error
                context_lines = []
                for line in logs.split('\n'):
                    if pattern.search(line):
                        context_lines.append(line.strip()[:100])
                        if len(context_lines) >= 2:
                            break
                
                found_errors.append({
                    'pattern': pattern_name.replace('_', ' ').title(),
                    'severity': self.get_severity(pattern_name),
                    'examples': context_lines[:2]
                })
        
        return found_errors
    
    def get_severity(self, pattern_name: str) -> str:
        """Determine severity of error pattern"""
        critical = ['oomkilled', 'crashloop', 'image_error']
        high = ['resource_limit', 'dependency_error', 'certificate_error']
        medium = ['config_error', 'permission_error', 'disk_pressure', 'memory_pressure']
        
        if pattern_name in critical:
            return 'CRITICAL'
        elif pattern_name in high:
            return 'HIGH'
        elif pattern_name in medium:
            return 'MEDIUM'
        else:
            return 'LOW'
    
    def get_pod_events(self, namespace: str, pod_name: str) -> List[str]:
        """Get events related to a pod"""
        stdout, _ = self.run_kubectl_command([
            'describe', 'pod', pod_name, '-n', namespace
        ])
        
        events = []
        in_events = False
        for line in stdout.split('\n'):
            if 'Events:' in line:
                in_events = True
                continue
            if in_events and line.strip() and not line.startswith('  '):
                break
            if in_events and line.strip():
                events.append(line.strip())
        
        return events[:self.config['max_events']]
    
    def generate_prometheus_metrics(self, scan_results: Dict) -> str:
        """Generate Prometheus metrics format"""
        metrics = []
        
        # Cluster metrics
        metrics.append(f"k8s_health_total_pods {scan_results['total_pods']}")
        metrics.append(f"k8s_health_problem_pods {len(scan_results['problem_pods'])}")
        
        if scan_results['total_pods'] > 0:
            metrics.append(f"k8s_health_problem_rate {((len(scan_results['problem_pods'])/scan_results['total_pods'])*100):.2f}")
        
        # Problem pod details
        for pod in scan_results['detailed_results']:
            metrics.append(f'k8s_health_pod_restarts{{pod="{pod["name"]}",namespace="{pod["namespace"]}"}} {pod["restart_count"]}')
            for issue in pod['issues']:
                metrics.append(f'k8s_health_pod_issues{{pod="{pod["name"]}",issue="{issue}"}} 1')
        
        return "\n".join(metrics)
    
    def generate_html_report(self, scan_results: Dict) -> str:
        """Generate HTML report for web viewing"""
        html = """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="UTF-8">
            <title>Cluster Health Scan Report</title>
            <style>
                * { box-sizing: border-box; }
                body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, 'Helvetica Neue', Arial, sans-serif; margin: 20px; background: #f5f7fa; }
                .container { max-width: 1200px; margin: 0 auto; background: white; padding: 20px; border-radius: 12px; box-shadow: 0 2px 12px rgba(0,0,0,0.1); }
                .header { background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); color: white; padding: 20px; border-radius: 8px; margin-bottom: 20px; }
                .stats { display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 20px; margin: 20px 0; }
                .stat-card { background: #f8f9fa; padding: 15px; border-radius: 8px; border-left: 4px solid #667eea; }
                .stat-number { font-size: 2em; font-weight: bold; color: #333; }
                .stat-label { color: #666; font-size: 0.9em; }
                .pod-card { background: white; border: 1px solid #e0e0e0; border-radius: 8px; padding: 15px; margin: 15px 0; }
                .pod-header { display: flex; justify-content: space-between; align-items: center; flex-wrap: wrap; }
                .pod-name { font-weight: bold; font-size: 1.1em; }
                .badge { display: inline-block; padding: 3px 8px; border-radius: 4px; font-size: 0.8em; font-weight: bold; }
                .badge-critical { background: #dc3545; color: white; }
                .badge-high { background: #fd7e14; color: white; }
                .badge-medium { background: #ffc107; color: black; }
                .badge-low { background: #28a745; color: white; }
                .issues { margin: 10px 0; }
                .issue-item { background: #fff3cd; padding: 5px 10px; margin: 5px 0; border-radius: 4px; }
                .logs { background: #f8f9fa; padding: 10px; border-radius: 4px; font-family: monospace; font-size: 0.9em; white-space: pre-wrap; overflow-x: auto; }
                .timestamp { color: #666; font-size: 0.8em; }
                .no-pods { text-align: center; padding: 40px; color: #666; }
            </style>
        </head>
        <body>
            <div class="container">
                <div class="header">
                    <h1>🔍 Kubernetes Cluster Health Scan</h1>
                    <p>Scan Time: """ + scan_results['scan_time'] + """</p>
        """
        
        if scan_results.get('cluster_info'):
            html += f"<p>Cluster: {scan_results['cluster_info'].get('cluster_name', 'unknown')} | Nodes: {scan_results['cluster_info'].get('nodes', 0)}</p>"
        
        html += """
                </div>
        """
        
        if scan_results['total_pods'] == 0:
            html += """
                <div class="no-pods">
                    <h2>⚠️ No pods found</h2>
                    <p>Could not connect to Kubernetes cluster or no pods are running.</p>
                </div>
            """
        else:
            html += """
                <div class="stats">
                    <div class="stat-card">
                        <div class="stat-number">""" + str(scan_results['total_pods']) + """</div>
                        <div class="stat-label">Total Pods</div>
                    </div>
                    <div class="stat-card">
                        <div class="stat-number">""" + str(len(scan_results['problem_pods'])) + """</div>
                        <div class="stat-label">Problem Pods</div>
                    </div>
                    <div class="stat-card">
                        <div class="stat-number">""" + (f"{((len(scan_results['problem_pods'])/scan_results['total_pods'])*100):.1f}%" if scan_results['total_pods'] > 0 else "0%") + """</div>
                        <div class="stat-label">Problem Rate</div>
                    </div>
                    <div class="stat-card">
                        <div class="stat-number">""" + str(len(scan_results['namespace_stats'])) + """</div>
                        <div class="stat-label">Namespaces</div>
                    </div>
                </div>
            """
            
            # Add problem pods
            for pod in scan_results['detailed_results']:
                html += f"""
                    <div class="pod-card">
                        <div class="pod-header">
                            <div>
                                <span class="pod-name">🔴 {pod['name']}</span>
                                <span class="badge badge-critical">CRITICAL</span>
                            </div>
                            <div class="timestamp">Restarts: {pod['restart_count']}</div>
                        </div>
                        <p><strong>Namespace:</strong> {pod['namespace']} | <strong>Node:</strong> {pod['node_name']}</p>
                        <div class="issues">
                            <strong>Issues:</strong>
                            <ul>
                """
                for issue in pod['issues']:
                    html += f"<li class='issue-item'>{issue}</li>"
                html += """
                            </ul>
                        </div>
                        <div class="logs">
                            <strong>Log Sample:</strong>
                """
                for log_entry in pod['logs_summary']:
                    html += f"<p><em>Container: {log_entry['container']}</em></p>"
                    html += f"<p>{log_entry['sample_logs']}</p>"
                html += """
                        </div>
                    </div>
                """
        
        html += """
            </div>
        </body>
        </html>
        """
        
        return html
    
    def scan_cluster(self) -> Dict:
        """Main scanning function with enhanced features"""
        # Check if kubectl is available
        if not self.check_kubectl_available():
            return {
                'total_pods': 0,
                'problem_pods': [],
                'detailed_results': [],
                'namespace_stats': {},
                'scan_time': datetime.now().isoformat(),
                'cluster_info': {'cluster_name': 'unavailable', 'nodes': 0},
                'error': 'Kubernetes cluster not accessible'
            }
        
        logger.info("🔍 Starting Cluster Health Scan...")
        logger.info("=" * 60)
        
        # Get cluster info
        cluster_info = self.get_cluster_info()
        logger.info(f"Cluster: {cluster_info['cluster_name']}")
        logger.info(f"Nodes: {cluster_info['nodes']}")
        
        pods = self.get_all_pods()
        total_pods = len(pods)
        problem_pods = []
        namespace_stats = defaultdict(int)
        
        logger.info(f"📊 Found {total_pods} pods in cluster")
        
        if total_pods == 0:
            logger.warning("No pods found in cluster")
            return {
                'total_pods': 0,
                'problem_pods': [],
                'detailed_results': [],
                'namespace_stats': {},
                'scan_time': datetime.now().isoformat(),
                'cluster_info': cluster_info
            }
        
        for pod in pods:
            metadata = pod.get('metadata', {})
            namespace = metadata.get('namespace', 'default')
            namespace_stats[namespace] += 1
            
            problem = self.analyze_pod_status(pod)
            if problem:
                problem_pods.append(problem)
        
        # Process problem pods for deep analysis
        detailed_results = []
        for problem in problem_pods:
            namespace = problem['namespace']
            pod_name = problem['name']
            
            logger.warning(f"⚠️  Problematic pod: {pod_name} (namespace: {namespace})")
            logger.info(f"   Issues: {', '.join(problem['issues'])}")
            
            # Get logs for each container
            logs_summary = []
            for container in problem['container_names']:
                logs = self.get_pod_logs(namespace, pod_name, container)
                error_patterns = self.extract_error_patterns(logs)
                
                if logs:
                    log_lines = logs.split('\n')
                    log_summary = '\n'.join(log_lines[:3] + ['...'] + log_lines[-3:]) if len(log_lines) > 6 else logs
                    logs_summary.append({
                        'container': container,
                        'sample_logs': log_summary,
                        'error_patterns': error_patterns
                    })
            
            # Get events
            events = self.get_pod_events(namespace, pod_name)
            
            # Analyze root cause with enhanced logic
            root_cause = self.analyze_root_cause(logs_summary, events, problem)
            
            detailed_results.append({
                **problem,
                'logs_summary': logs_summary,
                'events': events[:5],
                'root_cause': root_cause,
                'cluster_info': cluster_info
            })
        
        scan_results = {
            'total_pods': total_pods,
            'problem_pods': problem_pods,
            'detailed_results': detailed_results,
            'namespace_stats': dict(namespace_stats),
            'scan_time': datetime.now().isoformat(),
            'cluster_info': cluster_info
        }
        
        return scan_results
    
    def analyze_root_cause(self, logs_summary: List[Dict], events: List[str], problem: Dict) -> str:
        """Enhanced root cause analysis with severity levels"""
        all_errors = []
        severity_levels = []
        
        for log_entry in logs_summary:
            for error in log_entry.get('error_patterns', []):
                all_errors.append(error['pattern'])
                severity_levels.append(error['severity'])
        
        # Check for critical errors first
        if 'Image Error' in all_errors:
            return "CRITICAL: Image pull issue - verify image exists in registry, check registry credentials and network connectivity. Check if image is accessible from the cluster."
        
        if 'Crashloop' in all_errors:
            if 'OOMKilled' in str(problem['issues']):
                return "CRITICAL: Memory limit exceeded - increase memory limits or optimize application memory usage. Consider using memory profiling tools."
            elif 'Config Error' in all_errors:
                return "HIGH: Configuration issue - verify ConfigMap/Secret references exist and are correctly named. Check for typos and case sensitivity."
            elif 'Dependency Error' in all_errors:
                return "HIGH: Service dependency unavailable - check if required services are running and network policies allow connectivity. Verify service endpoints."
            elif 'Permission Error' in all_errors:
                return "MEDIUM: Permission issue - check file permissions, security contexts, and volume mounts. Verify service account permissions."
            else:
                return "HIGH: Application error - check application logs for specific error messages and exception traces. Consider adding more logging."
        
        if 'ImagePullBackOff' in str(problem['issues']):
            return "CRITICAL: Image pull authentication/network issue - check container registry access, credentials, and network policies. Verify image name and tag."
        
        if 'Resource Limit' in all_errors:
            return "HIGH: Resource quota exceeded - check cluster resource limits and adjust requests/limits. Consider scaling resources or optimizing application."
        
        if 'Certificate Error' in all_errors:
            return "HIGH: Certificate/SSL issue - check certificate validity, expiry dates, and trust chains. Renew certificates if expired."
        
        if 'Database Error' in all_errors:
            return "HIGH: Database connectivity issue - check database service availability, connection strings, and network policies."
        
        if not all_errors and not events:
            return "INFO: No specific error patterns found. Check pod configuration, environment variables, and volume mounts. Consider manual inspection."
        
        return f"Multiple issues detected: {', '.join(all_errors[:3])}. Investigate logs and events for details. Severity: {', '.join(severity_levels[:3])}"
    
    def generate_report(self, scan_results: Dict, format: str = 'console', output_file: str = None) -> str:
        """Generate report in specified format"""
        
        if format == 'json':
            report = json.dumps(scan_results, indent=2, default=str)
            if output_file:
                try:
                    with open(output_file, 'w') as f:
                        f.write(report)
                    logger.info(f"JSON report saved to {output_file}")
                except PermissionError:
                    logger.error(f"Permission denied: {output_file}")
                    return report
            return report
        
        if format == 'prometheus':
            report = self.generate_prometheus_metrics(scan_results)
            if output_file:
                try:
                    with open(output_file, 'w') as f:
                        f.write(report)
                    logger.info(f"Prometheus metrics saved to {output_file}")
                except PermissionError:
                    logger.error(f"Permission denied: {output_file}")
                    return report
            return report
        
        if format == 'html':
            report = self.generate_html_report(scan_results)
            if output_file:
                try:
                    with open(output_file, 'w') as f:
                        f.write(report)
                    logger.info(f"HTML report saved to {output_file}")
                except PermissionError:
                    logger.error(f"Permission denied: {output_file}")
                    return report
            return report
        
        # Console format (default)
        return self.generate_console_report(scan_results)
    
    def generate_console_report(self, scan_results: Dict) -> str:
        """Generate console-friendly report"""
        output = []
        
        output.append("\n" + "=" * 60)
        output.append("📋 CLUSTER HEALTH SCAN REPORT")
        output.append("=" * 60)
        output.append(f"⏰ Scan Time: {scan_results['scan_time']}")
        
        if scan_results.get('error'):
            output.append(f"❌ Error: {scan_results['error']}")
            output.append("\n" + "=" * 60)
            return "\n".join(output)
        
        output.append(f"📊 Total pods scanned: {scan_results['total_pods']}")
        output.append(f"🚨 Problematic pods found: {len(scan_results['problem_pods'])}")
        
        if scan_results['total_pods'] > 0 and len(scan_results['problem_pods']) > 0:
            output.append(f"⚠️  Problem rate: {((len(scan_results['problem_pods'])/scan_results['total_pods'])*100):.1f}%")
        
        output.append("\n📊 Namespace Distribution:")
        for namespace, count in sorted(scan_results['namespace_stats'].items()):
            output.append(f"   - {namespace}: {count} pods")
        
        if scan_results['detailed_results']:
            output.append("\n🚨 PROBLEM PODS DETAILS:")
            output.append("-" * 40)
            
            for idx, result in enumerate(scan_results['detailed_results'], 1):
                output.append(f"\n🔴 #{idx} POD: {result['name']}")
                output.append(f"   📍 Namespace: {result['namespace']}")
                output.append(f"   📊 Status: {result['phase']}")
                output.append(f"   🔄 Restart Count: {result['restart_count']}")
                output.append(f"   🖥️  Node: {result.get('node_name', 'unknown')}")
                
                output.append(f"\n   ⚠️  Issues Detected:")
                for issue in result['issues']:
                    output.append(f"      • {issue}")
                
                output.append(f"\n   🎯 Root Cause Analysis:")
                output.append(f"      {result['root_cause']}")
                
                output.append("\n   📝 Recent Events:")
                if result['events']:
                    for event in result['events']:
                        output.append(f"      • {event}")
                else:
                    output.append("      No recent events")
                
                output.append(f"\n   📋 Log Analysis:")
                for log_entry in result['logs_summary']:
                    output.append(f"\n      Container: {log_entry['container']}")
                    if log_entry['error_patterns']:
                        output.append(f"      ⚠️  Error Patterns Found:")
                        for error in log_entry['error_patterns']:
                            output.append(f"         - {error['pattern']} (Severity: {error['severity']})")
                    else:
                        output.append("      ✅ No error patterns detected in logs")
                    output.append("      Log Sample:")
                    for line in log_entry['sample_logs'].split('\n'):
                        output.append(f"        {line}")
                
                output.append("-" * 30)
        
        # Recommendations
        output.append("\n💡 RECOMMENDATIONS:")
        if len(scan_results['problem_pods']) > 0:
            output.append("1. 🔍 Use 'kubectl describe pod <pod-name> -n <namespace>' for detailed events")
            output.append("2. 📈 Check resource limits and requests")
            output.append("3. 🔧 Verify ConfigMaps, Secrets, and volume mounts")
            output.append("4. 🖥️  Monitor node resource usage with 'kubectl top nodes'")
            output.append("5. 🏥 Consider implementing health checks and probes")
            output.append("6. 📊 Review application logs for specific error patterns")
            output.append("7. 🔄 Check for known issues with the container images")
            output.append("8. 📧 Consider enabling notifications for critical issues")
        else:
            output.append("✅ Cluster appears healthy! Keep monitoring.")
        
        output.append("\n🔧 USEFUL COMMANDS:")
        output.append("   • Watch pods: kubectl get pods -w")
        output.append("   • Check events: kubectl get events --all-namespaces")
        output.append("   • Describe node: kubectl describe node <node-name>")
        output.append("   • View logs: kubectl logs <pod-name> -n <namespace>")
        
        output.append("\n" + "=" * 60)
        
        return "\n".join(output)

def main():
    """Main entry point with argument parsing"""
    parser = argparse.ArgumentParser(
        description='Kubernetes Cluster Health Scanner - Production Ready',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Basic scan with automatic kubeconfig detection
  python3 cluster-health-scan.py
  
  # Scan with specific kubeconfig
  python3 cluster-health-scan.py --kubeconfig ~/.kube/config
  
  # Scan specific namespace with custom threshold
  python3 cluster-health-scan.py --include-namespaces default,production --threshold 3
  
  # Generate HTML report
  python3 cluster-health-scan.py --format html --output report.html
  
  # Run as daemon with 60 second intervals
  python3 cluster-health-scan.py --daemon --interval 60
  
  # Generate Prometheus metrics
  python3 cluster-health-scan.py --format prometheus --output metrics.txt
        """
    )
    
    parser.add_argument('--context', help='Kubernetes context to use')
    parser.add_argument('--kubeconfig', help='Path to kubeconfig file')
    parser.add_argument('--format', choices=['console', 'json', 'html', 'prometheus'], 
                       default='console', help='Output format (default: console)')
    parser.add_argument('--output', help='Output file path')
    parser.add_argument('--threshold', type=int, default=5, help='Restart threshold (default: 5)')
    parser.add_argument('--exclude-namespaces', help='Comma-separated namespaces to exclude')
    parser.add_argument('--include-namespaces', help='Comma-separated namespaces to include')
    parser.add_argument('--slack-webhook', help='Slack webhook URL for notifications')
    parser.add_argument('--email', help='Email address for notifications')
    parser.add_argument('--daemon', action='store_true', help='Run as daemon with periodic scans')
    parser.add_argument('--interval', type=int, default=300, help='Scan interval in seconds for daemon mode (default: 300)')
    parser.add_argument('--verbose', action='store_true', help='Enable verbose logging')
    
    args = parser.parse_args()
    
    # Set logging level
    if args.verbose:
        logging.getLogger().setLevel(logging.DEBUG)
    
    # Configure scanner
    config = {}
    if args.exclude_namespaces:
        config['filters'] = {'exclude_namespaces': args.exclude_namespaces.split(',')}
    if args.include_namespaces:
        config['filters'] = config.get('filters', {})
        config['filters']['namespaces'] = args.include_namespaces.split(',')
    if args.threshold:
        config['restart_threshold'] = args.threshold
    
    scanner = ClusterHealthScanner(config, args.kubeconfig, args.context)
    
    # Daemon mode
    if args.daemon:
        logger.info(f"Starting daemon mode - scanning every {args.interval} seconds")
        logger.info(f"Using kubeconfig: {scanner.kubeconfig}")
        
        while True:
            try:
                results = scanner.scan_cluster()
                report = scanner.generate_report(results, args.format, args.output)
                
                if not args.output:
                    print(report)
                time.sleep(args.interval)
            except KeyboardInterrupt:
                logger.info("Shutting down daemon")
                break
            except Exception as e:
                logger.error(f"Error in daemon scan: {e}")
                time.sleep(args.interval)
        return
    
    # Single scan
    try:
        results = scanner.scan_cluster()
        report = scanner.generate_report(results, args.format, args.output)
        
        if not args.output:
            print(report)
            
    except KeyboardInterrupt:
        logger.info("Scan interrupted by user")
        sys.exit(1)
    except Exception as e:
        logger.error(f"Error during scan: {e}")
        sys.exit(1)

if __name__ == "__main__":
    main()
