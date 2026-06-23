## Step 0: Generate Auth Token for LocalStack Pro

Create a free account at app.localstack.cloud

Copy  token from Settings → Auth Tokens

Export it globally:
echo 'export LOCALSTACK_AUTH_TOKEN="<your-token>"' >> ~/.bashrc

Reload shell: 
source ~/.bashrc

Setting up LocalStack Pro with above auth token.
This will give you a more robust experience with better performance and additional features.

## Step 1: Update docker-compose.yml for LocalStack Pro

```yaml
services:
  localstack:
    image: localstack/localstack-pro:latest  # Pro image
    container_name: localstack-aws
    ports:
      - "4566:4566"      # Main AWS endpoint
      - "4510-4559:4510-4559"  # Service ports
    environment:
      - LOCALSTACK_AUTH_TOKEN=${LOCALSTACK_AUTH_TOKEN}  # Your token from env
      - SERVICES=apigateway,lambda,dynamodb,iam,cloudformation,cloudwatch,logs
      - DEBUG=1
      - PERSISTENCE=1
      - SKIP_SIGNATURE_VALIDATION=1
      - DOCKER_HOST=unix:///var/run/docker.sock
      - AWS_DEFAULT_REGION=us-east-1
      - AWS_ACCESS_KEY_ID=test
      - AWS_SECRET_ACCESS_KEY=test
      - LS_LOG=trace
      - ENABLE_CONFIG_UPDATES=1
    volumes:
      - "./localstack_data:/var/lib/localstack"
      - "/var/run/docker.sock:/var/run/docker.sock"
    networks:
      - localstack-net

networks:
  localstack-net:
    driver: bridge
```

## Step 2: Set Up Your Auth Token

```bash
# Set the token for your current session
export LOCALSTACK_AUTH_TOKEN="your-token-here"

# Make it permanent (add to .bashrc or .zshrc)
echo 'export LOCALSTACK_AUTH_TOKEN="your-token-here"' >> ~/.bashrc

# Or if using ZSH
echo 'export LOCALSTACK_AUTH_TOKEN="your-token-here"' >> ~/.zshrc

# Reload
source ~/.bashrc  # or source ~/.zshrc

# Verify it's set
echo $LOCALSTACK_AUTH_TOKEN
```

## Step 3: Create .env File (Recommended)

Create a `.env` file in your project root for easier management:

```bash
cat > .env << EOF
LOCALSTACK_AUTH_TOKEN=your-token-here
AWS_ACCESS_KEY_ID=test
AWS_SECRET_ACCESS_KEY=test
AWS_DEFAULT_REGION=us-east-1
EOF

# Make sure .env is in .gitignore
echo ".env" >> .gitignore
```

## Step 4: Update docker-compose.yml to Use .env

```yaml
services:
  localstack:
    image: localstack/localstack-pro:latest
    container_name: localstack-aws
    ports:
      - "4566:4566"
    environment:
      - LOCALSTACK_AUTH_TOKEN=${LOCALSTACK_AUTH_TOKEN}
      - SERVICES=apigateway,lambda,dynamodb,iam,cloudformation,cloudwatch,logs
      - DEBUG=1
      - PERSISTENCE=1
      - SKIP_SIGNATURE_VALIDATION=1
      - DOCKER_HOST=unix:///var/run/docker.sock
      - AWS_DEFAULT_REGION=${AWS_DEFAULT_REGION:-us-east-1}
      - AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID:-test}
      - AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY:-test}
      - LS_LOG=trace
    volumes:
      - "./localstack_data:/var/lib/localstack"
      - "/var/run/docker.sock:/var/run/docker.sock"
    networks:
      - localstack-net

networks:
  localstack-net:
    driver: bridge
```

## Step 5: Clean and Start LocalStack Pro

```bash
# Stop any existing containers
docker-compose down -v

# Clean up old data
sudo rm -rf /tmp/localstack 2>/dev/null || true
rm -rf localstack_data

# Pull the Pro image (requires auth)
docker pull localstack/localstack-pro:latest

# Start with your token
LOCALSTACK_AUTH_TOKEN="your-token-here" docker-compose up -d

# Or if you set the env variable:
docker-compose up -d

# Watch the logs to ensure it starts correctly
docker-compose logs -f
```

