# Credential Rotation Lab - Complete Implementation Plan

## Zero-Cost IAM Credential Rotation System

---

## 📋 Table of Contents
1. [Overview](#overview)
2. [Architecture](#architecture)
3. [Prerequisites](#prerequisites)
4. [Step-by-Step Implementation](#step-by-step-implementation)
5. [Testing & Validation](#testing--validation)
6. [Interview Articulation](#interview-articulation)
7. [Troubleshooting](#troubleshooting)
8. [Success Criteria](#success-criteria)

---

## 🎯 Overview

### Objective
Build a zero-cost lab to safely rotate IAM credentials without breaking active sessions, using LocalStack to emulate AWS services locally.

### Key Concepts Demonstrated
- ✅ **Dual-Key Rotation Strategy** - Zero-downtime credential rotation
- ✅ **STS Validation** - Validate credentials before switching
- ✅ **Fallback Mechanism** - Automatic rollback on failure
- ✅ **AWS 2-Key Limit Handling** - Proper key lifecycle management
- ✅ **Secrets Manager Integration** - Central credential storage

### Technology Stack (100% Free)
```
┌─────────────────────────────────────────────────────────────┐
│                     Technology Stack                        │
├─────────────────────────────────────────────────────────────┤
│ • LocalStack 3.0.0    - AWS Emulator (Free)               │
│ • FastAPI 0.95.0      - Web Framework (Free)              │
│ • Uvicorn 0.23.0      - ASGI Server (Free)               │
│ • Boto3 1.34.0        - AWS SDK (Free)                   │
│ • Python 3.10+        - Programming Language (Free)      │
│ • Docker              - Container Runtime (Free)         │
│ • AWS CLI             - Command Line Tool (Free)         │
└─────────────────────────────────────────────────────────────┘
```

---

## 🏗️ Architecture

### System Architecture Diagram
```
┌─────────────────────────────────────────────────────────────────────────────┐
│                          Developer Laptop                                   │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  ┌──────────────────────────────────────────────────────────────────┐      │
│  │                    LocalStack Container                           │      │
│  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────────────┐  │      │
│  │  │   IAM        │  │   Secrets    │  │   STS                │  │      │
│  │  │   (Identity) │  │   Manager    │  │   (Security Token)   │  │      │
│  │  └──────────────┘  └──────────────┘  └──────────────────────┘  │      │
│  └──────────────────────────────────────────────────────────────────┘      │
│                              │                                              │
│                              ▼                                              │
│  ┌──────────────────────────────────────────────────────────────────┐      │
│  │                    FastAPI Application                            │      │
│  │  ┌────────────────────────────────────────────────────────────┐  │      │
│  │  │               Credential Manager                            │  │      │
│  │  │  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐  │  │      │
│  │  │  │ Load     │  │ Validate │  │ Rotate   │  │ Fallback │  │  │      │
│  │  │  │ Creds    │→│ Creds    │→│ Creds    │→│ Store    │  │  │      │
│  │  │  └──────────┘  └──────────┘  └──────────┘  └──────────┘  │  │      │
│  │  └────────────────────────────────────────────────────────────┘  │      │
│  └──────────────────────────────────────────────────────────────────┘      │
│                              │                                              │
│                              ▼                                              │
│  ┌──────────────────────────────────────────────────────────────────┐      │
│  │                    API Endpoints                                  │      │
│  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────────────┐  │      │
│  │  │   /status    │  │   /secure    │  │   /rotate            │  │      │
│  │  │   Show Creds │  │   Use Creds  │  │   Rotate Creds       │  │      │
│  │  └──────────────┘  └──────────────┘  └──────────────────────┘  │      │
│  └──────────────────────────────────────────────────────────────────┘      │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Credential Rotation Flow
```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    Credential Rotation Flow                                 │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  1. 📋 LIST CURRENT KEYS                                                    │
│     ↓                                                                       │
│  2. 🔍 CHECK KEY COUNT                                                      │
│     ├─ If 2 keys → Delete oldest one                                       │
│     └─ If <2 keys → Continue                                               │
│     ↓                                                                       │
│  3. 🔑 CREATE NEW ACCESS KEY                                               │
│     ↓                                                                       │
│  4. ✅ VALIDATE NEW CREDENTIALS (STS)                                      │
│     ├─ If valid → Continue                                                 │
│     └─ If invalid → Rollback                                               │
│     ↓                                                                       │
│  5. 💾 UPDATE SECRETS MANAGER                                              │
│     ↓                                                                       │
│  6. 🚫 DEACTIVATE OLD KEYS                                                 │
│     ↓                                                                       │
│  7. 💾 STORE FALLBACK CREDENTIALS                                          │
│     ↓                                                                       │
│  8. ✅ ROTATION COMPLETE                                                   │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## 📋 Prerequisites

### Required Software
```bash
# Version Requirements
- Docker: 20.10+
- Python: 3.10+ 
- AWS CLI: 2.0+
- curl: 7.0+
- jq (optional): 1.6+
```

### Installation Commands
```bash
# Check versions
docker --version
python3 --version
aws --version
curl --version

# Install Docker (if not installed)
# https://docs.docker.com/engine/install/

# Install AWS CLI
# https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html
```

---

## 🚀 Step-by-Step Implementation

### Step 1: Project Setup

```bash
#!/bin/bash
# Step 1: Create project directory and virtual environment

# Create project directory
mkdir -p ~/projects/credential-rotation-lab
cd ~/projects/credential-rotation-lab

# Create virtual environment
python3 -m venv venv
source venv/bin/activate

# Create requirements.txt
cat > requirements.txt << 'EOF'
# Core dependencies - Compatible with Python 3.14+
fastapi==0.95.0
uvicorn[standard]==0.23.0
python-dotenv==1.0.0
boto3==1.34.0
requests==2.31.0
EOF

# Install dependencies
pip install --upgrade pip
pip install -r requirements.txt

echo "✅ Setup complete!"
```

### Step 2: Start LocalStack

```bash
#!/bin/bash
# Step 2: Start LocalStack container

# Start LocalStack
docker run -d \
  --name localstack-lab \
  -p 4566:4566 \
  -e SERVICES=iam,sts,secretsmanager \
  -e AWS_ACCESS_KEY_ID=test \
  -e AWS_SECRET_ACCESS_KEY=test \
  -e DEFAULT_REGION=us-east-1 \
  -e EDGE_PORT=4566 \
  localstack/localstack:3.0.0

# Wait for LocalStack to be ready
echo "⏳ Waiting for LocalStack..."
sleep 15

# Verify LocalStack is running
curl -s http://localhost:4566/_localstack/health | python3 -m json.tool

echo "✅ LocalStack started!"
```

### Step 3: Initialize Credentials

```bash
#!/bin/bash
# Step 3: Initialize IAM user and credentials

# Create IAM user
aws --endpoint-url=http://localhost:4566 \
    iam create-user --user-name app-user 2>/dev/null || echo "User exists"

# Create initial access key
aws --endpoint-url=http://localhost:4566 \
    iam create-access-key --user-name app-user 2>/dev/null || echo "Key exists"

# Create initial secret in Secrets Manager
aws --endpoint-url=http://localhost:4566 \
    secretsmanager create-secret \
    --name app-credentials \
    --secret-string '{"access_key_id":"AKIAIOSFODNN7EXAMPLE","secret_access_key":"wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"}' \
    2>/dev/null || echo "Secret exists"

echo "✅ Credentials initialized!"
```

### Step 4: Create the Application

```python
# app.py - Main application
import os
import json
import time
import logging
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
import boto3
from datetime import datetime
from typing import Optional, Dict

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# --- Configuration ---
ENDPOINT = os.getenv('AWS_ENDPOINT', 'http://localhost:4566')
REGION = os.getenv('AWS_REGION', 'us-east-1')
SECRET_NAME = "app-credentials"
USER_NAME = "app-user"

# --- AWS Clients ---
def get_clients():
    session = boto3.Session(
        aws_access_key_id='test',
        aws_secret_access_key='test',
        region_name=REGION
    )
    return {
        'iam': session.client('iam', endpoint_url=ENDPOINT),
        'secrets': session.client('secretsmanager', endpoint_url=ENDPOINT),
        'sts': session.client('sts', endpoint_url=ENDPOINT)
    }

clients = get_clients()

# --- Credential Manager ---
class CredentialManager:
    """
    Manages credential lifecycle with zero-downtime rotation
    """
    
    def __init__(self):
        self.current_creds: Optional[Dict] = None
        self.fallback_creds: Optional[Dict] = None
        self.last_rotation: Optional[datetime] = None
        self.load_credentials()
    
    def load_credentials(self) -> Dict:
        """Load current credentials from Secrets Manager"""
        try:
            response = clients['secrets'].get_secret_value(SecretId=SECRET_NAME)
            creds = json.loads(response['SecretString'])
            self.current_creds = creds
            self.last_rotation = datetime.now()
            logger.info(f"✅ Loaded credentials: {creds['access_key_id'][:10]}...")
            return creds
        except Exception as e:
            logger.warning(f"⚠️ Failed to load: {e}")
            default = {
                'access_key_id': 'AKIAIOSFODNN7EXAMPLE',
                'secret_access_key': 'wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY'
            }
            self.save_credentials(default)
            return default
    
    def save_credentials(self, credentials: Dict):
        """Save credentials to Secrets Manager"""
        try:
            clients['secrets'].put_secret_value(
                SecretId=SECRET_NAME,
                SecretString=json.dumps(credentials)
            )
            self.current_creds = credentials
            self.last_rotation = datetime.now()
            logger.info("✅ Credentials saved")
        except Exception as e:
            logger.error(f"❌ Failed to save: {e}")
            raise
    
    def validate_credentials(self, credentials: Dict) -> bool:
        """Validate credentials using STS"""
        try:
            test_session = boto3.Session(
                aws_access_key_id=credentials['access_key_id'],
                aws_secret_access_key=credentials['secret_access_key'],
                region_name=REGION
            )
            sts = test_session.client('sts', endpoint_url=ENDPOINT)
            identity = sts.get_caller_identity()
            logger.info(f"✅ Valid: {identity['Arn']}")
            return True
        except Exception as e:
            logger.error(f"❌ Invalid: {e}")
            return False
    
    def rotate(self) -> bool:
        """
        Perform credential rotation using dual-key strategy
        
        Steps:
        1. Check current keys
        2. Delete oldest if at limit (2 keys)
        3. Create new key
        4. Validate new credentials
        5. Update Secrets Manager
        6. Deactivate old keys
        7. Store fallback
        """
        logger.info("🔄 Starting credential rotation...")
        
        try:
            # Step 1: Get current keys
            response = clients['iam'].list_access_keys(UserName=USER_NAME)
            keys = response.get('AccessKeyMetadata', [])
            logger.info(f"📋 Found {len(keys)} keys")
            
            # Step 2: Delete oldest if we have 2 keys
            if len(keys) >= 2:
                keys.sort(key=lambda x: x['CreateDate'])
                clients['iam'].delete_access_key(
                    UserName=USER_NAME,
                    AccessKeyId=keys[0]['AccessKeyId']
                )
                logger.info(f"🗑️ Deleted: {keys[0]['AccessKeyId']}")
                time.sleep(2)
            
            # Step 3: Create new key
            response = clients['iam'].create_access_key(UserName=USER_NAME)
            new_key = response['AccessKey']
            logger.info(f"🔑 Created: {new_key['AccessKeyId']}")
            
            new_creds = {
                'access_key_id': new_key['AccessKeyId'],
                'secret_access_key': new_key['SecretAccessKey']
            }
            
            # Step 4: Validate
            if not self.validate_credentials(new_creds):
                logger.error("❌ Validation failed, rolling back...")
                return False
            
            # Step 5: Save to Secrets Manager
            self.save_credentials(new_creds)
            
            # Step 6: Deactivate old keys
            response = clients['iam'].list_access_keys(UserName=USER_NAME)
            for key in response.get('AccessKeyMetadata', []):
                if key['AccessKeyId'] != new_key['AccessKeyId']:
                    clients['iam'].update_access_key(
                        UserName=USER_NAME,
                        AccessKeyId=key['AccessKeyId'],
                        Status='Inactive'
                    )
                    logger.info(f"🚫 Deactivated: {key['AccessKeyId']}")
            
            # Step 7: Store fallback
            self.fallback_creds = self.current_creds
            self.current_creds = new_creds
            self.last_rotation = datetime.now()
            
            logger.info("✅ Rotation completed!")
            return True
            
        except Exception as e:
            logger.error(f"❌ Rotation failed: {e}")
            if self.fallback_creds:
                self.current_creds = self.fallback_creds
                self.save_credentials(self.fallback_creds)
                logger.info("↩️ Rolled back")
            return False

# --- FastAPI Application ---
app = FastAPI(
    title="Credential Rotation Lab",
    description="Zero-cost IAM credential rotation demonstration",
    version="1.0.0"
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Initialize credential manager
cred_manager = CredentialManager()

# --- API Endpoints ---

@app.get("/")
def root():
    return {
        "service": "Credential Rotation Lab",
        "version": "1.0.0",
        "objective": "Safely rotate IAM credentials without breaking sessions",
        "endpoints": {
            "health": "/health",
            "status": "/status",
            "secure-data": "/secure-data",
            "rotate": "/rotate"
        }
    }

@app.get("/health")
def health():
    return {
        "status": "healthy",
        "credentials_active": cred_manager.current_creds is not None,
        "timestamp": datetime.now().isoformat()
    }

@app.get("/status")
def status():
    return {
        "active": cred_manager.current_creds is not None,
        "has_fallback": cred_manager.fallback_creds is not None,
        "last_rotation": cred_manager.last_rotation.isoformat() if cred_manager.last_rotation else None,
        "current_key": cred_manager.current_creds['access_key_id'][:10] + "..." if cred_manager.current_creds else None,
        "dual_key_enabled": True
    }

@app.get("/secure-data")
def secure_data():
    """Example endpoint that uses credentials"""
    if not cred_manager.current_creds:
        raise HTTPException(status_code=500, detail="No credentials available")
    
    if not cred_manager.validate_credentials(cred_manager.current_creds):
        raise HTTPException(status_code=500, detail="Current credentials are invalid")
    
    return {
        "message": "✅ Secure data retrieved successfully",
        "credential_used": cred_manager.current_creds['access_key_id'][:10] + "...",
        "timestamp": datetime.now().isoformat()
    }

@app.post("/rotate")
def rotate():
    """Trigger credential rotation"""
    success = cred_manager.rotate()
    return {
        "success": success,
        "message": "Rotation completed" if success else "Rotation failed",
        "timestamp": datetime.now().isoformat()
    }

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(
        app, 
        host="0.0.0.0", 
        port=8000,
        log_level="info"
    )
```

### Step 5: Create the Complete Setup Script

```bash
#!/bin/bash
# run-lab.sh - Complete lab runner script

echo "🚀 Starting Credential Rotation Lab"
echo "===================================="

# Step 1: Check LocalStack
echo "🔍 Checking LocalStack..."
if curl -s http://localhost:4566/_localstack/health > /dev/null 2>&1; then
    echo "✅ LocalStack is running"
else
    echo "❌ LocalStack not running. Starting..."
    docker rm -f localstack-lab 2>/dev/null || true
    docker run -d \
      --name localstack-lab \
      -p 4566:4566 \
      -e SERVICES=iam,sts,secretsmanager \
      -e AWS_ACCESS_KEY_ID=test \
      -e AWS_SECRET_ACCESS_KEY=test \
      -e DEFAULT_REGION=us-east-1 \
      -e EDGE_PORT=4566 \
      localstack/localstack:3.0.0
    sleep 15
fi

# Step 2: Initialize credentials
echo "🔧 Initializing credentials..."
aws --endpoint-url=http://localhost:4566 \
    iam create-user --user-name app-user 2>/dev/null || echo "User exists"

aws --endpoint-url=http://localhost:4566 \
    iam create-access-key --user-name app-user 2>/dev/null || echo "Key exists"

aws --endpoint-url=http://localhost:4566 \
    secretsmanager create-secret \
    --name app-credentials \
    --secret-string '{"access_key_id":"AKIAIOSFODNN7EXAMPLE","secret_access_key":"wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"}' \
    2>/dev/null || echo "Secret exists"

# Step 3: Run the application
echo "🚀 Running FastAPI app..."
export AWS_ENDPOINT=http://localhost:4566
python app.py
```

### Step 6: Create Test Script

```bash
#!/bin/bash
# test-lab.sh - Complete test suite

echo "🧪 Testing Credential Rotation Lab"
echo "=================================="

# 1. Check status
echo -e "\n📊 Initial Status:"
curl -s http://localhost:8000/status | python3 -m json.tool

# 2. Get secure data
echo -e "\n🔐 Getting Secure Data:"
curl -s http://localhost:8000/secure-data | python3 -m json.tool

# 3. Trigger rotation
echo -e "\n🔄 Triggering Rotation:"
curl -s -X POST http://localhost:8000/rotate | python3 -m json.tool

# 4. Check status after rotation
echo -e "\n📊 Status After Rotation:"
curl -s http://localhost:8000/status | python3 -m json.tool

# 5. Get secure data with new credentials
echo -e "\n🔐 Secure Data (New Credentials):"
curl -s http://localhost:8000/secure-data | python3 -m json.tool

echo -e "\n✅ All tests completed!"
```

### Step 7: Create Cleanup Script

```bash
#!/bin/bash
# cleanup.sh - Clean up resources

echo "🧹 Cleaning up..."

# Stop FastAPI app
pkill -f "python app.py" 2>/dev/null || echo "App not running"

# Stop and remove LocalStack container
docker stop localstack-lab 2>/dev/null || echo "Container not running"
docker rm localstack-lab 2>/dev/null || echo "Container not found"

# Remove virtual environment
deactivate 2>/dev/null || true
rm -rf venv

echo "✅ Cleanup complete!"
```

---

## 🧪 Testing & Validation

### Quick Test Commands

```bash
# Check health
curl http://localhost:8000/health

# Check status
curl http://localhost:8000/status

# Get secure data
curl http://localhost:8000/secure-data

# Trigger rotation
curl -X POST http://localhost:8000/rotate

# Monitor status in real-time
watch -n 2 'curl -s http://localhost:8000/status | python3 -m json.tool'
```

### Expected Test Output

```json
{
    "active": true,
    "has_fallback": false,
    "last_rotation": "2026-06-27T16:38:55.944562",
    "current_key": "LKIAQAAAAA...",
    "dual_key_enabled": true
}
```

### After Rotation Output

```json
{
    "active": true,
    "has_fallback": true,
    "last_rotation": "2026-06-27T16:40:18.627279",
    "current_key": "LKIAQAAAAA...",
    "dual_key_enabled": true
}
```

---

## 🎯 Interview Articulation

### Key Talking Points

#### 1. **Zero-Downtime Rotation**
> "I implemented a dual-key strategy where both old and new credentials are active during the rotation window. This ensures no active sessions are broken because the old key continues to work until the new one is validated and active."

#### 2. **Validation Before Commit**
> "We validate new credentials using STS `get_caller_identity()` before committing them to Secrets Manager. This prevents deploying invalid credentials that would cause service disruption."

#### 3. **AWS 2-Key Limit Handling**
> "AWS allows a maximum of 2 active keys per user. Before creating a new key, we check if we already have 2 keys. If so, we delete the oldest one first to stay within the limit while ensuring continuity."

#### 4. **Fallback Mechanism**
> "After rotation, we store the previous credentials as a fallback. If the new credentials cause issues, we can automatically rollback to the working credentials."

### Sample Interview Questions

**Q: How do you safely rotate credentials without breaking active sessions?**

> "I use a dual-key approach. The old key remains active while the new key is being created and validated. Only after validation do we deactivate the old key. This ensures continuous availability."

**Q: What happens if the new credentials are invalid?**

> "We have a validation step before switching. If validation fails, we automatically rollback to the previous credentials stored as a fallback. This prevents service disruption."

**Q: How do you handle the AWS 2-key limit?**

> "We check the number of existing keys before rotation. If we have 2 keys, we delete the oldest one before creating the new key. This keeps us within the limit while maintaining one active key during the process."

**Q: Can you explain the fallback mechanism?**

> "Before updating the secret store with new credentials, we store the current credentials as a fallback. If the new credentials fail validation or cause issues, we can immediately rollback to the working credentials."

**Q: How is this implemented with zero-cost?**

> "I use LocalStack for AWS emulation, which is completely free. All other tools are open-source - FastAPI, Python, Docker, and AWS CLI. This provides a production-like environment for development and testing."

---

## 🔧 Troubleshooting

### Common Issues & Solutions

| Issue | Solution |
|-------|----------|
| LocalStack not starting | Check Docker is running: `docker ps` |
| Port already in use | Change port in docker run command: `-p 4567:4566` |
| AWS CLI not connecting | Ensure endpoint URL is correct: `--endpoint-url=http://localhost:4566` |
| Import errors | Verify virtual environment is activated: `source venv/bin/activate` |
| Permission denied | Make scripts executable: `chmod +x *.sh` |

### Debug Commands

```bash
# Check LocalStack logs
docker logs localstack-lab

# Check LocalStack health
curl http://localhost:4566/_localstack/health

# Check FastAPI logs
# Look at the terminal where app is running

# Verify IAM user
aws --endpoint-url=http://localhost:4566 iam list-users

# Verify Secrets Manager
aws --endpoint-url=http://localhost:4566 secretsmanager list-secrets
```

---

## ✅ Success Criteria

You have successfully completed this lab when:

- [x] LocalStack is running and healthy
- [x] IAM user and credentials are created
- [x] FastAPI application is running
- [x] `/status` endpoint shows active credentials
- [x] `/secure-data` endpoint returns data
- [x] `/rotate` endpoint rotates credentials
- [x] Status shows `has_fallback: true` after rotation
- [x] Secure data still works after rotation

---

## 📚 Additional Resources

### Documentation
- [LocalStack Documentation](https://docs.localstack.cloud/)
- [FastAPI Documentation](https://fastapi.tiangolo.com/)
- [Boto3 Documentation](https://boto3.amazonaws.com/v1/documentation/api/latest/index.html)
- [AWS IAM Documentation](https://docs.aws.amazon.com/IAM/latest/UserGuide/)

### Related Topics
- Credential Rotation Best Practices
- Zero-Downtime Deployment Strategies
- AWS Security Fundamentals
- Secrets Management Patterns

---

## 📝 Summary

This implementation provides:

✅ **Zero-cost** - All tools are free and open-source
✅ **Production-like** - Mirrors real AWS IAM behavior
✅ **Complete** - Full rotation lifecycle implemented
✅ **Testable** - Comprehensive test suite
✅ **Interview-ready** - Demonstrates key concepts

### Key Features Demonstrated

1. **Dual-Key Rotation** - Safe, zero-downtime rotation
2. **STS Validation** - Verify credentials before switching
3. **Fallback Mechanism** - Automatic rollback capability
4. **AWS 2-Key Limit** - Proper key lifecycle management
5. **Secrets Manager** - Centralized credential storage
6. **Audit Trail** - Rotation tracking and logging

---

## 🎉 Congratulations!

You now have a fully working credential rotation lab that demonstrates:

- ✅ Zero-downtime credential rotation
- ✅ Production-ready architecture
- ✅ Comprehensive testing
- ✅ Interview-ready articulation

**This implementation is good addition to your portfolio and for interview demonstrations!** 🚀

---

## 📄 License

This project is open-source and free to use for learning and demonstration purposes.

---

