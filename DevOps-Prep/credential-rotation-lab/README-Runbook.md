# Credential Rotation DevOps Runbook & Learnings

## Production-Grade Credential Rotation Implementation

---

## 📋 Table of Contents
1. [Executive Summary](#executive-summary)
2. [Runbook: Credential Rotation](#runbook-credential-rotation)
3. [Runbook: Troubleshooting](#runbook-troubleshooting)
4. [Runbook: Emergency Response](#runbook-emergency-response)
5. [DevOps Interview Learnings](#devops-interview-learnings)
6. [Common Interview Questions](#common-interview-questions)
7. [Advanced Scenarios](#advanced-scenarios)
8. [Key Takeaways](#key-takeaways)

---

## 🎯 Executive Summary

### What This Lab Demonstrates
A production-grade, zero-downtime credential rotation system that safely rotates IAM credentials without breaking active sessions.

### Key Achievements
```
┌─────────────────────────────────────────────────────────────┐
│                    Lab Success Metrics                       │
├─────────────────────────────────────────────────────────────┤
│ ✅ Zero-Downtime Rotation    - No active sessions broken   │
│ ✅ Automated Validation      - STS verification before     │
│ ✅ Fallback Mechanism        - Automatic rollback on fail  │
│ ✅ AWS 2-Key Limit Handling  - Proper lifecycle management │
│ ✅ Audit Trail               - Complete rotation logging   │
│ ✅ Zero-Cost                 - All tools are free          │
└─────────────────────────────────────────────────────────────┘
```

---

## 📖 Runbook: Credential Rotation

### Overview
This runbook provides step-by-step procedures for safely rotating IAM credentials in production environments.

### Pre-Rotation Checklist

```bash
#!/bin/bash
# pre-rotation-check.sh - Verify system readiness

echo "🔍 Pre-Rotation Health Check"

# 1. Check current credentials
echo "📊 Current Status:"
curl -s http://localhost:8000/status | python3 -m json.tool

# 2. Verify services are healthy
echo "🩺 Service Health:"
curl -s http://localhost:8000/health | python3 -m json.tool

# 3. Check LocalStack status
echo "☁️  LocalStack Status:"
curl -s http://localhost:4566/_localstack/health | python3 -m json.tool

# 4. Check number of active keys
echo "🔑 Active Keys:"
aws --endpoint-url=http://localhost:4566 \
    iam list-access-keys --user-name app-user

echo "✅ Pre-rotation check complete"
```

### Standard Rotation Procedure

```bash
#!/bin/bash
# rotate-credentials.sh - Standard credential rotation

echo "🔄 Starting Credential Rotation"

# Step 1: Backup current credentials
echo "💾 Backing up current credentials..."
aws --endpoint-url=http://localhost:4566 \
    secretsmanager get-secret-value \
    --secret-id app-credentials \
    --query 'SecretString' \
    --output text > backup-$(date +%Y%m%d-%H%M%S).json

# Step 2: Trigger rotation via API
echo "🔄 Triggering rotation..."
curl -X POST http://localhost:8000/rotate | python3 -m json.tool

# Step 3: Wait for propagation
echo "⏳ Waiting for propagation..."
sleep 5

# Step 4: Verify rotation
echo "🔍 Verifying rotation..."
curl -s http://localhost:8000/status | python3 -m json.tool

# Step 5: Test with new credentials
echo "🧪 Testing new credentials..."
curl -s http://localhost:8000/secure-data | python3 -m json.tool

echo "✅ Rotation complete!"
```

### Zero-Downtime Rotation Steps

```
┌─────────────────────────────────────────────────────────────┐
│              Zero-Downtime Rotation Steps                   │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  PHASE 1: PREPARATION                                      │
│  ├─ Check system health                                    │
│  ├─ Verify current credentials work                       │
│  ├─ Backup current credentials                            │
│  └─ Check AWS 2-key limit                                 │
│                                                             │
│  PHASE 2: ROTATION                                         │
│  ├─ Create new access key (old remains active)            │
│  ├─ Validate new credentials via STS                      │
│  ├─ Update Secrets Manager                                │
│  └─ Deactivate old keys                                   │
│                                                             │
│  PHASE 3: VALIDATION                                       │
│  ├─ Test with new credentials                             │
│  ├─ Verify fallback is available                          │
│  ├─ Check application health                              │
│  └─ Monitor for errors                                    │
│                                                             │
│  PHASE 4: COMPLETION                                       │
│  ├─ Log rotation event                                    │
│  ├─ Update documentation                                  │
│  ├─ Notify stakeholders                                   │
│  └─ Schedule next rotation                                │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### Scheduled Rotation Script

```bash
#!/bin/bash
# scheduled-rotation.sh - Cron job for automated rotation

# Configuration
LOG_FILE="/var/log/credential-rotation.log"
ALERT_EMAIL="devops@company.com"

# Log function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a $LOG_FILE
}

# Start rotation
log "🔄 Starting scheduled credential rotation"

# Run rotation
if curl -s -X POST http://localhost:8000/rotate > /tmp/rotation-result.json; then
    SUCCESS=$(cat /tmp/rotation-result.json | grep -o '"success":true')
    if [ -n "$SUCCESS" ]; then
        log "✅ Rotation completed successfully"
        
        # Get new status
        curl -s http://localhost:8000/status > /tmp/status-after-rotation.json
        log "📊 Status after rotation: $(cat /tmp/status-after-rotation.json)"
    else
        log "❌ Rotation failed"
        echo "Credential rotation failed at $(date)" | mail -s "ALERT: Rotation Failed" $ALERT_EMAIL
        exit 1
    fi
else
    log "❌ Unable to reach rotation endpoint"
    exit 1
fi

# Verify with secure endpoint
if curl -s http://localhost:8000/secure-data | grep -q "Secure data retrieved"; then
    log "✅ New credentials working correctly"
else
    log "❌ New credentials test failed"
    echo "Credentials test failed at $(date)" | mail -s "ALERT: Credentials Test Failed" $ALERT_EMAIL
    exit 1
fi

log "✅ Scheduled rotation complete"
```

### Cron Schedule Examples

```bash
# Rotate credentials daily at 2 AM
0 2 * * * /usr/local/bin/scheduled-rotation.sh

# Rotate credentials weekly on Sunday at 3 AM
0 3 * * 0 /usr/local/bin/scheduled-rotation.sh

# Rotate credentials monthly on 1st at 4 AM
0 4 1 * * /usr/local/bin/scheduled-rotation.sh
```

---

## 🔧 Runbook: Troubleshooting

### Common Issues and Solutions

#### Issue 1: Rotation Fails with "LimitExceeded"

```bash
# Problem: AWS 2-key limit reached
# Error: "Cannot exceed quota for AccessKeysPerUser: 2"

# Solution: Manually delete old keys
aws --endpoint-url=http://localhost:4566 \
    iam list-access-keys --user-name app-user

# Delete the oldest key
aws --endpoint-url=http://localhost:4566 \
    iam delete-access-key \
    --user-name app-user \
    --access-key-id <OLD_KEY_ID>

# Retry rotation
curl -X POST http://localhost:8000/rotate
```

#### Issue 2: Application Can't Validate New Credentials

```bash
# Problem: STS validation failing
# Symptoms: "Could not connect to the endpoint URL"

# Solution: Check LocalStack connectivity
curl -v http://localhost:4566/_localstack/health

# If LocalStack is not responding:
docker restart localstack-lab
sleep 10

# Re-initialize if needed
./init-lab.sh
```

#### Issue 3: Secrets Manager Not Found

```bash
# Problem: Secret doesn't exist
# Error: "ResourceNotFoundException"

# Solution: Create the secret
aws --endpoint-url=http://localhost:4566 \
    secretsmanager create-secret \
    --name app-credentials \
    --secret-string '{"access_key_id":"AKIAIOSFODNN7EXAMPLE","secret_access_key":"wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"}'
```

#### Issue 4: FastAPI App Not Responding

```bash
# Problem: Application unresponsive
# Symptoms: Connection refused

# Solution: Check application logs
ps aux | grep "python app.py"

# Restart if needed
pkill -f "python app.py"
python app.py &
```

### Diagnostic Commands

```bash
# Full diagnostic script
#!/bin/bash
echo "🔍 Credential Rotation Diagnostic"
echo "================================="

# 1. Check Docker
echo "1️⃣ Docker Status:"
docker ps | grep localstack

# 2. Check LocalStack
echo "2️⃣ LocalStack Health:"
curl -s http://localhost:4566/_localstack/health | python3 -m json.tool

# 3. Check IAM User
echo "3️⃣ IAM User:"
aws --endpoint-url=http://localhost:4566 iam get-user --user-name app-user 2>/dev/null || echo "User not found"

# 4. Check Access Keys
echo "4️⃣ Access Keys:"
aws --endpoint-url=http://localhost:4566 iam list-access-keys --user-name app-user 2>/dev/null || echo "No keys found"

# 5. Check Secrets
echo "5️⃣ Secrets:"
aws --endpoint-url=http://localhost:4566 secretsmanager get-secret-value --secret-id app-credentials 2>/dev/null | python3 -m json.tool || echo "Secret not found"

# 6. Check App Status
echo "6️⃣ Application Status:"
curl -s http://localhost:8000/status | python3 -m json.tool || echo "App not responding"

echo "✅ Diagnostic complete"
```

---

## 🚨 Runbook: Emergency Response

### Incident Response Procedure

```bash
#!/bin/bash
# emergency-response.sh - Emergency credential response

echo "🚨 EMERGENCY RESPONSE"
echo "===================================="

# Step 1: Assess the situation
echo "📊 Current Status:"
curl -s http://localhost:8000/status | python3 -m json.tool

# Step 2: Backup current state
echo "💾 Creating emergency backup..."
aws --endpoint-url=http://localhost:4566 \
    secretsmanager get-secret-value \
    --secret-id app-credentials \
    --query 'SecretString' \
    --output text > emergency-backup-$(date +%s).json

# Step 3: Check fallback availability
FALLBACK=$(curl -s http://localhost:8000/status | grep -o '"has_fallback":true')
if [ -n "$FALLBACK" ]; then
    echo "✅ Fallback credentials available"
else
    echo "⚠️ No fallback available - use manual backup"
fi

# Step 4: Emergency rollback if needed
read -p "Rollback to fallback credentials? (y/n): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    # Manual rollback process
    # Note: In production, you would restore from the last good backup
    echo "↩️ Performing emergency rollback..."
    # Restore from backup
    cat emergency-backup-*.json | python3 -m json.tool > /tmp/restore.json
    aws --endpoint-url=http://localhost:4566 \
        secretsmanager put-secret-value \
        --secret-id app-credentials \
        --secret-string "$(cat /tmp/restore.json)"
    echo "✅ Rollback complete"
fi

# Step 5: Verify
echo "🔍 Verifying restored credentials..."
curl -s http://localhost:8000/secure-data | python3 -m json.tool

echo "✅ Emergency response complete"
```

### Manual Rollback Procedure

```bash
#!/bin/bash
# manual-rollback.sh - Manual rollback to backup

echo "↩️ Manual Rollback Procedure"

# Step 1: List available backups
echo "📋 Available backups:"
ls -lh backup-*.json

# Step 2: Select backup file
read -p "Enter backup filename: " BACKUP_FILE

# Step 3: Verify backup file exists
if [ ! -f "$BACKUP_FILE" ]; then
    echo "❌ Backup file not found"
    exit 1
fi

# Step 4: Restore credentials
echo "🔄 Restoring from $BACKUP_FILE..."
aws --endpoint-url=http://localhost:4566 \
    secretsmanager put-secret-value \
    --secret-id app-credentials \
    --secret-string "$(cat $BACKUP_FILE)"

# Step 5: Verify restore
echo "🔍 Verifying restore..."
curl -s http://localhost:8000/status | python3 -m json.tool

echo "✅ Manual rollback complete"
```

### Communication Template

```
Subject: [EMERGENCY] Credential Rotation Alert

Priority: CRITICAL
Time: [TIMESTAMP]
Status: [SUCCESS/FAILURE]

SUMMARY
A credential rotation was triggered at [TIME] and the status is [STATUS].

DETAILS
• Rotation ID: [ROTATION_ID]
• Previous Key: [OLD_KEY_ID]
• New Key: [NEW_KEY_ID]  
• Status: [SUCCESS/FAILURE/ROLLBACK]
• Timestamp: [TIMESTAMP]

IMPACT
• Service Status: [HEALTHY/DEGRADED]
• Active Sessions: [COUNT] unaffected
• User Impact: [NONE/MINIMAL/SEVERE]

NEXT STEPS
• [ACTION 1]
• [ACTION 2]
• [ACTION 3]

ESCALATION
• Primary: [ON-CALL-ENGINEER]
• Secondary: [BACKUP-ENGINEER]
• Manager: [MANAGER]
```

---

## 📚 DevOps Interview Learnings

### Key Technical Learnings

#### 1. **AWS IAM Best Practices**

```python
# Key Learning: Always implement least privilege
# The rotation user should only have these permissions:

{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "iam:CreateAccessKey",
                "iam:DeleteAccessKey", 
                "iam:ListAccessKeys",
                "iam:UpdateAccessKey"
            ],
            "Resource": "arn:aws:iam::*:user/${aws:username}"
        },
        {
            "Effect": "Allow",
            "Action": [
                "secretsmanager:GetSecretValue",
                "secretsmanager:PutSecretValue"
            ],
            "Resource": "arn:aws:secretsmanager:*:*:secret:app-credentials-*"
        }
    ]
}
```

**Interview Takeaway**: "I implement the principle of least privilege by creating a dedicated rotation role with minimal permissions needed for rotation."

#### 2. **Zero-Downtime Patterns**

```python
# Key Learning: Dual-key pattern is essential
def rotate_credentials(self):
    # 1. Create new key (old remains active)
    new_key = self.iam.create_access_key()
    
    # 2. Validate before switching
    if self.validate_credentials(new_key):
        # 3. Update secret store
        self.secrets.put_secret_value(new_key)
        
        # 4. Deactivate old keys
        self.iam.deactivate_old_keys()
```

**Interview Takeaway**: "The dual-key approach ensures zero-downtime by maintaining active credentials throughout the rotation. Old credentials remain valid until new ones are verified."

#### 3. **Validation is Critical**

```python
# Key Learning: Always validate before switching
def validate_credentials(creds):
    try:
        # Use STS to test credentials
        sts = boto3.client('sts', **creds)
        identity = sts.get_caller_identity()
        return True
    except Exception:
        return False
```

**Interview Takeaway**: "I validate new credentials using STS `get_caller_identity` before committing them. This prevents deploying invalid credentials that would cause service disruption."

#### 4. **Fallback Strategies**

```python
# Key Learning: Always have a rollback plan
class CredentialManager:
    def __init__(self):
        self.current_creds = None
        self.fallback_creds = None  # Previous working credentials
    
    def rotate(self):
        # Store current as fallback
        self.fallback_creds = self.current_creds
        
        try:
            # Attempt rotation
            self.rotate_credentials()
        except Exception:
            # Automatic rollback
            self.current_creds = self.fallback_creds
```

**Interview Takeaway**: "I implement a fallback mechanism by storing the previous credentials. If rotation fails, we automatically rollback to the known working credentials."

#### 5. **Observability Matters**

```python
# Key Learning: Log everything
logger.info(f"🔄 Starting rotation")
logger.info(f"📋 Found {len(keys)} keys")
logger.info(f"🔑 Created new key: {new_key_id}")
logger.info(f"✅ Rotation completed in {duration}s")
```

**Interview Takeaway**: "Comprehensive logging is crucial for debugging rotation issues. I log each step with timestamps, including key IDs and validation results."

---

## 🎯 Common Interview Questions

### Q1: "How would you handle credential rotation at scale?"

**Answer:**
> "I would implement a centralized rotation system with the following characteristics:
> 
> 1. **Distribution**: Use a message queue to coordinate rotation across multiple services
> 2. **Grace Period**: Implement a configurable grace period for credential propagation
> 3. **Monitoring**: Track rotation success rates and duration metrics
> 4. **Automation**: Use infrastructure as code to manage rotation policies
> 5. **Validation**: Implement comprehensive pre and post-rotation validation"

### Q2: "What are the risks of credential rotation?"

**Answer:**
> "The main risks include:
> 
> 1. **Invalid Credentials**: Deploying unusable credentials
> 2. **Race Conditions**: Services using old credentials after deletion
> 3. **Propagation Delays**: Credentials not reaching all services
> 4. **Key Limit**: AWS 2-key limit causing creation failures
> 5. **Rollback Complexity**: Difficulty reverting to previous credentials
> 
> I mitigate these with validation, fallback mechanisms, and monitoring."

### Q3: "How would you design a credential rotation system for microservices?"

**Answer:**
> "I would design a system with:
> 
> 1. **Central Store**: AWS Secrets Manager as the source of truth
> 2. **Client Caching**: Services cache credentials with TTL
> 3. **Push vs Pull**: Services pull credentials periodically
> 4. **Graceful Degradation**: Fallback to cached credentials if store is unavailable
> 5. **Monitoring**: Track credential age and rotation status per service"

### Q4: "How do you ensure security during credential rotation?"

**Answer:**
> "I follow security best practices:
> 
> 1. **Encryption**: All secrets encrypted at rest and in transit
> 2. **Audit**: Logging all access and rotation events
> 3. **Least Privilege**: Minimal IAM permissions for rotation
> 4. **Validation**: STS validation before use
> 5. **Compliance**: Maintain audit trail for compliance requirements"

### Q5: "What would you do if a rotation fails in production?"

**Answer:**
> "My incident response would be:
> 
> 1. **Immediate**: Check if fallback credentials are available
> 2. **Rollback**: Automatically rollback if enabled
> 3. **Manual**: If automatic fails, manual restore from backup
> 4. **Analysis**: Investigate root cause from logs
> 5. **Prevention**: Implement fix to prevent recurrence"

---

## 🚀 Advanced Scenarios

### Scenario 1: Multi-Region Deployment

```python
# Multi-region rotation support
class MultiRegionRotation:
    def __init__(self, regions=['us-east-1', 'eu-west-1']):
        self.regions = regions
    
    def rotate_all_regions(self):
        for region in self.regions:
            try:
                self.rotate_region(region)
            except Exception as e:
                print(f"Region {region} rotation failed: {e}")
                # Continue with other regions
```

### Scenario 2: Service-Specific Credentials

```python
# Different credentials for different services
class ServiceCredentialManager:
    def __init__(self):
        self.service_creds = {
            'database': {'name': 'db-credentials'},
            'api': {'name': 'api-credentials'},
            'cache': {'name': 'cache-credentials'}
        }
    
    def rotate_service(self, service_name):
        if service_name in self.service_creds:
            return self.rotate(service_name)
```

### Scenario 3: Compliance Audit Trail

```python
# Full audit trail for compliance
class AuditLogger:
    def log_rotation(self, creds, status, user):
        audit_entry = {
            'timestamp': datetime.now().isoformat(),
            'access_key': creds['access_key_id'][:10],
            'status': status,
            'user': user,
            'ip_address': get_ip(),
            'user_agent': get_user_agent()
        }
        self.save_audit(audit_entry)
```

---

## 📊 Key Takeaways

### Technical Skills Demonstrated

```
┌─────────────────────────────────────────────────────────────┐
│                    Key Skills                               │
├─────────────────────────────────────────────────────────────┤
│ ✅ AWS IAM Deep Understanding                              │
│ ✅ Security Best Practices                                 │
│ ✅ Zero-Downtime Deployment                                │
│ ✅ Error Handling & Recovery                               │
│ ✅ Monitoring & Observability                              │
│ ✅ Automation & Scripting                                  │
│ ✅ Infrastructure as Code                                  │
│ ✅ System Design & Architecture                            │
└─────────────────────────────────────────────────────────────┘
```

### Interview Success Tips

1. **Explain the "Why"**: Always explain why you chose a particular approach
2. **Discuss Trade-offs**: Acknowledge and explain trade-offs
3. **Show Security Focus**: Emphasize security considerations
4. **Demonstrate Experience**: Share real-world examples
5. **Be Detailed**: Know the implementation details

### Common Pitfalls to Avoid

1. ❌ Not validating before switching
2. ❌ Deleting old keys immediately
3. ❌ Not having a rollback plan
4. ❌ Forgetting the 2-key limit
5. ❌ Not monitoring rotations
6. ❌ Insufficient logging

---

## 📝 Final Checklist

### Before Rotation
- [ ] Backup current credentials
- [ ] Check system health
- [ ] Verify AWS key limit
- [ ] Test current credentials
- [ ] Notify stakeholders

### During Rotation
- [ ] Create new key (keep old active)
- [ ] Validate new credentials
- [ ] Update secret store
- [ ] Deactivate old keys
- [ ] Store fallback credentials

### After Rotation
- [ ] Test new credentials
- [ ] Verify all services
- [ ] Log rotation event
- [ ] Update documentation
- [ ] Monitor for issues

### Continuous Improvement
- [ ] Review rotation logs
- [ ] Optimize rotation time
- [ ] Update automation
- [ ] Train team members
- [ ] Document learnings

---

## 🎓 Conclusion

### What You've Learned 
(from this implimentation)

1. **Technical Skills**: AWS IAM, Secrets Manager, STS validation
2. **Design Patterns**: Dual-key rotation, fallback mechanisms
3. **Best Practices**: Security, monitoring, automation
4. **Process Skills**: Runbook creation, incident response
5. **Interview Skills**: Articulating complex concepts


---

**This runbook and learnings guide is a comprehensive resource for credential rotation implementation!** 🚀
