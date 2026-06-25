### Overview

MiniStack setup tested ready to reuse for devops labs:

1. Install MiniStack (via `pip`)  
2. Run it in the background  
3. Configure AWS CLI  
4. Sanity‑check with S3  
5. (Optional) Wire it into Terraform

---

### 1. Install MiniStack in your virtualenv

From your project directory:

```bash
python -m venv .venv
source .venv/bin/activate

pip install --upgrade pip
pip install ministack awscli
```

Verify:

```bash
ministack -h
```

You should see the help text you already saw.

---

### 2. Start MiniStack

Foreground (for debugging):

```bash
ministack
```

Background (what you used, recommended):

```bash
ministack -d
```

You should see:

```text
MiniStack started in background (PID XXXX) on port 4566.
  Logs: /tmp/ministack-4566.log
  Stop: ministack --stop
```

To stop it later:

```bash
ministack --stop
```

---

### 3. Configure AWS CLI profile for MiniStack

Create a dedicated profile with **dummy credentials** (AWS CLI just needs *something*):

```bash
aws configure --profile ministack
```

Use:

```text
AWS Access Key ID: test
AWS Secret Access Key: test
Default region name: us-east-1
Default output format: json
```

---

### 4. Sanity‑check with S3

Always point the AWS CLI at MiniStack with `--endpoint-url`:

```bash
aws --profile ministack --endpoint-url http://localhost:4566 s3 mb s3://demo-bucket
aws --profile ministack --endpoint-url http://localhost:4566 s3 ls
```

You should see `demo-bucket` listed.

If something fails, tail the log:

```bash
tail -f /tmp/ministack-4566.log
```

---

### 5. (Optional) Terraform wired to MiniStack

Create `provider.tf`:

```hcl
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region                      = "us-east-1"
  access_key                  = "test"
  secret_key                  = "test"
  s3_use_path_style           = true
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true

  endpoints {
    s3        = "http://localhost:4566"
    dynamodb  = "http://localhost:4566"
    sqs       = "http://localhost:4566"
    sns       = "http://localhost:4566"
    lambda    = "http://localhost:4566"
    apigateway = "http://localhost:4566"
  }
}
```

Example `main.tf`:

```hcl
resource "aws_s3_bucket" "demo" {
  bucket = "tf-demo-bucket"
}
```

Then:

```bash
terraform init
terraform apply
```

---

### 6. Progressive way to reuse this for interview labs

You can now layer on:

- **More services**: SQS, SNS, DynamoDB, Lambda, etc.  
- **Kubernetes**: apps in kind/k3d talking to MiniStack endpoints  
- **CI**: job that runs `ministack -d`, `terraform apply`, tests, then `ministack --stop`
