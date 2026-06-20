# 🚀 Interactive Terminal-Based Implementation Plan
## AWS EIP Cleanup - Manual Step-by-Step Guide

### 📋 **Quick Reference Card**

| Service | URL | Credentials |
|---------|-----|-------------|
| LocalStack | http://localhost:4566 | test/test |
| SMTP4Dev | http://localhost:5000 | No auth |
| PostgreSQL | localhost:5432 | eip_user/eip_pass |
| Dashboard | http://localhost:8001 | No auth |
| Prometheus | http://localhost:9090 | No auth |
| Grafana | http://localhost:3000 | admin/admin |

---

## **STEP 0: Initial Setup (5 minutes)**

```bash
# Create project directory
mkdir -p ~/projects/aws-eip-cleanup-lab
cd ~/projects/aws-eip-cleanup-lab

# Create Python virtual environment
python3 -m venv venv
source venv/bin/activate

# Install dependencies (copy-paste entire block)
pip install boto3 psycopg2-binary fastapi uvicorn pydantic python-dotenv prometheus-client
```

---

## **STEP 1: Docker Compose File (2 minutes)**

Create `docker-compose.yml`:

```bash
cat > docker-compose.yml << 'EOF'
services:
  localstack:
    image: localstack/localstack:latest
    container_name: aws-emulator
    ports:
      - "4566:4566"
    environment:
      - SERVICES=ec2,sns
      - LOCALSTACK_AUTH_TOKEN=${LOCALSTACK_AUTH_TOKEN}
      - AWS_ACCESS_KEY_ID=test
      - AWS_SECRET_ACCESS_KEY=test
      - AWS_DEFAULT_REGION=us-east-1
    volumes:
      - ./localstack_data:/var/lib/localstack
    networks:
      - eip-network

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
    networks:
      - eip-network

  smtp4dev:
    image: rnwood/smtp4dev:latest
    container_name: email-capture
    ports:
      - "5000:80"
      - "25:25"
    volumes:
      - ./smtp4dev_data:/smtp4dev
    networks:
      - eip-network

networks:
  eip-network:
    driver: bridge

volumes:
  localstack_data:
  postgres_data:
  smtp4dev_data:
EOF
```

---

## **STEP 2: Set LocalStack Auth Token**

```bash
# Get token from: https://app.localstack.cloud → Settings → Auth Tokens
export LOCALSTACK_AUTH_TOKEN="**********dfdfdf*********"

# Verify token is set
echo $LOCALSTACK_AUTH_TOKEN
```

---

## **STEP 3: Start Services (2 minutes)**

```bash
# Start all services
docker-compose up -d

# Wait for initialization
sleep 15

# Verify LocalStack is working
curl http://localhost:4566/_localstack/health
```

**Expected output:**
```json
{"services": {"ec2": "available", "sns": "available"}, "edition": "pro"}
```

---

## **STEP 4: Create Database (2 minutes)**

```bash
# Connect to PostgreSQL and create table
docker exec -i eip-database psql -U eip_user -d eip_cleanup << 'EOF'
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

-- Verify table creation
\dt
EOF
```

---

## **STEP 5: Create Test EIPs (Interactive)**

```bash
# Create 5 test EIPs
python3 << 'EOF'
import boto3

ec2 = boto3.client(
    'ec2',
    endpoint_url='http://localhost:4566',
    aws_access_key_id='test',
    aws_secret_access_key='test',
    region_name='us-east-1'
)

print("📌 Creating 5 test EIPs...")
for i in range(5):
    response = ec2.allocate_address(Domain='vpc')
    print(f"  ✅ Created EIP {i+1}: {response['PublicIp']}")

# Show all EIPs
eips = ec2.describe_addresses()['Addresses']
print(f"\n📊 Total EIPs: {len(eips)}")
for eip in eips:
    print(f"  - {eip['PublicIp']}: Unattached")
EOF
```

---

## **STEP 6: Create Cleanup Script (Minimal)**