## Step 6: Verify Pro Features Are Working

```bash
# Check health - should show pro features
curl http://localhost:4566/_localstack/health | jq .

# Should show something like:
# {
#   "services": {
#     "dynamodb": "available",
#     "apigateway": "available",
#     "lambda": "available",
#     ...
#   },
#   "features": {
#     "pro": true,
#     "enterprise": false
#   }
# }

# Check version
curl http://localhost:4566/_localstack/version
```

## Step 7: Complete Pro Setup Script

Create `setup_pro.sh`:

```bash
#!/bin/bash
set -e

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "🚀 Setting up LocalStack Pro..."

# Check if token is set
if [ -z "$LOCALSTACK_AUTH_TOKEN" ]; then
    echo -e "${RED}❌ LOCALSTACK_AUTH_TOKEN not set!${NC}"
    echo "Please set it with:"
    echo "  export LOCALSTACK_AUTH_TOKEN='your-token-here'"
    echo "Or add to .env file"
    exit 1
fi

echo -e "${GREEN}✅ Auth token found${NC}"

# Stop existing
echo "Stopping existing containers..."
docker-compose down -v 2>/dev/null || true

# Clean up
echo "Cleaning up..."
rm -rf localstack_data
mkdir -p localstack_data

# Pull Pro image
echo "Pulling LocalStack Pro image..."
docker pull localstack/localstack-pro:latest

# Start
echo "Starting LocalStack Pro..."
docker-compose up -d

# Wait for it
echo "Waiting for services..."
sleep 15

# Check health
echo "Checking health..."
HEALTH=$(curl -s http://localhost:4566/_localstack/health)

if echo "$HEALTH" | grep -q '"pro":true'; then
    echo -e "${GREEN}✅ LocalStack Pro is running!${NC}"
else
    echo -e "${YELLOW}⚠️  Pro features not detected. Check logs:${NC}"
    echo "docker-compose logs -f"
fi

# Show status
echo ""
echo "📊 LocalStack Status:"
echo "$HEALTH" | jq '.' 2>/dev/null || echo "$HEALTH"

echo ""
echo "📝 To view logs: docker-compose logs -f"
echo "🔍 To test: aws --endpoint-url=http://localhost:4566 s3 ls"
```

## Step 8: Enhanced Deployment Script for Pro

Update `deploy.sh` with better error handling:

