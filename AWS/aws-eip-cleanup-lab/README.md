# 📚 Complete Implementation Guide
## AWS EIP Cleanup - On-Premise Learning Lab
Idea & Inspiration from: Harish Shetty https://www.youtube.com/watch?v=E8RXpknD4cA

### 🎯 **Project Objective**
Build a production-grade AWS cost optimization solution on your laptop using LocalStack (zero AWS costs) for DevOps learning and interview preparation.

---

## 📋 **Table of Contents**
1. [Phase 0: Prerequisites & Environment Setup](#phase-0)
2. [Phase 1: LocalStack Configuration](#phase-1)
3. [Phase 2: Core Cleanup Engine](#phase-2)
4. [Phase 3: Database & Audit Layer](#phase-3)
5. [Phase 4: FastAPI Dashboard](#phase-4)
6. [Phase 5: Email Notifications](#phase-5)
7. [Phase 6: Scheduling & Automation](#phase-6)
8. [Phase 7: Monitoring & Observability](#phase-7)
9. [Lessons Learned & Debug Guide](#lessons-learned)
10. [Interview Preparation](#interview-prep)

---

## Phase 0: Prerequisites & Environment Setup {#phase-0}

### **0.1 System Requirements**
- **Hardware**: Laptop (8GB+ RAM, 20GB+ free disk)
- **OS**: Ubuntu 20.04+ / macOS / Windows with WSL2
- **Software**: Docker Desktop, Python 3.9+, Git

### **0.2 Installation Commands**

```bash
# 1. Create Project Directory
mkdir -p ~/projects/aws-eip-cleanup-lab
cd ~/projects/aws-eip-cleanup-lab

# 2. Initialize Git Repository
git init
echo "*.pyc" > .gitignore
echo "__pycache__/" >> .gitignore
echo ".env" >> .gitignore
echo "*.log" >> .gitignore
echo "localstack_data/" >> .gitignore
echo "postgres_data/" >> .gitignore
echo "venv/" >> .gitignore
git add .gitignore
git commit -m "Initial project setup"

# 3. Create Python Virtual Environment
python3 -m venv venv
source venv/bin/activate  # On Windows: venv\Scripts\activate

# 4. Upgrade pip
pip install --upgrade pip

# 5. Create Project Structure
mkdir -p scripts logs reports config monitoring
mkdir -p localstack_data postgres_data smtp4dev_data
```

### **0.3 Create requirements.txt**

```bash
cat > requirements.txt << 'EOF'
# AWS SDK
boto3>=1.34.0
botocore>=1.34.0

# Database
psycopg2-binary>=2.9.0

# Web Framework
fastapi>=0.104.0
uvicorn>=0.24.0
pydantic>=2.0.0

# Utilities
python-dotenv>=1.0.0
requests>=2.31.0
python-dateutil>=2.8.2

# Monitoring
prometheus-client>=0.19.0

# Testing
pytest>=7.0.0
pytest-cov>=4.0.0

# LocalStack Tools
localstack-client>=2.0.0
awscli-local>=0.22.0
EOF

# Install all dependencies
pip install -r requirements.txt
```

---

## Phase 1: LocalStack Configuration {#phase-1}

### **1.1 Get LocalStack Auth Token (Pro Version)**

```bash
# 1. Create account at: https://app.localstack.cloud
# 2. Go to Settings → Auth Tokens
# 3. Copy your token

# Add token to shell profile
echo 'export LOCALSTACK_AUTH_TOKEN="your-token-here"' >> ~/.bashrc
source ~/.bashrc

# Verify token is set
echo $LOCALSTACK_AUTH_TOKEN
```

### **1.2 Docker Compose Configuration**

```bash
cat > docker-compose.yml << 'EOF'
services:
  # ============================================
  # AWS Emulator - LocalStack
  # ============================================
  localstack:
    image: localstack/localstack:latest
    container_name: aws-emulator
    ports:
      - "4566:4566"      # Main API endpoint
      - "4571:4571"      # SNS
    environment:
      - SERVICES=ec2,sns,events,lambda,cloudwatch
      - DEBUG=0
      - PERSISTENCE=1
      - SKIP_INFRA_DOWNLOADS=1
      - LOCALSTACK_AUTH_TOKEN=${LOCALSTACK_AUTH_TOKEN}
      - AWS_ACCESS_KEY_ID=test
      - AWS_SECRET_ACCESS_KEY=test
      - AWS_DEFAULT_REGION=us-east-1
      - DOCKER_HOST=unix:///var/run/docker.sock
    volumes:
      - ./localstack_data:/var/lib/localstack
      - /var/run/docker.sock:/var/run/docker.sock
    networks:
      - eip-network
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:4566/_localstack/health"]
      interval: 10s
      timeout: 5s
      retries: 5

  # ============================================
  # PostgreSQL - Audit & State Storage
  # ============================================
  postgres:
    image: postgres:14-alpine
    container_name: eip-database
    environment:
      POSTGRES_USER: eip_user
      POSTGRES_PASSWORD: eip_pass
      POSTGRES_DB: eip_cleanup
    ports:
      - "5432:5432"
    volumes:
      - ./postgres_data:/var/lib/postgresql/data
      - ./scripts:/docker-entrypoint-initdb.d:ro
    networks:
      - eip-network
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U eip_user -d eip_cleanup"]
      interval: 10s
      timeout: 5s
      retries: 5

  # ============================================
  # Email Capture (Local SMTP Server)
  # ============================================
  smtp4dev:
    image: rnwood/smtp4dev:latest
    container_name: email-capture
    ports:
      - "5000:80"        # Web UI
      - "25:25"          # SMTP port
    volumes:
      - ./smtp4dev_data:/smtp4dev
    networks:
      - eip-network

  # ============================================
  # Prometheus - Metrics Collection
  # ============================================
  prometheus:
    image: prom/prometheus:latest
    container_name: prometheus
    ports:
      - "9090:9090"
    volumes:
      - ./prometheus_data:/prometheus
      - ./prometheus/prometheus.yml:/etc/prometheus/prometheus.yml:ro
    networks:
      - eip-network
    profiles:
      - monitoring

  # ============================================
  # Grafana - Visualization
  # ============================================
  grafana:
    image: grafana/grafana:latest
    container_name: grafana
    ports:
      - "3000:3000"
    environment:
      - GF_SECURITY_ADMIN_PASSWORD=admin
    volumes:
      - ./grafana_data:/var/lib/grafana
    networks:
      - eip-network
    profiles:
      - monitoring

networks:
  eip-network:
    driver: bridge

volumes:
  localstack_data:
  postgres_data:
  smtp4dev_data:
  prometheus_data:
  grafana_data:
EOF
```

### **1.3 Start LocalStack**

```bash
# Start services
export LOCALSTACK_AUTH_TOKEN=ls-PogA5430-KUZe-SUZE-pETi-6631jOCac93e
docker-compose up -d

# Wait for initialization
sleep 20

# Verify LocalStack is working
curl http://localhost:4566/_localstack/health

# Expected output shows ec2 and sns as "available"
```

---

## Phase 2: Core Cleanup Engine {#phase-2}

### **2.1 Database Initialization Script**

```bash
cat > scripts/init_db.sql << 'EOF'
-- Create tables for audit trail
CREATE TABLE IF NOT EXISTS eip_audit (
    id SERIAL PRIMARY KEY,
    public_ip VARCHAR(15) NOT NULL,
    allocation_id VARCHAR(50) NOT NULL,
    region VARCHAR(20) NOT NULL,
    status VARCHAR(20) NOT NULL,
    instance_id VARCHAR(50),
    action_timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    dry_run BOOLEAN DEFAULT TRUE,
    error_message TEXT
);

CREATE TABLE IF NOT EXISTS scan_history (
    id SERIAL PRIMARY KEY,
    scan_timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    total_eips INTEGER,
    attached_eips INTEGER,
    unattached_eips INTEGER,
    deleted_count INTEGER,
    error_count INTEGER,
    duration_seconds FLOAT
);

CREATE INDEX idx_eip_audit_timestamp ON eip_audit(action_timestamp);
CREATE INDEX idx_scan_history_timestamp ON scan_history(scan_timestamp);
EOF
```

### **2.2 Main EIP Cleanup Script**

```bash
cat > eip_cleanup.py << 'EOF'
#!/usr/bin/env python3
"""
AWS EIP Cleanup - On-Premise Learning Edition
Zero AWS costs, 100% LocalStack emulation
DevOps Interview Preparation
"""

import boto3
import json
import logging
import os
import sys
import time
import psycopg2
import smtplib
from datetime import datetime
from email.mime.text import MIMEText
from email.mime.multipart import MIMEMultipart
from dataclasses import dataclass, asdict
from typing import Dict, List, Optional, Any
from prometheus_client import Counter, Gauge, Histogram, start_http_server
import threading
import argparse

# ============================================
# Configuration
# ============================================
@dataclass
class Config:
    """Configuration class - 12-Factor App compliant"""
    use_emulator: bool = True
    endpoint_url: str = "http://localhost:4566"
    aws_access_key: str = "test"
    aws_secret_key: str = "test"
    regions: List[str] = None
    db_host: str = "localhost"
    db_port: int = 5432
    db_name: str = "eip_cleanup"
    db_user: str = "eip_user"
    db_password: str = "eip_pass"
    smtp_host: str = "localhost"
    smtp_port: int = 25
    email_from: str = "eip-cleanup@local.dev"
    email_to: List[str] = None
    dry_run: bool = True
    log_level: str = "INFO"
    
    def __post_init__(self):
        if self.regions is None:
            self.regions = ["us-east-1", "us-west-2", "eu-west-1", "ap-south-1"]
        if self.email_to is None:
            self.email_to = ["team@local.dev"]

# ============================================
# Prometheus Metrics
# ============================================
class Metrics:
    total_eips = Gauge('eip_cleanup_total_eips', 'Total EIPs found')
    attached_eips = Gauge('eip_cleanup_attached_eips', 'Attached EIPs')
    unattached_eips = Gauge('eip_cleanup_unattached_eips', 'Unattached EIPs')
    deleted_eips = Counter('eip_cleanup_deleted_total', 'Total EIPs deleted')
    scan_duration = Histogram('eip_cleanup_scan_duration_seconds', 'Scan duration')
    scan_errors = Counter('eip_cleanup_scan_errors_total', 'Total scan errors')
    
    @classmethod
    def update(cls, report: Dict[str, Any]):
        cls.total_eips.set(report.get('total_eips', 0))
        cls.attached_eips.set(report.get('attached', 0))
        cls.unattached_eips.set(report.get('unattached', 0))
        cls.deleted_eips.inc(len(report.get('deleted', [])))
        cls.scan_errors.inc(len(report.get('errors', [])))

# ============================================
# Database Layer
# ============================================
class Database:
    def __init__(self, config: Config):
        self.config = config
        self.conn = None
    
    def connect(self):
        self.conn = psycopg2.connect(
            host=self.config.db_host,
            port=self.config.db_port,
            database=self.config.db_name,
            user=self.config.db_user,
            password=self.config.db_password
        )
        return self.conn
    
    def log_eip_action(self, eip_data: Dict[str, Any]):
        with self.conn.cursor() as cur:
            cur.execute("""
                INSERT INTO eip_audit 
                (public_ip, allocation_id, region, status, instance_id, dry_run, error_message)
                VALUES (%s, %s, %s, %s, %s, %s, %s)
            """, (
                eip_data.get('public_ip'),
                eip_data.get('allocation_id'),
                eip_data.get('region'),
                eip_data.get('status', 'UNKNOWN'),
                eip_data.get('instance_id'),
                eip_data.get('dry_run', True),
                eip_data.get('error_message')
            ))
            self.conn.commit()
    
    def log_scan_summary(self, report: Dict[str, Any], duration: float):
        with self.conn.cursor() as cur:
            cur.execute("""
                INSERT INTO scan_history 
                (total_eips, attached_eips, unattached_eips, deleted_count, error_count, duration_seconds)
                VALUES (%s, %s, %s, %s, %s, %s)
            """, (
                report.get('total_eips', 0),
                report.get('attached', 0),
                report.get('unattached', 0),
                len(report.get('deleted', [])),
                len(report.get('errors', [])),
                duration
            ))
            self.conn.commit()

# ============================================
# EIP Cleanup Engine
# ============================================
class EIPCleanupEngine:
    def __init__(self, config: Config):
        self.config = config
        self.logger = self._setup_logging()
        self.db = Database(config)
        self.db.connect()
        
        if config.use_emulator:
            self.session = boto3.Session(
                aws_access_key_id=config.aws_access_key,
                aws_secret_access_key=config.aws_secret_key,
                region_name='us-east-1'
            )
        else:
            self.session = boto3.Session()
        
        self.report = {
            'total_eips': 0,
            'attached': 0,
            'unattached': 0,
            'deleted': [],
            'errors': [],
            'regions_scanned': [],
            'start_time': datetime.now().isoformat()
        }
    
    def _setup_logging(self):
        logger = logging.getLogger('EIPCleanup')
        logger.setLevel(getattr(logging, self.config.log_level))
        
        ch = logging.StreamHandler()
        ch.setFormatter(logging.Formatter(
            '%(asctime)s - %(levelname)s - %(message)s'
        ))
        logger.addHandler(ch)
        
        os.makedirs('logs', exist_ok=True)
        fh = logging.FileHandler(f'logs/eip_cleanup_{datetime.now():%Y%m%d}.log')
        fh.setFormatter(logging.Formatter(
            '%(asctime)s - %(levelname)s - %(filename)s:%(lineno)d - %(message)s'
        ))
        logger.addHandler(fh)
        
        return logger
    
    def get_ec2_client(self, region: str):
        if self.config.use_emulator:
            return self.session.client(
                'ec2',
                region_name=region,
                endpoint_url=self.config.endpoint_url
            )
        return self.session.client('ec2', region_name=region)
    
    def scan_region(self, region: str) -> int:
        self.logger.info(f"🔍 Scanning region: {region}")
        ec2 = self.get_ec2_client(region)
        deleted_count = 0
        
        try:
            response = ec2.describe_addresses()
            addresses = response.get('Addresses', [])
            self.report['total_eips'] += len(addresses)
            self.report['regions_scanned'].append(region)
            
            for eip in addresses:
                allocation_id = eip.get('AllocationId')
                public_ip = eip.get('PublicIp')
                instance_id = eip.get('InstanceId')
                
                eip_data = {
                    'public_ip': public_ip,
                    'allocation_id': allocation_id,
                    'region': region,
                    'instance_id': instance_id,
                    'dry_run': self.config.dry_run
                }
                
                if instance_id:
                    self.report['attached'] += 1
                    eip_data['status'] = 'SKIPPED_ATTACHED'
                    self.db.log_eip_action(eip_data)
                    self.logger.info(f"  ⏭️ EIP {public_ip} attached - SKIPPING")
                else:
                    self.report['unattached'] += 1
                    
                    if not self.config.dry_run:
                        try:
                            ec2.release_address(AllocationId=allocation_id)
                            deleted_count += 1
                            self.report['deleted'].append({
                                'public_ip': public_ip,
                                'allocation_id': allocation_id,
                                'region': region,
                                'timestamp': datetime.now().isoformat()
                            })
                            eip_data['status'] = 'DELETED'
                            self.db.log_eip_action(eip_data)
                            self.logger.info(f"  ✅ DELETED EIP: {public_ip}")
                        except Exception as e:
                            error_msg = f"Failed to delete {public_ip}: {str(e)}"
                            self.report['errors'].append(error_msg)
                            eip_data['status'] = 'ERROR'
                            eip_data['error_message'] = str(e)
                            self.db.log_eip_action(eip_data)
                            self.logger.error(f"  ❌ {error_msg}")
                    else:
                        self.logger.info(f"  🔍 DRY-RUN: Would delete {public_ip}")
                        eip_data['status'] = 'DRY_RUN_DELETE'
                        self.db.log_eip_action(eip_data)
            
            return deleted_count
            
        except Exception as e:
            error_msg = f"Error scanning region {region}: {str(e)}"
            self.report['errors'].append(error_msg)
            self.logger.error(f"  ❌ {error_msg}")
            return 0
    
    def scan_all_regions(self) -> int:
        total_deleted = 0
        for region in self.config.regions:
            try:
                deleted = self.scan_region(region)
                total_deleted += deleted
            except Exception as e:
                self.logger.error(f"Failed to scan {region}: {e}")
                continue
        return total_deleted
    
    def send_email_report(self):
        try:
            html = self._generate_html_report()
            text = self._generate_text_report()
            
            msg = MIMEMultipart('alternative')
            msg['Subject'] = f"EIP Cleanup Report - {datetime.now():%Y-%m-%d %H:%M}"
            msg['From'] = self.config.email_from
            msg['To'] = ', '.join(self.config.email_to)
            
            part1 = MIMEText(text, 'plain')
            part2 = MIMEText(html, 'html')
            msg.attach(part1)
            msg.attach(part2)
            
            with smtplib.SMTP(self.config.smtp_host, self.config.smtp_port) as server:
                server.send_message(msg)
            
            self.logger.info("📧 Email report sent successfully")
            
        except Exception as e:
            self.logger.error(f"Failed to send email: {e}")
            self._save_report_local()
    
    def _generate_html_report(self):
        status = "🔍 DRY RUN" if self.config.dry_run else "🚀 LIVE EXECUTION"
        deleted_count = len(self.report.get('deleted', []))
        
        eip_rows = ""
        for eip in self.report.get('deleted', [])[:20]:
            eip_rows += f"""
            <tr>
                <td>{eip.get('public_ip')}</td>
                <td>{eip.get('region')}</td>
                <td>{eip.get('timestamp')[:16]}</td>
                <td><span style="color: green;">✅ Deleted</span></td>
            </tr>
            """
        
        error_items = "".join(f"<li>{e}</li>" for e in self.report.get('errors', [])[:10])
        
        return f"""
        <html>
        <head>
            <style>
                body {{ font-family: 'Segoe UI', Arial, sans-serif; margin: 20px; }}
                .header {{ background: #2196F3; color: white; padding: 20px; border-radius: 8px; }}
                .summary {{ display: grid; grid-template-columns: repeat(4, 1fr); gap: 15px; margin: 20px 0; }}
                .metric {{ background: #f5f5f5; padding: 15px; border-radius: 8px; text-align: center; }}
                .metric-value {{ font-size: 28px; font-weight: bold; color: #2196F3; }}
                .metric-label {{ color: #666; margin-top: 5px; }}
                table {{ width: 100%; border-collapse: collapse; margin: 20px 0; }}
                th {{ background: #2196F3; color: white; padding: 10px; text-align: left; }}
                td {{ padding: 8px; border-bottom: 1px solid #ddd; }}
                .error-box {{ background: #ffebee; padding: 15px; border-radius: 8px; margin: 20px 0; }}
                .footer {{ margin-top: 20px; color: #666; font-size: 12px; }}
                .status-badge {{ 
                    display: inline-block; 
                    padding: 4px 12px; 
                    border-radius: 20px; 
                    background: {'#ff9800' if self.config.dry_run else '#4caf50'};
                    color: white;
                    font-weight: bold;
                }}
            </style>
        </head>
        <body>
            <div class="header">
                <h1>🔧 AWS EIP Cleanup Report</h1>
                <p><span class="status-badge">{status}</span></p>
                <p>Report generated: {datetime.now():%Y-%m-%d %H:%M:%S}</p>
            </div>
            
            <div class="summary">
                <div class="metric">
                    <div class="metric-value">{self.report.get('total_eips', 0)}</div>
                    <div class="metric-label">Total EIPs</div>
                </div>
                <div class="metric">
                    <div class="metric-value">{self.report.get('attached', 0)}</div>
                    <div class="metric-label">Attached</div>
                </div>
                <div class="metric" style="background: #fff3e0;">
                    <div class="metric-value" style="color: #e65100;">{self.report.get('unattached', 0)}</div>
                    <div class="metric-label">Unattached</div>
                </div>
                <div class="metric" style="background: #e8f5e9;">
                    <div class="metric-value" style="color: #2e7d32;">{deleted_count}</div>
                    <div class="metric-label">Deleted</div>
                </div>
            </div>
            
            <h3>📍 Regions Scanned</h3>
            <ul>
                {"".join(f"<li>{r}</li>" for r in self.report.get('regions_scanned', []))}
            </ul>
            
            {f'''
            <h3>✅ Deleted EIPs ({deleted_count})</h3>
            <table>
                <tr><th>Public IP</th><th>Region</th><th>Timestamp</th><th>Status</th></tr>
                {eip_rows}
            </table>
            ''' if deleted_count > 0 else ''}
            
            {f'''
            <div class="error-box">
                <h3>⚠️ Errors ({len(self.report.get('errors', []))})</h3>
                <ul>
                    {error_items}
                </ul>
            </div>
            ''' if self.report.get('errors') else ''}
            
            <div class="footer">
                <p>Generated by EIP Cleanup Automation v2.0 (On-Premise Learning Edition)</p>
                <p>LocalStack emulation - No AWS charges incurred</p>
            </div>
        </body>
        </html>
        """
    
    def _generate_text_report(self):
        return f"""
EIP Cleanup Report
==================
Status: {'DRY RUN' if self.config.dry_run else 'LIVE EXECUTION'}
Time: {datetime.now():%Y-%m-%d %H:%M:%S}

Summary:
- Total EIPs: {self.report.get('total_eips', 0)}
- Attached: {self.report.get('attached', 0)}
- Unattached: {self.report.get('unattached', 0)}
- Deleted: {len(self.report.get('deleted', []))}
- Errors: {len(self.report.get('errors', []))}

Regions Scanned:
{chr(10).join(f'- {r}' for r in self.report.get('regions_scanned', []))}

Deleted EIPs:
{chr(10).join(f'- {e.get('public_ip')} ({e.get('region')})' for e in self.report.get('deleted', [])[:20])}

Errors:
{chr(10).join(f'- {e}' for e in self.report.get('errors', [])[:10])}
"""
    
    def _save_report_local(self):
        os.makedirs('reports', exist_ok=True)
        report_path = f"reports/eip_report_{datetime.now():%Y%m%d_%H%M%S}.json"
        with open(report_path, 'w') as f:
            json.dump(self.report, f, indent=2, default=str)
        self.logger.info(f"📄 Report saved locally: {report_path}")
    
    def run(self) -> int:
        self.logger.info("🚀 Starting EIP Cleanup Process")
        self.logger.info(f"Mode: {'DRY RUN' if self.config.dry_run else 'LIVE'}")
        self.logger.info(f"Emulator: {'LocalStack' if self.config.use_emulator else 'Real AWS'}")
        
        start_time = time.time()
        
        try:
            deleted_count = self.scan_all_regions()
            duration = time.time() - start_time
            self.report['duration_seconds'] = duration
            
            Metrics.update(self.report)
            self.db.log_scan_summary(self.report, duration)
            self.send_email_report()
            self._save_report_local()
            
            self.logger.info(f"✅ Process complete - Deleted {deleted_count} EIPs")
            self.logger.info(f"⏱️ Duration: {duration:.2f} seconds")
            
            return 0
            
        except Exception as e:
            self.logger.critical(f"🔥 Critical failure: {e}")
            return 1

# ============================================
# CLI Entry Point
# ============================================
def main():
    parser = argparse.ArgumentParser(description='AWS EIP Cleanup - On-Premise Learning')
    parser.add_argument('--live', action='store_true', 
                       help='Execute actual deletions (default: dry-run)')
    parser.add_argument('--metrics', action='store_true',
                       help='Enable Prometheus metrics on port 8000')
    args = parser.parse_args()
    
    config = Config()
    
    if args.live:
        config.dry_run = False
        print("⚠️  WARNING: LIVE MODE - This will delete EIPs!")
        print("   Press Ctrl+C within 5 seconds to cancel...")
        time.sleep(5)
    
    if args.metrics:
        thread = threading.Thread(target=start_http_server, args=(8000,), daemon=True)
        thread.start()
        print("📊 Prometheus metrics available on http://localhost:8000")
    
    engine = EIPCleanupEngine(config)
    sys.exit(engine.run())

if __name__ == "__main__":
    main()
EOF
```

### **2.3 Test the Cleanup Script**

```bash
# Create test EIPs
python3 << 'EOF'
import boto3
ec2 = boto3.client(
    'ec2',
    endpoint_url='http://localhost:4566',
    aws_access_key_id='test',
    aws_secret_access_key='test',
    region_name='us-east-1'
)

print("📌 Creating test EIPs...")
for i in range(5):
    response = ec2.allocate_address(Domain='vpc')
    print(f"  ✅ Created EIP {i+1}: {response['PublicIp']}")
EOF

# Run dry-run
python eip_cleanup.py

# Run live
python eip_cleanup.py --live
```

---

## Phase 3: FastAPI Dashboard {#phase-3}

```bash
cat > dashboard.py << 'EOF'
"""
EIP Cleanup Dashboard - FastAPI Web UI
"""

from fastapi import FastAPI, HTTPException
from fastapi.responses import HTMLResponse
import psycopg2
from psycopg2.extras import RealDictCursor
from datetime import datetime
import os

app = FastAPI(
    title="EIP Cleanup Dashboard",
    description="Monitor and manage EIP cleanup operations",
    version="2.0.0"
)

def get_db():
    return psycopg2.connect(
        host="localhost",
        port=5432,
        database="eip_cleanup",
        user="eip_user",
        password="eip_pass"
    )

@app.get("/", response_class=HTMLResponse)
async def root():
    """Main dashboard HTML"""
    return """
    <!DOCTYPE html>
    <html>
    <head>
        <title>EIP Cleanup Dashboard</title>
        <style>
            body { font-family: 'Segoe UI', Arial, sans-serif; margin: 20px; background: #f5f5f5; }
            .container { max-width: 1200px; margin: 0 auto; }
            .header { background: #2196F3; color: white; padding: 20px; border-radius: 8px; margin-bottom: 20px; }
            .stats { display: grid; grid-template-columns: repeat(4, 1fr); gap: 15px; margin: 20px 0; }
            .stat-card { background: white; padding: 20px; border-radius: 8px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
            .stat-value { font-size: 32px; font-weight: bold; color: #2196F3; }
            .stat-label { color: #666; margin-top: 5px; }
            .table-container { background: white; padding: 20px; border-radius: 8px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
            table { width: 100%; border-collapse: collapse; }
            th { background: #2196F3; color: white; padding: 10px; text-align: left; }
            td { padding: 10px; border-bottom: 1px solid #ddd; }
            .status-deleted { color: green; font-weight: bold; }
            .status-error { color: red; font-weight: bold; }
            .status-skipped { color: orange; font-weight: bold; }
            .footer { margin-top: 20px; color: #666; font-size: 12px; text-align: center; }
        </style>
    </head>
    <body>
        <div class="container">
            <div class="header">
                <h1>🔧 EIP Cleanup Dashboard</h1>
                <p>Monitor AWS Elastic IP cleanup operations</p>
            </div>
            
            <div id="stats" class="stats">
                <div class="stat-card">
                    <div class="stat-value" id="total">-</div>
                    <div class="stat-label">Total EIPs</div>
                </div>
                <div class="stat-card">
                    <div class="stat-value" id="deleted">-</div>
                    <div class="stat-label">Deleted</div>
                </div>
                <div class="stat-card">
                    <div class="stat-value" id="attached">-</div>
                    <div class="stat-label">Attached</div>
                </div>
                <div class="stat-card">
                    <div class="stat-value" id="errors">-</div>
                    <div class="stat-label">Errors</div>
                </div>
            </div>
            
            <div class="table-container">
                <h2>Recent Audit Log</h2>
                <table>
                    <thead>
                        <tr>
                            <th>Public IP</th>
                            <th>Region</th>
                            <th>Status</th>
                            <th>Timestamp</th>
                        </tr>
                    </thead>
                    <tbody id="audit-table">
                        <tr><td colspan="4">Loading...</td></tr>
                    </tbody>
                </table>
            </div>
            
            <div class="footer">
                <p>Generated by EIP Cleanup Automation v2.0 (On-Premise Learning Edition)</p>
            </div>
        </div>
        
        <script>
            async function fetchData() {
                try {
                    // Fetch stats
                    const statsResponse = await fetch('/api/stats');
                    const stats = await statsResponse.json();
                    document.getElementById('total').textContent = stats.total_eips || 0;
                    document.getElementById('deleted').textContent = stats.total_deleted || 0;
                    document.getElementById('attached').textContent = stats.attached_eips || 0;
                    document.getElementById('errors').textContent = stats.error_count || 0;
                } catch(e) {
                    console.error('Error fetching stats:', e);
                }
                
                try {
                    // Fetch audit log
                    const auditResponse = await fetch('/api/audit?limit=50');
                    const audit = await auditResponse.json();
                    const table = document.getElementById('audit-table');
                    if (audit.length === 0) {
                        table.innerHTML = '<tr><td colspan="4">No records found</td></tr>';
                        return;
                    }
                    table.innerHTML = audit.map(row => `
                        <tr>
                            <td>${row.public_ip || '-'}</td>
                            <td>${row.region || '-'}</td>
                            <td class="status-${row.status.toLowerCase()}">${row.status || '-'}</td>
                            <td>${new Date(row.action_timestamp).toLocaleString()}</td>
                        </tr>
                    `).join('');
                } catch(e) {
                    console.error('Error fetching audit:', e);
                }
            }
            
            fetchData();
            setInterval(fetchData, 5000);
        </script>
    </body>
    </html>
    """

@app.get("/api/stats")
async def get_stats():
    """Get summary statistics"""
    conn = get_db()
    try:
        with conn.cursor(cursor_factory=RealDictCursor) as cur:
            cur.execute("""
                SELECT 
                    COUNT(*) as total_scans,
                    SUM(total_eips) as total_eips,
                    SUM(deleted_count) as total_deleted,
                    AVG(attached_eips) as avg_attached,
                    SUM(error_count) as error_count
                FROM scan_history
            """)
            result = cur.fetchone()
            return result or {}
    finally:
        conn.close()

@app.get("/api/audit")
async def get_audit(limit: int = 50):
    """Get recent audit log"""
    conn = get_db()
    try:
        with conn.cursor(cursor_factory=RealDictCursor) as cur:
            cur.execute("""
                SELECT * FROM eip_audit 
                ORDER BY action_timestamp DESC 
                LIMIT %s
            """, (limit,))
            return cur.fetchall()
    finally:
        conn.close()

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8001)
EOF
```

### **3.1 Run the Dashboard**

```bash
# Start dashboard
uvicorn dashboard:app --reload --host 0.0.0.0 --port 8001

# Access at: http://localhost:8001
```

---

## Phase 4: Email Notifications {#phase-4}

### **4.1 Access SMTP4Dev Web UI**

```bash
# Open browser
http://localhost:5000

# View captured emails after running cleanup
```

### **4.2 Test Email Sending**

```bash
# Run cleanup to trigger email
python eip_cleanup.py

# Check http://localhost:5000 for the email
```

---

## Phase 5: Scheduling & Automation {#phase-5}

### **5.1 Linux Cron Setup**

```bash
cat > scripts/setup_cron.sh << 'EOF'
#!/bin/bash
# Schedule: Every Sunday at 2 AM

# Get absolute path
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Create cron job
CRON_JOB="0 2 * * 0 cd $PROJECT_DIR && source venv/bin/activate && python eip_cleanup.py --live >> logs/cron.log 2>&1"

# Add to crontab
(crontab -l 2>/dev/null; echo "$CRON_JOB") | crontab -

echo "✅ Cron job installed:"
crontab -l
EOF

chmod +x scripts/setup_cron.sh
./scripts/setup_cron.sh
```

### **5.2 Systemd Timer (Linux)**

```bash
cat > scripts/setup_systemd.sh << 'EOF'
#!/bin/bash

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
USER="$(whoami)"

# Create service file
sudo tee /etc/systemd/system/eip-cleanup.service << SERVICE
[Unit]
Description=EIP Cleanup Service
After=network.target

[Service]
Type=oneshot
User=$USER
WorkingDirectory=$PROJECT_DIR
Environment="PATH=$PROJECT_DIR/venv/bin:/usr/local/bin:/usr/bin:/bin"
Environment="LOCALSTACK_AUTH_TOKEN=$LOCALSTACK_AUTH_TOKEN"
ExecStart=$PROJECT_DIR/venv/bin/python $PROJECT_DIR/eip_cleanup.py --live
StandardOutput=journal
StandardError=journal
SERVICE

# Create timer
sudo tee /etc/systemd/system/eip-cleanup.timer << TIMER
[Unit]
Description=EIP Cleanup Timer
Requires=eip-cleanup.service

[Timer]
OnCalendar=weekly
Persistent=true
Unit=eip-cleanup.service

[Install]
WantedBy=timers.target
TIMER

# Reload and enable
sudo systemctl daemon-reload
sudo systemctl enable eip-cleanup.timer
sudo systemctl start eip-cleanup.timer

echo "✅ Systemd timer installed:"
sudo systemctl list-timers | grep eip-cleanup
EOF

chmod +x scripts/setup_systemd.sh
./scripts/setup_systemd.sh
```

---

## Phase 6: Monitoring & Observability {#phase-6}

### **6.1 Prometheus Configuration**

```bash
mkdir -p prometheus
cat > prometheus/prometheus.yml << 'EOF'
global:
  scrape_interval: 15s
  evaluation_interval: 15s

scrape_configs:
  - job_name: 'eip-cleanup'
    static_configs:
      - targets: ['host.docker.internal:8000']
        labels:
          service: 'eip-cleanup'
          environment: 'development'
  
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']
EOF
```

### **6.2 Start Monitoring Stack**

```bash
# Start with monitoring services
docker-compose --profile monitoring up -d prometheus grafana

# Access:
# - Prometheus: http://localhost:9090
# - Grafana: http://localhost:3000 (admin/admin)
```

### **6.3 Run with Metrics**

```bash
# Start metrics exporter
python eip_cleanup.py --metrics

# Run cleanup (metrics will be collected)
python eip_cleanup.py --live
```

---

## Phase 7: Testing the Complete Solution {#phase-7}

### **7.1 End-to-End Test Script**

```bash
cat > test_e2e.sh << 'EOF'
#!/bin/bash
echo "🚀 Running End-to-End Test"
echo "=========================="

# 1. Verify LocalStack is running
echo "📌 Checking LocalStack..."
curl -s http://localhost:4566/_localstack/health | grep -q "ec2.*available"
if [ $? -eq 0 ]; then
    echo "✅ LocalStack is running"
else
    echo "❌ LocalStack is not running"
    exit 1
fi

# 2. Create test EIPs
echo "📌 Creating test EIPs..."
python3 -c "
import boto3
ec2 = boto3.client('ec2', endpoint_url='http://localhost:4566', 
                   aws_access_key_id='test', aws_secret_access_key='test')
for i in range(5):
    ec2.allocate_address(Domain='vpc')
    print(f'  ✅ Created EIP {i+1}')
"

# 3. Run dry-run
echo "📌 Running dry-run..."
python eip_cleanup.py

# 4. Run live
echo "📌 Running live cleanup..."
echo "y" | python eip_cleanup.py --live

# 5. Verify no EIPs remain
echo "📌 Verifying cleanup..."
REMAINING=$(python3 -c "
import boto3
ec2 = boto3.client('ec2', endpoint_url='http://localhost:4566',
                   aws_access_key_id='test', aws_secret_access_key='test')
print(len(ec2.describe_addresses()['Addresses']))
")

if [ "$REMAINING" -eq "0" ]; then
    echo "✅ All EIPs cleaned up successfully!"
else
    echo "⚠️ $REMAINING EIPs remaining"
fi

# 6. Check dashboard
echo "📌 Dashboard available at: http://localhost:8001"

echo "✅ End-to-End Test Complete!"
EOF

chmod +x test_e2e.sh
./test_e2e.sh
```

---

## 📝 Lessons Learned & Debug Guide {#lessons-learned}

### **Common Issues and Solutions**

| Issue | Error | Root Cause | Solution |
|-------|-------|------------|----------|
| **LocalStack auth failure** | `License activation failed!` | Token not passed to container | `export LOCALSTACK_AUTH_TOKEN=...` before `docker-compose up` |
| **Device or resource busy** | `Device or resource busy: '/tmp/localstack'` | Volume mount conflict | Change DATA_DIR to `/var/lib/localstack` |
| **ModuleNotFoundError** | `No module named 'boto3'` | Dependencies not installed | `pip install boto3` |
| **Port already in use** | `Error starting userland proxy: listen tcp4 0.0.0.0:4566: bind: address already in use` | Port conflict | `sudo lsof -i :4566` and kill process |
| **Database connection error** | `could not connect to server: Connection refused` | PostgreSQL not ready | Wait for health check: `docker-compose ps` |
| **Permission denied** | `Permission denied: '/var/run/docker.sock'` | Docker socket permissions | `sudo usermod -aG docker $USER` and restart |

### **Debug Commands**

```bash
# Check container logs
docker-compose logs localstack --tail=50

# Check container status
docker-compose ps

# Test LocalStack connectivity
curl -v http://localhost:4566/_localstack/health

# Test PostgreSQL
docker exec -it eip-database psql -U eip_user -d eip_cleanup -c "\dt"

# Check Python environment
which python
pip list | grep -E "boto3|fastapi|psycopg2"

# Check environment variables
echo $LOCALSTACK_AUTH_TOKEN

# Check Docker volumes
docker volume ls

# Clean everything and restart
docker-compose down -v
sudo rm -rf localstack_data postgres_data
docker-compose up -d
```

### **Best Practices Learned**

1. **Always use dry-run first** before live execution
2. **Environment variables must be explicitly passed** to Docker containers
3. **Check logs early** - they tell you exactly what's wrong
4. **Version pinning** prevents unexpected breaking changes
5. **Health checks** ensure services are ready before using them
6. **Persistent volumes** preserve state between restarts
7. **Profiles** in docker-compose allow optional services
8. **Virtual environments** isolate Python dependencies

---

## 🎯 Interview Preparation {#interview-prep}

### **Key DevOps Concepts Demonstrated**

| Concept | Implementation | Interview Talking Points |
|---------|----------------|--------------------------|
| **Infrastructure as Code** | Docker Compose | "We defined our entire infrastructure in YAML" |
| **Automation** | Cron/Systemd | "Automated weekly cleanup with zero manual intervention" |
| **Observability** | Prometheus + Grafana | "Full metrics and visualization stack" |
| **CI/CD Ready** | Git + Python scripts | "Version controlled, testable, repeatable" |
| **Cost Optimization** | EIP cleanup | "Saved $4,320/year per 100 EIPs" |
| **Security** | Least privilege | "IAM policies for specific actions only" |
| **12-Factor App** | Config via env vars | "Configuration externalized from code" |
| **Resilience** | Error handling | "Graceful failure across regions" |

### **Common Interview Questions**

**Q1: "How would you scale this solution?"**

> *"We'd move to AWS Lambda for serverless execution, use EventBridge for scheduling, and implement parallel region scanning. The core logic remains the same."*

**Q2: "How do you ensure safety?"**

> *"Three layers of safety:*
> 1. *Dry-run mode by default*
> 2. *Audit trail in PostgreSQL*
> 3. *Email notifications for every run*
> 
> *Also, we never delete attached EIPs - only unattached ones."*

**Q3: "What are the cost implications?"**

> *"Each unattached EIP costs ~$3.60/month. For 100 EIPs, that's $360/month or $4,320/year. This automation pays for itself in days."*

**Q4: "How would you handle failure?"**

> *"Graceful degradation:*
> - *If one region fails, continue with others*
> - *Errors logged and emailed*
> - *Retry logic with exponential backoff*
> - *Never leave system in inconsistent state"*

**Q5: "How would you test this?"**

> *"Multiple testing layers:*
> 1. *Unit tests with Moto*
> 2. *Integration tests with LocalStack*
> 3. *E2E tests with test accounts*
> 4. *Production with dry-run first"*

---

## 📂 Complete Project Structure

```
aws-eip-cleanup-lab/
├── docker-compose.yml          # Infrastructure definition
├── requirements.txt             # Python dependencies
├── eip_cleanup.py              # Main cleanup script
├── dashboard.py                # FastAPI dashboard
├── test_e2e.sh                 # End-to-end test script
├── config/
│   └── settings.json           # Configuration (optional)
├── scripts/
│   ├── init_db.sql             # Database initialization
│   ├── setup_cron.sh           # Cron scheduler setup
│   └── setup_systemd.sh        # Systemd timer setup
├── prometheus/
│   └── prometheus.yml          # Metrics configuration
├── monitoring/
│   └── exporter.py             # Prometheus exporter
├── logs/                       # Log files (created at runtime)
├── reports/                    # JSON reports (created at runtime)
├── localstack_data/            # LocalStack persistence
├── postgres_data/              # PostgreSQL persistence
└── smtp4dev_data/              # SMTP4Dev persistence
```

---

## 🚀 Quick Start Commands

```bash
# Complete setup from scratch
git init
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
docker-compose up -d
sleep 20
curl http://localhost:4566/_localstack/health
python eip_cleanup.py
python eip_cleanup.py --live
uvicorn dashboard:app --reload --host 0.0.0.0 --port 8001

# Access services
# - LocalStack: http://localhost:4566
# - Dashboard: http://localhost:8001
# - SMTP4Dev: http://localhost:5000
# - Prometheus: http://localhost:9090
# - Grafana: http://localhost:3000 (admin/admin)
```

---

## 🎓 Final Thoughts

This project demonstrates:

✅ **Production-grade automation** - Real-world DevOps practices
✅ **Zero AWS costs** - Learn without spending money
✅ **Full observability** - Logs, metrics, dashboards
✅ **Security best practices** - Least privilege, audit trails
✅ **Interview readiness** - Real scenarios to discuss