```bash
cat > eip_cleanup.py << 'EOF'
import boto3
import psycopg2
import time
from datetime import datetime

# Configuration
ENDPOINT_URL = 'http://localhost:4566'
DB_CONFIG = {
    'host': 'localhost',
    'port': 5432,
    'database': 'eip_cleanup',
    'user': 'eip_user',
    'password': 'eip_pass'
}

def get_ec2():
    return boto3.client('ec2', endpoint_url=ENDPOINT_URL, 
                       aws_access_key_id='test',
                       aws_secret_access_key='test',
                       region_name='us-east-1')

def log_to_db(action, ip, allocation_id, region, status, dry_run=True):
    conn = psycopg2.connect(**DB_CONFIG)
    cur = conn.cursor()
    cur.execute("""
        INSERT INTO eip_audit (public_ip, allocation_id, region, status, dry_run)
        VALUES (%s, %s, %s, %s, %s)
    """, (ip, allocation_id, region, status, dry_run))
    conn.commit()
    conn.close()

def scan_and_clean(dry_run=True):
    ec2 = get_ec2()
    print(f"\n{'='*60}")
    print(f"🚀 EIP Cleanup - {'DRY RUN' if dry_run else 'LIVE'}")
    print(f"{'='*60}")
    print(f"Time: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n")
    
    response = ec2.describe_addresses()
    addresses = response.get('Addresses', [])
    
    if not addresses:
        print("📭 No EIPs found")
        return
    
    print(f"📊 Found {len(addresses)} EIPs\n")
    
    deleted = []
    errors = []
    
    for eip in addresses:
        public_ip = eip.get('PublicIp')
        allocation_id = eip.get('AllocationId')
        instance_id = eip.get('InstanceId')
        
        if instance_id:
            print(f"  ⏭️  {public_ip}: ATTACHED (skipping)")
            log_to_db(action='skipped', ip=public_ip, allocation_id=allocation_id, 
                     region='us-east-1', status='SKIPPED_ATTACHED', dry_run=dry_run)
        else:
            print(f"  🔍 {public_ip}: UNATTACHED")
            
            if not dry_run:
                try:
                    ec2.release_address(AllocationId=allocation_id)
                    deleted.append(public_ip)
                    print(f"    ✅ DELETED {public_ip}")
                    log_to_db(action='deleted', ip=public_ip, allocation_id=allocation_id,
                             region='us-east-1', status='DELETED', dry_run=False)
                except Exception as e:
                    errors.append(f"{public_ip}: {str(e)}")
                    print(f"    ❌ Error: {e}")
                    log_to_db(action='error', ip=public_ip, allocation_id=allocation_id,
                             region='us-east-1', status='ERROR', dry_run=False)
            else:
                print(f"    🔍 Would delete (dry-run)")
                log_to_db(action='dry_run', ip=public_ip, allocation_id=allocation_id,
                         region='us-east-1', status='DRY_RUN_DELETE', dry_run=True)
    
    print("\n" + "="*60)
    print("📊 SUMMARY")
    print("="*60)
    print(f"  Total EIPs:    {len(addresses)}")
    print(f"  Attached:      {len([a for a in addresses if a.get('InstanceId')])}")
    print(f"  Unattached:    {len([a for a in addresses if not a.get('InstanceId')])}")
    print(f"  Deleted:       {len(deleted)}")
    print(f"  Errors:        {len(errors)}")
    print(f"  Mode:          {'DRY RUN' if dry_run else 'LIVE'}")
    
    if deleted:
        print(f"\n✅ Deleted EIPs:")
        for ip in deleted:
            print(f"  - {ip}")
    
    if errors:
        print(f"\n❌ Errors:")
        for err in errors:
            print(f"  - {err}")

if __name__ == "__main__":
    print("\n🔍 Running in DRY-RUN mode (safe)")
    scan_and_clean(dry_run=True)
    
    print("\n" + "="*60)
    print("💡 To delete EIPs, run: python3 -c 'from eip_cleanup import scan_and_clean; scan_and_clean(dry_run=False)'")
EOF
```

---

## **STEP 7: Run Dry-Run (Safe Test)**

```bash
# Execute dry-run
python3 eip_cleanup.py
```

**Expected output:**
```
🔍 Running in DRY-RUN mode (safe)

============================================================
🚀 EIP Cleanup - DRY RUN
============================================================
Time: 2026-06-20 18:30:00

📊 Found 5 EIPs

  🔍 172.17.0.1: UNATTACHED
    🔍 Would delete (dry-run)
  🔍 172.17.0.2: UNATTACHED
    🔍 Would delete (dry-run)
  ...

============================================================
📊 SUMMARY
============================================================
  Total EIPs:    5
  Attached:      0
  Unattached:    5
  Deleted:       0
  Errors:        0
  Mode:          DRY RUN
```

---

## **STEP 8: Run Live Deletion**

```bash
# Execute live deletion
python3 -c "
from eip_cleanup import scan_and_clean
print('⚠️  WARNING: LIVE MODE - This will delete EIPs!')
print('   Press Ctrl+C within 5 seconds to cancel...')
import time
time.sleep(5)
scan_and_clean(dry_run=False)
"
```

---

## **STEP 9: Verify Cleanup**

```bash
# Check if EIPs were deleted
python3 << 'EOF'
import boto3

ec2 = boto3.client(
    'ec2',
    endpoint_url='http://localhost:4566',
    aws_access_key_id='test',
    aws_secret_access_key='test',
    region_name='us-east-1'
)

eips = ec2.describe_addresses()['Addresses']
print(f"\n📊 EIPs remaining: {len(eips)}")
for eip in eips:
    print(f"  - {eip['PublicIp']}: {eip.get('InstanceId', 'Unattached')}")
EOF
```

---

## **STEP 10: Check Email Report**

```bash
# Open SMTP4Dev web UI
# In browser, go to: http://localhost:5000
# You should see the email report from the cleanup

# Or check via command line
curl http://localhost:5000/api/messages 2>/dev/null | python3 -m json.tool
```

---

## **STEP 11: View Database Audit**

```bash
# Check audit log in PostgreSQL
docker exec -i eip-database psql -U eip_user -d eip_cleanup << 'EOF'
SELECT public_ip, region, status, action_timestamp, dry_run 
FROM eip_audit 
ORDER BY action_timestamp DESC 
LIMIT 10;
EOF
```