```bash
#!/bin/bash
set -e

echo "🚀 Deploying Badge System with LocalStack Pro..."

AWS_CMD="aws --endpoint-url=http://localhost:4566 --region us-east-1"

# Check if LocalStack is ready
echo "⏳ Checking LocalStack..."
for i in {1..30}; do
    if curl -s http://localhost:4566/_localstack/health | grep -q '"pro":true'; then
        echo "✅ LocalStack Pro ready"
        break
    fi
    sleep 2
done

# 1. Create DynamoDB Table
echo "📊 Creating DynamoDB table..."
$AWS_CMD dynamodb create-table \
    --table-name badge_reads \
    --attribute-definitions \
        AttributeName=badge_id,AttributeType=S \
        AttributeName=timestamp,AttributeType=S \
    --key-schema \
        AttributeName=badge_id,KeyType=HASH \
        AttributeName=timestamp,KeyType=RANGE \
    --billing-mode PAY_PER_REQUEST 2>/dev/null || echo "Table already exists"

# 2. Create IAM Role
echo "🔐 Creating IAM role..."
$AWS_CMD iam create-role \
    --role-name lambda-execution-role \
    --assume-role-policy-document '{
        "Version": "2012-10-17",
        "Statement": [{
            "Effect": "Allow",
            "Principal": {"Service": "lambda.amazonaws.com"},
            "Action": "sts:AssumeRole"
        }]
    }' 2>/dev/null || echo "Role already exists"

# 3. Create Lambda function
echo "⚡ Creating Lambda function..."
LAMBDA_ARN=$($AWS_CMD lambda create-function \
    --function-name badge-processor \
    --runtime python3.9 \
    --role arn:aws:iam::000000000000:role/lambda-execution-role \
    --handler lambda_function.lambda_handler \
    --zip-file fileb://lambda_function.zip \
    --environment Variables={TABLE_NAME=badge_reads} \
    --query 'FunctionArn' \
    --output text 2>/dev/null)

if [ -z "$LAMBDA_ARN" ]; then
    LAMBDA_ARN=$($AWS_CMD lambda get-function \
        --function-name badge-processor \
        --query 'Configuration.FunctionArn' \
        --output text)
fi

echo "✅ Lambda ARN: $LAMBDA_ARN"

# 4. Create API Gateway
echo "🌐 Creating API Gateway..."
API_ID=$($AWS_CMD apigateway create-rest-api \
    --name BadgeAPI \
    --query 'id' \
    --output text 2>/dev/null)

if [ -z "$API_ID" ]; then
    API_ID=$($AWS_CMD apigateway get-rest-apis \
        --query 'items[?name==`BadgeAPI`].id' \
        --output text)
fi

ROOT_ID=$($AWS_CMD apigateway get-resources \
    --rest-api-id $API_ID \
    --query 'items[0].id' \
    --output text)

RESOURCE_ID=$($AWS_CMD apigateway create-resource \
    --rest-api-id $API_ID \
    --parent-id $ROOT_ID \
    --path-part badge \
    --query 'id' \
    --output text 2>/dev/null || \
    $AWS_CMD apigateway get-resources \
        --rest-api-id $API_ID \
        --query 'items[?path==`/badge`].id' \
        --output text)

$AWS_CMD apigateway put-method \
    --rest-api-id $API_ID \
    --resource-id $RESOURCE_ID \
    --http-method POST \
    --authorization-type NONE 2>/dev/null

$AWS_CMD apigateway put-integration \
    --rest-api-id $API_ID \
    --resource-id $RESOURCE_ID \
    --http-method POST \
    --type AWS_PROXY \
    --integration-http-method POST \
    --uri arn:aws:apigateway:us-east-1:lambda:path/2015-03-31/functions/$LAMBDA_ARN/invocations 2>/dev/null

$AWS_CMD apigateway create-deployment \
    --rest-api-id $API_ID \
    --stage-name dev 2>/dev/null

echo ""
echo "✅ Deployment Complete!"
echo "📝 API Endpoint: http://localhost:4566/restapis/$API_ID/dev/_user_request_/badge"
echo "📊 DynamoDB Table: badge_reads"
```

## Step 9: Pro Features You Can Use

With LocalStack Pro, you get additional features:

```bash
# 1. CloudWatch Logs (better debugging)
aws --endpoint-url=http://localhost:4566 logs describe-log-groups

# 2. CloudFormation (infrastructure as code)
aws --endpoint-url=http://localhost:4566 cloudformation list-stacks

# 3. Enhanced Lambda performance
aws --endpoint-url=http://localhost:4566 lambda list-functions

# 4. API Gateway with custom domains
aws --endpoint-url=http://localhost:4566 apigateway get-domain-names

# 5. Extended service coverage
aws --endpoint-url=http://localhost:4566 s3 ls  # S3 now works too!
```

## Step 10: Troubleshooting Pro

```bash
# Check if token is valid
curl -H "Authorization: Bearer $LOCALSTACK_AUTH_TOKEN" \
     https://api.localstack.cloud/v1/validate

# Check pro status
curl http://localhost:4566/_localstack/health | jq '.features'

# View detailed logs
docker-compose logs -f localstack

# Reset everything
docker-compose down -v
rm -rf localstack_data
docker system prune -f
```

## Quick Start Commands

```bash
# 1. Set your token
export LOCALSTACK_AUTH_TOKEN="your-actual-token-here"

# 2. Start Pro
docker-compose up -d

# 3. Verify Pro is working
curl -s http://localhost:4566/_localstack/health | jq '.features'

# 4. Deploy your badge system
bash deploy.sh

# 5. Test
python3 test_quick.py
```

**Remember**: Your LocalStack Pro token is sensitive - never commit it to Git. Always use `.env` files and add them to `.gitignore`.