---

## **STEP 12: Create Dashboard (Optional)**

```bash
cat > dashboard.py << 'EOF'
from fastapi import FastAPI, HTMLResponse
import psycopg2
from psycopg2.extras import RealDictCursor

app = FastAPI()

def get_db():
    return psycopg2.connect(
        host='localhost', port=5432,
        database='eip_cleanup', user='eip_user', password='eip_pass'
    )

@app.get("/", response_class=HTMLResponse)
async def root():
    return """
    <html>
    <head><title>EIP Dashboard</title></head>
    <body style="font-family: Arial;">
        <h1>🔧 EIP Cleanup Dashboard</h1>
        <div id="stats"></div>
        <table id="audit" border="1"></table>
        <script>
            async function load() {
                const r = await fetch('/api/stats');
                const s = await r.json();
                document.getElementById('stats').innerHTML = `
                    <p>Total EIPs: ${s.total_eips || 0}</p>
                    <p>Deleted: ${s.total_deleted || 0}</p>
                    <p>Errors: ${s.error_count || 0}</p>
                `;
                
                const a = await fetch('/api/audit');
                const data = await a.json();
                document.getElementById('audit').innerHTML = 
                    '<tr><th>IP</th><th>Status</th><th>Time</th></tr>' +
                    data.map(r => `<tr><td>${r.public_ip}</td><td>${r.status}</td><td>${r.action_timestamp}</td></tr>`).join('');
            }
            load();
        </script>
    </body>
    </html>
    """

@app.get("/api/stats")
async def stats():
    conn = get_db()
    cur = conn.cursor(cursor_factory=RealDictCursor)
    cur.execute("SELECT COUNT(*) as total_eips, SUM(deleted_count) as total_deleted, SUM(error_count) as error_count FROM scan_history")
    return cur.fetchone() or {}

@app.get("/api/audit")
async def audit():
    conn = get_db()
    cur = conn.cursor(cursor_factory=RealDictCursor)
    cur.execute("SELECT public_ip, status, action_timestamp FROM eip_audit ORDER BY action_timestamp DESC LIMIT 20")
    return cur.fetchall()

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8001)
EOF

# Start dashboard
uvicorn dashboard:app --host 0.0.0.0 --port 8001 &

# Access at: http://localhost:8001
```

---

## **STEP 13: Schedule Automation (Linux/Mac)**

```bash
# Add to crontab to run weekly
(crontab -l 2>/dev/null; echo "0 2 * * 0 cd $PWD && source venv/bin/activate && python3 -c 'from eip_cleanup import scan_and_clean; scan_and_clean(dry_run=False)' >> logs/weekly.log 2>&1") | crontab -

# Verify cron job
crontab -l
```

---

## **STEP 14: Quick Cleanup**

```bash
# Stop all services
docker-compose down

# Remove data (for fresh start)
docker-compose down -v
sudo rm -rf localstack_data postgres_data smtp4dev_data

# Or restart
docker-compose up -d
```

---

## **📊 Quick Command Reference Card**

```bash
# ============================================
# QUICK REFERENCE - Copy & Paste Commands
# ============================================

# 1. Start everything
export LOCALSTACK_AUTH_TOKEN="************************************"
docker-compose up -d && sleep 15

# 2. Check status
curl http://localhost:4566/_localstack/health
docker-compose ps

# 3. Create test EIPs (5)
python3 -c "import boto3; ec2=boto3.client('ec2', endpoint_url='http://localhost:4566', aws_access_key_id='test', aws_secret_access_key='test'); [ec2.allocate_address(Domain='vpc') for _ in range(5)]"

# 4. Run dry-run
python3 eip_cleanup.py

# 5. Run live
python3 -c "from eip_cleanup import scan_and_clean; scan_and_clean(dry_run=False)"

# 6. View emails
curl http://localhost:5000/api/messages 2>/dev/null | python3 -m json.tool

# 7. View database
docker exec -i eip-database psql -U eip_user -d eip_cleanup -c "SELECT * FROM eip_audit ORDER BY id DESC LIMIT 10;"

# 8. Stop everything
docker-compose down

# 9. Clean everything
docker-compose down -v && sudo rm -rf localstack_data postgres_data smtp4dev_data
```

---

## **✅ Success Checklist**

- [ ] Docker Compose running (`docker-compose ps`)
- [ ] LocalStack responding (`curl http://localhost:4566/_localstack/health`)
- [ ] Created test EIPs (5 created)
- [ ] Dry-run completed without errors
- [ ] Live deletion removed all EIPs
- [ ] Email received in SMTP4Dev (http://localhost:5000)
- [ ] Database audit populated
- [ ] Dashboard working (http://localhost:8001)

---

## **🎯 Key Takeaways**

| Lesson | Why It Matters |
|--------|----------------|
| **Always dry-run first** | Prevents accidental deletion in production |
| **Check logs early** | Saves hours of debugging |
| **Environment variables must be exported** | Docker containers need explicit env vars |
| **LocalStack needs auth token** | Pro version requires license |
| **PostgreSQL tables need creation** | No automatic schema migration |

